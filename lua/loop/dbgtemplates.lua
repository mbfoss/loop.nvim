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
---@field launch_args  table<string,any>|nil
---@field attach_args  table<string,any>|nil
---@field server_command string|string[]|nil
---@field terminate_debuggee boolean|nil
---@field launch_post_configure boolean|nil

---@type table<string,loop.Config.Debugger>
local debuggers = {}

-- Helper: safely get mason bin path (works even if mason not installed yet)
local function mason_bin(name)
    local mason_registry = nil
    local ok, registry = pcall(require, "mason-registry")
    if ok then
        mason_registry = registry
    end

    if mason_registry and mason_registry.is_installed and mason_registry.is_installed(name) then
        local pkg = mason_registry.get_package(name)
        if pkg and pkg.get_install_path then
            local path = pkg:get_install_path()
            local bin = path .. "/bin/" .. name
            ---@diagnostic disable-next-line: undefined-field
            if vim.uv.fs_stat(bin) then
                return bin
            end
            -- Some packages use different binary names
            local alt = path .. "/" .. name
            if vim.uv.fs_stat(alt) then
                return alt
            end
        end
    end

    -- Fallback: assume it's in PATH (user installed manually)
    return name
end

-- ==================================================================
-- Lua (local debugging inside Neovim or standalone scripts)
-- ==================================================================
debuggers.lua = {
    dap = {
        adapter_id = "lua",
        name = "Local Lua Debugger",
        type = "executable",
        -- This is the official adapter from the Lua community
        command = { "node",
            vim.fn.stdpath("data") ..
            "/mason/packages/local-lua-debugger-vscode/extension/extension/debugAdapter.js",
        }, -- or "lua-debug"
        -- Optional: some versions need extra args
    },
    -- Launch: debug current file or project
    launch_args = {
        type = "lua-local",
        request = "launch",
        name = "Debug",
        program = {
            lua = "lua5.1",
            file = "main.lua"
        }
    },

    -- Attach: to a running Lua process (e.g. Neovim itself or external script)
    attach_args = {
        type = "lua_local",
        request = "attach",
        name = "Attach to Running Lua Process",
        processId = "${select-process-pid}",
        cwd = "${projdir}",
        sourceMaps = true,
    },
}

-- ==================================================================
-- C / C++ / Rust / Objective-C
-- ==================================================================
debuggers.lldb = {
    dap = {
        adapter_id = "lldb",
        name = "LLDB (via lldb-dap)",
        type = "executable",
        command = { mason_bin("lldb-dap") },
    },
    launch_args = {
        program = get_task_program,
        args = get_task_args,
        cwd = "${projdir}",
        stopOnEntry = false,
        runInTerminal = true,
        initCommands = {
            -- Optional: silence stdin/stdout redirection warnings
            -- "settings set target.input-path /dev/null",
            -- "settings set target.output-path /dev/null",
        },
    },
    attach_args = {
        pid = "${select-process-pid}",
        program = get_task_program,
    },
}

-- ==================================================================
-- Go
-- ==================================================================
debuggers.go = {
    dap = {
        adapter_id = "go",
        name = "Delve (dlv)",
        type = "executable",
        command = { mason_bin("delve") },
        args = { "dap", "-l", "127.0.0.1:0" },
    },
    launch_args = {
        mode = "debug",
        program = "${projdir}",
        dlvToolPath = mason_bin("delve"),
    },
    attach_args = {
        mode = "local",
        processId = "${select-process-pid}",
    },
}

-- ==================================================================
-- Python
-- ==================================================================
debuggers.python = {
    dap = {
        adapter_id = "debugpy",
        name = "debugpy",
        type = "executable",
        command = { "python3", "-m", "debugpy.adapter" },
    },
    launch_args = {
        program = function(task) return task.command end,
        cwd = get_task_cwd,
        stopOnEntry = false,
        justMyCode = false,
        console = "integratedTerminal",
        env = function(task) return task.env end,
    },
}

-- ==================================================================
-- Node.js / TypeScript / JavaScript
-- ==================================================================
debuggers.node = {
    dap = {
        adapter_id = "node",
        name = "Node.js (node-debug2)",
        type = "executable",
        command = { mason_bin("node-debug2-adapter") },
    },
    launch_args = {
        type = "node",
        program = "${file}",
        cwd = "${projdir}",
        runtimeExecutable = "node",
        sourceMaps = true,
        protocol = "inspector",
        console = "integratedTerminal",
    },
    attach_args = {
        type = "node",
        processId = "${select-process-pid}",
    },
}

debuggers.javascript = debuggers.node
debuggers.typescript = debuggers.node

-- ==================================================================
-- Chrome / Edge / Web (Browser)
-- ==================================================================
debuggers.chrome = {
    dap = {
        adapter_id = "chrome",
        name = "Chrome",
        type = "executable",
        command = { mason_bin("chrome-debug-adapter") },
    },
    launch_args = {
        type = "chrome",
        name = "Launch Chrome",
        url = "http://localhost:3000",
        webRoot = "${projdir}",
        sourceMaps = true,
        userDataDir = false,
    },
    attach_args = {
        type = "chrome",
        program = "${file}",
        port = 9222,
        webRoot = "${projdir}",
    },
}

-- ==================================================================
-- Bash
-- ==================================================================
debuggers.bash = {
    dap = {
        adapter_id = "bash",
        name = "bashdb",
        type = "executable",
        command = { mason_bin("bash-debug-adapter") },
    },
    launch_args = {
        name = "Launch Bash Script",
        type = "bashdb",
        program = "${file}",
        cwd = "${projdir}",
        pathBash = "bash",
        pathBashdb = mason_bin("bashdb"),
        pathCat = "cat",
        pathMkfifo = "mkfifo",
        pathPkill = "pkill",
        env = {},
        terminalKind = "integrated",
    },
}

-- ==================================================================
-- PHP
-- ==================================================================
debuggers.php = {
    dap = {
        adapter_id = "php",
        name = "PHP Debug (vscode-php-debug)",
        type = "executable",
        command = { mason_bin("php-debug") },
    },
    launch_args = {
        name = "Listen for Xdebug",
        type = "php",
        port = 9003,
        pathMappings = {
            ["/var/www/html"] = "${projdir}",
        },
    },
}

-- ==================================================================
-- Java
-- ==================================================================
debuggers.java = {
    dap = {
        adapter_id = "java",
        name = "Java (jdtls)",
        type = "server",
        host = "127.0.0.1",
        port = 9000,
    },
    attach_args = {}
}

-- ==================================================================
-- C# / .NET
-- ==================================================================
debuggers.csharp = {
    dap = {
        adapter_id = "netcoredbg",
        name = "netcoredbg",
        type = "executable",
        command = { mason_bin("netcoredbg") },
        args = { "--interpreter=vscode" },
    },
    launch_args = {
        type = "coreclr",
        name = "Launch .NET",
        program = function()
            return vim.fn.input("Path to dll: ", vim.fn.getcwd() .. "/bin/Debug/", "file")
        end,
    },
    attach_args = {
        type = "coreclr",
        name = "Attach to Process",
        processId = "${select-process-pid}",
    },
}

return debuggers
