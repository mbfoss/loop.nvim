local M = {}

-- ===================================================================
-- Types
-- ===================================================================

---@class loop.extmarks.Mark
---@field id number
---@field group string
---@field ns number
---@field row number        -- 0-based
---@field col number        -- 0-based
---@field opts vim.api.keyset.set_extmark

---@alias loop.extmarks.ById table<number, loop.extmarks.Mark>
---@alias loop.extmarks.ByFile table<string, loop.extmarks.ById>

---@class loop.extmarks.GroupData
---@field ns number
---@field byfile loop.extmarks.ByFile
---@field id_to_file table<number, string>

---@class loop.extmarks.GroupInfo
---@field priority number|nil

---@type table<string, loop.extmarks.GroupInfo>
local _defined_groups = {}

---@type table<string, loop.extmarks.GroupData>
local _groups = {}

local _init_done = false

-- ===================================================================
-- Helpers
-- ===================================================================

---@param file string
---@return integer
local function _get_loaded_bufnr(file)
    local bufnr = vim.fn.bufnr(file, false)
    return (bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr)) and bufnr or -1
end

---@param bufnr integer
---@param mark loop.extmarks.Mark
local function _place_extmark(bufnr, mark)
    vim.api.nvim_buf_set_extmark(
        bufnr,
        mark.ns,
        mark.row,
        mark.col,
        mark.opts
    )
end

---@param bufnr integer
---@param ns integer
local function _clear_buf_namespace(bufnr, ns)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---@param bufnr integer
---@param group string
local function _apply_buffer_extmarks(bufnr, group)
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then return end
    file = vim.fn.fnamemodify(file, ":p")

    local group_data = _groups[group]
    if not group_data then return end

    local file_data = group_data.byfile[file]
    if not file_data then return end

    for _, mark in pairs(file_data) do
        _place_extmark(bufnr, mark)
    end
end


---@param bufnr number
local function _sync_file_extmarks(bufnr)
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then return end
    file = vim.fn.fnamemodify(file, ":p")

    for _, group_data in pairs(_groups) do
        local file_table = group_data.byfile[file]
        if not file_table then
            goto continue
        end

        local placed = vim.api.nvim_buf_get_extmarks(
            bufnr,
            group_data.ns,
            0,
            -1,
            { details = false }
        )

        for _, m in ipairs(placed) do
            local id, row, col = m[1], m[2], m[3]
            local mark = file_table[id]
            if mark then
                mark.row = row
                mark.col = col
            end
        end

        ::continue::
    end
end


local function _ensure_init()
    if _init_done then return end
    _init_done = true

    local augroup = vim.api.nvim_create_augroup("loopplugin_extmarks", { clear = true })

    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
        group = augroup,
        callback = function(ev)
            for group in pairs(_defined_groups) do
                _apply_buffer_extmarks(ev.buf, group)
            end
        end,
    })


    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        callback = function(ev)
            local bufnr = ev.buf
            _sync_file_extmarks(bufnr)
        end
    })
end

-- ===================================================================
-- Public API
-- ===================================================================

---@param group string
---@param opts? { priority?: number }
function M.define_group(group, opts)
    assert(group, "group required")
    assert(not _defined_groups[group], "group already defined")

    _defined_groups[group] = {
        priority = opts and opts.priority or nil,
    }
end

---@param id number
---@param file string
---@param row number        -- 0-based
---@param col number        -- 0-based
---@param group string
---@param opts vim.api.keyset.set_extmark       -- extmark opts
function M.place_file_extmark(id, file, row, col, group, opts)
    _ensure_init()

    local group_info = _defined_groups[group]
    assert(group_info, "group not defined")

    file = vim.fn.fnamemodify(file, ":p")
    local bufnr = _get_loaded_bufnr(file)

    local group_data = _groups[group]
    if not group_data then
        group_data = {
            ns = vim.api.nvim_create_namespace("loopplugin_extmarks_" .. group),
            byfile = {},
            id_to_file = {},
        }
        _groups[group] = group_data
    end

    -- remove previous instance of this id
    local old_file = group_data.id_to_file[id]
    if old_file then
        local old_bufnr = _get_loaded_bufnr(old_file)
        if old_bufnr >= 0 then
            vim.api.nvim_buf_del_extmark(old_bufnr, group_data.ns, id)
        end
    end

    group_data.id_to_file[id] = file
    group_data.byfile[file] = group_data.byfile[file] or {}

    local mark = {
        id = id,
        group = group,
        ns = group_data.ns,
        row = row,
        col = col,
        opts = vim.tbl_extend("force", {
            id = id,
            priority = group_info.priority,
        }, opts or {}),
    }

    group_data.byfile[file][id] = mark

    if bufnr >= 0 then
        _place_extmark(bufnr, mark)
    end
end

---@param id number
---@param group string
function M.remove_file_extmark(id, group)
    _ensure_init()
    assert(_defined_groups[group], "group not defined")

    local group_data = _groups[group]
    if not group_data then return end

    local file = group_data.id_to_file[id]
    if not file then return end

    group_data.id_to_file[id] = nil

    local file_table = group_data.byfile[file]
    if not file_table then return end

    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        vim.api.nvim_buf_del_extmark(bufnr, group_data.ns, id)
    end

    file_table[id] = nil
end

---@param file string
---@param group string
function M.remove_file_extmarks(file, group)
    _ensure_init()
    assert(_defined_groups[group], "group not defined")

    file = vim.fn.fnamemodify(file, ":p")

    local group_data = _groups[group]
    if not group_data then return end

    local file_table = group_data.byfile[file]
    if not file_table then return end

    for id in pairs(file_table) do
        group_data.id_to_file[id] = nil
    end

    group_data.byfile[file] = nil

    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        _clear_buf_namespace(bufnr, group_data.ns)
    end
end

---@param group string
function M.remove_extmarks(group)
    _ensure_init()
    assert(_defined_groups[group], "group not defined")

    local group_data = _groups[group]
    if not group_data then return end

    for file in pairs(group_data.byfile) do
        local bufnr = _get_loaded_bufnr(file)
        if bufnr >= 0 then
            _clear_buf_namespace(bufnr, group_data.ns)
        end
    end

    _groups[group] = nil
end

function M.clear_all()
    _ensure_init()

    for _, group_data in pairs(_groups) do
        for file in pairs(group_data.byfile) do
            local bufnr = _get_loaded_bufnr(file)
            if bufnr >= 0 then
                _clear_buf_namespace(bufnr, group_data.ns)
            end
        end
    end

    _groups = {}
end

---@param group string
function M.refresh_group(group)
    _ensure_init()
    assert(_defined_groups[group], "group not defined")

    local group_data = _groups[group]
    if not group_data then return end

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            _clear_buf_namespace(bufnr, group_data.ns)
            _apply_buffer_extmarks(bufnr, group)
        end
    end
end

---@param file string
---@return table<number, loop.extmarks.Mark>
function M.get_file_extmarks_by_id(file)
    file = vim.fn.fnamemodify(file, ":p")

    ---@type table<number, loop.extmarks.Mark>
    local out = {}

    for _, group_data in pairs(_groups) do
        local file_table = group_data.byfile[file]
        if file_table then
            for id, mark in pairs(file_table) do
                out[id] = mark
            end
        end
    end

    return out
end

return M
