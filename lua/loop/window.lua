local M = {}
local log = require('loop.tools.Logger').create_logger("window")
local buftools = require('loop.tools.buffer')
local buffer_flag_key = "loopplugin_efc0bed4-145b"

---@type boolean
local setup_done = false

---@type number
local loop_win = -1

---@class loop.TabInfo
---@field filetype string
---@field label string
---@field active_buf number
---@field follow boolean

---@type loop.TabInfo[]
local tabs_data = {
    { filetype = "loop-events",      label = "Events",      active_buf = -1, follow = true },
    { filetype = "loop-tasks",       label = "Tasks",       active_buf = -1, follow = true },
    { filetype = "loop-breakpoints", label = "Breakpoints", active_buf = -1, follow = false },
}

---@type loop.TabInfo
local events_tab = tabs_data[1]
---@type loop.TabInfo
local tasks_tab = tabs_data[2]

---@type loop.TabInfo
local active_tab = events_tab

---@type integer
local events_log_ns = vim.api.nvim_create_namespace("events_log")

---@param buf integer
---@param lines string[]
local function append_lines(buf, lines)
    for i, s in ipairs(lines) do
        lines[i] = s:gsub("\n", "") -- removes all `\n`
    end
    local count = vim.api.nvim_buf_line_count(buf)
    -- If buffer is empty and first line is "", replace instead of append
    if count == 1 then
        local firstln = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
        if firstln == "" then
            vim.api.nvim_buf_set_lines(buf, 0, 1, false, lines)
            return
        end
    end
    -- Otherwise, append at end
    vim.api.nvim_buf_set_lines(buf, count, count, false, lines)
end

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

---@param buf number
---@param set_active_tab fun(tab: loop.TabInfo)
local function set_keymaps(buf, set_active_tab)
    local modes = { "n", "t" }
    local idx = 0
    for _, tab in ipairs(tabs_data) do
        if tab.active_buf ~= -1 then
            idx = idx + 1
            local key = tostring(idx)
            for _, mode in ipairs(modes) do
                local ok, err = pcall(vim.api.nvim_buf_del_keymap, buf, mode, key)
                log:log({ 'remove keymap ', ok, err })
            end
            vim.keymap.set(modes, key, function()
                log:log({ "setting active tab: ", tab.filetype })
                set_active_tab(tab)
            end, { buffer = buf })
        end
    end
end

---@param tab loop.TabInfo
---@param set_active_tab fun(tab: loop.TabInfo)
---@return number, boolean
local function get_or_create_tab_buff(tab, set_active_tab)
    if tab.active_buf ~= -1 then
        return tab.active_buf, false
    end

    tab.active_buf = vim.api.nvim_create_buf(false, true)

    log:log('buffer created for ' .. tab.filetype)
    log:log(tab)

    local buf = tab.active_buf
    vim.api.nvim_buf_set_var(buf, buffer_flag_key, 1)

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = tab.filetype
    vim.bo[buf].modifiable = false

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer = buf,
        once = true,
        callback = function()
            log:log('buffer deleted from ' .. tab.filetype)
            log:log(tab)
            if buf == tab.active_buf then
                tab.active_buf = -1
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = buf,
        callback = function()
            log:log("buf enter: win = " .. tostring(vim.api.nvim_get_current_win()) .. " buf " .. tostring(buf))
            --- don't set keymaps if outside loop_win (mainly because of the Quickfix buffer)
            if vim.api.nvim_get_current_win() == loop_win then
                set_keymaps(buf, set_active_tab)
            end
        end,
    })

    return buf, true
end

---@param req_tab loop.TabInfo
local function set_active_tab(req_tab)
    log:log({ "setting active page: ", req_tab.filetype })
    if loop_win == -1 then
        log:log({ "no active window" })
        return
    end
    local win = loop_win
    local winbar_parts = { "%#LoopPluginInactiveTab#" }
    local tabidx = 0
    for _, tab in ipairs(tabs_data) do
        if tab.active_buf ~= -1 then
            tabidx = tabidx + 1
            if tabidx ~= 1 then table.insert(winbar_parts, '|') end
            local active = false
            if req_tab == tab then
                active = true
                active_tab = tab
                local bufnr = get_or_create_tab_buff(active_tab, set_active_tab)
                vim.api.nvim_win_set_buf(win, bufnr)
                if tab.follow then
                    local last_line = vim.api.nvim_buf_line_count(bufnr)
                    vim.api.nvim_win_set_cursor(win, { last_line, 0 })
                end
            end
            if active then table.insert(winbar_parts, "%#LoopPluginActiveTab#") end
            local label = ' [' .. tostring(tabidx) .. ']' .. tab.label .. ' '
            table.insert(winbar_parts, string.format("%%%d@v:lua.LoopProject._winbar_click@%s%%T", tabidx, label))
            if active then table.insert(winbar_parts, "%#LoopPluginInactiveTab#") end
        end
    end
    vim.wo[win].winbar = table.concat(winbar_parts, '')
end

local function protect_split_window_buffer(buf)
    local owned, _ = pcall(vim.api.nvim_buf_get_var, buf, buffer_flag_key)
    if not owned then
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
    if loop_win and win ~= loop_win then
        local buf = vim.api.nvim_win_get_buf(win)
        for _, tab in ipairs(tabs_data) do
            if buf == tab.active_buf then
                log:info("dropping buffer from non-split window")
                local bufnr = vim.api.nvim_create_buf(true, true)
                vim.api.nvim_win_set_buf(win, bufnr)
                break
            end
        end
    end
end

---@param lines string[]
---@param level nil|"info"|"warn"|"error"
function _add_events(lines, level)
    local buf, buf_created = get_or_create_tab_buff(events_tab, set_active_tab)
    if buf_created then
        vim.api.nvim_buf_set_name(buf, "Events")
    end

    level = level or "info"
    vim.bo[buf].modifiable = true

    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local line_count = vim.api.nvim_buf_line_count(buf)

    -- Prepare formatted lines
    local formatted_lines = {}
    local prefixes = {}
    for _, line in ipairs(lines) do
        local prefix = timestamp
        table.insert(formatted_lines, prefix .. " " .. line)
        table.insert(prefixes, prefix)
    end

    local hl_groups = {
        info = "LoopPluginEventInfo",
        warn = "LoopPluginEventWarn",
        error = "LoopPluginEventsError"
    };
    local hl_group = hl_groups[level or 'info']

    -- Append lines first
    append_lines(buf, formatted_lines)

    -- Highlight the prefix safely
    for i, prefix in ipairs(prefixes) do
        local row = line_count + i - 1
        -- Get actual line text to avoid out-of-range errors
        local line_text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
        local end_col = math.min(#prefix, #line_text) -- cap at line length
        vim.api.nvim_buf_set_extmark(buf, events_log_ns, row, 0, {
            end_col = end_col,
            hl_group = hl_group,
        })
    end

    vim.bo[buf].modifiable = false

    -- Scroll to end if following
    if events_tab.follow and loop_win > 0 and vim.api.nvim_win_get_buf(loop_win) == buf then
        local last_line = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_win_set_cursor(loop_win, { last_line, 0 })
    end
end

---@param lines string[]
---@param level nil|"info"|"warn"|"error"
function M.add_events(lines, level)
    assert(setup_done)
    _add_events(lines, level)
    if level == "error" then
    end
end

---@return string[]
function M.tab_names()
    local arr = {}
    for _,t in ipairs(tabs_data) do
        if t.active_buf ~= -1 then
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
        for _,t in ipairs(tabs_data) do
            if t.active_buf ~= -1 and tabname == t.label then
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
    ---@type loop.TabInfo
    --- parallel tasks are not supportet,
    --- delete the previous buffer if any
    if tasks_tab.active_buf ~= -1 then
        vim.api.nvim_buf_delete(tasks_tab.active_buf, { force = true })
        assert(tasks_tab.active_buf == -1)
    end
    tasks_tab.label = label
    return get_or_create_tab_buff(tasks_tab, set_active_tab)
end

function M.setup(config)
    if setup_done then
        error('Loop.nvim: setup() cannot be called more than once')
        return
    end
    setup_done = true

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
