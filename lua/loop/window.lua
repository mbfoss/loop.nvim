local M = {}
local Page = require('loop.pages.Page')
local OutputPage = require('loop.pages.OutputPage')
local ItemListPage = require('loop.pages.ItemListPage')
local BreakpointsPage = require('loop.pages.BreakpointsPage')
local uitools = require('loop.tools.uitools')
local jsontools = require('loop.tools.json')
local selector = require("loop.selector")

---@type boolean
local setup_done = false

---@type number
local _loop_win = -1
---@type number
local _loop_win_height_ratio

---@class loop.TabInfo
---@field label string
---@field pages loop.pages.Page[]
---@field active_page_idx number|nil
---@field list_prefix string|nil


local _tabs = {
    ---@type loop.TabInfo
    events = { label = "Messages", pages = { OutputPage:new("Messages") }, active_page_idx = 1 },
    ---@type loop.TabInfo
    breakpoints = { label = "Breakpoints", pages = {} },
    ---@type loop.TabInfo
    tasks = { label = "Task", pages = {}, list_prefix = "Task - " },
    ---@type loop.TabInfo
    debug = { label = "Debug", pages = {}, list_prefix = "Debug - " },
    ---@type loop.TabInfo
    threads = { label = "Threads", pages = {}, list_prefix = "Threads - " },
    ---@type loop.TabInfo
    stacktrace = { label = "Stack", pages = {}, list_prefix = "Stack - " },
}
local _tabs_arr = {
    _tabs.events,
    _tabs.breakpoints,
    _tabs.tasks,
    _tabs.debug,
    _tabs.threads,
    _tabs.stacktrace,
}
---@type number
local _active_tab_idx = 1

---@param vim_tab_id number
---@return number
local function _count_normal_windows(vim_tab_id)
    local wins_in_tab = vim.api.nvim_tabpage_list_wins(vim_tab_id)
    local count = 0
    for _, win in ipairs(wins_in_tab) do
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative == "" then
            count = count + 1
        end
    end
    return count
end

local function _quit_if_last_window()
    if _loop_win ~= -1 then
        local count = _count_normal_windows(vim.api.nvim_win_get_tabpage(_loop_win))
        if count == 1 then
            local tab_count = #vim.api.nvim_list_tabpages()
            if tab_count > 1 then
                M.hide_window()
            else
                -- only our window remains, quit neovim
                vim.cmd('quit')
            end
        end
    end
end

local function _on_win_new_or_close()
    if _loop_win == -1 then
        return
    end
    local winid = _loop_win
    local count = _count_normal_windows(vim.api.nvim_win_get_tabpage(winid))
    --this should be configurable
    if count <= 2 then
        vim.schedule(_quit_if_last_window)
    end
    if count <= 1 then
        return
    end
    vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = winid })
    if _loop_win_height_ratio then
        vim.api.nvim_win_set_height(winid, math.floor(vim.o.lines * _loop_win_height_ratio))
    else
        vim.api.nvim_win_set_height(winid, math.floor(vim.o.lines * 0.17))
    end
end

---@type fun(action: "next"|"prev")
local _cycle_pages

---@param req_tab loop.TabInfo|nil
local function _setup_active_tab(req_tab)
    if not req_tab then
        req_tab = _tabs_arr[_active_tab_idx]
    end
    if #req_tab.pages == 0 then
        req_tab = _tabs.events
    end

    local page_idx = req_tab.active_page_idx or 1
    assert(page_idx > 0 and page_idx <= #req_tab.pages)

    --- set keymaps
    ---@type table<string,loop.pages.page.KeyMapItem>
    local keymaps = {
        ["<c-p>"] = {
            callback = function() _cycle_pages("prev") end,
            desc = "Move to previous page",
        },
        ["<c-n>"] = {
            callback = function() _cycle_pages("next") end,
            desc = "Move to previous page",
        },
        ["<c-l>"] = {
            callback = _ui_select_page,
            desc = "Select page",
        },
    }
    req_tab.pages[page_idx]:set_keymaps(keymaps)

    -- update window if visible
    if _loop_win ~= -1 then
        local win = _loop_win
        local winbar_parts = { "%#LoopPluginInactiveTab#" }
        local tabidx = 0
        for arr_idx, tab in ipairs(_tabs_arr) do
            local active = false
            if req_tab == tab then
                _active_tab_idx = arr_idx
                active = true
                local buf = tab.pages[page_idx]:get_or_create_buf()
                vim.api.nvim_win_set_buf(win, buf)
            end
            if #tab.pages > 0 then
                tabidx = tabidx + 1
                if tabidx ~= 1 then table.insert(winbar_parts, '|') end
                if active then table.insert(winbar_parts, "%#LoopPluginActiveTab#") end
                local labelparts = { ' ' }
                table.insert(labelparts, tab.label)
                if #tab.pages > 1 then
                    if not active then
                        vim.list_extend(labelparts, { ' (', tostring(#tab.pages), ')' })
                    else
                        vim.list_extend(labelparts,
                            { ' (', tostring(tab.active_page_idx), '/', tostring(#tab.pages), ')' })
                    end
                end
                table.insert(labelparts, ' ')
                local label = table.concat(labelparts, '')
                table.insert(winbar_parts, string.format("%%%d@v:lua.LoopProject._winbar_click@%s%%T", arr_idx, label))
                if active then
                    table.insert(winbar_parts, "%#LoopPluginInactiveTab#")
                end
            end
        end
        -- add right aligned current page/buffer info
        --if #_active_tab.pages > 0 then
        --    local name = _active_tab.pages[_active_tab.active_page_idx or 1]:get_name() or _active_tab.label
        --    table.insert(winbar_parts, "%=" .. name)
        --end
        -- set the winbar
        vim.wo[win].winbar = table.concat(winbar_parts, '')
    end
end


---@param req_tabidx number
---@param req_pageidx number|nil
local function _setup_active_tab_idx(req_tabidx, req_pageidx)
    local req_tab = _tabs_arr[req_tabidx]
    assert(req_tab)
    if not req_tab or #req_tab.pages == 0 then
        return
    end
    if req_pageidx and req_pageidx > 0 and req_pageidx <= #req_tab.pages then
        req_tab.active_page_idx = req_pageidx
    end
    _setup_active_tab(req_tab)
end

---@param action "next"|"prev"
_cycle_pages = function(action)
    if vim.api.nvim_get_current_win() ~= _loop_win then return end

    local tabidx = _active_tab_idx
    local tab = _tabs_arr[tabidx]
    local pageidx = tab.active_page_idx or 1

    local dir = action == "next" and 1 or -1

    if (#tab.pages > 0) then
        pageidx = pageidx + dir
    end

    -- if page goes out of bounds, move to next/prev tab with pages
    if pageidx < 1 or pageidx > #tab.pages then
        local start_idx = tabidx
        repeat
            tabidx = (tabidx - 1 + dir) % #_tabs_arr + 1
            tab = _tabs_arr[tabidx]
        until (#tab.pages > 0) or (tabidx == start_idx)
        pageidx = dir == 1 and 1 or #tab.pages
    end

    _setup_active_tab_idx(tabidx, pageidx)
end

function _ui_select_page()
    local choices = {}
    for tabidx, tab in ipairs(_tabs_arr) do
        for pageidx, page in ipairs(tab.pages) do
            local label = tab.list_prefix or ''
            label = label .. page:get_name()
            ---@type loop.SelectorItem
            local item = {
                label = label,
                data = { tabidx = tabidx, pageidx = pageidx },
            }
            table.insert(choices, item)
        end
    end
    selector.select("Select page", choices, nil, function(data)
        if data and data.tabidx then
            _setup_active_tab_idx(data.tabidx, data.pageix)
        end
    end)
end

---@param tab loop.TabInfo
function _delete_tab_pages(tab)
    assert(tab ~= _tabs.events)
    _setup_active_tab(_tabs.events)
    for _, page in ipairs(tab) do
        page:destroy()
    end
    tab.pages = {}
    tab.active_page_idx = nil
end

---@param tab loop.TabInfo
---@param page loop.pages.Page
function _add_tab_page(tab, page)
    table.insert(tab.pages, page)
    tab.active_page_idx = #tab.pages
    _setup_active_tab(tab)
end

local function protect_split_window_buffer(buf)
    if not Page.is_page(buf) then
        vim.schedule(function()
            _setup_active_tab_idx(_active_tab_idx, nil)
            if vim.api.nvim_buf_is_valid(buf) then
                uitools.smart_open_buffer(buf)
            end
        end)
    end
end

function M.winbar_click(id, clicks, button, mods)
    local tab = _tabs_arr[id]
    if tab then
        _setup_active_tab(tab)
    end
end

---@param tab loop.TabInfo | nil
local function create_window(tab)
    if _loop_win ~= -1 then
        _setup_active_tab(tab)
        return
    end

    local prev_win = vim.api.nvim_get_current_win()
    -- Open a bottom split.
    vim.cmd('botright split')
    -- Get the new window ID.
    _loop_win = vim.api.nvim_get_current_win()
    _on_win_new_or_close()
    vim.api.nvim_set_current_win(prev_win)

    _setup_active_tab(tab)

    vim.api.nvim_create_autocmd("WinResized", {
        --pattern = tostring(_loop_win), -- Only trigger for window ID 1001
        callback = function()
            if _loop_win ~= -1 then
                local height = vim.api.nvim_win_get_height(_loop_win)
                local ratio = height / vim.o.lines
                -- protect againt the case our window is the only one open
                if ratio < 0.5 then
                    _loop_win_height_ratio = ratio
                end
            end
        end,
    })
end

local function _on_window_enter()
    -- do not allow our buffers in another window
    local win = vim.api.nvim_get_current_win()
    if win ~= _loop_win then
        local buf = vim.api.nvim_win_get_buf(win)
        if Page.is_page(buf) then
            local bufnr = vim.api.nvim_create_buf(true, true)
            vim.api.nvim_win_set_buf(win, bufnr)
        end
    end
end

---@param lines string[]
---@param level nil|"warn"|"error"
function M.add_events(lines, level)
    assert(setup_done)

    ---@type loop.pages.OutputPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = _tabs.events.pages[1]
    assert(page)
    assert(getmetatable(page) == OutputPage)
    local timestamp = os.date("%H:%M:%S")
    local output = {}
    for _, line in ipairs(lines) do
        table.insert(output, timestamp .. ' ' .. line)
    end
    page:add_lines(output, level, #timestamp)
    if level == "error" then
        M.show_events()
    end
end

---@param breakpoints table<string, integer[]>
---@param proj_dir string
function M.update_breakpoints(breakpoints, proj_dir)
    assert(setup_done)
    ---@type loop.pages.BreakpointsPage
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = _tabs.breakpoints.pages[1]
    if not page then
        page = BreakpointsPage:new()
        _add_tab_page(_tabs.breakpoints, page)
    end
    assert(getmetatable(page) == BreakpointsPage)
    if page then
        page:setlist(breakpoints, proj_dir)
        _setup_active_tab(_tabs.breakpoints)
    end
end

function M.show_window()
    assert(setup_done)
    create_window(nil)
end

function M.hide_window()
    assert(setup_done)
    if _loop_win and vim.api.nvim_win_is_valid(_loop_win) then
        vim.api.nvim_win_close(_loop_win, false)
        _loop_win = -1
    end
end

---@return boolean
function M.toggle_window()
    assert(setup_done)
    if _loop_win ~= -1 then
        M.hide_window()
        return false
    else
        M.show_window()
        return true
    end
end

function M.show_events()
    assert(setup_done)
    create_window(_tabs.events)
end

function M.show_task_output()
    create_window(_tabs.tasks)
end

function M.delete_task_buffers()
    _delete_tab_pages(_tabs.tasks)
    _delete_tab_pages(_tabs.debug)
end

---@param name string -- task name
---@param bufnr number
function M.add_term_task_page(name, bufnr)
    assert(setup_done)
    assert(type(name) == "string")
    assert(vim.api.nvim_buf_is_valid(bufnr))

    local page = Page:new("term", name)
    page:assign_buf(bufnr)

    _add_tab_page(_tabs.tasks, page)
end

---@param name string -- task name
---@return loop.pages.OutputPage
function M.add_debug_task_page(name)
    assert(setup_done)
    assert(type(name) == "string")
    -- create page
    local page = OutputPage:new(name)
    _add_tab_page(_tabs.tasks, page)
    return page
end

---@param name string -- task name
---@param bufnr number
function M.add_debug_term_page(name, bufnr)
    assert(setup_done)
    assert(type(name) == "string")
    -- create page
    local page = Page:new("term", name)
    page:assign_buf(bufnr)
    _add_tab_page(_tabs.debug, page)
end

---@param name string -- task name
---@return loop.pages.OutputPage
function M.add_debug_output_page(name)
    assert(setup_done)
    assert(type(name) == "string")
    -- create page
    local page = OutputPage:new(name)
    _add_tab_page(_tabs.debug, page)
    return page
end

---@param name string -- task name
---@return loop.pages.ItemListPage
function M.add_stacktrace_page(name)
    assert(setup_done)
    assert(type(name) == "string")
    -- create page
    local page = ItemListPage:new(name)
    _add_tab_page(_tabs.stacktrace, page)
    return page
end

---@param config_dir string
function M.save_settings(config_dir)
    local config = { height = _loop_win_height_ratio }
    jsontools.save_to_file(vim.fs.joinpath(config_dir, "window.json"), config)
end

---@param config_dir string
function M.load_settings(config_dir)
    local loaded, config = jsontools.load_from_file(vim.fs.joinpath(config_dir, "window.json"))
    if loaded then
        _loop_win_height_ratio = config.height
    end
end

function M.setup(_)
    if setup_done then
        error('Loop.nvim: setup() cannot be called more than once')
        return
    end
    -- setup only once
    setup_done = true

    do
        vim.api.nvim_set_hl(0, "LoopPluginInactiveTab", { link = "WinBar" })
        vim.api.nvim_set_hl(0, "LoopPluginActiveTab", { link = "Special" })
        vim.api.nvim_set_hl(0, "LoopPluginEventWarn", { link = "WarningMsg" })
        vim.api.nvim_set_hl(0, "LoopPluginEventsError", { link = "ErrorMsg" })
    end

    vim.api.nvim_create_autocmd("WinEnter", { callback = _on_window_enter })

    vim.api.nvim_create_autocmd("WinNew", {
        callback = function(_)
            _on_win_new_or_close()
        end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        callback = function(args)
            local closed_winid = tonumber(args.match)
            if closed_winid == _loop_win then
                _loop_win = -1
            else
                _on_win_new_or_close()
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        callback = function()
            local win = vim.api.nvim_get_current_win()
            if win == _loop_win then
                local buf = vim.api.nvim_win_get_buf(win)
                protect_split_window_buffer(buf)
            end
        end,
    })
end

return M
