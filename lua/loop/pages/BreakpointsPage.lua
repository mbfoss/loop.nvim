local Page = require('loop.pages.page')
local class = require('loop.tools.class')

--- Represents a specialized Page for managing and displaying breakpoints.
--- Inherits from `loop.pages.Page`.
---@class loop.pages.BreakpointsPage : loop.pages.Page
---@field new fun(self: loop.pages.BreakpointsPage, filetype: string, on_buf_enter: fun(buf: integer)): loop.pages.BreakpointsPage
local BreakpointsPage = class(Page)

--- Format a single breakpoint entry for display.
--- Shows filename:line and optional condition/log indicators.
---@param entry { filename:string, line:number, condition:string|nil, hitCondition:string|nil, logMessage:string|nil }
---@return string
local function format_entry(entry)
    local parts = { entry.filename .. ':' .. tostring(entry.line) }

    if entry.condition and entry.condition ~= '' then
        table.insert(parts, 'if ' .. entry.condition)
    end

    if entry.hitCondition and entry.hitCondition ~= '' then
        table.insert(parts, 'hits=' .. entry.hitCondition)
    end

    if entry.logMessage and entry.logMessage ~= '' then
        table.insert(parts, 'log: ' .. entry.logMessage:gsub('\n', ' ')) -- sanitize newlines
    end

    return table.concat(parts, '  ')
end

--- Initialize a BreakpointsPage instance.
---@param filetype string Filetype for syntax highlighting (e.g., "lua")
---@param on_buf_enter fun(buf: integer) Callback when entering buffer
function BreakpointsPage:init(filetype, on_buf_enter)
    Page.init(self, filetype, on_buf_enter)
    self._items = {}    -- List of breakpoint entries
    self._idx = 1       -- Current selection index (1-based)
end

--- Get buffer, creating it if needed and refreshing content on creation.
---@return integer buf Buffer handle
---@return boolean created True if buffer was just created
function BreakpointsPage:get_buf()
    local buf, created = Page.get_buf(self)
    if created then
        self:refresh_buffer()
    end
    return buf, created
end

--- Refresh the buffer content with current breakpoints and highlight selection.
function BreakpointsPage:refresh_buffer()
    local buf = self.buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    -- 1. build lines -------------------------------------------------
    local lines = {}
    for _, entry in ipairs(self._items) do
        lines[#lines+1] = format_entry(entry)
    end

    -- 2. write lines -------------------------------------------------
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- 3. highlight the *selected* line -------------------------------
    --TODO
end

--- Set or update the list of breakpoint items.
--- Supports replacing or appending. Adjusts selection index safely.
---
--- Expected item structure:
--- ```lua
--- {
---   filename = "path/to/file.lua",
---   line = 42,
---   condition = "x > 10",        -- optional
---   hitCondition = "5",          -- optional
---   logMessage = "x = {x}"       -- optional
--- }
--- ```
---
---@param items table<string, {line:number, condition?:string, hitCondition?:string, logMessage?:string}[]> Breakpoints grouped by filename
---@param action? '"replace"'|'"append"' Action to perform (default: replace)
function BreakpointsPage:setlist(items, action)
    action = action or 'replace'

    if action ~= 'append' then
        self._items = {}
        self._idx = 1
    end

    for file, bpts in pairs(items or {}) do
        for _, bp in ipairs(bpts) do
            if bp.line and type(bp.line) == 'number' then
                table.insert(self._items, {
                    filename = file,
                    line = bp.line,
                    condition = bp.condition or '',
                    hitCondition = bp.hitCondition or '',
                    logMessage = bp.logMessage or '',
                })
            end
        end
    end

    -- Clamp selection index
    if #self._items == 0 then
        self._idx = 1
    elseif self._idx > #self._items then
        self._idx = #self._items
    end

    -- Ensure buffer exists and refresh
    self:get_buf()
    self:refresh_buffer()
end

-- Optional: Add navigation helpers
--- Move selection up
function BreakpointsPage:select_prev()
    if #self._items > 0 then
        self._idx = (self._idx - 2) % #self._items + 1
        self:refresh_buffer()
    end
end

--- Move selection down
function BreakpointsPage:select_next()
    if #self._items > 0 then
        self._idx = self._idx % #self._items + 1
        self:refresh_buffer()
    end
end

--- Get currently selected breakpoint or nil
---@return {filename:string, line:number, condition:string, hitCondition:string, logMessage:string}|nil
function BreakpointsPage:get_selected()
    return self._items[self._idx]
end

return BreakpointsPage
