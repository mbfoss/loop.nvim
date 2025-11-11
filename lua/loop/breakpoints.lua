local json = require('loop.tools.json')
local log = require('loop.tools.Logger').create_logger("breakpoints")

--- Breakpoints sign manager for Neovim.
--- Handles visualization (via signs), persistence (JSON), and toggling of breakpoints.
---@class loop.dap.breakpoint_manager
local M = {}

--- Internal table mapping file paths to their list of breakpoints.
--- @type table<string, loop.breakpoints.Breakpoint[]>
local _breakpoints = {}

--- Represents a single breakpoint.
---@class loop.breakpoints.Breakpoint
---@field line integer                     Line number of the breakpoint
---@field condition? string|nil            Optional condition expression
---@field hitCondition? string|nil         Optional hit condition
---@field logMessage? string|nil           Optional log message

--- Whether setup() has been called.
---@type boolean
local _setup_done = false

--- Tracks whether breakpoints need to be saved to disk.
---@type boolean
local _need_saving = false

--- Sign group name for breakpoint signs.
---@type string
local signs_group = "loopplugin_bp_signs"

--- Sign name used to display a breakpoint in the gutter.
---@type string
local sign_for_breakpoint = "loopplugin_bp_sign"

-- ----------------------------------------------------------------------
-- Internal utility functions
-- ----------------------------------------------------------------------

--- Remove all signs from a given buffer.
---@param bufnr integer Buffer number
local function _remove_buf_signs(bufnr)
    log:log('removing all buffer signs')
    vim.fn.sign_unplace(signs_group, { buffer = bufnr })
end

--- Add a single sign for a given line in a buffer.
---@param bufnr integer Buffer number
---@param line integer Line number
local function _add_buf_sign(bufnr, line)
    log:log({ 'adding buffer sign ', line })
    vim.fn.sign_place(
        line,                -- sign ID (using line as ID for simplicity)
        signs_group,         -- sign group name
        sign_for_breakpoint, -- sign type name
        bufnr,               -- buffer handle
        { lnum = line, priority = 10 }
    )
end

--- Add all breakpoint signs to a buffer (based on stored breakpoints).
---@param bufnr integer Buffer number
local function _add_buf_signs(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    local file = vim.fn.fnamemodify(name, ":p")
    local bps = _breakpoints[file]
    if bps then
        for _, v in pairs(bps) do
            _add_buf_sign(bufnr, v.line)
        end
    end
end

--- Get the loaded buffer number for a given file, or -1 if not loaded.
---@param file string File path
---@return integer bufnr Buffer number or -1 if not loaded
local function _get_loaded_bufnr(file)
    local bufnr = vim.fn.bufnr(file, false)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        return bufnr
    end
    return -1
end

--- Remove a sign from a file (if the buffer is loaded).
---@param file string File path
---@param line integer Line number
local function _remove_file_sign(file, line)
    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        log:log({ 'removing buffer sign ', line })
        vim.fn.sign_unplace(signs_group, { buffer = bufnr, id = line })
    end
end

--- Add a sign to a file (if the buffer is loaded).
---@param file string File path
---@param line integer Line number
local function _add_file_sign(file, line)
    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        _add_buf_sign(bufnr, line)
    end
end

--- Refresh all signs in all loaded buffers.
local function refresh_all_signs()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            _remove_buf_signs(bufnr)
            _add_buf_signs(bufnr)
        end
    end
end

--- Check if a file has a breakpoint on a specific line.
---@param file string  File path
---@param line integer  Line number
---@return boolean has_breakpoint  True if a breakpoint exists on that line
local function _have_file_breakpoint(file, line)
    local bps = _breakpoints[file]
    if not bps then
        return false
    end
    for _, v in pairs(bps) do
        if line == v.line then
            return true
        end
    end
    return false
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
    for _, v in pairs(bps) do
        if v.line ~= line then
            table.insert(new_bps, v)
        end
    end
    _breakpoints[file] = new_bps
    return #bps ~= #new_bps
end

--- Remove a single breakpoint and its sign.
---@param path string File path (possibly relative)
---@param line integer Line number
---@return boolean removed True if a breakpoint was removed
local function _remove_breakpoint(path, line)
    local file = vim.fn.fnamemodify(path, ":p")
    local removed = _remove_file_breakpoint(file, line)
    if removed then
        _remove_file_sign(file, line)
    end
    return removed
end

--- Remove all breakpoints and their signs from all files.
local function _remove_all_breakpoints()
    for file, btps in pairs(_breakpoints) do
        for _, b in ipairs(btps) do
            _remove_file_sign(file, b.line)
        end
    end
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
        _add_file_sign(file, line)
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
    _need_saving = true
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if not _remove_breakpoint(file, lnum) then
        _add_breakpoint(file, lnum)
    end
end

--- Reset (clear) all breakpoints.
function M.reset()
    _need_saving = true
    _remove_all_breakpoints()
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
        _breakpoints[file] = bps
    end
    refresh_all_signs()
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
    if proj_config_dir and type(proj_config_dir) == 'string' and vim.fn.isdirectory(proj_config_dir) == 1 then
        local data = {}
        local files = _breakpoints.get_breakpoint_files()
        for _, file in ipairs(files) do
            data[file] = _breakpoints.get_file_breakpoints(file)
        end
        local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')
        return json.save_to_file(breakpoints_file, data)
    end
    _need_saving = false
    return true, nil
end

--- Setup the breakpoint sign system and autocommands.
---@param opts? table Optional setup options (currently unused)
function M.setup(opts)
    assert(not _setup_done, "setup already done")
    _setup_done = true

    vim.fn.sign_define(sign_for_breakpoint, { text = '●', texthl = 'Debug' })

    -- Remove signs when buffers are deleted or unloaded
    vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
        pattern = "*",
        callback = function(args)
            vim.fn.sign_unplace(signs_group, { buffer = args.buf })
        end,
    })

    -- Reapply signs after reading a buffer
    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(args)
            _add_buf_signs(args.buf)
        end,
    })

    -- Clean up signs when buffers are deleted
    vim.api.nvim_create_autocmd("BufDelete", {
        callback = function(args)
            _remove_buf_signs(args.buf)
        end,
    })
end

return M
