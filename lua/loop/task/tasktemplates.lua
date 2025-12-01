return {
    {
        name = "Lua check",
        type = "tool",
        command = { "luacheck", "${projdir}" },
        cwd = "${projdir}",
        quickfix_matcher = "luacheck",
        depends_on = {},
    },

    {
        name = "Build ${filename}",
        type = "tool",
        command = { "g++", "-g", "-std=c++23", "${file}", "-o", "${fileroot}.out" },
        cwd = "${projdir}",
        quickfix_matcher = "gcc",
        depends_on = {},
    },

    {
        name = "Run ${filename}",
        type = "app",
        command = "${fileroot}.out",
        cwd = "${projdir}",
        depends_on = { "Build ${filename}" },
    },

    {
        name = "Debug ${filename} (lldb)",
        type = "debug",
        command = "${fileroot}.out",
        cwd = "${projdir}",
        debugger = "lldb",
        debugger_args = {
            stopOnEntry = true,
            environment = {},
            sourceLanguages = { "cpp" },
        },
        depends_on = { "Build ${filename}" },
    },

    {
        name = "Attach to node",
        type = "debug",
        command = nil,
        debugger = "js-debug",
        debugger_args = {
            port = 9229,
            restart = true,
        },
    },
    {
        name = "Debug lua file",
        type = "debug",
        command = "${file}",
        debugger = "lua:local",
    },

    {
        name = "Attach to OSV (lua)",
        type = "debug",
        debugger = "lua:remote",
        debugger_args = {
            port = 8086,
            restart = true,
        },
    },

    {
        name = "Debug Python",
        type = "debug",
        command = "main.py",
        debugger = "debugpy",
        debugger_args = {
            stopOnEntry = true,
            justMyCode = false,
        },
    },
}
