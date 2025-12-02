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
        debug_adapter = "lldb",
        debug_request = "launch",
        debug_args = {
            stopOnEntry = false,
        },
        depends_on = { "Build ${filename}" },
    },

}
