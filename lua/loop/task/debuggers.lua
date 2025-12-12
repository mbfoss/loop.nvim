require('loop.task.taskdef')
local strtools = require('loop.tools.strtools')

---@param task loop.Task
local function get_task_command(task)
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

---@class loop.Config.Debugger
---@field adapter_config loop.dap.AdapterConfig
---@field launch_args    table<string,any>|nil
---@field attach_args    table<string,any>|nil
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
    adapter_config = {
        adapter_id = "lua",
        name = "Local Lua Debugger",
        type = "executable",
        -- This is the official adapter from the Lua community
        command = { "node",
            vim.fn.stdpath("data") ..
            "/mason/packages/local-lua-debugger-vscode/extension/extension/debugAdapter.js",
        }, -- or "lua-debug"
        env = {
            LUA_PATH = vim.fn.stdpath("data")
                .. "/mason/packages/local-lua-debugger-vscode/extension/debugger/?.lua;;"
        },
        -- Optional: some versions need extra args
    },
    -- Launch: debug current file or project
    launch_args = {
        type = "lua-local",
        request = "launch",
        name = "Debug",
        cwd = "${projdir}",
        program = {
            lua = vim.fn.exepath("lua"),
            file = get_task_command,
            communication = 'stdio',
        },
    },
}


debuggers["lua:remote"] = {
    adapter_config = {
        adapter_id = "lua",
        name = "Lua Remote Debugger",
        type = "server",
        host = "127.0.0.1",
        port = 8086,
    },
    attach_args = {
        request = "attach",
        type = "lua",
        host = "127.0.0.1",
        cwd = "${projdir}",
        stopOnEntry = false,
    },
    terminate_debuggee = false, -- NEVER kill the process we attached to
}

-- ==================================================================
-- C / C++ / Rust / Objective-C
-- ==================================================================
debuggers.lldb = {
    adapter_config = {
        adapter_id = "lldb",
        name = "LLDB (via lldb-dap)",
        type = "executable",
        command = { mason_bin("lldb-dap") },
    },
    launch_args = {
        program = get_task_command,
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
        pid = "${select-pid}",
        program = get_task_command,
    },
}

-- ──────────────────────────────────────────────────────────────
-- JavaScript / TypeScript / Node.js (pwa-node, pwa-chrome, etc.)
-- server command: node dapDebugServer.js
-- ──────────────────────────────────────────────────────────────
debuggers["js-debug"] = {
    adapter_config = {
        adapter_id = "js-debug",
        name = "js-debug",
        type = "server",
        host = "::1",
        port = 8123,
        cwd = os.getenv("HOME"),
    },
    launch_args = {
        type = "pwa-node",
        request = "launch",
        runtimeExecutable = "node",
        program = function(task) return task.command or nil end,
        cwd = get_task_cwd,
        stopOnEntry = false,
        attachSimplePort = 0,
        sourceMaps = true,  
        --outputCapture = "std",
    },
    attach_args = {
        type = "pwa-node",
        request = "attach",
        name = "Attach to Node (localhost)",
        address = "127.0.0.1",
        port = "${prompt:Inspector port:}",
        cwd = "${projdir}",
        restart = true,      -- auto-reconnect if process restarts
        localRoot = "${projdir}",
        remoteRoot = "/app", -- change if your container path is different
        skipFiles = { "<node_internals>/**", "node_modules/**" },
    },
}

-- ==================================================================
-- Python
-- ==================================================================
debuggers.debugpy = { -- tested
    adapter_config = {
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

debuggers["debugpy:remote"] = {
    adapter_config = {
        adapter_id = "debugpy",
        name = "Python Remote Debugger",
        type = "server",
        host = "127.0.0.1",
        port = 8086,
    },
    attach_args = {
        justMyCode = false,
        console = "integratedTerminal",
    },
}

-- ==================================================================
-- Go
-- ==================================================================
debuggers.go = { -- untested
    adapter_config = {
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
        processId = "${select-pid}",
    },
}

-- ==================================================================
-- Chrome / Edge / Web (Browser)
-- ==================================================================
debuggers.chrome = { -- untested
    adapter_config = {
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
debuggers.bash = { -- untested
    adapter_config = {
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
debuggers.php = { -- untested
    adapter_config = {
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
debuggers.java = { -- untested
    adapter_config = {
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
debuggers.csharp = { -- untested
    adapter_config = {
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
        processId = "${select-pid}",
    },
}

return debuggers
