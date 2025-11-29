local json = require('loop.tools.json')

local M = {}

---@class loop.dap.SourceBreakpoint
---@field id number
---@field file string
---@field line integer
---@field column integer|nil
---@field condition string|nil
---@field hitCondition string|nil
---@field logMessage string|nil


---@class loop.dap.breakpoints.TrackerCallbacks
---@field on_added fun(bp:loop.dap.SourceBreakpoint)|nil
---@field on_removed fun(bp:loop.dap.SourceBreakpoint)|nil
---@field on_all_removed fun(bpts:loop.dap.SourceBreakpoint[])|nil
---@field on_status_update fun(bp:loop.dap.SourceBreakpoint, verified:boolean|nil)|nil

local _last_breakpoint_id = 1000

---@type table<string,table<number,number>> -- file --> line --> id
local _source_breakpoints = {}

---@type table<number,loop.dap.SourceBreakpoint>
local _by_id = {} -- breakpoints by unique id

---@type table<number,boolean>
local _verified = {}

local _last_tracker_id = 0
---@type table<number,loop.dap.breakpoints.TrackerCallbacks>
local _trackers = {}

--- Tracks whether breakpoints need to be saved to disk.
---@type boolean
local _need_saving = false

local function _norm(file)
    if not file or file == "" then return file end
    return vim.fn.fnamemodify(file, ":p")
end

--- Check if a file has a breakpoint on a specific line.
---@param file string  File path
---@param line integer  Line number
---@return number|nil
---@return loop.dap.SourceBreakpoint|nil
local function _get_source_breakpoint(file, line)
    local lines = _source_breakpoints[file]
    if not lines then return nil, nil end
    local id = lines[line]
    if not id then return nil, nil end
    return id, _by_id[id]
end

--- Check if a file has a breakpoint on a specific line.
---@param file string  File path
---@param line integer  Line number
---@return boolean has_breakpoint  True if a breakpoint exists on that line
local function _have_source_breakpoint(file, line)
    return _get_source_breakpoint(file, line) ~= nil
end

--- Remove a single breakpoint and its sign.
---@param file string File path
---@param line integer Line number
---@return boolean removed True if a breakpoint was removed
local function _remove_source_breakpoint(file, line)
    local lines = _source_breakpoints[file]
    if not lines then return false end

    local id = lines[line]
    if not id then return false end

    local bp = _by_id[id]
    if bp then
        lines[line] = nil
        _by_id[id] = nil

        for type, tracker in pairs(_trackers) do
            if tracker.on_removed then tracker.on_removed(bp) end
        end
    end
    return true
end

---@param file string File path
local function _clear_file_breakpoints(file)
    local lines = _source_breakpoints[file]

    local removed = {}

    if not lines then return end
    for _, id in pairs(lines) do
        local bp = _by_id[id]
        if bp then
            table.insert(removed, bp)
            _by_id[id] = nil
        end
    end

    _source_breakpoints[file] = nil

    for type, tracker in pairs(_trackers) do
        for _, bp in pairs(removed) do
            if tracker.on_removed then tracker.on_removed(bp) end
        end
    end
end

local function _clear_breakpoints()
    ---@type loop.dap.SourceBreakpoint[]
    local removed = vim.tbl_values(_by_id)
    _by_id = {}
    _source_breakpoints = {}
    _need_saving = true
    for type, tracker in pairs(_trackers) do
        if tracker.on_all_removed then tracker.on_all_removed(removed) end
    end
end


--- Add a new breakpoint and display its sign.
---@param file string File path
---@param line integer Line number
---@param condition? string condition
---@param hitCondition? string Optional hit condition
---@param logMessage? string Optional log message
---@return boolean added
local function _add_breakpoint(file, line, condition, hitCondition, logMessage)
    if _have_source_breakpoint(file, line) then
        return false
    end
    local id = _last_breakpoint_id + 1
    _last_breakpoint_id = id

    ---@type loop.dap.SourceBreakpoint
    local bp = {
        id = id,
        file = file,
        line = line,
        condition = condition,
        hitCondition = hitCondition,
        logMessage = logMessage
    }

    _by_id[id] = bp

    _source_breakpoints[file] = _source_breakpoints[file] or {}
    local lines = _source_breakpoints[file]
    lines[line] = id

    _need_saving = true

    for type, tracker in pairs(_trackers) do
        if tracker.on_added then tracker.on_added(bp) end
    end

    return true
end

---@param file string
---@param lnum number
function M.toggle_breakpoint(file, lnum)
    file = _norm(file)
    if not _remove_source_breakpoint(file, lnum) then
        _add_breakpoint(file, lnum)
    end
end

---@param file string
function M.clear_file_breakpoints(file)
    _clear_file_breakpoints(_norm(file))
end

--- clear all breakpoints.
function M.clear_all_breakpoints()
    _clear_breakpoints()
end

---@param id number
---@param verified boolean
function M.update_verified_status(id, verified)
    local bp = _by_id[id]
    if bp then
        _verified[id] = verified
        for type, tracker in pairs(_trackers) do
            if tracker.on_status_update then tracker.on_status_update(bp, verified) end
        end
    end
end

function M.reset_verified_status()
    for id, bp in pairs(_by_id) do
        for type, tracker in pairs(_trackers) do
            if tracker.on_status_update then tracker.on_status_update(bp, nil) end
        end
    end
    for id, bp in pairs(_by_id) do
        _verified[bp.id] = nil
    end
end

--- Load breakpoints from a JSON file in the given project config directory.
---@param proj_config_dir string Path to project config directory
---@return boolean success True on success
---@return string|nil errmsg Optional error message
function M.load_breakpoints(proj_config_dir)
    assert(proj_config_dir and type(proj_config_dir) == 'string')
    local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')

    local loaded, data = json.load_from_file(breakpoints_file)
    if not loaded or type(data) ~= "table" then
        return false, data
    end

    _clear_breakpoints()

    ---@type loop.dap.SourceBreakpoint[]
    local breakpoints = data
    for _, bp in ipairs(breakpoints) do
        local file = vim.fn.fnamemodify(bp.file, ":p")
        _add_breakpoint(file, bp.line, bp.condition, bp.hitCondition, bp.logMessage)
    end

    _need_saving = false
    return true, nil
end

--- Save all breakpoints to a JSON file in the given project config directory.
---@param proj_config_dir string Path to project config directory
---@return boolean success True if saved or no save needed
---@return string|nil errmsg Optional error message
function M.save_breakpoints(proj_config_dir)
    if not _need_saving then
        return true
    end
    if type(proj_config_dir) ~= 'string' or vim.fn.isdirectory(proj_config_dir) == 0 then
        return false, "Invalid argument"
    end

    local data = vim.tbl_values(_by_id)

    local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')
    local ok, err = json.save_to_file(breakpoints_file, data)
    if not ok then
        return false, err
    end

    _need_saving = false
    return true
end

---@return boolean
function M.have_breakpoints()
    return next(_by_id) ~= nil
end

---@return number[]
function M.get_ids()
    return vim.tbl_keys(_by_id)
end

---@param id number
---@return loop.dap.SourceBreakpoint
function M.get_breakpoint(id)
    return _by_id[id]
end

---@param handler fun(bp:loop.dap.SourceBreakpoint)
function M.for_each(handler)
    for _, bp in ipairs(_by_id) do
        handler(bp)
    end
end

---@param id number
---@return boolean|nil
function M.is_verified(id)
    return _verified[id]
end

---@param callbacks loop.dap.breakpoints.TrackerCallbacks
---@return number
function M.add_tracker(callbacks)
    local tracker_id = _last_tracker_id + 1
    _last_tracker_id = tracker_id
    _trackers[tracker_id] = callbacks
    if callbacks then
        --initial snapshot
        for id, bp in pairs(_by_id) do
            callbacks.on_added(bp)
            local verified = _verified[id]
            if verified then
                callbacks.on_status_update(bp, verified)
            end
        end
    end
    return tracker_id
end

---@param id number
---@return boolean
function M.remove_tracker(id)
    local removed = _trackers[id] ~= nil
    _trackers[id] = nil
    return removed
end

return M
