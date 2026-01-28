local extmarks = require("loop.extmarks")

local M = {}

-- ===================================================================
-- Types (unchanged externally)
-- ===================================================================

---@class loop.signs.Sign
---@field id number
---@field group string
---@field name string
---@field lnum number
---@field priority number

---@alias loop.signs.ById table<number, loop.signs.Sign>
---@alias loop.signs.BySignName table<string, loop.signs.ById>
---@alias loop.signs.ByFile table<string, loop.signs.BySignName>

---@class loop.signs.GroupData
---@field byfile loop.signs.ByFile
---@field id_to_file table<number, string>

---@class loop.signs.GroupInfo
---@field sign_names table<string, { text: string, texthl: string }>
---@field priority number

---@type table<string, loop.signs.GroupInfo>
local _defined_signs = {}

---@type table<string, loop.signs.GroupData>
local _signs = {}

-- ===================================================================
-- Helpers
-- ===================================================================

local function _normalize_file(file)
    return vim.fn.fnamemodify(file, ":p")
end

-- ===================================================================
-- Public API
-- ===================================================================

---@param group string
---@param priority number
function M.define_sign_group(group, priority)
    assert(group and priority)
    assert(not _defined_signs[group], "sign group already defined")

    _defined_signs[group] = {
        sign_names = {},
        priority = priority,
    }

    -- mirrored extmark group
    extmarks.define_group(group, { priority = priority })
end

---@param group string
---@param name string
---@param text string
---@param texthl string
function M.define_sign(group, name, text, texthl)
    assert(group and name and text and texthl)

    local g = _defined_signs[group]
    assert(g, "sign group not defined")
    assert(not g.sign_names[name], "sign already defined")

    g.sign_names[name] = {
        text = text,
        texthl = texthl,
    }
end

---@param id number
---@param file string
---@param line number   -- 1-based (sign API preserved)
---@param group string
---@param name string
function M.place_file_sign(id, file, line, group, name)
    local g = _defined_signs[group]
    assert(g and g.sign_names[name], "sign group/name not defined")

    file = _normalize_file(file)

    local group_data = _signs[group]
    if not group_data then
        group_data = { byfile = {}, id_to_file = {} }
        _signs[group] = group_data
    end

    -- remove this id from all names in this file
    local file_table = group_data.byfile[file]
    if file_table then
        for _, signs in pairs(file_table) do
            signs[id] = nil
        end
    end

    group_data.id_to_file[id] = file
    group_data.byfile[file] = group_data.byfile[file] or {}

    local byname = group_data.byfile[file]
    byname[name] = byname[name] or {}

    local sign = {
        id = id,
        group = group,
        name = name,
        lnum = line,
        priority = g.priority,
    }

    byname[name][id] = sign

    local def = g.sign_names[name]

    extmarks.place_file_extmark(
        id,
        file,
        line - 1, -- extmarks are 0-based
        0,
        group,
        {
            sign_text = def.text,
            sign_hl_group = def.texthl,
        }
    )
end

---@param id number
---@param group string
function M.remove_file_sign(id, group)
    assert(_defined_signs[group], "sign group not defined")

    local group_data = _signs[group]
    if not group_data then return end

    local file = group_data.id_to_file[id]
    if not file then return end

    group_data.id_to_file[id] = nil

    local file_table = group_data.byfile[file]
    if file_table then
        for _, signs in pairs(file_table) do
            signs[id] = nil
        end
    end

    extmarks.remove_file_extmark(id, group)
end

---@param file string
---@param group string
function M.remove_file_signs(file, group)
    assert(_defined_signs[group], "sign group not defined")

    file = _normalize_file(file)

    local group_data = _signs[group]
    if not group_data then return end

    local file_table = group_data.byfile[file]
    if not file_table then return end

    for _, signs in pairs(file_table) do
        for id in pairs(signs) do
            group_data.id_to_file[id] = nil
        end
    end

    group_data.byfile[file] = nil

    extmarks.remove_file_extmarks(file, group)
end

---@param group string
function M.remove_signs(group)
    assert(_defined_signs[group], "sign group not defined")

    _signs[group] = nil
    extmarks.remove_extmarks(group)
end

function M.clear_all()
    _signs = {}
    extmarks.clear_all()
end

---@param group string
function M.refresh_all_signs(group)
    assert(_defined_signs[group], "sign group not defined")
    extmarks.refresh_group(group)
end

---@param file string
---@return table<number, loop.signs.Sign>
function M.get_file_signs_by_id(file)
    file = vim.fn.fnamemodify(file, ":p")
    ---@type table<number, loop.signs.Sign>
    local out = {}
    for _, group_data in pairs(_signs) do
        local file_table = group_data.byfile[file]
        if file_table then
            for _, signs in pairs(file_table) do
                for id, sign in pairs(signs) do
                    out[id] = sign
                end
            end
        end
    end
    return out
end

return M
