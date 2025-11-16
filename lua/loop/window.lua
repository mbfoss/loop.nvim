local M = {}
local log = require('loop.tools.Logger').create_logger("window")
local Page = require('loop.pages.Page')
local EventsPage = require('loop.pages.EventsPage')
local TaskPage = require('loop.pages.TaskPage')
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
---@field page any
---@field used boolean

---@type loop.TabInfo[]
local tabs_data = {
    { label = "Events",      page = nil, used = true },
    { label = "Task",        page = nil, used = false },
    { label = "Breakpoints", page = nil, used = false },
    { label = "Debug",       page = nil, used = false },
}

local events_tab = tabs_data[1]
local tasks_tab = tabs_data[2]
local breakpoints_tab = tabs_data[3]

---@type loop.TabInfo
local active_tab = events_tab

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

---@param req_tab loop.TabInfo
local function set_active_tab(req_tab)
    req_tab.used = true
    log:log({ "setting active page: ", req_tab.label })
    if _loop_win == -1 then
        log:log({ "no active window" })
        return
    end
    local win = _loop_win
    local winbar_parts = { "%#LoopPluginInactiveTab#" }
    local tabidx = 0
    for arr_idx, tab in ipairs(tabs_data) do
        if tab.page and tab.used then
            tabidx = tabidx + 1
            if tabidx ~= 1 then table.insert(winbar_parts, '|') end
            local active = false
            if req_tab == tab then
                active = true
                active_tab = tab
                local buf = tab.page:get_buf()
                vim.api.nvim_win_set_buf(win, buf)
            end
            if active then table.insert(winbar_parts, "%#LoopPluginActiveTab#") end
            local label = ' [' .. tostring(tabidx) .. ']' .. tab.label .. ' '
            table.insert(winbar_parts, string.format("%%%d@v:lua.LoopProject._winbar_click@%s%%T", arr_idx, label))
            if active then table.insert(winbar_parts, "%#LoopPluginInactiveTab#") end
        end
    end
    vim.wo[win].winbar = table.concat(winbar_parts, '')
end

local function protect_split_window_buffer(buf)
    if not Page.is_page(buf) then
        vim.schedule(function()
            set_active_tab(active_tab)
            if vim.api.nvim_buf_is_valid(buf) then
                uitools.smart_open_buffer(buf)
            end
        end)
    end
end

function M.winbar_click(id, clicks, button, mods)
    --local message = string.format("Clicked on ID: %s, Clicks: %d, Button: %s, Mods: %s", id, clicks, button, mods)
    local tab = tabs_data[id]
    if tab then
        set_active_tab(tab)
    end
end

---@param tab loop.TabInfo | nil
local function create_window(tab)
    if _loop_win ~= -1 then
        set_active_tab(tab or active_tab)
        return
    end

    local prev_win = vim.api.nvim_get_current_win()
    -- Open a bottom split.
    vim.cmd('botright split')
    -- Get the new window ID.
    _loop_win = vim.api.nvim_get_current_win()
    _on_win_new_or_close()
    vim.api.nvim_set_current_win(prev_win)

    set_active_tab(tab or active_tab)

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

local function on_window_enter()
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

    ---@type loop.pages.EventsPage
    local page = events_tab.page
    assert(getmetatable(page) == EventsPage)
    page:add_events(lines, level)
    if level == "error" then
        M.show_events()
    end
end

---@param breakpoints table<string, integer[]>
---@param proj_dir string
function M.update_breakpoints(breakpoints, proj_dir)
    ---@type loop.pages.BreakpointsPage
    local page = breakpoints_tab.page
    assert(getmetatable(page) == BreakpointsPage)
    page:setlist(breakpoints, proj_dir)
    set_active_tab(breakpoints_tab)
end

---@return string[]
function M.tab_names()
    local arr = {}
    for _, t in ipairs(tabs_data) do
        if t.used then
            table.insert(arr, t.label)
        end
    end
    return arr
end

---@param tabname? string
function M.show_window(tabname)
    assert(setup_done)
    local tab = nil
    if tabname then
        for _, t in ipairs(tabs_data) do
            if tabname == t.label then
                tab = t
                break
            end
        end
    end
    create_window(tab)
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
    create_window(events_tab)
end

function M.show_task_output()
    create_window(tasks_tab)
end

---@param bufnr number
---@param name string -- task name
function M.add_task_buffer(bufnr, name)
    assert(setup_done)
    ---@type loop.pages.TaskPage
    local page = tasks_tab.page
    assert(getmetatable(page) == TaskPage)
    tasks_tab.label = name
    page:assign_buf(bufnr)
end

local function _on_buf_enter(page)
    --- don't set keymaps if outside _loop_win
    if vim.api.nvim_get_current_win() ~= _loop_win then
        return
    end
    local idx = 0
    for _, tab in ipairs(tabs_data) do
        if tab.page and tab.used then
            idx = idx + 1
            if tab.page ~= page then
                local key = tostring(idx)
                page:set_keymap(key, function()
                    log:log({ "setting active tab: ", tab.label })
                    set_active_tab(tab)
                end)
            end
        end
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

    -- create pages
    do
        events_tab.page      = EventsPage:new("loop-events", _on_buf_enter)
        tasks_tab.page       = TaskPage:new("loop-tasks", _on_buf_enter)
        breakpoints_tab.page = BreakpointsPage:new("loop-breakpoints", _on_buf_enter)
    end

    do
        vim.api.nvim_set_hl(0, "LoopPluginInactiveTab", { link = "WinBar" })
        vim.api.nvim_set_hl(0, "LoopPluginActiveTab", { link = "Special" })
        vim.api.nvim_set_hl(0, "LoopPluginEventInfo", { link = "Normal" })
        vim.api.nvim_set_hl(0, "LoopPluginEventWarn", { link = "DiagnosticWarn" })
        vim.api.nvim_set_hl(0, "LoopPluginEventsError", { link = "DiagnosticError" })
    end

    vim.api.nvim_create_autocmd("WinEnter", { callback = on_window_enter })

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
