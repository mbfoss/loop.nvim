local M = {}

require('loop.task.taskdef')
local strtools = require('loop.tools.strtools')

---@class loop.Config.Debug
---@field stack_levels_limit number
---@field sign_priority number

---@class loop.Config.Debugger
---@field dap          loop.dap.session.Args.DAP
---@field request      "launch" | "attach"
---@field default_request_args  table<string,any>
---@field terminate_debuggee boolean|nil

---@class loop.Config
---@field debug loop.Config.Debug
---@field debuggers loop.Config.Debugger[]

---@param task loop.Task
local function get_task_program(task)
    local cmdparts = strtools.cmd_to_string_array(task.command or "")
    return cmdparts[1]
end

---@param task loop.Task
local function get_task_args(task)
    local cmdparts = strtools.cmd_to_string_array(task.command or "")
    return { unpack(cmdparts, 2) }
end

---@param task loop.Task
local function get_task_cwd(task)
    return task.cwd or vim.fn.getcwd()
end

---@type loop.Config
M.defaut_config = {
    debug = {
        sign_priority = 12,
        stack_levels_limit = 100,
        auto_switch_page = true,
    },

    debuggers = {
        -- ──────────────────────────────────────────────────────────────
        -- LLDB (C/C++/Rust/ObjC) – best experience
        -- ──────────────────────────────────────────────────────────────
        lldb = {
            dap = {
                name = "lldb",
                type = "local",
                cmd = { "lldb-dap" }, -- or full path if needed
            },
            request = "launch",
            default_request_args = {
                request = "launch",
                type = "lldb",
                program = get_task_program,
                args = get_task_args,
                cwd = get_task_cwd,
                stopOnEntry = false,
                env = function(task) return task.env end,
                sourceLanguages = { "cpp", "c", "rust", "objc" },
                initCommands = {
                --    "settings set target.input-path /dev/null",
                --    "settings set target.output-path /dev/null",
                },
            },
            terminate_debuggee = true,
        },

        ["js-debug"] = {
            dap = {
                name = "js-debug",
                type = "remote",
                host = "::1",
                port = 8123
            },
            request = "launch",
            default_request_args = {
                type = "pwa-node",
                request = "launch",
                runtimeExecutable = "node",
                program = function(task) return task.command or nil end,
                cwd = get_task_cwd,
                stopOnEntry = true,
                sourceMaps = true,
                outputCapture = "std",
            },
            terminate_debuggee = true,
        },

        -- ──────────────────────────────────────────────────────────────
        -- debugpy (Python) – rock solid
        -- ──────────────────────────────────────────────────────────────
        debugpy = {
            dap = {
                name = "debugpy",
                type = "local",
                cmd = { "python3", "-m", "debugpy.adapter" },
            },
            request = "launch",
            default_request_args = {
                program = function(task) return task.command or "${file}" end,
                cwd = get_task_cwd,
                stopOnEntry = true,
                justMyCode = false,
                console = "integratedTerminal",
                env = function(task) return task.env end,
            },
            terminate_debuggee = true,
        },

        -- ──────────────────────────────────────────────────────────────
        -- netcoredbg (.NET Core / .NET 5+)
        -- ──────────────────────────────────────────────────────────────
        netcoredbg = {
            dap = {
                name = "netcoredbg",
                type = "local",
                cmd = { "netcoredbg", "--interpreter=vscode" },
            },
            request = "launch",
            default_request_args = {
                program = get_task_program,
                args = get_task_args,
                cwd = get_task_cwd,
                stopOnEntry = true,
                env = function(task) return task.env end,
            },
            terminate_debuggee = true,
        },

        -- ──────────────────────────────────────────────────────────────
        -- bashdb (Bash scripts)
        -- ──────────────────────────────────────────────────────────────
        bashdb = {
            dap = {
                name = "bashdb",
                type = "local",
                cmd = { "bashdb", "--adapter" },
            },
            request = "launch",
            default_request_args = {
                program = get_task_program,
                cwd = get_task_cwd,
                stopOnEntry = true,
            },
        },
    },
}

M.current = nil
return M
