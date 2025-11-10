M = {}

---@param str string
---@return string
function M.human_case(str)
    -- Replace underscores with spaces
    str = str:gsub("_", " ")

    -- Insert space before uppercase letters (camelCase -> camel Case)
    str = str:gsub("(%l)(%u)", "%1 %2")

    -- Capitalize first letter of each word
    str = str:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)

    return str
end

---@param str_or_array string|string[]
---@return string, string[]|nil
function M.get_program_and_args(str_or_array)
    assert(type(str_or_array) == 'string' or type(str_or_array) == 'table')
    local cmd = nil
    local args = nil

    if type(str_or_array) == 'string' then
        cmd = str_or_array
    else
        cmd = str_or_array[1]
        if #str_or_array > 1 then
            args = {}
            for i = 2, #str_or_array do
                args[#args + 1] = str_or_array[i]
            end
        end
    end

    return cmd, args
end

-- Escape a single argument only if necessary
local function _escape_shell_arg(arg)
    arg = arg or ""
    -- Only escape if it contains shell-special characters or spaces
    if arg:match('[%s;&|$`"\'<>]') then
        -- Wrap in single quotes and escape existing single quotes
        arg = "'" .. arg:gsub("'", "'\\''") .. "'"
    end
    return arg
end

---@param cmd_and_args string[]
---@return string
function M.get_shell_command(cmd_and_args)
    local parts = {}
    -- Replace nils and escape each part as needed
    for i, str in ipairs(cmd_and_args) do
        table.insert(parts, _escape_shell_arg(str))
    end
    return table.concat(parts, " ")
end

---@param errors string[]|nil
---@return string[]
function M.indent_errors(errors, parent_msg)
    errors = errors or {}
    errors = vim.tbl_map(function(v)
        if type(v) == 'string' then
            return '  ' .. v
        else
            return '  ' .. vim.inspect(v)
        end
    end, errors or {})
    table.insert(errors, 1, parent_msg)
    return errors
end

return M
