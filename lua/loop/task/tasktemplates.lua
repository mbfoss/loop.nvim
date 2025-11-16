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
        name = "Debug ${FILENAME}",
        type = "debug",
        debug = {
            adapter = "dap_exe",
            run_in_terminal = false,
            stop_on_entry = true,
        },
        command = "${FILEROOT}.out",
        cwd = "${PROJDIR}",
        depends_on = { "Build ${FILENAME}" },
    }
}
