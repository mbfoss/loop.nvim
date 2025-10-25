local M = {}

local builtin_matchers = {
    ------------------------------------------------------------------
    -- GCC / Clang
    ------------------------------------------------------------------
    ["$gcc"] = {
        regexp = "^([^:]+):(%d+):(%d+):%s*(%w+):%s*(.+)",
        file = 1,
        line = 2,
        column = 3,
        severity = 4,
        message = 5,
    },

    ------------------------------------------------------------------
    -- TypeScript (tsc --watch)
    ------------------------------------------------------------------
    ["$tsc-watch"] = {
        -- src/file.ts(12,3): error TS2339: Property 'x' does not exist...
        regexp = "^%s*([^%(]+)%((%d+),(%d+)%):%s*(%w+)%s+TS%d+:%s*(.+)",
        file = 1,
        line = 2,
        column = 3,
        severity = 4,
        message = 5,
    },

    ------------------------------------------------------------------
    -- ESLint (stylish formatter)
    ------------------------------------------------------------------
    ["$eslint-stylish"] = {
        --   12:34  error  Unexpected console statement  no-console
        regexp = "^%s*(%d+):(%d+)%s+(%w+)%s+(.-)%s+[%w%-]+$",
        file = vim.fn.expand("%:p"), -- current file
        line = 1,
        column = 2,
        severity = 3,
        message = 4,
    },

    ------------------------------------------------------------------
    -- MSVC (msCompile)
    ------------------------------------------------------------------
    ["$msCompile"] = {
        -- file.cpp(123) : error C2065: 'undeclared' : undeclared identifier
        regexp = "^([^%(]+)%((%d+)%)%s*:%s*(%w+)%s+C%d+:%s*(.+)",
        file = 1,
        line = 2,
        severity = 3,
        message = 4,
    },

    ------------------------------------------------------------------
    -- Less compiler
    ------------------------------------------------------------------
    ["$lessCompile"] = {
        -- ParseError: expected '{' in file.less on line 12, column 5
        regexp = "^%w+:%s*(.-)%s+in%s+([^(]+)%s+on%s+line%s+(%d+),%s+column%s+(%d+)",
        file = 2,
        line = 3,
        column = 4,
        severity = 1,
        message = 1,
    },
}


local function strip_ansi_codes(input)
    -- Pattern to match specific ANSI escape codes that are used for coloring and cursor movements
    local pattern = "\27%[%d*;?%d*;?%d*[mGKHK]"
    local cleaned_output = input:gsub(pattern, "")
    return cleaned_output
end

-- ----------------------------------------------------------------------
-- Helper: turn a line into a quickfix entry
-- ----------------------------------------------------------------------
local function make_qf_entry(m, line)
    local captures = { line:match(m.regexp) }
    if #captures == 0 then
        return nil
    end

    local entry = {
        filename = captures[m.file] or "",
        lnum     = tonumber(captures[m.line]) or 0,
        col      = tonumber(captures[m.column] or 0) or 0,
        text     = captures[m.message] or "",
    }

    -- optional type → 'E' (error) or 'W' (warning)
    if m.severity then
        local typ = captures[m.severity]:lower()
        entry.type = (typ:find("error") or typ:find("fatal")) and "E" or "W"
    end

    return entry
end

--- @param lines  string[]   raw compiler / linter output
--- @param matcher table   "$name" or a custom matcher table
--- @param module string|nil
--- @return boolean true if matched
local function _add_to_quickfix(lines, matcher, module)
    local qf = {}
    for _, line in ipairs(lines) do
        line = line:gsub("[\r]+$", "")
        line = strip_ansi_codes(line)
        local e = make_qf_entry(matcher, line)
        if e then
            e.module = module
            table.insert(qf, e)
        end
    end

    if #qf == 0 then
        return false
    end

    vim.fn.setqflist(qf, "a")
    return true
end

--- @param module string | nil
function M.clear(module)
    if module then
        local list = vim.fn.getqflist()
        local filtered = vim.tbl_filter(function(item) return item.module ~= module end, list)
        vim.fn.setqflist(filtered, "r") -- replace current list
    else
        vim.fn.setqflist({}, "r")
    end
end

-- ----------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------
--- Add lines to the quickfix list using a VS Code problem-matcher.
--- @param lines  string[]   raw compiler / linter output
--- @param matcher string|table   "$name" or a custom matcher table
--- @param group string | nil
--- @return boolean true if matched
function M.add(lines, matcher, group)
    ------------------------------------------------------------------
    -- 1. Resolve a built-in matcher when a string is passed
    ------------------------------------------------------------------
    if type(matcher) == "string" then
        matcher = builtin_matchers[matcher]
    end

    ------------------------------------------------------------------
    -- 2. If we still have a table → process it
    ------------------------------------------------------------------
    if type(matcher) == "table" and matcher.regexp then
        return _add_to_quickfix(lines, matcher, group)
    end
    return false
end

return M
