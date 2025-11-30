local M = {}
local Page = require('loop.pages.Page')
local OutputPage = require('loop.pages.OutputPage')
local ItemListPage = require('loop.pages.ItemListPage')
local ItemTreePage = require('loop.pages.ItemTreePage')
local BreakpointsPage = require('loop.pages.BreakpointsPage')
local StackTracePage = require('loop.pages.StackTracePage')
local uitools = require('loop.tools.uitools')
local jsontools = require('loop.tools.json')
local selector = require("loop.selector")
local signs = require('loop.signs')

---@class loop.TabInfo
---@field index number
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
    events = { index = 1, label = "Messages", pages = {}, active_page_idx = 1 },
    ---@type loop.TabInfo
    breakpoints = { index = 2, label = "Breakpoints", pages = {} },
    ---@type loop.TabInfo
    tasks = { index = 3, label = "Task", pages = {}, list_prefix = "Task - " },
    ---@type loop.TabInfo
    debug_sessions = { index = 4, label = "Debug Sessions", pages = {} },
    ---@type loop.TabInfo
    debug_output = { index = 5, label = "Debug Console", pages = {}, list_prefix = "Debug Console - " },
    ---@type loop.TabInfo
    threads = { index = 6, label = "Threads", pages = {}, list_prefix = "Threads - " },
    ---@type loop.TabInfo
    stacktrace = { index = 7, label = "Call Stack", pages = {}, list_prefix = "Call Stack - " },
}

local _tabs_arr = (function()
    local arr = {}
    for _, t in pairs(_tabs) do
        assert(not arr[t.index])
        arr[t.index] = t
    end
    return arr
end)()

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

local function _setup_tabs()
    if _loop_win == -1 then
        return
    end

    local active_tab = _tabs_arr[_active_tab_idx]
    if #active_tab.pages == 0 then
        active_tab = _tabs.events
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
            desc = "Move to previous page",
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
    assert(tab ~= _tabs.events)
    _setup_tabs()
    for _, page in ipairs(tab) do
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
    if _active_tab_idx ~= id then
        _set_active_tab(id, nil)
    else
        local tab = _tabs_arr[id]
        if tab then
            local pageidx = tab.active_page_idx + 1
            if pageidx > #tab.pages then pageidx = 1 end
            _set_active_tab(id, pageidx)
        end
    end
end

local function create_window()
    if _loop_win ~= -1 then
        return
    end

    local prev_win = vim.api.nvim_get_current_win()
    -- Open a bottom split.
    vim.cmd('botright split')
    -- Get the new window ID.
    _loop_win = vim.api.nvim_get_current_win()
    _on_win_new_or_close()
    vim.api.nvim_set_current_win(prev_win)

    _setup_tabs()

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

-- do not allow our buffers in another window
--[[
local function _on_window_enter()
    local win = vim.api.nvim_get_current_win()
    if win ~= _loop_win then
        local buf = vim.api.nvim_win_get_buf(win)
        if Page.is_page(buf) then
            local bufnr = vim.api.nvim_create_buf(true, true)
            vim.api.nvim_win_set_buf(win, bufnr)
        end
    end
end
]] --

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
    for _, line in ipairs(lines) do
        page:add_line(timestamp .. ' ' .. line, level, #timestamp)
    end
    if level == "error" then
        M.show_events()
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

function M.show_events()
    assert(setup_done)
    _set_active_tab(_tabs.events.index, nil)
    create_window()
end

function M.show_task_output()
    _set_active_tab(_tabs.tasks.index, nil)
    create_window()
end

function M.show_stacktrace()
    _set_active_tab(_tabs.stacktrace.index, nil)
    create_window()
end

function M.delete_task_buffers()
    _delete_tab_pages(_tabs.tasks)
    _delete_tab_pages(_tabs.debug_sessions)
    _delete_tab_pages(_tabs.debug_output)
    _delete_tab_pages(_tabs.stacktrace)
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
    _set_active_tab(_tabs.tasks.index, nil)
end

---@param task_name string -- task name
---@return loop.job.debugjob.Tracker
function M.add_debug_task(task_name)
    assert(setup_done)
    assert(type(task_name) == "string")
    -- create page
    local task_page = OutputPage:new(task_name)
    _add_tab_page(_tabs.tasks, task_page)

    local sessionspage = ItemTreePage:new("Debug sessions")
    _add_tab_page(_tabs.debug_sessions, sessionspage)
    created = true

    local output_pages = {}
    local stacktrace_pages = {}

    ---@type loop.job.debugjob.Tracker
    local tracker = {
        on_trace = function(text, level)
            task_page:add_line(text, level)
        end,
        on_sess_added = function(id, name, parent_id)
            sessionspage:add_item({ id = id, text = name }, parent_id)
            task_page:add_line("[" .. name .. "] debug session created")            
        end,
        on_sess_removed = function(id, name)
            sessionspage:remove_item(id)
        end,
        on_sess_state = function (sess_id, name, data)
            task_page:add_line("[" .. name .. "] " .. data.state)
            if data.state == "ended" then
                signs.remove_signs("currentframe")
                local page = stacktrace_pages[sess_id]
                if page then
                    page:clear_content()
                end                
            end
        end,
        on_output = function(sess_id, sess_name, category, output)
            ---@type loop.pages.OutputPage|nil
            ---@diagnostic disable-next-line: assign-type-mismatch
            local page = output_pages[sess_id]
            if not page then
                page = OutputPage:new(sess_name)
                _add_tab_page(_tabs.debug_output, page)
                output_pages[sess_id] = page
            end
            local level = category == "stderr" and "error" or nil
            page:add_line(output, level)
        end,
        on_new_term = function(name, bufnr)
            local page = Page:new("term", name)
            page:assign_buf(bufnr)
            _add_tab_page(_tabs.debug_output, page)
        end,
        on_thread_pause = function(sess_id, sess_name, event_data)
            if not event_data.thread_id then return end
            -- handle current frame sign
            event_data.stack_provider({threadId = event_data.thread_id, levels=1}, function(err, data)
                local topframe = data and data.stackFrames[1] or nil
                if topframe and topframe.source and topframe.source.path then
                    signs.place_file_sign(topframe.source.path, topframe.line, "currentframe", "currentframe")
                    uitools.smart_open_file(topframe.source.path, topframe.line, topframe.column)
                end
            end)
            -- handle stack trace page
            ---@type loop.pages.StackTracePage|nil
            ---@diagnostic disable-next-line: assign-type-mismatch
            local page = stacktrace_pages[sess_id]
            if not page then
                page = StackTracePage:new(sess_name)
                _add_tab_page(_tabs.stacktrace, page)
                stacktrace_pages[sess_id] = page
            end
            page:set_content(event_data)
        end,
        on_thread_continue = function (sess_id, sess_name)
            signs.remove_signs("currentframe")
            local page = stacktrace_pages[sess_id]
            if page then
                page:clear_content()
            end
        end
    }
    return tracker
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

    _tabs.events.pages[1] = OutputPage:new("Messages")
    _tabs.events.pages[1]:add_keymaps(get_page_keymap())

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

    --vim.api.nvim_create_autocmd("WinEnter", { callback = _on_window_enter })

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
