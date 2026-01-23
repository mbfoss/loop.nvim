local M = {}

local strtools = require('loop.tools.strtools')

-- Neovim's JSON encoder (perfect escaping)
local function encode_one(v)
    return vim.json.encode(v)
end

local _indent = "  "

local jsonschema = require("loop.tools.jsonschema")

---@param schema table|nil
---@param key string|number
---@param value any
---@return table|nil
local function resolve_subschema(schema, key, value)
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


---@param keys string[]
---@param schema table|nil        -- schema node for this table
local function _order_keys(keys, schema)
     vim.fn.sort(keys) -- required even with strtools.order_strings()
    local order = type(schema) == "table" and schema.__order or nil
    if order then
        strtools.order_strings(keys, order)
    end
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
        return encode_one(value)
    elseif t == "table" then
        if vim.islist(value) then
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
            local keys = {}
            for k in pairs(value) do
                table.insert(keys, k)
            end
            _order_keys(keys, schema)
            if #keys == 0 then return "{}" end
            local parts = { "{" }
            for _, k in ipairs(keys) do
                local key_json = type(k) == "string" and encode_one(k) or ('"' .. tostring(k) .. '"')
                local subschema = resolve_subschema(schema, k, value[k])
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

    local decode_ok, data = pcall(vim.fn.json_decode, content)
    if not decode_ok or type(data) ~= "table" then
        return false, "failed to parse json " .. (type(data) == "string" and data or "")
    end
    return true, data
end

---@param content string
---@return boolean
---@return any | nil
function M.from_string(content)
    local decode_ok, data = pcall(vim.fn.json_decode, content)
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
