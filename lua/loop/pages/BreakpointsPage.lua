local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')

local breakpoints = require('loop.dap.breakpoints')

---@class loop.pages.BreakpointsPage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.BreakpointsPage): loop.pages.BreakpointsPage
local BreakpointsPage = class(ItemListPage)

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean
---@return loop.pages.ItemListPage.Item
local function _format_item(bp, verified)
    local symbol = verified and "●" or "○"
    if bp.logMessage and bp.logMessage ~= "" then
        symbol = symbol .. "▶" -- logpoint
    end
    if bp.condition and bp.condition ~= "" then
        symbol = symbol .. "◆" -- conditional
    end
    if bp.hitCondition and bp.hitCondition ~= "" then
        symbol = symbol .. "▲" -- hit-condition
    end

    local parts = { symbol }
    table.insert(parts, " ")
    table.insert(parts, bp.file)
    table.insert(parts, ":")
    table.insert(parts, tostring(bp.line))
    -- 3. Optional qualifiers
    if bp.condition and bp.condition ~= "" then
        table.insert(parts, " if " .. bp.condition)
    end
    if bp.hitCondition and bp.hitCondition ~= "" then
        table.insert(parts, " hits=" .. bp.hitCondition)
    end
    if bp.logMessage and bp.logMessage ~= "" then
        table.insert(parts, " log: " .. bp.logMessage:gsub("\n", " "))
    end

    ---@type loop.pages.ItemListPage.highlight
    local highlight = {
        start_col = 0,
        end_col = #symbol,
        group = "Debug"
    }
    ---@type loop.pages.ItemListPage.Item
    return { id = bp.id, text = table.concat(parts, ''), highlights = {highlight} }
end

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean|nil
  function BreakpointsPage:_update_one(bp, verified)
    if bp.file and bp.line then
        if verified == nil then verified = true end
        self:set_item(_format_item(bp, verified))
    end
end

---@param bp loop.dap.SourceBreakpoint
  function BreakpointsPage:_on_added(bp)
    self:_update_one(bp)
end

--- @param bp loop.dap.SourceBreakpoint
function BreakpointsPage:_on_removed(bp)
    self:remove_item(bp.id)
end

---@param bpts loop.dap.SourceBreakpoint[]
  function BreakpointsPage:_on_all_removed(bpts)
    self:set_items({})
end

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean|nil
  function BreakpointsPage:_on_status_update(bp, verified)
    self:_update_one(bp, verified)
end

function BreakpointsPage:init()
    ItemListPage.init(self, "Breakpoints")
    self._items = {}
    self._index = {}

    require('loop.dap.breakpoints').add_tracker({
        on_added = function (bp) self:_update_one(bp) end,
        on_removed = function (bp) self:_on_removed(bp) end,
        on_all_removed = function (bpts) self:_on_all_removed(bpts) end,
        on_status_update = function (bp, verified) self:_on_status_update(bp, verified) end,
    })    
end

function BreakpointsPage:_on_item_selected(item)
    vim.notify("BreakpointsPage item selected: " .. vim.inspect(item or "nil"))
end

return BreakpointsPage
