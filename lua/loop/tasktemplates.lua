return {
    {
        name = "Lua check",
        type = "build",
        command = {"luacheck", "${PROJDIR}"},
        cwd = "${PROJDIR}",
        problem_matcher = "$luacheck",
        depends_on = {},
    },    
    {
        name = "Build ${FILENAME}",
        type = "build",
        command = {"g++", "-g", "-std=c++23", "${FILE}", "-o", "${FILEROOT}.out", "-fdiagnostics-color=always"},
        cwd = "${PROJDIR}",
        problem_matcher = "$gcc",
        depends_on = {},
    },
    {
        name = "Run ${FILENAME}",
        type = "run",
        command = "${FILEROOT}.out",
        cwd = "${PROJDIR}",
        depends_on = { "Build ${FILENAME}" },
    },
    {
        name = "Debug ${FILENAME}",
        type = "debug:launch",
        command = "${FILEROOT}.out",
        cwd = "${PROJDIR}",
        depends_on = { "Build ${FILENAME}" },
    },
    {
        name = "Attach Debugger",
        type = "debug:attach",
    },
}