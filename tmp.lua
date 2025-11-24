local json = require('loop.tools.json')
local signs = require('loop.signs')

local M = {}

---Internal table mapping file paths to their list of breakpoints.
---@type table<string, loop.dap.proto.SourceBreakpoint[]>
local _breakpoints = {}

---Internal table mapping file paths to breakpoints states by line
---@type table<string, table<number,boolean>>
local _livebreakpoints = {}

--- Whether setup() has been called.
---@type boolean
local _setup_done = false

--- Tracks whether breakpoints need to be saved to disk.
---@type boolean
local _need_saving = false

--- Check if a file has a breakpoint on a specific line.
---@param file string  File path
---@param line integer  Line number
---@return boolean has_breakpoint  True if a breakpoint exists on that line
local function _have_file_breakpoint(file, line)
    local bps = _breakpoints[file]
    if not bps then
        return false
    end
    for _, v in ipairs(bps) do
        if line == v.line then
            return true
        end
    end
    return false
end

---@param file string
---@param line number
---@return boolean|nil
function _get_live_bp_state(file, line)
    local f = vim.fn.fnamemodify(file, ":p")
    local bpts = _livebreakpoints[f]
    if not bpts then return nil end
    return bpts[line]
end

function M.has_breakpoint(file, line)
    local f = vim.fn.fnamemodify(file, ":p")
    return _have_file_breakpoint(f, line)
end

--- Add a breakpoint to a file if it doesn't already exist on that line.
---@param file string  File path
---@param line integer  Line number
---@param condition? string|nil  Optional conditional expression
---@param hitCondition? string|nil  Optional hit condition
---@param logMessage? string|nil  Optional log message
---@return boolean added  True if a new breakpoint was added, false if one already existed
local function _add_file_breakpoint(file, line, condition, hitCondition, logMessage)
    if _have_file_breakpoint(file, line) then
        return false
    end
    if not _breakpoints[file] then
        _breakpoints[file] = {}
    end
    table.insert(_breakpoints[file], {
        line = line,
        condition = condition,
        hitCondition = hitCondition,
        logMessage = logMessage,
    })
    _need_saving = true
    return true
end

--- Remove a breakpoint from a specific line in a file.
---@param file string  File path
---@param line integer  Line number
---@return boolean removed  True if a breakpoint was removed, false if none was found
local function _remove_file_breakpoint(file, line)
    local bps = _breakpoints[file]
    if not bps then
        return false
    end
    local new_bps = {}
    for _, v in ipairs(bps) do
        if v.line ~= line then
            table.insert(new_bps, v)
        end
    end
    _breakpoints[file] = new_bps
    local changed = #bps ~= #new_bps
    _need_saving = _need_saving or changed
    return changed
end

--- Remove a single breakpoint and its sign.
---@param path string File path (possibly relative)
---@param line integer Line number
---@return boolean removed True if a breakpoint was removed
local function _remove_breakpoint(path, line)
    local file = vim.fn.fnamemodify(path, ":p")
    local removed = _remove_file_breakpoint(file, line)
    if removed then
        signs.remove_file_sign(file, line, "breakpoints")
    end
    return removed
end

---@param path string File path (possibly relative)
local function _clear_file_breakpoints(path)
    local file = vim.fn.fnamemodify(path, ":p")
    if _breakpoints[file] then
        _breakpoints[file] = {}
        signs.remove_file_signs(file, "breakpoints")
        _need_saving = true
    end
end

--- Remove all breakpoints and their signs from all files.
local function _clear_breakpoints()
    for file, bps in pairs(_breakpoints) do
        for _, b in ipairs(bps) do
            signs.remove_file_sign(file, b.line, "breakpoints")
        end
    end
    _breakpoints = {}
    _need_saving = true
end


--- Add a new breakpoint and display its sign.
---@param path string File path
---@param line integer Line number
---@param condition? string Optional condition
---@param hitCondition? string Optional hit condition
---@param logMessage? string Optional log message
local function _add_breakpoint(path, line, condition, hitCondition, logMessage)
    local file = vim.fn.fnamemodify(path, ":p")
    local added = _add_file_breakpoint(file, line, condition, hitCondition, logMessage)
    if added then
        local livestate = _get_live_bp_state(path, line)
        local sign = livestate ~= false and "active_breakpoint" or "inactive_breakpoint"
        signs.place_file_sign(file, line, "breakpoints", sign)
    end
end

---@param breakpoints table<string, loop.dap.proto.SourceBreakpoint[]>
local function _apply_breakpoints(breakpoints)
    for file, _ in pairs(_breakpoints) do
        signs.remove_file_signs(file, "breakpoints")
    end
    _breakpoints = breakpoints
    for file, filebps in pairs(_breakpoints) do
        local livebpts = _livebreakpoints[file]
        for _, bp in ipairs(filebps) do
            local livestate = livebpts and livebpts[bp.line]
            local sign = livestate ~= false and "active_breakpoint" or "inactive_breakpoint"
            signs.place_file_sign(file, bp.line, "breakpoints", sign)
        end
    end
end

-- ----------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------

--- Toggle a breakpoint on the current line.
--- If a breakpoint exists, remove it; otherwise, add one.
function M.toggle_breakpoint()
    local file = vim.fn.expand("%:p")
    if file == "" then
        return
    end
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if not _remove_breakpoint(file, lnum) then
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

---@param filepath string
function M.clear_file_breakpoints(filepath)
    _clear_file_breakpoints(filepath)
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
    for file, bps in pairs(data) do
        if type(file) ~= "string" or type(bps) ~= "table" then
            return false, "invalid file or breakpoint list"
        end
        for i, bp in ipairs(bps) do
            if type(bp.line) ~= "number" or bp.line < 1 then
                return false, "invalid line number at index " .. i
            end
        end
    end
    _apply_breakpoints(data)
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
    local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')
    local ok, err = json.save_to_file(breakpoints_file, _breakpoints)
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

---@return table<string,loop.dap.proto.SourceBreakpoint[]>
function M.get_breakpoints()
    return vim.deepcopy(_breakpoints)
end

function M.clear_live_breakpoints()
    _livebreakpoints = {}
    _refresh_breakpoints()
end

---@param file string
---@param line number
---@param verified boolean
function M.set_live_breakpoint(file, line, verified)
    local f = vim.fn.fnamemodify(file, ":p")
    _livebreakpoints[f] = _livebreakpoints[f] or {}
    local filebreakpoints = _livebreakpoints[f]
    filebreakpoints[line] = verified
    local sign = verified ~= false and "active_breakpoint" or "inactive_breakpoint"
    signs.place_file_sign(file, line, "breakpoints", sign)
end

---@param file string
---@param line number
function M.remove_live_breakpoint(file, line)
    local f = vim.fn.fnamemodify(file, ":p")
    if _livebreakpoints[f] then
        local filebreakpoints = _livebreakpoints[f]
        if filebreakpoints[line] then
            filebreakpoints[line] = nil
        end
    end
    if _have_file_breakpoint(file, line) then
        signs.place_file_sign(file, line, "breakpoints", "active_breakpoint")
    else
        signs.remove_file_sign(file, line, "breakpoints")
    end
end

--- Setup the breakpoint sign system and autocommands.
---@param _? table Optional setup options (currently unused)
function M.setup(_)
    assert(not _setup_done, "setup already done")
    _setup_done = true
end

return M



    local sign = verified ~= false and "active_breakpoint" or "inactive_breakpoint"
