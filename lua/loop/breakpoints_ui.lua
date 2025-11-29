local signs = require('loop.signs')
local window = require('loop.window')
local breakpoints = require('loop.dap.breakpoints')

local M = {}

---@param bp loop.dap.SourceBreakpoint
local function _update_breakpoint_ui(bp)
    if bp.file and bp.line then
        local verified = breakpoints.is_verified(bp.id)
        if verified == nil then verified = true end
        local sign = verified and "active_breakpoint" or "inactive_breakpoint"
        signs.place_file_sign(bp.file, bp.line, "breakpoints", sign)
        window.get_breakpoints_page():set_item({ id = bp.id, text = vim.inspect(bp) })
    end
end

---@param bp loop.dap.SourceBreakpoint
local function _on_added(bp)
    _update_breakpoint_ui(bp)
end

---@param bp loop.dap.SourceBreakpoint
local function _on_removed(bp)
    signs.remove_file_sign(bp.file, bp.line, "breakpoints")
    window.get_breakpoints_page():remove_item(bp.id)
end

local function _on_all_removed()
    local files = {}
    breakpoints.for_each(function (bp)
        files[bp.file] = true        
    end)

    for _, file in pairs(files) do
        signs.remove_file_signs(file, "breakpoints")
    end
    window.get_breakpoints_page():set_items({})
end

---@param id number
---@param verified boolean|nil
local function _on_status_update(bp, verified)
    _update_breakpoint_ui(bp)
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
