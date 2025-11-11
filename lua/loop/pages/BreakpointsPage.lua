local Page = require('loop.pages.page')
local class = require('loop.tools.class')

---@class loop.pages.BreakpointsPage: loop.pages.Page
---@field new fun(self: loop.pages.BreakpointsPage, filetype : string, on_buf_enter : fun(buf : number)) : loop.pages.BreakpointsPage
local BreakpointsPage = class(Page)

local function format_entry(entry)
    return entry.filename .. '|' .. tostring(entry.lnum)
end

---@param filetype string
---@param on_buf_enter fun(buf: number)
function BreakpointsPage:init(filetype, on_buf_enter)
    Page.init(self, filetype, on_buf_enter)
    self.state = {
        items = {},                                                -- list of entries
        idx   = 1,                                                 -- current position (1-based)
        ns_id = vim.api.nvim_create_namespace('loop-breakpoints'), -- for extmarks
    }
end

-- ----------------------------------------------------------------------
-- Refresh the quickfix buffer content
-- ----------------------------------------------------------------------
function BreakpointsPage:refresh_buffer()
    if not vim.api.nvim_buf_is_valid(self.buf) then
        return
    end

    local lines = {}
    for i, entry in ipairs(self.state.items) do
        lines[i] = format_entry(entry)
    end

    vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

    -- highlight current line
    vim.api.nvim_buf_clear_namespace(self.buf, self.state.ns_id, 0, -1)
    if self.state.idx > 0 and self.state.idx <= #self.state.items then
        vim.api.nvim_buf_set_extmark(self.buf, self.state.ns_id, self.state.idx - 1, 0, {
            end_line = self.state.idx,
            hl_group = 'CursorLine',
            hl_eol = true,
        })
    end
end

--- Set the list of items (same shape as :caddexpr)
function BreakpointsPage:setlist(items, action)
    if action == 'replace' or action == nil then
        self.state.items = {}
        self.state.idx   = 1
    end

    for _, entry in ipairs(items) do
        table.insert(self.state.items, vim.tbl_extend('keep', entry, {
            filename = entry.filename,
            lnum     = entry.lnum
        }))
    end

    if #self.state.items > 0 and self.state.idx > #self.state.items then
        self.state.idx = #self.state.items
    end

    self:refresh_buffer()
end

return BreakpointsPage
