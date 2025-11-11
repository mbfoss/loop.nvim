local M = {}
local log = require('loop.tools.Logger').create_logger("window")
local Page = require('loop.pages.Page')
local EventsPage = require('loop.pages.EventsPage')
local TaskPage = require('loop.pages.TaskPage')
local BreakpointsPage = require('loop.pages.BreakpointsPage')

local buftools = require('loop.tools.buffer')

---@type boolean
local setup_done = false

---@type number
local loop_win = -1

---@class loop.TabInfo
---@field label string
---@field page any

---@type loop.TabInfo[]
local tabs_data = {
    { label = "Events",      page = nil },
    { label = "Tasks",       page = nil },
    { label = "Breakpoints", page = nil },
}

local events_tab = tabs_data[1]
local tasks_tab = tabs_data[2]
local breakpoints_tab = tabs_data[3]

---@type loop.TabInfo
local active_tab = events_tab

local function resize_split_window()
    if loop_win == -1 then
        return
    end
    local winid = loop_win
    local tab = vim.api.nvim_win_get_tabpage(winid)
    local wins_in_tab = vim.api.nvim_tabpage_list_wins(tab)
    local count = 0
    for _, win in ipairs(wins_in_tab) do
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative == "" then
            count = count + 1
        end
    end
    if count <= 1 then
        return
    end
    vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = winid })
    vim.api.nvim_win_set_height(winid, math.floor(vim.o.lines * 0.25))
end

---@param req_tab loop.TabInfo
local function set_active_tab(req_tab)
    log:log({ "setting active page: ", req_tab.label })
    if loop_win == -1 then
        log:log({ "no active window" })
        return
    end

    local win = loop_win
    local winbar_parts = { "%#LoopPluginInactiveTab#" }
    local tabidx = 0
    for arr_idx, tab in ipairs(tabs_data) do
        if tab.page and tab.page:used() then
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
                buftools.smart_open_buffer(buf)
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
    if loop_win == -1 then
        local prev_win = vim.api.nvim_get_current_win()
        -- Open a bottom split.
        vim.cmd('botright split')
        -- Get the new window ID.
        loop_win = vim.api.nvim_get_current_win()
        resize_split_window()
        vim.api.nvim_set_current_win(prev_win)
    end
    set_active_tab(tab or active_tab)
end

local function on_window_enter()
    -- do not allow our buffers in another window
    local win = vim.api.nvim_get_current_win()
    if win ~= loop_win then
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
function M.update_breakpoints(breakpoints)
    ---@type loop.pages.BreakpointsPage
    local page = breakpoints_tab.page
    assert(getmetatable(page) == BreakpointsPage)
    page:setlist(breakpoints)
    set_active_tab(breakpoints_tab)
end

---@return string[]
function M.tab_names()
    local arr = {}
    for _, t in ipairs(tabs_data) do
        if t.page:used() then
            table.insert(arr, t.label)
        end
    end
    return arr
end

---@param tabname string|nil
function M.show_window(tabname)
    assert(setup_done)
    local tab = nil
    if tabname then
        for _, t in ipairs(tabs_data) do
            if t.page:used() and tabname == t.label then
                tab = t
                break
            end
        end
    end
    create_window(tab)
end

function M.hide_window()
    assert(setup_done)
    if loop_win and vim.api.nvim_win_is_valid(loop_win) then
        vim.api.nvim_win_close(loop_win, false)
        loop_win = -1
    end
end

---@return boolean
function M.toggle_window()
    assert(setup_done)
    if loop_win ~= -1 then
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

---@param label string
function M.create_task_buffer(label)
    assert(setup_done)
    tasks_tab.label = label

    ---@type loop.pages.TaskPage
    local page = tasks_tab.page
    assert(getmetatable(page) == TaskPage)
    return page:new_buf()
end

local function _on_buf_enter(page)
    --- don't set keymaps if outside loop_win
    if vim.api.nvim_get_current_win() ~= loop_win then
        return
    end
    local idx = 0
    for _, tab in ipairs(tabs_data) do
        if tab.page and tab.page:used() then
            idx = idx + 1
            if tab.page ~= page  then
                local key = tostring(idx)
                page:set_keymap(key, function()
                    log:log({ "setting active tab: ", tab.label })
                    set_active_tab(tab)
                end)
            end
        end
    end
end


function M.setup(config)
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
        -- Define a custom highlight group that inherits from 'WinBar'
        local winbar_hl = vim.api.nvim_get_hl(0, { name = "WinBar", link = true })
        local title_hl = vim.api.nvim_get_hl(0, { name = "Title", link = true })
        vim.api.nvim_set_hl(0, "LoopPluginInactiveTab", { fg = winbar_hl.fg, bg = winbar_hl.bg, })
        vim.api.nvim_set_hl(0, "LoopPluginActiveTab",
            { fg = title_hl.fg, bg = title_hl.bg, underline = true, bold = true })

        vim.api.nvim_set_hl(0, "LoopPluginEventInfo", { link = "Normal" })
        vim.api.nvim_set_hl(0, "LoopPluginEventWarn", { link = "DiagnosticWarn" })
        vim.api.nvim_set_hl(0, "LoopPluginEventsError", { link = "DiagnosticError" })
        vim.api.nvim_set_hl(0, "LoopBreakpointsCursorLine", { link = "Visual" })
    end

    vim.api.nvim_create_autocmd("WinEnter", { callback = on_window_enter })

    vim.api.nvim_create_autocmd("WinNew", {
        callback = function(args)
            resize_split_window()
        end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        callback = function(args)
            local closed_winid = tonumber(args.match)
            if closed_winid == loop_win then
                log:log("detected window close")
                loop_win = -1
            else
                resize_split_window()
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        callback = function()
            local win = vim.api.nvim_get_current_win()
            if win == loop_win then
                local buf = vim.api.nvim_win_get_buf(win)
                protect_split_window_buffer(buf)
            end
        end,
    })
end

return M
