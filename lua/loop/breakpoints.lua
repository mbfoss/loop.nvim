local json = require('loop.tools.json')
local uitools = require('loop.tools.uitools')
local signs = require('loop.signs')
local window = require('loop.window')

local M = {}

local _last_breakpoint_id = 1000

---@class loop.breakpoint.Data
---@field verified boolean
---@field file string
---@field source_breakpoint loop.dap.proto.SourceBreakpoint

---@type table<number, loop.breakpoint.Data>
local _breakpoints = {} -- breakpoints by unique id

---@type table<string,table<number,number>> -- file --> line --> id
local _source_breakpoints = {}

--- Whether setup() has been called.
---@type boolean
local _setup_done = false

--- Tracks whether breakpoints need to be saved to disk.
---@type boolean
local _need_saving = false

--- Check if a file has a breakpoint on a specific line.
---@param file string  File path
---@param line integer  Line number
---@return number|nil
---@return loop.breakpoint.Data|nil
local function _get_source_breakpoint(file, line)
    local lines = _source_breakpoints[file]
    if not lines then return nil, nil end
    local id = lines[line]
    if not id then return nil, nil end
    return id, _breakpoints[id]
end

--- Check if a file has a breakpoint on a specific line.
---@param file string  File path
---@param line integer  Line number
---@return boolean has_breakpoint  True if a breakpoint exists on that line
local function _have_source_breakpoint(file, line)
    return _get_source_breakpoint(file, line) ~= nil
end


---@param file string File path (possibly relative)
---@param line integer Line number
local function _refresh_breakpoint_sign(file, line)
    local id, bp = _get_source_breakpoint(file, line)
    if id and bp then
        local sign = bp.verified and "active_breakpoint" or "inactive_breakpoint"
        signs.place_file_sign(file, line, "breakpoints", sign)
        window.get_breakpoints_page():set_item({ id = id, text = vim.inspect(bp) })
    end
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

    lines[line] = nil
    _breakpoints[id] = nil

    signs.remove_file_sign(file, line, "breakpoints")
    window.get_breakpoints_page():remove_item(id)
    return true
end

---@param file string File path
local function _clear_file_breakpoints(file)
    local page = window.get_breakpoints_page()
    local lines = _source_breakpoints[file]
    if not lines then return end
    for _, id in pairs(lines) do
        _breakpoints[id] = nil
        page:remove_item(id)
    end
    _source_breakpoints[file] = nil
    signs.remove_file_signs(file, "breakpoints")
end

local function _clear_breakpoints()
    for file, _ in pairs(_source_breakpoints) do
        signs.remove_file_signs(file, "breakpoints")
    end
    window.get_breakpoints_page():set_items({})
    _breakpoints = {}
    _source_breakpoints = {}
    _need_saving = true
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

    ---@type loop.breakpoint.Data
    local bp = {
        verified = true,
        file = file,
        source_breakpoint = {
            line = line,
            condition = condition,
            hitCondition = hitCondition,
            logMessage = logMessage
        }
    }
    _breakpoints[id] = bp

    _source_breakpoints[file] = _source_breakpoints[file] or {}
    local lines = _source_breakpoints[file]

    lines[line] = lines[line] or {}
    lines[line] = id

    _need_saving = true

    _refresh_breakpoint_sign(file, line)
    return true
end

-- ----------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------

--- Toggle a breakpoint on the current line.
--- If a breakpoint exists, remove it; otherwise, add one.
function M.toggle_breakpoint()
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return
    end
    local file = vim.fn.expand("%:p")
    if file == "" then
        return
    end
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if not _remove_source_breakpoint(file, lnum) then
        _add_breakpoint(file, lnum)
    end
end

function M.get_breakpoint(file, line)
    local full = vim.fn.fnamemodify(file, ":p")
    local bps = _breakpoints[full] or {}
    for _, bp in ipairs(bps) do
        if bp.line == line then return bp end
    end
end

---@param file string
function M.clear_file_breakpoints(file)
    file = vim.fn.fnamemodify(file, ":p")
    _clear_file_breakpoints(file)
end

--- clear all breakpoints.
function M.clear_all_breakpoints()
    _clear_breakpoints()
end

--- Load breakpoints from a JSON file in the given project config directory.
---@param proj_config_dir string Path to project config directory
---@return boolean success True on success
---@return string|nil errmsg Optional error message
function M.load_breakpoints(proj_config_dir)
    assert(_setup_done)
    assert(proj_config_dir and type(proj_config_dir) == 'string')
    local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')

    local loaded, data = json.load_from_file(breakpoints_file)
    if not loaded or type(data) ~= "table" then
        return false, data
    end

    _clear_breakpoints()

    ---@type table<number, loop.breakpoint.Data>
    local breakpoints = data
    for id, bp in pairs(breakpoints) do
        if bp and bp.file and bp.source_breakpoint then
            local sb = bp.source_breakpoint
            local file = vim.fn.fnamemodify(bp.file, ":p")
            _add_breakpoint(file, sb.line, sb.condition, sb.hitCondition, sb.logMessage)
        end
    end

    _need_saving = false
    return true, nil
end

--- Save all breakpoints to a JSON file in the given project config directory.
---@param proj_config_dir string Path to project config directory
---@return boolean success True if saved or no save needed
---@return string|nil errmsg Optional error message
function M.save_breakpoints(proj_config_dir)
    assert(_setup_done)
    if not _need_saving then
        return true
    end
    if type(proj_config_dir) ~= 'string' or vim.fn.isdirectory(proj_config_dir) == 0 then
        return false, "Invalid argument"
    end
    -- we don't need to save verified
    ---@type table<number, loop.breakpoint.Data>    
    local breakpoints = vim.deepcopy(_breakpoints)
    for _, b in pairs(breakpoints) do
        b.verified = nil
    end
    local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')
    local ok, err = json.save_to_file(breakpoints_file, breakpoints)
    if not ok then
        return false, err
    end
    _need_saving = false
    return true
end

---@return boolean
function M.have_breakpoints()
    return next(_breakpoints) ~= nil
end

---@return table<number, table<number, loop.breakpoint.Data>>
function M.get_breakpoints()
    return vim.deepcopy(_breakpoints)
end

--- Setup the breakpoint sign system and autocommands.
---@param _? table Optional setup options (currently unused)
function M.setup(_)
    assert(not _setup_done, "setup already done")
    _setup_done = true
end

return M
