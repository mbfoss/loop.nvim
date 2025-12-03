local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')
local uitools = require('loop.tools.uitools')
local projinfo = require("loop.projinfo")

---@class loop.pages.BreakpointsPage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.BreakpointsPage, proj_dir:string|nil): loop.pages.BreakpointsPage
local BreakpointsPage = class(ItemListPage)

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean
---@param proj_dir string
---@return loop.pages.ItemListPage.Item
local function _format_item(bp, verified, proj_dir)
    local symbol = verified and "●" or "○"
    if bp.logMessage and bp.logMessage ~= "" then
        symbol = "▶" -- logpoint
    end
    if bp.condition and bp.condition ~= "" then
        symbol = "◆" -- conditional
    end
    if bp.hitCondition and bp.hitCondition ~= "" then
        symbol = "▲" -- hit-condition
    end

    local file = bp.file
    if proj_dir then
        file = vim.fs.relpath(proj_dir, file) or file
    end

    local parts = { symbol }
    table.insert(parts, " ")
    table.insert(parts, file)
    table.insert(parts, ":")
    table.insert(parts, tostring(bp.line))
    -- 3. Optional qualifiers
    if bp.condition and bp.condition ~= "" then
        table.insert(parts, " | if " .. bp.condition)
    end
    if bp.hitCondition and bp.hitCondition ~= "" then
        table.insert(parts, " | hits=" .. bp.hitCondition)
    end
    if bp.logMessage and bp.logMessage ~= "" then
        table.insert(parts, " | log: " .. bp.logMessage:gsub("\n", " "))
    end

    ---@type loop.pages.ItemListPage.Highlight
    local highlight = {
        start_col = 0,
        end_col = #symbol,
        group = "Debug"
    }
    ---@type loop.pages.ItemListPage.Item
    return { id = bp.id, data = bp,  text = table.concat(parts, ''), highlights = {highlight} }
end

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean|nil
  function BreakpointsPage:_update_one(bp, verified)
    if bp.file and bp.line then
        if verified == nil then verified = true end
        self:set_item(_format_item(bp, verified, projinfo.proj_dir))
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
  function BreakpointsPage:update_verification(bp, verified)
    self:_update_one(bp, verified)
end

function BreakpointsPage:init()
    ItemListPage.init(self, "Breakpoints")

    self:add_tracker({
        on_selection = function (item)
            if item then
                ---@type loop.dap.SourceBreakpoint
                local bp = item.data
                uitools.smart_open_file(bp.file, bp.line, bp.column)
            end
        end
    })

    require('loop.dap.breakpoints').add_tracker({
        on_added = function (bp) self:_update_one(bp) end,
        on_removed = function (bp) self:_on_removed(bp) end,
        on_all_removed = function (bpts) self:_on_all_removed(bpts) end,
    })    
end

return BreakpointsPage
