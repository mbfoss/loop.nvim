local M = {}

---@alias loop.sign.SignGroup "breakpoints"|"currentframe"
---@alias loop.sign.SignName "active_breakpoint"|"currentframe"

---@alias loop.signs.LineSigns table<loop.sign.SignName,boolean>

---@alias loop.signs.GroupSigns table<number,loop.signs.LineSigns>

---@alias loop.signs.FileSigns table<loop.sign.SignGroup, loop.signs.GroupSigns>

---@type table<string, loop.signs.FileSigns> -- by file
local _signs = {}

--- Whether setup() has been called.
---@type boolean
local _setup_done = false

---@type string
local _signs_id_prefix = "loopplugin_signs_"

-- ----------------------------------------------------------------------
-- Internal utility functions
-- ----------------------------------------------------------------------

local function _sign_id(bufnr, line)
    return bufnr * 1000000 + line -- 1M per buffer
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

--- Remove all signs from a given buffer.
---@param bufnr integer Buffer number
---@param group loop.sign.SignGroup
local function _remove_buf_signs(bufnr, group)
    vim.fn.sign_unplace(_signs_id_prefix .. group, { buffer = bufnr })
end

--- Add a single sign for a given line in a buffer.
---@param bufnr integer Buffer number
---@param line integer Line number
---@param group loop.sign.SignGroup
---@param name loop.sign.SignName
local function _add_buf_sign(bufnr, line, group, name)
    vim.fn.sign_place(
        _sign_id(bufnr, line),     -- sign ID
        _signs_id_prefix .. group, -- sign group name
        _signs_id_prefix .. name,  -- sign type name
        bufnr,                     -- buffer handle
        { lnum = line, priority = 10 }
    )
end

---@param bufnr integer Buffer number
---@param group loop.sign.SignGroup
local function _add_buf_signs(bufnr, group)
    local file = vim.api.nvim_buf_get_name(bufnr)
    file = vim.fn.fnamemodify(file, ":p")
    local filesigns = _signs[file]
    for line, linesigns in pairs(filesigns[group] or {}) do
        for sign, _ in pairs(linesigns or {}) do
            _add_buf_sign(bufnr, line, group, sign)
        end
    end
end

--- Add a sign to a file (if the buffer is loaded).
---@param file string File path
---@param line integer Line number
---@param group loop.sign.SignGroup
---@param name loop.sign.SignName
function M.add_file_sign(file, line, group, name)
    assert(_setup_done)
    file = vim.fn.fnamemodify(file, ":p")

    _signs[file] = _signs[file] or {}
    local filesigns = _signs[file]

    filesigns[group] = filesigns[group] or {}
    local groupsigns = filesigns[group]

    groupsigns[line] = groupsigns[line] or {}
    local linesigns = groupsigns[line]

    linesigns[name] = true

    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        _add_buf_sign(bufnr, line, group, name)
    end
end

--- Remove a sign from a file (if the buffer is loaded).
---@param file string File path
---@param line integer Line number
---@param group loop.sign.SignGroup
function M.remove_file_sign(file, line, group)
    assert(_setup_done)
    file = vim.fn.fnamemodify(file, ":p")
    local filesigns = _signs[file]
    local removed = false
    if filesigns then
        local groupsigns = filesigns[group]
        if groupsigns and groupsigns[line] then
            groupsigns[line] = nil
            removed = true
        end
    end
    if removed then
        local bufnr = _get_loaded_bufnr(file)
        if bufnr >= 0 then
            vim.fn.sign_unplace(_signs_id_prefix .. group, { buffer = bufnr, id = _sign_id(bufnr, line) })
        end
    end
end

--- Remove a sign from a file (if the buffer is loaded).
---@param file string File path
---@param group loop.sign.SignGroup
function M.remove_file_signs(file, group)
    assert(_setup_done)
    file = vim.fn.fnamemodify(file, ":p")
    local filesigns = _signs[file]
    local removed = false
    if filesigns and filesigns[group] then
        filesigns[group] = nil
        removed = true
    end
    if removed then
        local bufnr = _get_loaded_bufnr(file)
        if bufnr >= 0 then
            _remove_buf_signs(bufnr, group)
        end
    end
end

---@param group loop.sign.SignGroup
function M.refresh_all_signs(group)
    assert(_setup_done)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            _remove_buf_signs(bufnr, group)
            _add_buf_signs(bufnr, group)
        end
    end
end

---@param name loop.sign.SignName
---@param text string
---@param hightlight string
local function _define_sign(name, text, hightlight)
    vim.fn.sign_define(_signs_id_prefix .. name, { text = text, texthl = hightlight })
end

--- Setup the breakpoint sign system and autocommands.
---@param _? table Optional setup options (currently unused)
function M.setup(_)
    assert(not _setup_done, "setup already done")
    _setup_done = true

    _define_sign("active_breakpoint", '●', 'Debug')
    _define_sign("currentframe", '>', 'Todo')

    -- Remove signs when buffers are deleted or unloaded
    vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
        callback = function(args)
            _remove_buf_signs(args.buf, "breakpoints")
            _remove_buf_signs(args.buf, "currentframe")
        end,
    })

    -- Reapply signs after reading a buffer
    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(args)
            _add_buf_signs(args.buf, "breakpoints")
            _add_buf_signs(args.buf, "currentframe")
        end,
    })
end

return M
