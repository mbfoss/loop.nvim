require('loop.task.taskdef')
local strtools = require('loop.tools.strtools')

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

---@class loop.Config.Debug
---@field stack_levels_limit number
---@field sign_priority table<string,number>

---@class loop.Config.Debugger
---@field dap          loop.dap.session.Args.DAP
---@field launch_args  table<string,any>
---@field attach_args  table<string,any>
---@field server_command string|string[]|nil
---@field terminate_debuggee boolean|nil
---@field launch_post_configure boolean|nil

---@type table<string,loop.Config.Debugger>
local debuggers = {
    -- ──────────────────────────────────────────────────────────────
    -- LLDB (C/C++/Rust/ObjC)
    -- ──────────────────────────────────────────────────────────────
    lldb = {
        server_command = nil, -- command to run a server processe that the dap process connects to
        dap = {
            adapter_id = "lldb",
            name = "lldb",
            type = "executable",
            command = { "lldb-dap" },
        },
        launch_args = {
            program = get_task_program,
            args = get_task_args,
            cwd = get_task_cwd,
            stopOnEntry = false,
            environment = function(task) return task.env end,
            sourceLanguages = { "cpp", "c", "rust", "objc" },
            initCommands = {
                --    "settings set target.input-path /dev/null",
                --    "settings set target.output-path /dev/null",
            },
            runInTerminal = true,
        },
        attach_args = {
            program = get_task_program,
            pid = "${select-process-pid}",
            stopOnEntry = false,
        },
    },
}

return debuggers
