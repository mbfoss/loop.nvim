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
---@field request      "launch" | "attach"
---@field default_request_args  table<string,any>
---@field terminate_debuggee boolean|nil


---@type table<string,loop.Config.Debugger>
local debuggers = {
    -- ──────────────────────────────────────────────────────────────
    -- LLDB (C/C++/Rust/ObjC)
    -- ──────────────────────────────────────────────────────────────
    lldb = {
        dap = {
            adapter_id = "lldb",
            name = "lldb",
            type = "executable",
            command = { "lldb-dap" }, -- or full path if needed
            --cmd  = "/Library/Developer/CommandLineTools/usr/bin/lldb-dap"
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
            runInTerminal = true,
        },
        terminate_debuggee = true,
    },
    -- ──────────────────────────────────────────────────────────────
    -- JavaScript / TypeScript / Node.js (pwa-node, pwa-chrome, etc.)
    -- server command: node dapDebugServer.js
    -- ──────────────────────────────────────────────────────────────
    node = {
        dap = {
            adapter_id = "js-debug",
            name = "js-debug",
            type = "server",
            host = "::1",
            port = 8123,
            cwd = os.getenv("HOME"),
        },
        request = "launch",
        default_request_args = {
            type = "pwa-node",
            request = "launch",
            runtimeExecutable = "node",
            program = function(task) return task.command or nil end,
            cwd = get_task_cwd,
            stopOnEntry = false,
            sourceMaps = true,
            --outputCapture = "std",
        },
        terminate_debuggee = true,
    },
    -- ──────────────────────────────────────────────────────────────
    -- debugpy (Python)
    -- ──────────────────────────────────────────────────────────────
    debugpy = {
        dap = {
            adapter_id = "debugpy",
            name = "debugpy",
            type = "executable",
            command = { "python3", "-m", "debugpy.adapter" },
        },
        request = "launch",
        default_request_args = {
            program = function(task) return task.command or "${file}" end,
            cwd = get_task_cwd,
            stopOnEntry = false,
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
            adapter_id = "netcoredbg",
            name = "netcoredbg",
            type = "executable",
            command = { "netcoredbg", "--interpreter=vscode" },
        },
        request = "launch",
        default_request_args = {
            program = get_task_program,
            args = get_task_args,
            cwd = get_task_cwd,
            stopOnEntry = false,
            env = function(task) return task.env end,
        },
        terminate_debuggee = true,
    },
    -- ──────────────────────────────────────────────────────────────
    -- bashdb (Bash scripts)
    -- ──────────────────────────────────────────────────────────────
    bashdb = {
        dap = {
            adapter_id = "bashdb",
            name = "bashdb",
            type = "executable",
            command = { "bashdb", "--adapter" },
        },
        request = "launch",
        default_request_args = {
            program = get_task_program,
            cwd = get_task_cwd,
            stopOnEntry = false,
        },
    },
    -- ──────────────────────────────────────────────────────────────
    -- LuaJIT via CodeLLDB (great for embedded/C modules)
    -- ──────────────────────────────────────────────────────────────
    luajit_lldb = {
        dap = {
            adapter_id = "lldb",
            name = "LuaJIT via LLDB",
            type = "executable",
            command = { "lldb-dap" },
        },
        request = "launch",
        default_request_args = {
            program = get_task_program,
            args = get_task_args,
            cwd = get_task_cwd,
            stopOnEntry = false,
            initCommands = {
                "command script import " ..
                vim.fn.stdpath("data") .. "/mason/packages/codelldb/extension/lldb/luajit.lua",
                "settings set target.input-path /dev/null",
                "settings set target.output-path /dev/null",
            },
            sourceLanguages = { "lua" },
            runInTerminal = false,
        },
        terminate_debuggee = true,
    },
    -- ──────────────────────────────────────────────────────────────
    -- Lua - local-lua-debugger-vscode (recommended for pure Lua)
    -- ──────────────────────────────────────────────────────────────
    lua_local = {
        dap = {
            adapter_id = "lua-local",
            name = "Local Lua Debugger",
            type = "executable",
            command = "node",
            args = {
                vim.fn.stdpath("data") .. "/mason/packages/local-lua-debugger-vscode/extension/out/server.js",
            },
        },
        request = "launch",
        default_request_args = {
            type = "lua-local",
            request = "launch",
            name = "Launch Current File",
            program = {
                lua = "lua", -- change to "luajit" if you use LuaJIT
                file = "${file}",
            },
            args = get_task_args,
            cwd = get_task_cwd,
            env = function(task) return task.env or {} end,
            stopOnEntry = false,
        },
        terminate_debuggee = true,
    },
    -- ──────────────────────────────────────────────────────────────
    -- Generic Lua Remote Debugger (works for Neovim plugins, scripts, etc.)
    -- ──────────────────────────────────────────────────────────────
    lua_remote = {
        dap = {
            adapter_id = "lua-remote",
            name = "Lua Remote Debugger",
            type = "server", -- we attach to a running adapter
            host = "127.0.0.1",
            port = 5678,     -- change if you wan
        },
        request = "attach",
        default_request_args = {
            type = "lua-local", -- protocol name used by local-lua-debugger-vscode / OSV
            request = "attach",
            name = "Attach to Lua process",
            host = "127.0.0.1",
            port = 5678,
            program = {
                lua = "lua", -- or "luajit" if the target uses LuaJIT
            },
            cwd = "${workspaceFolder}",
            stopOnEntry = false,
            -- Optional: useful when debugging inside containers or with path remapping
            -- sourceFileMap = {
            --     ["/remote/path"] = "${workspaceFolder}",
            -- },
        },
        terminate_debuggee = false, -- NEVER kill the process we attached to
    },

    -- ──────────────────────────────────────────────────────────────
    -- Go (delve)
    -- Server command: dlv dap -l 127.0.0.1:38697 --log
    -- ──────────────────────────────────────────────────────────────
    delve = {
        dap = {
            adapter_id = "delve",
            name = "delve",
            type = "server",
            port = 38697,
        },
        request = "launch",
        default_request_args = {
            mode = "debug",
            program = "${workspaceFolder}",
            args = get_task_args,
            env = function(task) return task.env end,
            cwd = get_task_cwd,
        },
        terminate_debuggee = true,
    },

    -- ──────────────────────────────────────────────────────────────
    -- Rust (via codelldb – better than delve for Rust)
    -- Server command: codelldb --port 38690
    -- ──────────────────────────────────────────────────────────────
    codelldb = {
        dap = {
            adapter_id = "codelldb",
            name = "codelldb",
            type = "server",
            port = 38690,
        },
        request = "launch",
        default_request_args = {
            program = get_task_program,
            args = get_task_args,
            cwd = get_task_cwd,
            stopOnEntry = false,
            env = function(task) return task.env end,
        },
        terminate_debuggee = true,
    },

    -- ──────────────────────────────────────────────────────────────
    -- PHP (php-debug / Intelephense)
    -- ──────────────────────────────────────────────────────────────
    php = {
        dap = {
            adapter_id = "php",
            name = "php-debug",
            type = "executable",
            command = "node",
            args = { vim.fn.stdpath("data") .. "/mason/packages/php-debug-adapter/extension/out/phpDebug.js" },
        },
        request = "launch",
        default_request_args = {
            name = "Listen for Xdebug",
            type = "php",
            request = "launch",
            port = 9003,
            stopOnEntry = false,
            pathMappings = {
                ["/var/www/html"] = "${workspaceFolder}",
            },
        },
        terminate_debuggee = false, -- Xdebug is “attach” style
    },

    -- ──────────────────────────────────────────────────────────────
    -- Java (vscode-java-debug)
    -- ──────────────────────────────────────────────────────────────
    java = {
        dap = {
            adapter_id = "java",
            name = "vscode-java-debug",
            type = "executable",
            command = "java",
            args = {
                "-jar",
                vim.fn.stdpath("data") ..
                "/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar",
            },
        },
        request = "launch",
        default_request_args = {
            mainClass = function()
                -- you can make this smarter with gradle/maven parsing
                return vim.fn.input("Main class: ", "", "file")
            end,
            projectName = vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            stopOnEntry = false,
        },
        terminate_debuggee = true,
    },

    -- ──────────────────────────────────────────────────────────────
    -- Generic “attach to any local process” (pick PID)
    -- ──────────────────────────────────────────────────────────────
    lldb_attach_proess = {
        dap = {
            adapter_id = "lldb",
            name = "Attach to process (PID)",
            type = "executable",
            command = { "lldb-dap" },
        },
        request = "attach",
        default_request_args = {
            name = "Attach to PID",
            program = get_task_program,
            pid = "${select-process-pid}",
            stopOnEntry = true,
        },
        terminate_debuggee = false,
    }
}

return debuggers
