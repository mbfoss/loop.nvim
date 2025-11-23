local M = {}

---@alias loop.sign.SignGroup "breakpoints"|"currentframe"
---@alias loop.sign.SignName  "active_breakpoint"|"inactive_breakpoint"|"currentframe"

---@alias loop.signs.LineSigns table<loop.sign.SignName, boolean>
---@alias loop.signs.GroupSigns table<number, loop.signs.LineSigns>   -- line → signs
---@alias loop.signs.FileSigns  table<loop.sign.SignGroup, loop.signs.GroupSigns>

---@type table<string, loop.signs.FileSigns>  -- absolute path → signs
local _signs = {}

local _setup_done = false
local _signs_id_prefix = "loopplugin_signs_"

-- Use global unique IDs instead of bufnr*1M+line
local function _sign_id(bufnr, line)
    return bufnr * 1000000 + line -- 1M per buffer
end

local function _get_loaded_bufnr(file)
    local bufnr = vim.fn.bufnr(file, false)
    return (bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr)) and bufnr or -1
end

local function _remove_buf_signs(bufnr, group)
    vim.fn.sign_unplace(_signs_id_prefix .. group, { buffer = bufnr })
end

local function _place_sign(bufnr, line, group, name)
    vim.fn.sign_place(
        _sign_id(bufnr, line),
        _signs_id_prefix .. group,
        _signs_id_prefix .. name,
        bufnr,
        { lnum = line, priority = 10 }
    )
end

local function _apply_buffer_signs(bufnr, group)
    local file = vim.api.nvim_buf_get_name(bufnr)
    file = vim.fn.fnamemodify(file, ":p")
    local filesigns = _signs[file]
    if not filesigns then return end

    local groupsigns = filesigns[group]
    if not groupsigns then return end

    for line, linesigns in pairs(groupsigns) do
        for name, _ in pairs(linesigns) do
            -- We don't store the numeric ID, so we can't reuse it.
            -- Just place a new one (Neovim will replace any existing in same group/name).
            -- This is simpler and safe.
            _place_sign(bufnr, line, group, name)
        end
    end
end

-- ------------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------------

function M.add_file_sign(file, line, group, name)
    assert(_setup_done, "loop.signs.setup() not called")
    file = vim.fn.fnamemodify(file, ":p")

    _signs[file] = _signs[file] or {}
    local filesigns = _signs[file]
    filesigns[group] = filesigns[group] or {}
    local groupsigns = filesigns[group]
    groupsigns[line] = groupsigns[line] or {}
    groupsigns[line][name] = true

    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        _place_sign(bufnr, line, group, name) -- 0 lets Neovim pick ID
    end
end

function M.remove_file_sign(file, line, group)
    assert(_setup_done)
    file = vim.fn.fnamemodify(file, ":p")
    local filesigns = _signs[file]
    if not filesigns then return end

    local groupsigns = filesigns[group]
    if not groupsigns then return end

    groupsigns[line] = nil
    if not next(groupsigns) then
        filesigns[group] = nil
    end

    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        -- Remove only this specific sign type in this group
        vim.fn.sign_unplace(_signs_id_prefix .. group, {
            buffer = bufnr,
            id = _sign_id(bufnr, line),
        })
    end
end

function M.remove_file_signs(file, group)
    assert(_setup_done)
    file = vim.fn.fnamemodify(file, ":p")
    local filesigns = _signs[file]
    if filesigns and filesigns[group] then
        filesigns[group] = nil
        local bufnr = _get_loaded_bufnr(file)
        if bufnr >= 0 then
            _remove_buf_signs(bufnr, group)
        end
    end
end

function M.clear_all()
    for file, filesigns in pairs(_signs) do
        for group, _ in pairs(filesigns) do
            local bufnr = _get_loaded_bufnr(file)
            if bufnr >= 0 then
                _remove_buf_signs(bufnr, group)
            end
        end
    end
    _signs = {}
end

function M.refresh_all_signs(group)
    assert(_setup_done)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            _remove_buf_signs(bufnr, group)
            _apply_buffer_signs(bufnr, group)
        end
    end
end

-- ------------------------------------------------------------------
-- Setup
-- ------------------------------------------------------------------

local function _define_sign(name, text, hl)
    vim.fn.sign_define(_signs_id_prefix .. name, {
        text = text,
        texthl = hl,
    })
end

function M.setup()
    if _setup_done then return end
    _setup_done = true

    _define_sign("active_breakpoint", "●", "Debug")
    _define_sign("currentframe", "▶", "Todo")

    -- Clean up when buffer is deleted/unloaded
    vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
        callback = function(ev)
            local bufnr = ev.buf
            _remove_buf_signs(bufnr, "breakpoints")
            _remove_buf_signs(bufnr, "currentframe")
        end,
    })

    -- Re-apply signs when a buffer becomes visible/loaded
    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(ev)
            _apply_buffer_signs(ev.buf, "breakpoints")
            _apply_buffer_signs(ev.buf, "currentframe")
        end,
    })
end

return M
