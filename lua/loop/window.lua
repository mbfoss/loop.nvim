local M = {}
local log = require('loop.tools.Logger').create_logger("window")
local Page = require('loop.pages.Page')
local EventsPage = require('loop.pages.EventsPage')
local TaskPage = require('loop.pages.TaskPage')
local DebugTaskPage = require('loop.pages.DebugTaskPage')
local BreakpointsPage = require('loop.pages.BreakpointsPage')
local uitools = require('loop.tools.uitools')
local jsontools = require('loop.tools.json')

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


local _tabs = {
    ---@type loop.TabInfo
    events = { label = "Events", pages = { EventsPage:new() }, active_page_idx = 1 },
    ---@type loop.TabInfo
    tasks = { label = "Tasks", pages = {} },
    ---@type loop.TabInfo
    breakpoints = { label = "Breakpoints", pages = {} },
    ---@type loop.TabInfo
    debug = { label = "Debug", pages = {} },
}

local _tabs_arr = { _tabs.events, _tabs.tasks, _tabs.breakpoints, _tabs.debug }

---@type loop.TabInfo
local _active_tab = _tabs.events

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


---@param tab loop.TabInfo
local function _tab_key_handler(target_tab, setup_active_tab)
    if vim.api.nvim_get_current_win() ~= _loop_win then
        return
    end
    if target_tab == _active_tab then
        if #_active_tab.pages > 1 then
            local idx = _active_tab.active_page_idx
            idx = idx and (idx + 1) or 1
            if idx > #_active_tab.pages then
                idx = 1
            end
            _active_tab.active_page_idx = idx
        end
    end
    setup_active_tab(target_tab)
end

---@param req_tab loop.TabInfo
local function _setup_active_tab(req_tab)
    if #req_tab.pages == 0 then
        req_tab = _tabs.events
    end

    log:log({ "setting active page: ", req_tab.label })

    local page_idx = req_tab.active_page_idx or 1
    assert(page_idx > 0 and page_idx <= #req_tab.pages)

    --- set keymaps
    do
        local keymaps = {}
        local idx = 0
        for _, tab in ipairs(_tabs_arr) do
            if #tab.pages > 0 then
                idx = idx + 1
                local key = tostring(idx)
                keymaps[key] = function()
                    _tab_key_handler(tab, _setup_active_tab)
                end
            end
        end
        req_tab.pages[page_idx]:set_keymaps(keymaps)
    end

    -- update window if visible
    if _loop_win ~= -1 then
        local win = _loop_win
        local winbar_parts = { "%#LoopPluginInactiveTab#" }
        local tabidx = 0
        for arr_idx, tab in ipairs(_tabs_arr) do
            local active = false
            if req_tab == tab then
                active = true
                _active_tab = tab
                local buf = tab.pages[page_idx]:get_or_create_buf()
                vim.api.nvim_win_set_buf(win, buf)
            end
            if #tab.pages > 0 then
                tabidx = tabidx + 1
                if tabidx ~= 1 then table.insert(winbar_parts, '|') end
                if active then table.insert(winbar_parts, "%#LoopPluginActiveTab#") end
                local label = ' [' .. tostring(tabidx) .. '] ' .. tab.label
                if active and tab.active_page_idx then
                    local name = _active_tab.pages[_active_tab.active_page_idx or 1]:get_name()
                    if #tab.pages > 1 then
                        label = label .. ' - ' .. tab.active_page_idx .. '/' .. #tab.pages         
                    end
                    if name then label = label .. ' - ' .. name end
                elseif #tab.pages > 1 then
                    label = label .. ' (' .. #tab.pages .. ')'
                end
                label = label .. ' '
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

local function protect_split_window_buffer(buf)
    if not Page.is_page(buf) then
        vim.schedule(function()
            _setup_active_tab(_active_tab)
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
        _setup_active_tab(tab or _active_tab)
        return
    end

    local prev_win = vim.api.nvim_get_current_win()
    -- Open a bottom split.
    vim.cmd('botright split')
    -- Get the new window ID.
    _loop_win = vim.api.nvim_get_current_win()
    _on_win_new_or_close()
    vim.api.nvim_set_current_win(prev_win)

    _setup_active_tab(tab or _active_tab)

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
            log:info("dropping buffer from non-split window")
            local bufnr = vim.api.nvim_create_buf(true, true)
            vim.api.nvim_win_set_buf(win, bufnr)
        end
    end
end

---@param lines string[]
---@param level nil|"info"|"warn"|"error"
function M.add_events(lines, level)
    assert(setup_done)

    ---@type loop.pages.EventsPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = _tabs.events.pages[1]
    assert(page)
    assert(getmetatable(page) == EventsPage)
    page:add_events(lines, level)
    if level == "error" then
        M.show_events()
    end
end

---@param breakpoints table<string, integer[]>
---@param proj_dir string
function M.update_breakpoints(breakpoints, proj_dir)
    assert(setup_done)
    if #_tabs.breakpoints.pages == 0 then
        table.insert(_tabs.breakpoints.pages, BreakpointsPage:new())
    end
    ---@type loop.pages.BreakpointsPage
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = _tabs.breakpoints.pages[1]
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
    _setup_active_tab(_tabs.events)
    for _, page in ipairs(_tabs.tasks.pages) do
        page:destroy()
    end
    _tabs.tasks.pages = {}
    _tabs.tasks.active_page_idx = nil
end

---@param name string -- task name
---@param bufnr number
function M.add_term_task(name, bufnr)
    assert(setup_done)
    assert(type(name) == "string")
    assert(vim.api.nvim_buf_is_valid(bufnr))

    local page = TaskPage:new()
    page:set_name(name)
    page:assign_buf(bufnr)

    table.insert(_tabs.tasks.pages, page)
    _tabs.tasks.active_page_idx = #_tabs.tasks.pages

    _setup_active_tab(_tabs.tasks)
end

---@param name string -- task name
---@param debugjob loop.job.DebugJob
function M.add_debug_task(name, debugjob)
    assert(setup_done)
    assert(type(name) == "string")
    
    local page = DebugTaskPage:new()
    page:set_name(name)
    
    local init_sessions = debugjob:track_sessions(function (id, session)
        page:add_session(id, session)
    end)
    page:set_session_list(init_sessions)

    table.insert(_tabs.tasks.pages, page)
    _tabs.tasks.active_page_idx = #_tabs.tasks.pages

    _setup_active_tab(_tabs.tasks)    
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
        vim.api.nvim_set_hl(0, "LoopPluginEventInfo", { link = "Normal" })
        vim.api.nvim_set_hl(0, "LoopPluginEventWarn", { link = "DiagnosticWarn" })
        vim.api.nvim_set_hl(0, "LoopPluginEventsError", { link = "DiagnosticError" })
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
                log:log("detected window close")
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
