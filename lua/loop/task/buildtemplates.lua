require('loop.task.taskdef')
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
        command = { "g++", "-g", "-std=c++23", "${file:cpp}", "-o", "${fileroot}.out" },
        cwd = "${projdir}",
        quickfix_matcher = "gcc",
        depends_on = {},
    },
}
