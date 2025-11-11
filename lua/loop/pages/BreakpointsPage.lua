local Page = require('loop.pages.page')
local class = require('loop.tools.class')

--- Represents a specialized Page for managing and displaying breakpoints.
--- Inherits from `loop.pages.Page`.
---@class loop.pages.BreakpointsPage : loop.pages.Page
---@field new fun(self: loop.pages.BreakpointsPage, filetype: string, on_buf_enter: fun(buf: integer)): loop.pages.BreakpointsPage
local BreakpointsPage = class(Page)

--- Format a single breakpoint entry for display in the buffer.
---@param entry { filename:string, line:number, condition:string, hitCondition:string, logMessage:string }
---@return string
local function format_entry(entry)
    return entry.filename .. ':' .. tostring(entry.line)
end

--- Initialize a BreakpointsPage instance.
---@param filetype string  Filetype associated with this page
---@param on_buf_enter fun(buf: integer)  Callback invoked when entering the buffer
function BreakpointsPage:init(filetype, on_buf_enter)
    Page.init(self, filetype, on_buf_enter)
    self._items = {}                                                -- list of breakpoint entries
    self._idx   = 1                                                 -- current selection index (1-based)
    self._ns_id = vim.api.nvim_create_namespace('loop-breakpoints') -- namespace for highlights/extmarks
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

--- Refresh the content of the associated buffer to reflect the current _
--- Rebuilds the lines and highlights the active breakpoint line.
function BreakpointsPage:refresh_buffer()
    if not vim.api.nvim_buf_is_valid(self.buf) then
        return
    end
    local lines = {}
    for i, entry in ipairs(self._items) do
        lines[i] = format_entry(entry)
    end

    vim.bo[self.buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
    vim.bo[self.buf].modifiable = false

    -- Clear previous highlights
    vim.api.nvim_buf_clear_namespace(self.buf, self._ns_id, 0, -1)

    -- Highlight the current line
    if self._idx > 0 and self._idx <= #self._items then
        vim.api.nvim_buf_set_extmark(self.buf, self._ns_id, self._idx - 1, 0, {
            end_line = self._idx,
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
---@param items table<string, {line:number, condition:string, hitCondition:string, logMessage:string}>  List of breakpoints to display
---@param action? "replace"|"append"|nil
function BreakpointsPage:setlist(items, action)
    if action ~= 'append' then
        self._items = {}
        self._idx   = 1
    end

    for file, bpts in pairs(items) do
        for _, bp in ipairs(bpts) do
            table.insert(self._items, {
                filename = file,
                line = bp.line,
                condition = bp.condition,
                hitCondition = bp.hitCondition,
                logMessage = bp.logMessage,
            })
        end
    end

    if #self._items > 0 and self._idx > #self._items then
        self._idx = #self._items
    end

    self:get_buf() -- ensure the buffer is created
    self:refresh_buffer()
end

return BreakpointsPage
