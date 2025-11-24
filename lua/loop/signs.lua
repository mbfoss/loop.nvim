---@class loop.signs
local M = {}

local config = require("loop.config")

---@alias loop.signs.SignGroup '"breakpoints"'|'"currentframe"'
---@alias loop.signs.SignName '"active_breakpoint"'|'"inactive_breakpoint"'|'"currentframe"'

---@class loop.signs.LineSigns table<loop.signs.SignName, true>        -- set-like: sign name present on this line
---@class loop.signs.FileSigns table<number, loop.signs.LineSigns>        -- line → signs on that line
---@class loop.signs.GroupSigns table<string, loop.signs.FileSigns>       -- absolute filepath → lines

--- Main storage: group → file → line → signs
---@type table<loop.signs.SignGroup, loop.signs.GroupSigns>
local _signs = {}

local _setup_done = false
local _signs_id_prefix = "loopplugin_signs_"

-- -------------------------------------------------------------------
-- Private helpers
-- -------------------------------------------------------------------

--- Generate a unique sign ID from buffer number and line
---@param bufnr integer
---@param line integer
---@return integer
local function _sign_id(bufnr, line)
    return bufnr * 1000000 + line
end

--- Return the loaded buffer number for a file, or -1 if not loaded
---@param file string absolute path
---@return integer bufnr >=0 if loaded, -1 otherwise
local function _get_loaded_bufnr(file)
    local bufnr = vim.fn.bufnr(file, false)
    return (bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr)) and bufnr or -1
end

--- Remove all signs of a specific group from a buffer
---@param bufnr integer
---@param group loop.signs.SignGroup
local function _remove_buf_signs(bufnr, group)
    vim.fn.sign_unplace(_signs_id_prefix .. group, { buffer = bufnr })
end

--- Place a single sign in a buffer
---@param bufnr integer
---@param line integer
---@param group loop.signs.SignGroup
---@param name loop.signs.SignName
local function _place_sign(bufnr, line, group, name)
    vim.fn.sign_place(
        _sign_id(bufnr, line),
        _signs_id_prefix .. group,
        _signs_id_prefix .. name,
        bufnr,
        { lnum = line, priority = config.current.debug.sign_priority or 12 }
    )
end

--- Re-apply all stored signs of one group to a specific buffer
---@param bufnr integer
---@param group loop.signs.SignGroup
local function _apply_buffer_signs(bufnr, group)
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then return end
    file = vim.fn.fnamemodify(file, ":p")

    local group_table = _signs[group]
    if not group_table then return end

    local file_table = group_table[file]
    if not file_table then return end

    for line, line_signs in pairs(file_table) do
        for name, _ in pairs(line_signs) do
            _place_sign(bufnr, line, group, name)
        end
    end
end

-- -------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------

--- Add or update a sign at a specific line in a file
---@param file string path to file (relative or absolute)
---@param line integer 1-based line number
---@param group loop.signs.SignGroup
---@param name loop.signs.SignName
function M.place_file_sign(file, line, group, name)
    assert(_setup_done, "loop.signs.setup() must be called first")

    file = vim.fn.fnamemodify(file, ":p")

    -- Ensure nested tables exist
    local group_table = _signs[group] or {}
    _signs[group] = group_table

    local file_table = group_table[file] or {}
    group_table[file] = file_table

    local line_table = file_table[line] or {}
    file_table[line] = line_table

    line_table[name] = true

    -- Place immediately if buffer is loaded
    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        _place_sign(bufnr, line, group, name)
    end
end

--- Remove a specific sign from a line (other signs on the same line remain)
---@param file string
---@param line integer
---@param group loop.signs.SignGroup
function M.remove_file_sign(file, line, group)
    assert(_setup_done, "loop.signs.setup() must be called first")

    file = vim.fn.fnamemodify(file, ":p")

    local group_table = _signs[group]
    if not group_table then return end

    local file_table = group_table[file]
    if not file_table then return end

    file_table[line] = nil

    -- Clean up empty containers
    if not next(file_table) then
        group_table[file] = nil
        if not next(group_table) then
            _signs[group] = nil
        end
    end

    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        vim.fn.sign_unplace(_signs_id_prefix .. group, {
            buffer = bufnr,
            id = _sign_id(bufnr, line),
        })
    end
end

--- Remove all signs of a group from a file
---@param file string
---@param group loop.signs.SignGroup
function M.remove_file_signs(file, group)
    assert(_setup_done, "loop.signs.setup() must be called first")

    file = vim.fn.fnamemodify(file, ":p")

    local group_table = _signs[group]
    if not group_table then return end

    group_table[file] = nil

    if not next(group_table) then
        _signs[group] = nil
    end

    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        _remove_buf_signs(bufnr, group)
    end
end

--- Remove all signs of a specific group across **all files and buffers**
--- This clears the internal storage for that group and removes every visible sign from Neovim.
---@param group loop.signs.SignGroup
function M.remove_signs(group)
    assert(_setup_done, "loop.signs.setup() must be called first")

    local group_table = _signs[group]
    if not group_table then
        return -- nothing to do
    end

    -- Remove all visible signs from every loaded buffer that belongs to this group
    for file, _ in pairs(group_table) do
        local bufnr = _get_loaded_bufnr(file)
        if bufnr >= 0 then
            _remove_buf_signs(bufnr, group)
        end
    end

    -- Clear the internal data structure for this group
    _signs[group] = nil
end

--- Remove all signs from all files and buffers
function M.clear_all()
    for group, group_table in pairs(_signs) do
        for file, _ in pairs(group_table) do
            local bufnr = _get_loaded_bufnr(file)
            if bufnr >= 0 then
                _remove_buf_signs(bufnr, group)
            end
        end
    end
    _signs = {}
end

--- Refresh all signs of one group in all currently loaded buffers
---@param group loop.signs.SignGroup
function M.refresh_all_signs(group)
    assert(_setup_done, "loop.signs.setup() must be called first")

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            _remove_buf_signs(bufnr, group)
            _apply_buffer_signs(bufnr, group)
        end
    end
end

-- -------------------------------------------------------------------
-- Setup & sign definitions
-- -------------------------------------------------------------------

---@param name loop.signs.SignName
---@param text string
---@param texthl string
local function _define_sign(name, text, texthl)
    vim.fn.sign_define(_signs_id_prefix .. name, {
        text = text,
        texthl = texthl,
    })
end

--- Initialize the signs module – must be called once before use
function M.setup()
    if _setup_done then return end
    _setup_done = true

    _define_sign("active_breakpoint", "●", "Debug")
    _define_sign("inactive_breakpoint", "○", "Debug")
    _define_sign("currentframe", "▶", "Todo")

    -- Clean up signs when buffers are unloaded/deleted
    vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
        callback = function(ev)
            local bufnr = ev.buf
            _remove_buf_signs(bufnr, "breakpoints")
            _remove_buf_signs(bufnr, "currentframe")
        end,
    })

    -- Re-apply signs when a buffer is read (re)loaded
    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(ev)
            _apply_buffer_signs(ev.buf, "breakpoints")
            _apply_buffer_signs(ev.buf, "currentframe")
        end,
    })
end

return M
