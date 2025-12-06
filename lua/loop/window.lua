local M = {}
local Page = require('loop.pages.Page')
local OutputPage = require('loop.pages.OutputPage')
local BreakpointsPage = require('loop.pages.BreakpointsPage')
local ItemListPage = require('loop.pages.ItemListPage')
local ItemTreePage = require('loop.pages.ItemTreePage')
local StackTracePage = require('loop.pages.StackTracePage')
local uitools = require('loop.tools.uitools')
local jsontools = require('loop.tools.json')
local selector = require("loop.selector")

---@class loop.TabInfo
---@field label string
---@field pages loop.pages.Page[]
---@field active_page_idx number|nil
---@field list_prefix string|nil

---@type boolean
local setup_done = false

---@type number
local _loop_win = -1
---@type number
local _loop_win_height_ratio
---@type fun(action: "next"|"prev")
local _cycle_pages
---@type fun()
local _ui_select_page

local _tabs = {
    ---@type loop.TabInfo
    build = { label = "Build", pages = {}, list_prefix = "Build - " },
    ---@type loop.TabInfo
    run = { label = "Run", pages = {}, list_prefix = "Run - " },
    ---@type loop.TabInfo
    debug = { label = "Debug", pages = {}, list_prefix = "Debug - " },
    ---@type loop.TabInfo
    breakpoints = { label = "Breakpoints", pages = {} },
    ---@type loop.TabInfo
    debug_output = { label = "Debug Console", pages = {}, list_prefix = "Debug Console - " },
    ---@type loop.TabInfo
    threads = { label = "Threads", pages = {}, list_prefix = "Threads - " },
    ---@type loop.TabInfo
    stacktrace = { label = "Call Stack", pages = {}, list_prefix = "Call Stack - " },
    ---@type loop.TabInfo
    variables = { label = "Variables", pages = {}, list_prefix = "Variables - " },
}

local _tabs_arr = {
    _tabs.build,
    _tabs.run,
    _tabs.debug,
    _tabs.breakpoints,
    _tabs.debug_output,
    _tabs.threads,
    _tabs.stacktrace,
    _tabs.variables
}

---@type number
local _active_tab_idx = 1

---@param tab loop.TabInfo
---@return number
local function _get_tab_index(tab)
    for idx, t in ipairs(_tabs_arr) do
        if t == tab then return idx end
    end
    return 0
end

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
end

local function _setup_tabs()
    if _loop_win == -1 then
        return
    end

    local active_tab = _tabs_arr[_active_tab_idx]
    if #active_tab.pages == 0 then
        return
    end

    local page_idx = active_tab.active_page_idx or 1
    assert(page_idx > 0 and page_idx <= #active_tab.pages)

    -- update window if visible
    local win = _loop_win
    local winbar_parts = { "%#LoopPluginInactiveTab#" }
    local tabidx = 0
    for arr_idx, tab in ipairs(_tabs_arr) do
        local active = false
        if active_tab == tab then
            _active_tab_idx = arr_idx
            active = true
            local buf = tab.pages[page_idx]:get_or_create_buf()
            vim.api.nvim_win_set_buf(win, buf)
        end
        if #tab.pages > 0 then
            tabidx = tabidx + 1
            if tabidx ~= 1 then table.insert(winbar_parts, '|') end
        end
        if #tab.pages == 1 then
            local str = (" %s "):format(tab.label)
            if active then table.insert(winbar_parts, "%#LoopPluginActiveTab#") end
            table.insert(winbar_parts, string.format("%%%d@v:lua.LoopProject._winbar_click@%s%%T", arr_idx * 1000, str))
            if active then table.insert(winbar_parts, "%#LoopPluginInactiveTab#") end
        end
        if #tab.pages > 1 then
            local str = (" %s "):format(tab.label)
            table.insert(winbar_parts, string.format("%%%d@v:lua.LoopProject._winbar_click@%s%%T", arr_idx * 1000, str))
            for idx, page in ipairs(tab.pages) do
                local active_page = active and idx == page_idx
                local str2 = '[' .. tostring(idx) .. ']'
                if active_page then table.insert(winbar_parts, "%#LoopPluginActiveTab#") end
                table.insert(winbar_parts,
                    string.format("%%%d@v:lua.LoopProject._winbar_click@%s%%T", arr_idx * 1000 + idx, str2))
                if active_page then table.insert(winbar_parts, "%#LoopPluginInactiveTab#") end
            end
            table.insert(winbar_parts, ' ')
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


---@param req_tabidx number
---@param req_pageidx number|nil
local function _set_active_tab(req_tabidx, req_pageidx)
    local req_tab = _tabs_arr[req_tabidx]
    assert(req_tab)
    if not req_tab or #req_tab.pages == 0 then
        return
    end
    _active_tab_idx = req_tabidx
    if req_pageidx and req_pageidx > 0 and req_pageidx <= #req_tab.pages then
        req_tab.active_page_idx = req_pageidx
    end
    _setup_tabs()
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

    _set_active_tab(tabidx, pageidx)
end

_ui_select_page = function()
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
            _set_active_tab(data.tabidx, data.pageix)
        end
    end)
end

---@return table<string,loop.pages.page.KeyMap>
local function get_page_keymap()
    --- set keymaps
    ---@type table<string,loop.pages.page.KeyMap>
    local keymaps = {
        ["<c-p>"] = {
            callback = function()
                if vim.api.nvim_get_current_win() == _loop_win then
                    _cycle_pages("prev")
                end
            end,
            desc = "Move to next page",
        },
        ["<c-n>"] = {
            callback = function()
                if vim.api.nvim_get_current_win() == _loop_win then
                    _cycle_pages("next")
                end
            end,
            desc = "Move to previous page",
        },
        ["<c-l>"] = {
            callback = function()
                if vim.api.nvim_get_current_win() == _loop_win then
                    _ui_select_page()
                end
            end,
            desc = "Select page",
        },
    }
    return keymaps
end

---@param tab loop.TabInfo
local function _delete_tab_pages(tab)
    for _, page in ipairs(tab.pages) do
        page:destroy()
    end
    tab.pages = {}
    tab.active_page_idx = nil
end

---@param tab loop.TabInfo
---@param page loop.pages.Page
local function _add_tab_page(tab, page)
    page:add_keymaps(get_page_keymap())
    table.insert(tab.pages, page)
    tab.active_page_idx = #tab.pages
    _setup_tabs()
end

local function protect_split_window_buffer(buf)
    if not Page.is_page(buf) then
        local name =
            uitools.is_regular_buffer(buf)
            and vim.api.nvim_buf_get_name(buf) or nil
        vim.schedule(function()
            _setup_tabs()
            if name then
                uitools.smart_open_file(name, nil, nil)
            end
        end)
    end
end

function M.winbar_click(id, clicks, button, mods)
    local tab_idx = math.floor(id / 1000)
    local page_idx = id % 1000

    if _active_tab_idx ~= tab_idx then
        _set_active_tab(tab_idx, nil)
    else
        local tab = _tabs_arr[tab_idx]
        if tab then
            if page_idx and page_idx > 0 then
                _set_active_tab(tab_idx, page_idx)
            else
                local pageidx = tab.active_page_idx + 1
                if pageidx > #tab.pages then pageidx = 1 end
                _set_active_tab(tab_idx, pageidx)
            end
        end
    end
end

local function create_window()
    if _loop_win ~= -1 then
        return
    end

    do
        local tab = _tabs_arr[_active_tab_idx]
        if not tab or not tab.pages[tab.active_page_idx] then
            local page = OutputPage:new("")
            _add_tab_page(_tabs.build, page)
            _set_active_tab(_get_tab_index(_tabs.build), nil)
        end
    end

    local prev_win = vim.api.nvim_get_current_win()
    -- Open a bottom split.
    vim.cmd('bot split')
    -- Get the new window ID.
    _loop_win = vim.api.nvim_get_current_win()
    if _loop_win_height_ratio then
        vim.api.nvim_win_set_height(_loop_win, math.floor(vim.o.lines * _loop_win_height_ratio))
    else
        vim.api.nvim_win_set_height(_loop_win, math.floor(vim.o.lines * 0.17))
    end
    vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = _loop_win })
    vim.api.nvim_set_current_win(prev_win)
    vim.wo[_loop_win].spell = false

    _setup_tabs()

    vim.api.nvim_create_autocmd("WinResized", {
        callback = function()
            if _loop_win ~= -1 then
                local height = vim.api.nvim_win_get_height(_loop_win)
                local ratio = height / vim.o.lines
                -- only save of we are not the only window vertically
                if ratio < 0.7 then
                    _loop_win_height_ratio = ratio
                end
            end
        end,
    })
end

-- remove winbar after split
local function _on_window_enter()
    local winid = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(winid)
    if winid ~= _loop_win and Page.is_page(buf) then
        local winbar = vim.wo[winid].winbar
        if type(winbar) == 'string' and winbar:match('v:lua.LoopProject._winbar_click') then
            vim.wo[winid].winbar = nil
        end
    end
end

local function _ensure_breakpoints_page()
    assert(setup_done)
    local page = _tabs.breakpoints.pages[1]
    if not page then
        page = BreakpointsPage:new()
        _add_tab_page(_tabs.breakpoints, page)
    end
end

function M.show_window()
    assert(setup_done)
    create_window()
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

function M.remove_task_pages()
    _delete_tab_pages(_tabs.build)
    _delete_tab_pages(_tabs.run)
    _delete_tab_pages(_tabs.debug)
    _delete_tab_pages(_tabs.debug_output)
    _delete_tab_pages(_tabs.stacktrace)
    _delete_tab_pages(_tabs.variables)
end

---@param type "build"|"run"|"debug"|"debugoutput"|"stacktrace"|"variables"
---@param page loop.pages.Page
function M.add_page(type, page)
    assert(setup_done)
    local tab
    local activate
    if type == "build" then
        tab = _tabs.build
        activate = true
    elseif type == "run" then
        tab = _tabs.run
        activate = true
    elseif type == "debug" then
        tab = _tabs.debug
        activate = true
    elseif type == "debugoutput" then
        tab = _tabs.debug_output
    elseif type == "stacktrace" then
        tab = _tabs.stacktrace
    elseif type == "variables" then
        tab = _tabs.variables
    end
    assert(tab)
    _add_tab_page(tab, page)
    if activate then
        _set_active_tab(_get_tab_index(tab), nil)
        create_window()
    end
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

    -- ensure breakpoints page is shown if there are breakpoints
    require('loop.dap.breakpoints').add_tracker({
        on_added = function() _ensure_breakpoints_page() end
    })

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
