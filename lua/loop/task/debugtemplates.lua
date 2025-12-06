require('loop.task.taskdef')

---@type loop.taskTemplate[]
return {
    -- ==================================================================
    -- Lua
    -- ==================================================================
    {
        name = "Debug current Lua file (local-lua-debugger-vscode)",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file:lua}",
            cwd = "${projdir}",
            debug_adapter = "lua",
            debug_request = "launch",
            -- everything else (program.file, cwd, etc.) is filled automatically
        }
    },

    {
        name = "Attach to remote Lua process",
        task = {
            name = "Attach",
            type = "debug",
            debug_adapter = "lua:remote",
            debug_request = "attach",
            debug_args = {
                host = "127.0.0.1",
                port = 8086,
            },
        }
    },

    -- ==================================================================
    -- C / C++ / Rust / Objective-C (lldb-dap)
    -- ==================================================================
    {
        name = "Debug executable with LLDB (launch)",
        task = {
            name = "Debug",
            type = "debug",
            command = "${select-file:Select binary:}",
            cwd = "${projdir}",
            debug_adapter = "lldb",
            debug_request = "launch",
            debug_args = {
                runInTerminal = true, -- most people want this
                stopOnEntry = false,
            },
        }
    },

    {
        name = "Attach to running process (LLDB)",
        task = {
            name = "Attach",
            type = "debug",
            debug_adapter = "lldb",
            debug_request = "attach",
            debug_args = { pid = "${select-pid}" },
        }
    },

    -- ==================================================================
    -- Node.js / JavaScript / TypeScript
    -- ==================================================================
    {
        name = "Debug Node.js script (js-debug)",
        task = {
            name = "Debug",
            type = "debug",
            command = { "node", "${file:js}" },
            cwd = "${projdir}",
            debug_adapter = "js-debug",
            debug_request = "launch",
            debug_args = {
                sourceMaps = true,
                stopOnEntry = false,
            },
        }
    },

    {
        name = "Attach to Node.js process (js-debug)",
        task = {
            name = "Attach",
            type = "debug",
            debug_adapter = "js-debug",
            debug_request = "attach",
            debug_args = {
                address = "127.0.0.1",
                port = "${prompt:Inspector port}",
                restart = true,
            },
        }
    },

    -- ==================================================================
    -- Python
    -- ==================================================================
    {
        name = "Debug Python script (debugpy)",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file:python}",
            cwd = "${projdir}",
            debug_adapter = "debugpy",
            debug_request = "launch",
            debug_args = {
                justMyCode = false,
            },
        }
    },

    -- ==================================================================
    -- Go
    -- ==================================================================
    {
        name = "Debug Go program (delve)",
        task = {
            name = "Debug Go program (delve)",
            type = "debug",
            cwd = "${projdir}",
            debug_adapter = "go",
            debug_request = "launch",
            debug_args = { mode = "debug" }, -- program is auto-filled from cwd
        }
    },

    {
        name = "Attach to Go process (delve)",
        task = {
            name = "Attach",
            type = "debug",
            debug_adapter = "go",
            debug_request = "attach",
            debug_args = {
                mode = "local",
                processId = "${select-pid}",
            },
        }
    },

    -- ==================================================================
    -- Chrome / Web
    -- ==================================================================
    {
        name = "Launch Chrome and debug",
        task = {
            name = "Launch",
            type = "debug",
            debug_adapter = "chrome",
            debug_request = "launch",
            debug_args = {
                url = "http://localhost:3000",
                webRoot = "${projdir}",
                userDataDir = false,
                sourceMaps = true,
            },
        }
    },

    {
        name = "Attach to running Chrome",
        task = {
            name = "Attach",
            type = "debug",
            debug_adapter = "chrome",
            debug_request = "attach",
            debug_args = {
                port = 9222,
                webRoot = "${projdir}",
            },
        }
    },

    -- ==================================================================
    -- Bash
    -- ==================================================================
    {
        name = "Debug Bash script (bashdb)",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file}",
            cwd = "${projdir}",
            debug_adapter = "bash",
            debug_request = "launch",
            -- program and cwd are auto-filled
        }
    },

    -- ==================================================================
    -- PHP (Xdebug)
    -- ==================================================================
    {
        name = "Listen for Xdebug (PHP)",
        task = {
            name = "Listen",
            type = "debug",
            debug_adapter = "php",
            debug_request = "launch",
            debug_args = {
                port = 9003,
                pathMappings = { ["/var/www/html"] = "${projdir}" }, -- change if needed
            },
        }
    },

    -- ==================================================================
    -- C# / .NET
    -- ==================================================================
    {
        name = "Debug .NET DLL (netcoredbg)",
        task = {
            name = "Debug",
            type = "debug",
            debug_adapter = "netcoredbg",
            debug_request = "launch",
            debug_args = {
                program = function()
                    return vim.fn.input("Path to dll: ", vim.fn.getcwd() .. "/bin/Debug/", "file")
                end,
            },
        }
    },

    {
        name = "Attach to .NET process",
        task = {
            name = "Attach",
            type = "debug",
            debug_adapter = "netcoredbg",
            debug_request = "attach",
            debug_args = { processId = "${select-pid}" },
        }
    },

    -- ==================================================================
    -- Java (jdtls)
    -- ==================================================================
    {
        name = "Attach to Java process (JDWP)",
        task = {
            name = "Attach",
            type = "debug",
            debug_adapter = "java",
            debug_request = "attach",
            debug_args = {
                hostName = "127.0.0.1",
                port = 5005,
            },
        }
    },
}
