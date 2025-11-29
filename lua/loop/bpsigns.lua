local signs = require('loop.signs')
local breakpoints = require('loop.dap.breakpoints')

local M = {}

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean|nil
local function _udpate_one(bp, verified)
    if bp.file and bp.line then
        if verified == nil then verified = true end
        local sign = verified and "active_breakpoint" or "inactive_breakpoint"
        signs.place_file_sign(bp.file, bp.line, "breakpoints", sign)
    end
end

---@param bp loop.dap.SourceBreakpoint
local function _on_added(bp)
    _udpate_one(bp, nil)
end

---@param bp loop.dap.SourceBreakpoint
local function _on_removed(bp)
    signs.remove_file_sign(bp.file, bp.line, "breakpoints")
end

---@param bpts loop.dap.SourceBreakpoint[]
local function _on_all_removed(bpts)
    local files = {}
    for _, bp in ipairs(bpts) do
        files[bp.file] = true
    end
    for file, _ in pairs(files) do
        signs.remove_file_signs(file, "breakpoints")
    end
end

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean|nil
local function _on_status_update(bp, verified)
    _udpate_one(bp, verified)
end


--- Setup the breakpoint sign system and autocommands.
---@param _? table Optional setup options (currently unused)
function M.setup(_)
    assert(not _setup_done, "setup already done")
    _setup_done = true


    require('loop.dap.breakpoints').add_tracker({
        on_added = _on_added,
        on_removed = _on_removed,
        on_all_removed = _on_all_removed,
        on_status_update = _on_status_update
    })
end

return M
