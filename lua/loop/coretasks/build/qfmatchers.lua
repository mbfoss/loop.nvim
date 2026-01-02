local strtools = require("loop.tools.strtools")

---@class loop.task.QuickFixItem
---@field filename string
---@field lnum number
---@field col number
---@field text string|nil
---@field type string|nil

--------------------------------------------------------------------------------
local function make_item(file, lnum, col, text, type)
    return {
        filename = file,
        lnum     = tonumber(lnum) or 1,
        col      = tonumber(col) or 1,
        text     = text,
        type     = type or "E",
    }
end

---@param line string
---@param context table
---@return loop.task.QuickFixItem|nil
local function _parse_gcc(line, context)
    -----------------------------------------------------------------
    -- GCC / Clang compile-time diagnostics
    -----------------------------------------------------------------
    local file, lnum, col, severity, message = line:match("^(.+):(%d+):(%d+):%s+([%a%s]+):%s+(.+)$")
    if file then
        local type = "E"
        if severity == "warning" then type = "W" end
        if severity == "note" then type = "I" end

        return {
            filename = file,
            lnum     = tonumber(lnum),
            col      = tonumber(col),
            text     = message,
            type     = type,
        }
    end
    -----------------------------------------------------------------
    -- GNU ld: file.o:(.text+0x25): undefined reference to `foo`
    -----------------------------------------------------------------
    local obj_file, msg = line:match("^(.+):%(%.[^%)]+%)[:%s]+(.+)$")
    if obj_file then
        return {
            filename = obj_file,
            lnum     = 1,
            col      = 1,
            text     = msg,
            type     = "E",
        }
    end
    -----------------------------------------------------------------
    -- Any line with "undefined reference to `symbol`"
    -----------------------------------------------------------------
    local sym = line:match("undefined reference to [`']([^'`']+)[`']")
    if sym then
        return {
            filename = "",
            lnum     = 1,
            col      = 1,
            text     = "undefined reference to `" .. sym .. "`",
            type     = "E",
        }
    end
    return nil
end


---@param line string The raw output line from luacheck
---@param context table Additional context
---@return loop.task.QuickFixItem|nil
local function _parse_luacheck(line, context)
    -- Match warning lines (indented with spaces/tabs, contain filename:line:col)
    local warning_pattern = "^%s*(.-):(%d+):(%d+):%s*(.+)$"
    local file, lnum, col, message = line:match(warning_pattern)

    if not (file and lnum and col and message) then
        return nil
    end

    -- Convert to numbers
    lnum = tonumber(lnum)
    col = tonumber(col)

    ---@type loop.task.QuickFixItem
    local item = {
        filename = file,
        lnum = lnum or 1,
        col = col or 1,
        text = message,
        type = "W", -- Warning
    }

    return item
end

--- TypeScript / Microsoft Style (tsc, eslint)
local function _parse_typescript(line, _)
    -- file(line,col): error TS1234: message
    local file, lnum, col, msg = line:match("^(.+)%((%d+),(%d+)%):%s+(.+)$")
    if file then return make_item(file, lnum, col, msg, "E") end
    return nil
end

--- Python Tracebacks
local function _parse_python(line, _)
    --   File "path/to/file.py", line 123, in <module>
    local file, lnum = line:match('File "([^"]+)", line (%d+)')
    if file then
        return make_item(file, lnum, 1, "Python Traceback", "E")
    end
    return nil
end

--- Go Compiler
local function _parse_go(line, _)
    -- file:line:col: message
    -- file:line: message
    local file, lnum, col, msg = line:match("^([^%s:]+):(%d+):(%d+):%s+(.+)$")
    if not file then
        file, lnum, msg = line:match("^([^%s:]+):(%d+):%s+(.+)$")
        col = 1
    end
    if file then return make_item(file, lnum, col, msg, "E") end
    return nil
end

--- Pytest / Unittest
--- Pattern: >       assert 0
---          test_file.py:10: AssertionError
local function _parse_pytest(line, _)
    local file, lnum, msg = line:match("^([^%s:]+%.py):(%d+):%s+(.+)$")
    if file then
        return make_item(file, lnum, 1, msg, "E")
    end
    return nil
end

--- Cargo Test (Rust)
--- Pattern: --> src/main.rs:10:5
local function _parse_cargo(line, _)
    local file, lnum, col = line:match("^%s*-->%s+([^%s:]+):(%d+):(%d+)")
    if file then
        return make_item(file, lnum, col, "Rust Compiler/Test Error", "E")
    end
    -- Also catch panic locations: panicked at '...', src/lib.rs:18:5
    file, lnum, col = line:match("panicked at '.-',%s+([^%s:]+):(%d+):(%d+)")
    if file then return make_item(file, lnum, col, "Panic", "E") end
    return nil
end

--- Go Test
--- Pattern:     main_test.go:15: error message
local function _parse_gotest(line, _)
    local file, lnum, msg = line:match("^%s+([^%s:]+_test%.go):(%d+):%s+(.+)$")
    if file then
        return make_item(file, lnum, 1, msg, "E")
    end
    return nil
end

--- MSVC (cl.exe)
local function _parse_msvc(line, _)
    -- file.cpp(10): error C1234: message
    local file, lnum, type_code, msg = line:match("^(.-)%((%d+)%):%s+([%a]+)%s+[%a%d]+:%s+(.+)$")
    if file then
        local severity = (type_code:lower() == "warning") and "W" or "E"
        return make_item(file, lnum, 1, msg, severity)
    end
    return nil
end

--- Generic Lint (Shellcheck, etc.)
--- Pattern: file:line:col: severity: message
local function _parse_lint(line, _)
    local file, lnum, col, sev, msg = line:match("^([^%s:]+):(%d+):(%d+):%s+([^:]+):%s+(.+)$")
    if file then
        local t = sev:match("[Ww]arn") and "W" or "E"
        return make_item(file, lnum, col, msg, t)
    end
    return nil
end

--- Generic parser for tools that support "Unix" or "GCC" output formats
--- Works for: Shellcheck, ESLint (unix format), Mypy, Flake8, etc.
local function _parse_generic_unix(line, _)
    -- Pattern: path/to/file.ext:line:col: [severity] message
    local file, lnum, col, msg = line:match("^([^%s:]+):(%d+):(%d+):%s*(.*)$")
    if file then
        local type = "E"
        if msg:lower():find("warning") or msg:lower():find("low") then
            type = "W"
        elseif msg:lower():find("note") or msg:lower():find("info") then
            type = "I"
        end
        return make_item(file, lnum, col, msg, type)
    end
    return nil
end

---@type table<string,fun(line:string,context:table):loop.task.QuickFixItem>
return {
    gcc      = _parse_gcc,
    luacheck = _parse_luacheck,
    tsc      = _parse_typescript,
    python   = _parse_python,
    go       = _parse_go,
    pytest   = _parse_pytest,
    cargo    = _parse_cargo,
    gotest   = _parse_gotest,
    msvc     = _parse_msvc,
    lint     = _parse_lint,
    unix     = _parse_generic_unix
}
