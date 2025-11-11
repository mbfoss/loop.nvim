local Page = require('loop.pages.page')
local class = require('loop.tools.class')

--- Represents a specialized Page for managing and displaying breakpoints.
--- Inherits from `loop.pages.Page`.
---@class loop.pages.BreakpointsPage : loop.pages.Page
---@field state { items: table[], idx: integer, ns_id: integer }  Current internal state
---@field buf integer?  Buffer handle (inherited from Page)
---@field new fun(self: loop.pages.BreakpointsPage, filetype: string, on_buf_enter: fun(buf: integer)): loop.pages.BreakpointsPage
local BreakpointsPage = class(Page)

--- Format a single breakpoint entry for display in the buffer.
---@param entry { filename: string, lnum: integer }
---@return string
local function format_entry(entry)
    return entry.filename .. '|' .. tostring(entry.lnum)
end

--- Initialize a BreakpointsPage instance.
---@param filetype string  Filetype associated with this page
---@param on_buf_enter fun(buf: integer)  Callback invoked when entering the buffer
function BreakpointsPage:init(filetype, on_buf_enter)
    Page.init(self, filetype, on_buf_enter)
    self.state = {
        items = {},                                                -- list of breakpoint entries
        idx   = 1,                                                 -- current selection index (1-based)
        ns_id = vim.api.nvim_create_namespace('loop-breakpoints'), -- namespace for highlights/extmarks
    }
end

function BreakpointsPage:get_buf()
    local buf, created = Page.get_buf(self)
    if created then
        self:refresh_buffer()
    end
    return buf, created
end

-- ----------------------------------------------------------------------
-- Refresh the quickfix-like buffer content
-- ----------------------------------------------------------------------

--- Refresh the content of the associated buffer to reflect the current state.
--- Rebuilds the lines and highlights the active breakpoint line.
function BreakpointsPage:refresh_buffer()
    if not vim.api.nvim_buf_is_valid(self.buf) then
        return
    end

    local lines = {}
    for i, entry in ipairs(self.state.items) do
        lines[i] = format_entry(entry)
    end

    vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

    -- Clear previous highlights
    vim.api.nvim_buf_clear_namespace(self.buf, self.state.ns_id, 0, -1)

    -- Highlight the current line
    if self.state.idx > 0 and self.state.idx <= #self.state.items then
        vim.api.nvim_buf_set_extmark(self.buf, self.state.ns_id, self.state.idx - 1, 0, {
            end_line = self.state.idx,
            hl_group = 'CursorLine',
            hl_eol = true,
        })
    end
end

--- Set or update the list of breakpoint items.
--- Items should have the same structure as those used by `:caddexpr`.
---
--- Example item: `{ filename = "file.lua", lnum = 12 }`
---
---@param items { filename: string, lnum: integer }[]  List of breakpoints to display
---@param action? '"replace"'|string  If `"replace"` or `nil`, replaces existing items; otherwise appends
function BreakpointsPage:setlist(items, action)
    if action == 'replace' or action == nil then
        self.state.items = {}
        self.state.idx   = 1
    end

    for _, entry in ipairs(items) do
        table.insert(self.state.items, vim.tbl_extend('keep', entry, {
            filename = entry.filename,
            lnum     = entry.lnum,
        }))
    end

    if #self.state.items > 0 and self.state.idx > #self.state.items then
        self.state.idx = #self.state.items
    end

    self:refresh_buffer()
end

return BreakpointsPage
