local M = {}
local config = require('loop.config')

---@alias SimpleValue string | number | boolean | table

local function _is_simple_data(value, _seen)
    _seen = _seen or {}
    local t = type(value)
    if t == "string" or t == "number" or t == "boolean" then return true end
    if t ~= "table" then return false, ("unsupported type: %s"):format(t) end
    if _seen[value] then return true end
    _seen[value] = true

    for k, v in pairs(value) do
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" then
            return false, ("table key must be string or number, got %s"):format(kt)
        end
        local ok, err = _is_simple_data(v, _seen)
        if not ok then return false, ("invalid value at key %s: %s"):format(vim.inspect(k), err) end
    end
    return true
end

local ESCAPE_MARKER = "\001"

-- FIXED: Correct async string expansion with proper placeholder replacement
local function _expand_string_async(str, callback)
    if type(str) ~= "string" then
        return callback(false, nil, "Input must be a string")
    end
    if str:find(ESCAPE_MARKER, 1, true) then
        return callback(false, nil, "String contains internal escape sequence")
    end

    local escaped = str:gsub("%$%${(.-)}", ESCAPE_MARKER .. "{%1}")

    -- Single macro case
    local single_macro = str:match("^%${([^}]+)}$")
    if single_macro then
        local fn = config.current.macros[single_macro]
        if not fn then
            return callback(false, nil, ("Unknown macro: ${%s}"):format(single_macro))
        end

        local ok, err = pcall(fn, function(value, macro_err)
            if macro_err then
                callback(false, nil, macro_err)
            elseif not _is_simple_data(value) then
                callback(false, nil, ("Macro ${%s} returned invalid data"):format(single_macro))
            else
                callback(true, value)
            end
        end)

        if not ok then
            callback(false, nil, ("Macro ${%s} crashed: %s"):format(single_macro, err))
        end
        return
    end

    -- Multiple macros: build list first, then resolve sequentially
    local macros = {}
    local template = escaped:gsub("%${([^}]+)}", function(name)
        local id = #macros + 1
        table.insert(macros, { name = name, id = id })
        return "\002" .. id .. "\002"
    end)

    if #macros == 0 then
        local final = template:gsub(ESCAPE_MARKER .. "{(.-)}", "${%1}")
        return callback(true, final)
    end

    local result_parts = { template }
    local pending = #macros
    local success = true
    local last_err = nil

    for _, macro in ipairs(macros) do
        local fn = config.current.macros[macro.name]
        if not fn then
            success = false
            last_err = ("Unknown macro: ${%s}"):format(macro.name)
            pending = pending - 1
            if pending == 0 then callback(success, nil, last_err) end
            goto continue
        end

        local ok, call_err = pcall(fn, function(value, err)
            if not success then
                pending = pending - 1
                if pending == 0 then callback(success, nil, last_err) end
                return
            end

            if err then
                success = false
                last_err = err
            elseif type(value) ~= "string" then
                success = false
                last_err = ("Macro ${%s} returned non-string: %s"):format(macro.name, type(value))
            else
                -- Replace placeholder in all parts
                local placeholder = "\002" .. macro.id .. "\002"
                for i, part in ipairs(result_parts) do
                    result_parts[i] = part:gsub(placeholder, value, 1)
                end
            end

            pending = pending - 1
            if pending == 0 then
                local final_result = table.concat(result_parts):gsub(ESCAPE_MARKER .. "{(.-)}", "${%1}")
                callback(success, final_result, last_err)
            end
        end)

        if not ok then
            success = false
            last_err = ("Macro ${%s} crashed: %s"):format(macro.name, call_err)
            pending = pending - 1
            if pending == 0 then callback(success, nil, last_err) end
        end

        ::continue::
    end
end

-- Table expansion — unchanged and correct
local function _expand_table_async(tbl, seen, final_callback)
    seen = seen or {}
    if seen[tbl] then return final_callback(true) end
    seen[tbl] = true

    local keys_to_process = {}
    for k, v in pairs(tbl) do
        if type(v) == "string" then
            table.insert(keys_to_process, { key = k, value = v })
        elseif type(v) == "table" then
            table.insert(keys_to_process, { key = k, value = v, is_table = true })
        end
    end

    if #keys_to_process == 0 then return final_callback(true) end

    local pending = #keys_to_process
    local success = true
    local last_err = nil

    for _, item in ipairs(keys_to_process) do
        if item.is_table then
            _expand_table_async(item.value, seen, function(ok, err)
                if not ok then
                    success = false; last_err = err or "nested table failed"
                end
                pending = pending - 1
                if pending == 0 then final_callback(success, last_err) end
            end)
        else
            _expand_string_async(item.value, function(ok, expanded, err)
                if ok then
                    tbl[item.key] = expanded
                else
                    success = false
                    last_err = err
                end
                pending = pending - 1
                if pending == 0 then final_callback(success, last_err) end
            end)
        end
    end
end

-- Public API
---@param tbl table
---@param callback fun(success:boolean, result_table:table|nil, err:string|nil)
function M.resolve_macros(tbl, callback)
    if not tbl or type(tbl) ~= "table" then
        return vim.schedule(function() callback(false, nil, "Input must be a table") end)
    end

    local tbl_copy = vim.deepcopy(tbl)
    _expand_table_async(tbl_copy, {}, function(success, err)
        vim.schedule(function()
            callback(success, success and tbl_copy or nil, err)
        end)
    end)
end

return M
