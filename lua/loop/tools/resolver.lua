local M = {}

local config = require('loop.config')


---@alias SimpleValue string | number | boolean | table

---@param value any
---@param _seen table   -- internal: for cycle detection (optional)
---@return boolean is_valid
---@return string? error_message   -- nil if valid
local function _is_simple_data(value, _seen)
    -- Basic allowed types
    local t = type(value)
    if t == "string" or t == "number" or t == "boolean" then
        return true
    end

    if t ~= "table" then
        return false, ("unsupported type: %s"):format(t)
    end

    -- Cycle detection
    if _seen[value] then
        return true  -- allow cycles (treat as already validated branch)
    end
    _seen[value] = true

    -- Validate table contents (keys must be string/number, values must be simple)
    for k, v in pairs(value) do
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" then
            return false, ("table key must be string or number, got %s"):format(kt)
        end

        local ok, err = _is_simple_data(v, _seen)
        if not ok then
            return false, ("invalid value at key %s: %s"):format(vim.inspect(k), err)
        end
    end

    -- Also check array-like part (optional, but recommended for strictness)
    -- This prevents sparse tables or tables with non-integer keys in sequence
    if not pcall(function() return #value end) then
        -- If # operator fails (sparse or invalid), we still allow if all keys are valid
        -- But you can make this stricter if desired
    end

    return true
end

-- Public wrapper (clean API)
local function _validate_simple_data(value)
    local ok, err = _is_simple_data(value, {})
    if not ok then
        return false, err or "validation failed"
    end
    return true
end


local ESCAPE_MARKER = "\001" -- Safe internal marker

---@param str string
---@return boolean success
---@return any result
---@return string|nil err
local function _expand_string(str)
    if type(str) ~= "string" then
        return false, nil, "Input must be a string"
    end

    -- Safety: prevent conflict with escape marker
    if str:find(ESCAPE_MARKER, 1, true) then
        return false, nil, "String contains internal escape sequence"
    end

    local success = true
    local err_msg = nil

    -- Step 1: Escape literal $${macro}
    local escaped = str:gsub("%$%${(.-)}", ESCAPE_MARKER .. "{%1}")

    -- Step 2: Check if the original string is EXACTLY one macro: "${something}"
    local single_macro_name = str:match("^%${([^}]+)}$")
    if single_macro_name then
        local fn = config.current.macros[single_macro_name]
        if not fn then
            return false, nil, ("Unknown macro: ${%s}"):format(single_macro_name)
        end
        local value, err = fn()
        if err ~= nil then
            return false, nil, err or ("Macro failed: ${%s}"):format(single_macro_name)
        end
        if not _validate_simple_data(value) then
            return false, nil, err or ("Macro failed (invalid return value): ${%s}"):format(single_macro_name)            
        end
        return true, value, nil
    end

    -- Step 3: Normal expansion (zero or multiple macros)
    local result = escaped:gsub("%${([^}]+)}", function(name)
        if not success then return "" end
        local fn = config.current.macros[name]
        if not fn then
            success = false
            err_msg = ("Unknown macro: ${%s}"):format(name)
            return ""
        end
        local value, err = fn()
        if value == nil then
            success = false
            err_msg = err or ("Macro failed: ${%s}"):format(name)
            return ""
        end
        if type(value) ~= "string" then
            success = false
            err_msg = ("Macro ${%s} returned non-string: %s"):format(name, vim.inspect(value))
            return ""
        end
        return value
    end)
    -- Step 4: Restore escaped $${macro} → ${macro}
    result = result:gsub(ESCAPE_MARKER .. "{(.-)}", "${%1}")
    return success, result, err_msg
end

---@param tbl table
---@param seen table
---@return boolean success
---@return string|nil errmsg
local function _expand_macros(tbl, seen)
    if seen[tbl] then return true end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        if type(v) == "string" then
            local ok, err
            ok, tbl[k], err = _expand_string(v)
            if not ok then
                return false, err
            end
        elseif type(v) == "table" then
            local ok, err = _expand_macros(v, seen)
            if not ok then
                return false, err
            end
        end
    end
    return true
end

---@param tbl table
---@return boolean resolved or not
---@return string|nil error
function M.resolve_macros(tbl)
    if tbl == nil then return true end
    assert(type(tbl) == 'table')
    local ok, err = _expand_macros(tbl, {})
    return ok, err
end

return M
