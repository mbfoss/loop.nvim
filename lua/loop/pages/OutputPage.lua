local Page = require('loop.pages.Page')
local strtools = require('loop.tools.strtools')
local class = require('loop.tools.class')

-- namespace for error highlights
local _error_hl_ns = vim.api.nvim_create_namespace("LoopPluginOutputPageHl")

---@class loop.pages.OutputPage: loop.pages.Page
---@field new fun(self: loop.pages.OutputPage, name:string) : loop.pages.OutputPage
local OutputPage = class(Page)


local _hl_groups = {
    warn = "LoopPluginEventWarn",
    error = "LoopPluginEventsError"
};

---@param buf integer
---@param line string
---@param highlight nil|"warn"|"error"
---@param highligh_endcol nil|number
local function append_line(buf, line, highlight, highligh_endcol)
    -- remove all \r
    line = line:gsub("\r", "")
    line = line:gsub("\n", " ")

    local count = vim.api.nvim_buf_line_count(buf)

    local hl_group = _hl_groups[highlight]

    local _highlight_line = function(row)
        local line_text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
        local end_col = #line_text
        if highligh_endcol then
            end_col = math.min(end_col, highligh_endcol)
        end
        vim.api.nvim_buf_set_extmark(buf, _error_hl_ns, row, 0, {
            end_col = end_col,
            hl_group = hl_group,
        })
    end

    -- If buffer is empty and first line is "", replace instead of append
    if count == 1 then
        local firstln = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
        if firstln == "" then
            vim.api.nvim_buf_set_lines(buf, 0, 1, false, { line })
            -- highlight replacement if requested
            if highlight then
                _highlight_line(0)
            end

            return
        end
    end

    -- Append at end
    vim.api.nvim_buf_set_lines(buf, count, count, false, { line })
    -- Highlight newly added lines if requested
    if highlight then
        _highlight_line(count)
    end
end

---@param name string
function OutputPage:init(name)
    Page.init(self, "output", name)
    self:follow_last_line()
end

---@param line string
---@param highlight nil|"warn"|"error"
---@param highligh_endcol nil|number
function OutputPage:add_line(line, highlight, highligh_endcol)
    local buf = self:get_or_create_buf()

    local on_last_line = false
    local line_count = vim.api.nvim_buf_line_count(buf)
    local cur_win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(cur_win) == buf then
        -- Get current cursor position
        local cur = vim.api.nvim_win_get_cursor(cur_win)
        local cur_line = cur[1]
        if cur_line == line_count then
            on_last_line = true
        end
    end

    vim.bo[buf].modifiable = true
    append_line(buf, line, highlight, highligh_endcol)
    vim.bo[buf].modifiable = false

    if on_last_line and vim.api.nvim_win_get_buf(cur_win) == buf then
        local last_line = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_win_set_cursor(cur_win, { last_line, 0 })
    end

    self:send_change_notification()
end

return OutputPage
