local Page = require('loop.pages.Page')
local class = require('loop.tools.class')

---@class loop.pages.OutputPage: loop.pages.Page
---@field new fun(self: loop.pages.OutputPage) : loop.pages.OutputPage
local OutputPage = class(Page)

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

function OutputPage:init()
    Page.init(self, "loop-events")
end

---@param lines string[]
---@param level nil|"info"|"warn"|"error"
function OutputPage:add_events(lines, level)
    local buf = self:get_or_create_buf()

    level = level or "info"
    vim.bo[buf].modifiable = true

    local timestamp = os.date("%H:%M:%S")
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
end

return OutputPage
