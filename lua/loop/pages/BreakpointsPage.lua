local Page = require('loop.pages.page')
local class = require('loop.tools.class')

---@class loop.pages.BreakpointsPage : loop.pages.Page
---@field new fun(self: loop.pages.BreakpointsPage, filetype: string, on_buf_enter: fun(buf: integer)): loop.pages.BreakpointsPage
local BreakpointsPage = class(Page)

-- Static namespace for extmarks
local NS_ID = vim.api.nvim_create_namespace('loop-breakpoints-hl')

-- ----------------------------------------------------------------------
-- Helper: pick the right sign for a breakpoint
-- ----------------------------------------------------------------------
local function breakpoint_sign(entry)
    if entry.enabled == false then
        return " " -- disabled → no sign
    end
    if entry.logMessage and entry.logMessage ~= "" then
        return "▶" -- logpoint
    end
    if entry.condition and entry.condition ~= "" then
        return "◆" -- conditional
    end
    if entry.hitCondition and entry.hitCondition ~= "" then
        return "▲" -- hit-condition
    end
    return "●" -- plain breakpoint
end

-- ----------------------------------------------------------------------
-- Format a breakpoint entry for UI (e.g. Telescope, quickfix, etc.)
-- ----------------------------------------------------------------------
local function format_entry(entry)
    local parts = {}
    -- 1. Sign
    table.insert(parts, breakpoint_sign(entry))
    -- 2. File + line
    table.insert(parts, " ")
    table.insert(parts, entry.filename)
    table.insert(parts, ":")
    table.insert(parts, tostring(entry.line))
    -- 3. Optional qualifiers
    if entry.condition and entry.condition ~= "" then
        table.insert(parts, " if " .. entry.condition)
    end
    if entry.hitCondition and entry.hitCondition ~= "" then
        table.insert(parts, " hits=" .. entry.hitCondition)
    end
    if entry.logMessage and entry.logMessage ~= "" then
        table.insert(parts, " log: " .. entry.logMessage:gsub("\n", " "))
    end
    return table.concat(parts, "")
end

function BreakpointsPage:init(filetype, on_buf_enter)
    Page.init(self, filetype, on_buf_enter)
    self._items = {}
    self._idx = 1
end

function BreakpointsPage:get_buf()
    local buf, created = Page.get_buf(self)
    if created then
        self:refresh_buffer()
    end
    return buf, created
end

function BreakpointsPage:refresh_buffer()
    local buf = self.buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    -- 1. Build lines
    local lines = {}
    for _, entry in ipairs(self._items) do
        lines[#lines + 1] = format_entry(entry)
    end

    -- 2. Update buffer
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- 3. Highlight selected line using extmark
    vim.api.nvim_buf_clear_namespace(buf, NS_ID, 0, -1)

    for idx, entry in ipairs(self._items) do
        local line_idx = idx - 1
        vim.api.nvim_buf_set_extmark(buf, NS_ID, line_idx, 0, {
            end_col = 1,
            hl_group = 'Debug',
            hl_eol = true,
            priority = 200,
        })
    end
end

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

    -- Clamp index
    if #self._items == 0 then
        self._idx = 1
    elseif self._idx > #self._items then
        self._idx = #self._items
    end

    self:get_buf()
    self:refresh_buffer()
end

-- Navigation
function BreakpointsPage:select_prev()
    if #self._items > 0 then
        self._idx = (self._idx - 2) % #self._items + 1
        self:refresh_buffer()
    end
end

function BreakpointsPage:select_next()
    if #self._items > 0 then
        self._idx = self._idx % #self._items + 1
        self:refresh_buffer()
    end
end

function BreakpointsPage:get_selected()
    return self._items[self._idx]
end

return BreakpointsPage
