local Page = require('loop.pages.Page')
local strtools = require('loop.tools.strtools')
local class = require('loop.tools.class')

---@class loop.pages.EventsPage: loop.pages.Page
---@field new fun(self: loop.pages.EventsPage, name:string) : loop.pages.EventsPage
local EventsPage = class(Page)

---@type integer
local events_log_ns = vim.api.nvim_create_namespace("events_log")

---@param buf integer
---@param lines string[]
local function append_lines(buf, lines)
    lines = strtools.clean_and_split_lines(lines)
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

---@param name string
function EventsPage:init(name)
    Page.init(self, "events", name)
    self:follow_last_line()
end

---@param lines string[]
---@param level nil|"info"|"warn"|"error"
function EventsPage:add_events(lines, level)
    local buf = self:get_or_create_buf()

    level = level or "info"
    vim.bo[buf].modifiable = true

    local timestamp = os.date("%H:%M:%S")
    local line_count = vim.api.nvim_buf_line_count(buf)

    local on_last_line = false
    local cur_win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(cur_win) == buf then
        -- Get current cursor position
        local cur = vim.api.nvim_win_get_cursor(cur_win)
        local cur_line = cur[1]
        if cur_line == line_count then
            on_last_line = true
        end
    end

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

    if on_last_line and vim.api.nvim_win_get_buf(cur_win) == buf then
        local last_line = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_win_set_cursor(cur_win, { last_line, 0 })
    end

    vim.bo[buf].modifiable = false
end

return EventsPage
