local M = {}

-- Helper: join JSON-pointer path
local function join_path(base, key)
    if base == "/" then return "/" .. key end
    return base .. "/" .. key
end

-- Helper: add error message
local function add_error(errors, path, msg)
    table.insert(errors, path .. ": " .. msg)
end

-- Helper: check enum
local function check_enum(enum_tbl, value)
    for _, v in ipairs(enum_tbl) do
        if v == value then return true end
    end
    return false
end

-- Core recursive validator
---@param schema table
---@param data any
---@param path string
local function validate(schema, data, path)
    local errors = {}

    -- 1. type check
    local sch_type = schema.type
    if sch_type then
        local ok = false
        if sch_type == "object" and type(data) == "table" and not vim.isarray(data) then ok = true end
        if sch_type == "array" and vim.isarray(data) then ok = true end
        if sch_type == "string" and type(data) == "string" then ok = true end
        if sch_type == "number" and type(data) == "number" then ok = true end
        if sch_type == "boolean" and type(data) == "boolean" then ok = true end
        if not ok then
            add_error(errors, path, ("expected %s, got %s"):format(sch_type, type(data)))
            return errors
        end
    end

    -- 2. enum check
    if schema.enum then
        if not check_enum(schema.enum, data) then
            add_error(errors, path, "value not in enum: " .. table.concat(schema.enum, ", "))
            return errors
        end
    end

    -- 3. object handling
    if sch_type == "object" then
        local props    = schema.properties or {}
        local required = schema.required or {}

        -- required fields
        for _, key in ipairs(required) do
            if data[key] == nil then
                add_error(errors, join_path(path, key), "required property missing")
            end
        end

        -- validate known properties
        for key, subschema in pairs(props) do
            if data[key] ~= nil then
                local sub_err = validate(subschema, data[key], join_path(path, key))
                if sub_err then vim.list_extend(errors, sub_err) end
            end
        end

        -- Handle additionalProperties
        local addl = schema.additionalProperties
        if addl ~= true then
            -- Forbid all unknown properties
            for key in pairs(data) do
                if not props[key] then
                    local valid_props = table.concat(vim.tbl_keys(props), ', ')
                    add_error(errors, join_path(path, key),
                    "Invalid property name, valid properties are: " .. valid_props)
                end
            end
        elseif addl and type(addl) == "table" then
            -- Allow unknown properties, but validate their values
            for key, value in pairs(data) do
                if not props[key] then
                    local sub_err = validate(addl, value, join_path(path, key))
                    if sub_err then vim.list_extend(errors, sub_err) end
                end
            end
        end
    end

    -- 4. array handling
    if sch_type == "array" then
        local items = schema.items
        if items then
            for i, value in ipairs(data) do
                local sub_err = validate(items, value, path .. "/" .. i)
                if sub_err then vim.list_extend(errors, sub_err) end
            end
        end
    end

    -- 5. string pattern
    if sch_type == "string" and schema.pattern and #schema.pattern > 0 then
        if not data:match(schema.pattern) then
            add_error(errors, path, ("string does not match pattern %q"):format(schema.pattern))
        end
    end

    -- 6. oneOf (first match wins)
    if schema.oneOf then
        local matched = false
        local sub_errors = {}
        for i, sub in ipairs(schema.oneOf) do
            local sub_err = validate(sub, data, path)
            if not sub_err or #sub_err == 0 then
                matched = true
                break
            else
                table.insert(sub_errors, ("  option %d errors: %s"):format(i, table.concat(sub_err, "; ")))
            end
        end
        if not matched then
            add_error(errors, path, "failed to match any schema in oneOf. Details:\n" .. table.concat(sub_errors, "\n"))
        end
    end

    -- Return nil on success
    if #errors == 0 then return nil end
    return errors
end

-- Public entry point
---@param schema_str string
---@param data any
function M.validate(schema_str, data)
    local ok, schema_obj = pcall(vim.fn.json_decode, schema_str)
    if not ok then
        return { "failed to decode schema: " .. schema_obj }
    end
    if type(data) ~= "table" then
        return { "data must be a table" }
    end
    assert(schema_obj)
    assert(type(schema_obj.type) == "string")
    return validate(schema_obj, data, "/")
end

return M
