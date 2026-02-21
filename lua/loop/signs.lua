local extmarks = require("loop.extmarks")

local M = {}

-- ===================================================================
-- Types
-- ===================================================================

---@class loop.signs.Group
---@field define_sign fun(name:string, text:string, texthl:string)
---@field place_file_sign fun(id:number, file:string, lnum:number, name:string,user_data:any)
---@field remove_file_sign fun(id:number)
---@field remove_file_signs fun(file:string)
---@field remove_signs fun()
---@field get_signs fun(committed:boolean): loop.signs.Sign[]
---@field get_sign fun(file:string, lnum:number, committed:boolean): loop.signs.Sign?
---@field refresh fun()

---@class loop.signs.Sign
---@field id number
---@field file string
---@field name string
---@field lnum number
---@field priority number
---@field user_data any

-- ===================================================================
-- Public API
-- ===================================================================

---@param group string
---@param opts { priority:number }
---@return loop.signs.Group
function M.define_group(group, opts)
    assert(group, "group required")
    assert(opts and opts.priority, "priority required")

    local priority = opts.priority
    local sign_defs = {} ---@type table<string,{text:string,texthl:string}>

    local ext = extmarks.define_group(group, {
        priority = priority,
    })

    return {

        ----------------------------------------------------------------
        -- Define sign appearance
        ----------------------------------------------------------------
        define_sign = function(name, text, texthl)
            assert(name and text and texthl, "invalid sign definition")
            assert(not sign_defs[name], "sign already defined")

            sign_defs[name] = {
                text = text,
                texthl = texthl,
            }
        end,

        ----------------------------------------------------------------
        -- Place sign (delegates fully to extmarks)
        ----------------------------------------------------------------
        place_file_sign = function(id, file, lnum, name, user_data)
            assert(sign_defs[name], "sign not defined")
            assert(lnum >= 1, "lnum must be 1-based")

            local def = sign_defs[name]

            ext.place_file_extmark(
                id,
                file,
                lnum,
                0,
                {
                    sign_text = def.text,
                    sign_hl_group = def.texthl,
                },
                {
                    name = name, -- stored inside extmark
                    user_data = user_data
                }
            )
        end,

        ----------------------------------------------------------------
        -- Remove single sign
        ----------------------------------------------------------------
        remove_file_sign = function(id)
            ext.remove_extmark(id)
        end,

        ----------------------------------------------------------------
        -- Remove all signs from file
        ----------------------------------------------------------------
        remove_file_signs = function(file)
            ext.remove_file_extmarks(file)
        end,

        ----------------------------------------------------------------
        -- Remove entire group
        ----------------------------------------------------------------
        remove_signs = function()
            ext.remove_extmarks()
        end,

        ----------------------------------------------------------------
        -- Query all signs (derived from extmarks)
        ----------------------------------------------------------------
        get_signs = function(committed)
            local marks = ext.get_extmarks(committed)

            ---@type loop.signs.Sign[]
            local result = {}

            for _, mark in ipairs(marks) do
                local user = mark.user_data
                if user and user.name then
                    result[#result + 1] = {
                        id = mark.id,
                        file = mark.file,
                        name = user.name,
                        lnum = mark.lnum,
                        priority = priority,
                        user_data = user.user_data
                    }
                end
            end

            return result
        end,

        ----------------------------------------------------------------
        -- Get a single sign by file and line
        ----------------------------------------------------------------
        get_sign = function(file, lnum, committed)
            local mark = ext.get_extmark(file, lnum, committed)
            if mark then
                local user = mark.user_data
                if user and user.name and mark.file == file and mark.lnum == lnum then
                    return {
                        id = mark.id,
                        file = mark.file,
                        name = user.name,
                        lnum = mark.lnum,
                        priority = priority,
                        user_data = user.user_data
                    }
                end
            end
            return nil
        end,

        ----------------------------------------------------------------
        -- Refresh extmarks
        ----------------------------------------------------------------
        refresh = function()
            ext.refresh()
        end,
    }
end

return M
