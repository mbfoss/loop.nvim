--[[
@ -35,20 +36,19 @@ local debuggers = {
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
        request_args = {
            program = get_task_program,
            args = get_task_args,
            cwd = get_task_cwd,
            stopOnEntry = false,
            env = function(task) return task.env end,
            sourceLanguages = { "cpp", "c", "rust", "objc" },
            initCommands = {
                --    "settings set target.input-path /dev/null",
@ -56,281 +56,11 @@ local debuggers = {
            },
            runInTerminal = true,
        },
    },

    -- ──────────────────────────────────────────────────────────────
    -- Generic “attach to any local process” (pick PID)
    -- ──────────────────────────────────────────────────────────────
    ["lldb:attach"] = {
        dap = {
            adapter_id = "lldb",
            name = "Attach to process (PID)",
            type = "executable",
            command = { "lldb-dap" },
        },
        request = "attach",
        request_args = {
            program = get_task_program,
            pid = "${select-pid}",
            stopOnEntry = true,
        },
        terminate_debuggee = false,
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
        request_args = {
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
        request_args = {
            program = function(task) return task.command end,
            cwd = get_task_cwd,
            stopOnEntry = false,
            justMyCode = false,
            console = "integratedTerminal",
            env = function(task) return task.env end,
        },

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
        request_args = {
            program = get_task_program,
            args = get_task_args,
            cwd = get_task_cwd,
            stopOnEntry = false,
            env = function(task) return task.env end,
        },

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
        request_args = {
            program = get_task_program,
            cwd = get_task_cwd,
            stopOnEntry = false,
        },
    },
    -- ──────────────────────────────────────────────────────────────
    -- LuaJIT via CodeLLDB (great for embedded/C modules)
    -- ──────────────────────────────────────────────────────────────
    ["luajit-lldb"] = {
        dap = {
            adapter_id = "lldb",
            name = "LuaJIT via LLDB",
            type = "executable",
            command = { "lldb-dap" },
        },
        request = "launch",
        request_args = {
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

    },
    -- ──────────────────────────────────────────────────────────────
    -- Lua - local-lua-debugger-vscode (recommended for pure Lua)
    -- ──────────────────────────────────────────────────────────────
    ["lua:local"] = {
        dap = {
            adapter_id = "lua-local",
            name = "Local Lua Debugger",
            type = "executable",
            command = { "node", "/Users/Dev/Projects/local-lua-debugger-vscode/extension/debugAdapter.js" },
        },
        request = "launch",
        request_args = {
            type = "lua",
            request = "launch",
            program = {
                lua = "lua", -- change to "luajit" if you use LuaJIT
                file = get_task_program,
            },
            args = get_task_args,
            cwd = get_task_cwd,
            env = function(task) return task.env or {} end,
            stopOnEntry = false,
        },

    },
    -- ──────────────────────────────────────────────────────────────
    -- Generic Lua Remote Debugger (works for Neovim plugins, scripts, etc.)
    -- ──────────────────────────────────────────────────────────────
    ["lua:remote"] = {
        dap = {
            adapter_id = "lua:remote",
            name = "Lua Remote Debugger",
            type = "server", -- we attach to a running adapter
            host = "127.0.0.1",
            port = 8086,     -- change if you wan
        },
        request = "attach",
        request_args = {
            request = "attach",
            type = "lua",
            host = "127.0.0.1",
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
        request_args = {
            mode = "debug",
            program = "${workspaceFolder}",
            args = get_task_args,
            env = function(task) return task.env end,
            cwd = get_task_cwd,
        },

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
        request_args = {
            program = get_task_program,
            args = get_task_args,
            cwd = get_task_cwd,
            stopOnEntry = false,
            env = function(task) return task.env end,
        },

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
        request_args = {
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
            command = { "java", "-jar",
                vim.fn.stdpath("data") ..
                "/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar" },
        },
        request = "launch",
        request_args = {
            mainClass = function()
                -- you can make this smarter with gradle/maven parsing
                return vim.fn.input("Main class: ", "", "file")
            end,
            projectName = vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            stopOnEntry = false,
        },

    },
}

]]--