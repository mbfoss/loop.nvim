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
        name = "Debug Node.js (js-debug)",
        type = "debug",
        command = nil,
        cwd = "${PROJDIR}",
        debugger = "js-debug",
        debugger_args = {
            request = "launch",
            runtimeExecutable = "node",
            program = "${PROJDIR}/main.js",
            stopOnEntry = true,
            attachSimplePort = 0,
            __restart = true,
            sourceMaps = true,
        },
    },

    {
        name = "Attach to Node --inspect",
        type = "debug",
        command = nil,
        debugger = "js-debug",
        debugger_args = {
            request = "attach",
            port = 9229,
            restart = true,
        },
    },

    {
        name = "Debug Python",
        type = "debug",
        command = nil,
        debugger = "debugpy",
        debugger_args = {
            program = "${file}",
            stopOnEntry = true,
            justMyCode = false,
        },
    },
}
