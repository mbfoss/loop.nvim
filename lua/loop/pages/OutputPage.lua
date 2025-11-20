local Page = require('loop.pages.Page')
local strtools = require('loop.tools.strtools')
local class = require('loop.tools.class')

-- namespace for error highlights
local _error_hl_ns = vim.api.nvim_create_namespace("LoopPluginOutputPageHl")

---@class loop.pages.OutputPage: loop.pages.Page
---@field new fun(self: loop.pages.OutputPage, name:string) : loop.pages.OutputPage
local OutputPage = class(Page)

---@param buf integer
---@param lines string[]
---@param error_highlight boolean|nil
local function append_lines(buf, lines, error_highlight)
    lines = strtools.clean_and_split_lines(lines)
    local count = vim.api.nvim_buf_line_count(buf)

    local _highlight_line = function(row)
        local line_text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
        local end_col = #line_text
        vim.api.nvim_buf_set_extmark(buf, _error_hl_ns, row, 0, {
            end_col = end_col,
            hl_group = 'ErrorMsg',
        })
    end

    -- If buffer is empty and first line is "", replace instead of append
    if count == 1 then
        local firstln = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
        if firstln == "" then
            vim.api.nvim_buf_set_lines(buf, 0, 1, false, lines)

            -- highlight replacement if requested
            if error_highlight then
                for i = 0, #lines - 1 do
                    _highlight_line(i)
                end
            end

            return
        end
    end

    -- Append at end
    vim.api.nvim_buf_set_lines(buf, count, count, false, lines)

    -- Highlight newly added lines if requested
    if error_highlight then
        for i = 0, #lines - 1 do
            local row = count + i
            _highlight_line(row)
        end
    end
end

---@param name string
function OutputPage:init(name)
    Page.init(self, "output", name)
    self:follow_last_line()
end

---@param lines string[]
---@param error_highlight boolean|nil
function OutputPage:add_lines(lines, error_highlight)
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
    append_lines(buf, lines, error_highlight)
    vim.bo[buf].modifiable = false

    if on_last_line and vim.api.nvim_win_get_buf(cur_win) == buf then
        local last_line = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_win_set_cursor(cur_win, { last_line, 0 })
    end
end

return OutputPage
