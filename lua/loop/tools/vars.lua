local M = {}

local _project_dir = nil

local function is_regular_file()
    local buftype = vim.bo.buftype
    local name = vim.fn.expand("%:p")
    return buftype == ""  and name ~= ""
end

local user_vars_resolvers = {
    HOME       = function(_) return os.getenv("HOME") end,
    FILE       = function(_) return is_regular_file() and vim.fn.expand("%:p") or nil end,
    FILENAME   = function(_) return is_regular_file() and vim.fn.expand("%:t") or nil end,
    FILEEXT    = function(_) return is_regular_file() and vim.fn.expand("%:e") or nil end,
    FILEROOT   = function(_) return is_regular_file() and vim.fn.expand("%:p:r") or nil end,
    FILEDIR    = function(_) return is_regular_file() and vim.fn.expand("%:p:h") or nil end,
    PROJDIR    = function(args) return _project_dir end,
    CWD        = function(_) return vim.fn.getcwd() end,
    FILETYPE   = function(_) return is_regular_file() and vim.bo.filetype or nil end,
    TMPDIR     = function(_) return os.getenv("TMPDIR") end,
    DATE       = function(_) return os.date("%F") end,
    TIME       = function(_) return os.date("%T") end,
    TIMESTAMP  = function(_) return os.date("%Y-%m-%dT%H:%M:%S") end,
}

---@param str string
---@param check_only boolean
---@return string 
---@return boolean
---@return string[]|nil
local function try_expand_string(str, check_only)

    local ESCAPE_MARKER = "\1" -- non-printable placeholder

    -- Step 0: Safety check — ensure the string doesn't already contain the placeholder
    if str:find(ESCAPE_MARKER, 1, true) then
        return str, false
    end

    local success = true
    local unresolved_vars = {}

    -- Step 1: Escape $${VAR} → placeholder
    str = str:gsub("%$%${(.-)}", ESCAPE_MARKER .. "{%1}")

    -- Step 2: Expand normal ${...}
    local result = str:gsub("%${(.-)}", function(content)
        -- Handle ${ENV:VAR}
        local env_var = content:match("^ENV:(.+)$")
        if env_var then
            local env_val = os.getenv(env_var)
            if env_val ~= nil then
                return env_val
            else
                success = false
                table.insert(unresolved_vars, content)
                return ''
            end
        end
        -- Handle ${VAR}
        local resolver = user_vars_resolvers[content]
        if not resolver then
            success = false
            table.insert(unresolved_vars, content)
            return ''
        end
        if check_only then
            return ''
        end
        local resolved = resolver()
        if not resolved then
            success = false
            table.insert(unresolved_vars, content)
        end
        return resolved
    end)

    -- Step 3: Unescape placeholders → back to literal ${VAR}
    result = result:gsub(ESCAPE_MARKER .. "{(.-)}", "${%1}")

    return result, success, unresolved_vars
end

---@param errors string[]
---@param tbl table
---@param filename string
---@param index number
---@param seen table
function M.check_strings(errors, tbl, filename, index, seen)
    seen = seen or {}
    if seen[tbl] then return true end
    seen[tbl] = true

    local ok = true

    for k, v in pairs(tbl) do
        if type(v) == "string" then
            local _, success, unresolved = try_expand_string(v, true)
            if not success then
                table.insert(errors,
                    'Invalid variables found in ' ..
                    vim.inspect(k) .. ' in ' .. filename .. ' at position ' .. index .. ': ' .. vim.inspect(unresolved))
            end
        elseif type(v) == "table" then
            M.check_strings(errors, v, filename, index, seen)
        end
    end
    return ok
end

---@param tbl table
---@param seen table
---@param unresolved string[]
---@return boolean
local function _expand_strings(tbl, seen, unresolved)
    if seen[tbl] then return true end
    seen[tbl] = true

    local ok = true
    for k, v in pairs(tbl) do
        if type(v) == "string" then
            local success, unres
            tbl[k], success, unres = try_expand_string(v, false)
            if not success then
                unres = unres or {}
                for _, var in ipairs(unres) do 
                    table.insert(unresolved, var)
                end
                ok = ok and success
            end
        elseif type(v) == "table" then
            local success, unres = _expand_strings(v, seen, unresolved)
            if not success then
                unres = unres or {}
                for _, var in ipairs(unres) do 
                    table.insert(unresolved, var)
                end
                ok = false
            end
        end
    end
    return ok
end

local function value_to_string(t, indent, seen)
    indent = indent or 0
    seen = seen or {}
    local lines = {}

    local function indent_str(level)
        return string.rep("  ", level)
    end

    local function is_seen(tbl)
        for _, v in ipairs(seen) do
            if v == tbl then return true end
        end
        return false
    end

    if type(t) ~= "table" then
        return indent_str(indent) .. tostring(t)
    end

    if is_seen(t) then
        return indent_str(indent) .. "*recursive table*"
    end

    table.insert(seen, t)
    table.insert(lines, indent_str(indent) .. "{")

    for k, v in pairs(t) do
        local keyStr = "[" .. tostring(k) .. "]"
        local valueStr

        if type(v) == "table" then
            valueStr = value_to_string(v, indent + 1, seen)
        elseif type(v) == "string" then
            valueStr = '"' .. v .. '"'
        else
            valueStr = tostring(v)
        end

        table.insert(lines, indent_str(indent + 1) .. keyStr .. " = " .. valueStr)
    end

    table.insert(lines, indent_str(indent) .. "}")
    return table.concat(lines, "\n")
end

---@param proj_dir string
function M.set_context(proj_dir)
    _project_dir = proj_dir
end

---@param str string
function M.expand_string(str)
    assert(type(str) == 'string')
    return try_expand_string(str, false)
end

---@param tbl table
---@return boolean
---@return string[]
function M.expand_strings(tbl)
    if tbl == nil then 
        return false, {"invalid input"}
    end
    assert(type(tbl) == 'table')
    local unresolved = {}
    local ok = _expand_strings(tbl, {}, unresolved)
    return ok, unresolved
end

---@param var any
function M.inspect(var)
    return value_to_string(var)
end


return M