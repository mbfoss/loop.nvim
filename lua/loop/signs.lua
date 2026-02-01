local extmarks = require("loop.extmarks")

local M = {}

-- ===================================================================
-- Types
-- ===================================================================

---@class loop.signs.Group
---@field define_sign fun(name:string, text:string, texthl:string)
---@field place_file_sign fun(id:number, file:string, lnum:number, name:string)
---@field remove_file_sign fun(id:number)
---@field remove_file_signs fun(file:string)
---@field remove_signs fun()
---@field refresh fun()

---@class loop.signs.Sign
---@field id number
---@field name string
---@field lnum number
---@field priority number

---@alias loop.signs.ById table<number, loop.signs.Sign>
---@alias loop.signs.BySignName table<string, loop.signs.ById>
---@alias loop.signs.ByFile table<string, loop.signs.BySignName>

---@class loop.signs.GroupData
---@field byfile loop.signs.ByFile
---@field id_to_file table<number, string>

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
---@param opts { priority:number }
---@param on_update? fun(file:string,signs:loop.signs.ById)
---@return loop.signs.Group
function M.define_group(group, opts, on_update)
    assert(group, "group required")
    assert(opts and opts.priority, "priority required")

    local priority = opts.priority

    -- group-local state (closure)
    ---@type loop.signs.GroupData
    local data = {
        byfile = {},
        id_to_file = {},
    }

    local sign_defs = {} ---@type table<string,{text:string,texthl:string}>

    -- extmark update bridge
    local function on_marks_update(file, marks)
        file = _normalize_file(file)

        local file_table = data.byfile[file]
        if not file_table then return end

        ---@type loop.signs.ById
        local updated = {}

        for id, mark in pairs(marks) do
            for _, signs in pairs(file_table) do
                local sign = signs[id]
                if sign then
                    sign.lnum = mark.lnum
                    updated[id] = sign
                    break
                end
            end
        end

        if on_update then
            on_update(file, updated)
        end
    end

    -- mirror extmarks group
    local ext = extmarks.define_group(
        group,
        { priority = priority },
        on_marks_update
    )

    -- ===============================================================
    -- Returned API (closure)
    -- ===============================================================

    ---@type loop.signs.Group
    return {

        define_sign = function(name, text, texthl)
            assert(name and text and texthl, "invalid sign definition")
            assert(not sign_defs[name], "sign already defined")

            sign_defs[name] = {
                text = text,
                texthl = texthl,
            }
        end,

        place_file_sign = function(id, file, lnum, name)
            assert(sign_defs[name], "sign not defined")
            assert(lnum >= 1, "lnum must be 1-based")

            file = _normalize_file(file)

            -- remove id from previous file
            local old_file = data.id_to_file[id]
            if old_file then
                local ft = data.byfile[old_file]
                if ft then
                    for _, signs in pairs(ft) do
                        signs[id] = nil
                    end
                end
            end

            data.id_to_file[id] = file
            data.byfile[file] = data.byfile[file] or {}

            local byname = data.byfile[file]
            byname[name] = byname[name] or {}

            local sign = {
                id = id,
                name = name,
                lnum = lnum,
                priority = priority,
            }

            byname[name][id] = sign

            local def = sign_defs[name]

            ext.place_file_extmark(
                id,
                file,
                lnum,
                0,
                {
                    sign_text = def.text,
                    sign_hl_group = def.texthl,
                }
            )
        end,

        remove_file_sign = function(id)
            local file = data.id_to_file[id]
            if not file then return end

            data.id_to_file[id] = nil

            local ft = data.byfile[file]
            if ft then
                for _, signs in pairs(ft) do
                    signs[id] = nil
                end
            end

            ext.remove_extmark(id)
        end,

        remove_file_signs = function(file)
            file = _normalize_file(file)

            local ft = data.byfile[file]
            if not ft then return end

            for _, signs in pairs(ft) do
                for id in pairs(signs) do
                    data.id_to_file[id] = nil
                end
            end

            data.byfile[file] = nil
            ext.remove_file_extmarks(file)
        end,

        remove_signs = function()
            data.byfile = {}
            data.id_to_file = {}
            ext.remove_extmarks()
        end,

        refresh = function()
            ext.refresh()
        end,
    }
end

return M
