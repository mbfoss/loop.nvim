local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')


local function _breakpoint_sign(entry)
    if entry.enabled == false then
        return " "     -- disabled → no sign
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
local function _format_entry(entry)
    local parts = {}
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

---@class loop.pages.BreakpointsPage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.BreakpointsPage, keymaps:loop.pages.page.KeyMaps): loop.pages.BreakpointsPage
local BreakpointsPage = class(ItemListPage)

---@param keymaps loop.pages.page.KeyMaps
function BreakpointsPage:init(keymaps)
    ItemListPage.init(self, "Breakpoints", keymaps)
end

function BreakpointsPage:set_breakpoints(breakpoints)
    ---@type loop.pages.ItemListPage.Item[]
    local items = {}
    for file, lines in pairs(breakpoints or {}) do
        for _, entry in ipairs(lines) do
            table.insert(items, {
                id = #items,
                text = _breakpoint_sign(entry) .. ' ' .. file .. _format_entry(entry)
            })
        end
    end
    self:set_items(items)
end

return BreakpointsPage
