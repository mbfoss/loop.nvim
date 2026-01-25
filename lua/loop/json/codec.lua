local M = {}

local jsonschema = require("loop.json.validator")
local tabletools = require("loop.tools.tabletools")

local _indent = "  "

-- Neovim's JSON encoder (perfect escaping)
local function _encode_one(v)
    return vim.json.encode(v)
end

---@param schema table|nil
---@param key string|number
---@param value any
---@return table|nil
local function _resolve_subschema(schema, key, value)
    if type(schema) ~= "table" then
        return nil
    end

    -- 1. Direct property
    if schema.properties and schema.properties[key] then
        return schema.properties[key]
    end

    -- 2. oneOf resolution (full validation)
    if schema.oneOf then
        for _, candidate in ipairs(schema.oneOf) do
            -- validate returns nil on success
            if jsonschema.validate(candidate, value) == nil then
                return candidate
            end
        end
    end

    -- 3. additionalProperties (fallback)
    if type(schema.additionalProperties) == "table" then
        return schema.additionalProperties
    end

    return nil
end

---@generic T
---@param tbl table<T, any> (table) Table
---@param schema table|nil -- schema node for this table
---@return T[] : List of keys
local function _get_ordred_keys(tbl, schema)
    local keys = tabletools.tbl_keys(tbl)

    local order = type(schema) == "table" and schema["x-order"] or nil
    if not order then
        vim.fn.sort(keys)
        return keys
    end
    
    local ordered = {}
    for i = 1, #order do
        ordered[i] = order[i]
    end
    local index = 0
    local priorities = {}
    for _, v in ipairs(ordered) do
        index = index + 1
        priorities[v] = index
    end
    if index ~= #keys then
        vim.fn.sort(keys)
        for _, v in ipairs(keys) do
            if not priorities[v] then
                index = index + 1
                priorities[v] = index
            end
        end
    end
    table.sort(keys, function(a, b) return priorities[a] < priorities[b] end)
    return keys
end

local function _decode(str)
    local sub = string.sub
    local byte = string.byte
    local tonumber = tonumber
    local insert = table.insert

    local function decode_error(pos, msg)
        error(("Invalid JSON at position %d: %s"):format(pos or 0, msg or "syntax error"))
    end

    if type(str) ~= "string" then
        decode_error(nil, "input must be a string")
    end

    local i = 1
    local len = #str

    local parse_value

    local function skip()
        while i <= len do
            local c = byte(str, i)
            if c > 32 then return end
            i = i + 1
        end
    end

    local function parse_string()
        if byte(str, i) ~= 34 then decode_error(i, "expected '\"'") end
        i = i + 1
        local buf = {}
        while i <= len do
            local c = byte(str, i)
            if c == 34 then
                i = i + 1
                return table.concat(buf)
            end
            if c == 92 then
                i = i + 1
                if i > len then decode_error(i, "unterminated escape") end
                local esc = byte(str, i)
                i = i + 1
                if esc == 34 or esc == 92 or esc == 47 then
                    buf[#buf + 1] = string.char(esc)
                elseif esc == 98 then
                    buf[#buf + 1] = "\b"
                elseif esc == 102 then
                    buf[#buf + 1] = "\f"
                elseif esc == 110 then
                    buf[#buf + 1] = "\n"
                elseif esc == 114 then
                    buf[#buf + 1] = "\r"
                elseif esc == 116 then
                    buf[#buf + 1] = "\t"
                elseif esc == 117 then
                    local hex = sub(str, i, i + 3)
                    if #hex ~= 4 or not hex:match("^%x%x%x%x$") then
                        decode_error(i - 1, "invalid \\u escape")
                    end
                    buf[#buf + 1] = string.char(tonumber(hex, 16))
                    i = i + 4
                else
                    decode_error(i - 1, "unknown escape")
                end
            else
                buf[#buf + 1] = string.char(c)
                i = i + 1
            end
        end
        decode_error(i, "unterminated string")
    end

    local function parse_number()
        local start = i
        local c = byte(str, i)

        if c == 45 then i = i + 1 end -- allow leading -

        while i <= len do
            c = byte(str, i)
            if (c >= 48 and c <= 57) or c == 46 or c == 69 or c == 101 or c == 43 or c == 45 then
                i = i + 1
            else
                break
            end
        end

        local num_str = sub(str, start, i - 1)
        local num = tonumber(num_str)
        if not num then
            decode_error(start, "invalid number")
        end
        return num
    end

    local function parse_array()
        if byte(str, i) ~= 91 then decode_error(i, "expected '['") end
        i = i + 1
        skip()

        local arr = {}
        if byte(str, i) == 93 then
            i = i + 1
            return arr
        end

        repeat
            insert(arr, parse_value())
            skip()
            local c = byte(str, i)
            if c == 93 then
                i = i + 1
                return arr
            elseif c ~= 44 then
                decode_error(i, "expected ',' or ']'")
            end
            i = i + 1
            skip()
        until false
    end

    local function parse_object()
        if byte(str, i) ~= 123 then decode_error(i, "expected '{'") end
        i = i + 1
        skip()

        local obj = tabletools.ordered_table()

        if byte(str, i) == 125 then
            i = i + 1
            return obj
        end

        repeat
            if byte(str, i) ~= 34 then decode_error(i, "expected string key") end
            local key = parse_string()

            skip()
            if byte(str, i) ~= 58 then decode_error(i, "expected ':'") end
            i = i + 1
            skip()

            local val = parse_value()
            obj[key] = val

            skip()
            local c = byte(str, i)
            if c == 125 then
                i = i + 1
                return obj
            elseif c ~= 44 then
                decode_error(i, "expected ',' or '}'")
            end
            i = i + 1
            skip()
        until false
    end

    parse_value = function()
        skip()
        if i > len then decode_error(i, "unexpected EOF") end

        local c = byte(str, i)
        if c == 34 then
            return parse_string()
        elseif c == 123 then
            return parse_object()
        elseif c == 91 then
            return parse_array()
        elseif c == 116 and sub(str, i, i + 3) == "true" then
            i = i + 4; return true
        elseif c == 102 and sub(str, i, i + 4) == "false" then
            i = i + 5; return false
        elseif c == 110 and sub(str, i, i + 3) == "null" then
            i = i + 4; return nil
        elseif (c >= 48 and c <= 57) or c == 45 then
            return parse_number()
        else
            decode_error(i, ("unexpected byte %d"):format(c))
        end
    end

    local result = parse_value()
    skip()
    if i <= len then
        decode_error(i, "extra data after value")
    end

    return result
end


---@param value string
---@param level number
---@param path string
---@param schema any
local function _serialize(value, level, path, schema)
    local indent_str  = _indent:rep(level)
    local next_indent = _indent:rep(level + 1)
    local t           = type(value)

    if t == "nil" or t == "number" or t == "boolean" or t == "string" or value == vim.NIL then
        return _encode_one(value)
    elseif t == "table" then
        if tabletools.is_list(value) then
            -- ARRAY STYLE
            if #value == 0 then return "[]" end

            local parts = { "[" }
            for i = 1, #value do
                table.insert(parts, "\n" .. next_indent .. _serialize(value[i], level + 1, path .. '[]/'))
                if i < #value then table.insert(parts, ",") end
            end
            table.insert(parts, "\n" .. indent_str .. "]")
            return table.concat(parts)
        else
            -- MAP STYLE
            local keys = _get_ordred_keys(value, schema)
            if #keys == 0 then return "{}" end
            local parts = { "{" }
            for _, k in ipairs(keys) do
                local key_json = type(k) == "string" and _encode_one(k) or ('"' .. tostring(k) .. '"')
                local subschema = _resolve_subschema(schema, k, value[k])
                local val_json = _serialize(value[k], level + 1, path .. k .. '/', subschema)
                table.insert(parts, "\n" .. next_indent .. key_json .. ": " .. val_json .. ",")
            end
            -- Remove trailing comma
            parts[#parts] = parts[#parts]:gsub(",$", "")
            table.insert(parts, "\n" .. indent_str .. "}")
            return table.concat(parts)
        end
    else
        error("Unsupported type: " .. t)
    end
end

--- Pretty JSON encoder using only real Neovim built-ins
---@param obj any
---@param schema any
---@return string
local function json_encode_pretty(obj, schema)
    return _serialize(obj, 0, "/", schema)
end

-- ──────────────────────────────────────────────────────────────────────────────
--   Custom JSON decoder that preserves object key order
-- ──────────────────────────────────────────────────────────────────────────────

---@param content string
---@return boolean,any
local function _json_decode_ordered(content)
    local ok, decoded_or_err = pcall(_decode, content, true)
    return ok, decoded_or_err
end

---@param filepath string
---@param data any
---@return boolean
---@return string | nil
function M.save_to_file(filepath, data)
    local json = json_encode_pretty(data, nil)
    assert(type(json) == 'string')
    local fd = io.open(filepath, "w")
    if not fd then
        return false, "Cannot open file for write '" .. filepath or "" .. "'"
    end
    local ok, ret_or_err = pcall(function() fd:write(json) end)
    fd:close()
    return ok, ret_or_err
end

---@param filepath string
---@return boolean
---@return any | nil
function M.load_from_file(filepath)
    local fd = io.open(filepath, "r")
    if not fd then
        return false, "Cannot open file for read"
    end
    local read_ok, content = pcall(function() return fd:read("*a") end)
    fd:close()

    if not read_ok then
        return false, content
    end

    local decode_ok, data = _json_decode_ordered(content)
    if not decode_ok or type(data) ~= "table" then
        return false, "failed to parse json " .. (type(data) == "string" and data or "")
    end
    return true, data
end

---@param content string
---@return boolean
---@return any | nil
function M.from_string(content)
    local decode_ok, data = _json_decode_ordered(content)
    if not decode_ok or type(data) ~= "table" then
        return false, "failed to parse json " .. (type(data) == "string" and data or "")
    end
    return true, data
end

---@param data any
---@param schema any
---@return string
function M.to_string(data, schema)
    return json_encode_pretty(data, schema)
end


return M
