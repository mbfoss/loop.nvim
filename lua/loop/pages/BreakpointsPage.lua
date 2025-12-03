local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')
local uitools = require('loop.tools.uitools')
local projinfo = require("loop.projinfo")

---@class loop.pages.BreakpointsPage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.BreakpointsPage, proj_dir:string|nil): loop.pages.BreakpointsPage
local BreakpointsPage = class(ItemListPage)

---@param item loop.pages.ItemListPage.Item
local function _item_formatter(item)
    ---@type loop.dap.SourceBreakpoint
    local bp = item.data.bp
    local verified = item.data.verified
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
    if projinfo.proj_dir then
        file = vim.fs.relpath(projinfo.proj_dir, file) or file
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
    return table.concat(parts, '')
end


---@param item loop.pages.ItemListPage.Item
---@return loop.pages.ItemListPage.Highlight[]
local function _item_highlighter(item)
    ---@type loop.pages.ItemListPage.Highlight
    local highlight = {
        start_col = 0,
        end_col = 1,
        group = "Debug"
    }
    return { highlight }
end

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean|nil
function BreakpointsPage:_update_one(bp, verified)
    if bp.file and bp.line then
        if verified == nil then verified = true end
        self:upsert_item({ id = bp.id, data = { bp = bp, verified = verified } })
    end
end

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean
function BreakpointsPage:_on_added(bp, verified)
    self:_update_one(bp, verified)
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
    ItemListPage.init(self, "Breakpoints", {
        formatter = _item_formatter,
        highlighter = _item_highlighter,
    })

    self:add_tracker({
        on_selection = function(item)
            if item then
                ---@type loop.dap.SourceBreakpoint
                local bp = item.data.bp
                uitools.smart_open_file(bp.file, bp.line, bp.column)
            end
        end
    })

    require('loop.debugui').add_tracker({
        on_bp_added = function(bp, verified) self:_update_one(bp, verified) end,
        on_bp_removed = function(bp) self:_on_removed(bp) end,
        on_all_bp_removed = function(bpts) self:_on_all_removed(bpts) end,
        on_bp_state_update = function(bp, verified) self:update_verification(bp, verified) end,
    })
end

return BreakpointsPage
