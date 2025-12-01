return {
    {
        name = "Lua check",
        type = "tool",
        command = { "luacheck", "${PROJDIR}" },
        cwd = "${PROJDIR}",
        quickfix_matcher = "luacheck",
        depends_on = {},
    },

    {
        name = "Build ${FILENAME}",
        type = "tool",
        command = { "g++", "-g", "-std=c++23", "${FILE}", "-o", "${FILEROOT}.out" },
        cwd = "${PROJDIR}",
        quickfix_matcher = "gcc",
        depends_on = {},
    },

    {
        name = "Run ${FILENAME}",
        type = "app",
        command = "${FILEROOT}.out",
        cwd = "${PROJDIR}",
        depends_on = { "Build ${FILENAME}" },
    },

    {
        name = "Debug ${FILENAME} (lldb)",
        type = "debug",
        command = "${FILEROOT}.out",
        cwd = "${PROJDIR}",
        debugger = "lldb",
        debugger_args = {
            stopOnEntry = true,
            environment = {},
            sourceLanguages = { "cpp" },
        },
        depends_on = { "Build ${FILENAME}" },
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
