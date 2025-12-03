return {
    {
        name = "Lua check",
        type = "build",
        command = { "luacheck", "${projdir}" },
        cwd = "${projdir}",
        quickfix_matcher = "luacheck",
        depends_on = {},
    },

    {
        name = "Build ${filename}",
        type = "build",
        command = { "g++", "-g", "-std=c++23", "${file}", "-o", "${fileroot}.out" },
        cwd = "${projdir}",
        quickfix_matcher = "gcc",
        depends_on = {},
    },
}
