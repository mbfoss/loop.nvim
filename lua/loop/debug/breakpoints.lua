local signs             = require('loop.debug.signs')
local Trackers          = require('loop.tools.Trackers')

local M                 = {}

local _setup_done       = false

---@class loop.debugui.Tracker
---@field on_bp_added fun(bp:loop.dap.SourceBreakpoint, verified:boolean)|nil
---@field on_bp_removed fun(bp:loop.dap.SourceBreakpoint)|nil
---@field on_all_bp_removed fun(bpts:loop.dap.SourceBreakpoint[])|nil
---@field on_bp_state_update fun(bp:loop.dap.SourceBreakpoint, verified:boolean)

---@type loop.tools.Trackers<loop.debugui.Tracker>
local _trackers         = Trackers:new()

---@class loop.debug_ui.Breakpointata
---@field breakpoint loop.dap.SourceBreakpoint
---@field states table<number,boolean>|nil

---@type table<number,loop.debug_ui.Breakpointata>
local _breakpoints_data = {}

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean
---@return loop.signs.SignName
local function _get_breakpoint_sign(bp, verified)
    -- Determine the sign type based on breakpoint fields
    local sign
    if bp.logMessage then
        sign = verified and "logpoint" or "logpoint_inactive"
    elseif bp.condition or bp.hitCondition then
        sign = verified and "conditional_breakpoint" or "conditional_breakpoint_inactive"
    else
        sign = verified and "active_breakpoint" or "inactive_breakpoint"
    end
    return sign
end

---@param data loop.debug_ui.Breakpointata
---@@return boolean
local function _get_breakpoint_state(data)
    local verified = nil
    if data.states then
        for _, state in ipairs(data.states) do
            verified = verified or state
        end
    end
    if verified == nil then verified = true end
    return verified
end

---@param data loop.debug_ui.Breakpointata
local function _refresh_breakpoint_sign(data)
    local verified = _get_breakpoint_state(data)
    local sign = _get_breakpoint_sign(data.breakpoint, verified)
    signs.place_file_sign(data.breakpoint.file, data.breakpoint.line, "breakpoints", sign)
    _trackers:invoke("on_bp_state_update", data.breakpoint, verified)
end

---@param bp loop.dap.SourceBreakpoint
local function _on_breakpoint_added(bp)
    _breakpoints_data[bp.id] = {
        breakpoint = bp,
    }
    local sign = _get_breakpoint_sign(bp, true)
    signs.place_file_sign(bp.file, bp.line, "breakpoints", sign)
    _trackers:invoke("on_bp_added", bp, true)
end

---@param bp loop.dap.SourceBreakpoint
local function _on_breakpoint_removed(bp)
    _breakpoints_data[bp.id] = nil
    signs.remove_file_sign(bp.file, bp.line, "breakpoints")
    _trackers:invoke("on_bp_removed", bp)
end

---@param removed loop.dap.SourceBreakpoint[]
local function _on_all_breakpoints_removed(removed)
    _breakpoints_data = {}
    local files = {}
    for _, bp in ipairs(removed) do
        files[bp.file] = true
    end
    for file, _ in pairs(files) do
        signs.remove_file_signs(file, "breakpoints")
    end
    _trackers:invoke("on_all_bp_removed", removed)
end

---@param task_name string -- task name
---@return loop.job.debugjob.Tracker
function M.track_new_debugjob(task_name)
    assert(_setup_done)
    assert(type(task_name) == "string")

    ---@type loop.job.debugjob.Tracker
    local tracker = {
        on_sess_added = function(id, name, parent_id, ctrl)
            for _, data in pairs(_breakpoints_data) do
                data.states = data.states or {}
                data.states[id] = false
                _refresh_breakpoint_sign(data)
            end
        end,
        on_sess_removed = function(id, name)
            for _, data in pairs(_breakpoints_data) do
                if data.states then
                    data.states[id] = nil
                    _refresh_breakpoint_sign(data)
                end
            end
        end,
        on_breakpoint_event = function(sess_id, session_name, event)
            for _, state in ipairs(event) do
                local bp = _breakpoints_data[state.breakpoint_id]
                if bp then
                    bp.states = bp.states or {}
                    bp.states[sess_id] = state.verified
                    local data = _breakpoints_data[state.breakpoint_id]
                    if data then
                        _refresh_breakpoint_sign(data)
                    end
                end
            end
        end,
        on_exit = function(code) end
    }
    return tracker
end

---@param callbacks loop.debugui.Tracker
---@return number
function M.add_tracker(callbacks)
    local tracker_id = _trackers:add_tracker(callbacks)
    --initial snapshot
    if callbacks.on_bp_added then
        for _, data in pairs(_breakpoints_data) do
            local verified = _get_breakpoint_state(data)
            callbacks.on_bp_added(data.breakpoint, verified)
        end
    end
    return tracker_id
end

---@param id number
---@return boolean
function M.remove_tracker(id)
    return _trackers:remove_tracker(id)
end

--- Setup the breakpoint sign system and autocommands.
---@param _? table Optional setup options (currently unused)
function M.setup(_)
    assert(not _setup_done, "setup already done")
    _setup_done = true

    require('loop.dap.breakpoints').add_tracker({
        on_added = _on_breakpoint_added,
        on_removed = _on_breakpoint_removed,
        on_all_removed = _on_all_breakpoints_removed
    })
end

return M
