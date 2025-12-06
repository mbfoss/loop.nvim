require('loop.task.taskdef')



---@type loop.taskTemplate[]
return {
    {
        name = "Lua check",
        task = {
            name = "Check",
            type = "build",
            command = { "luacheck", "${projdir}" },
            cwd = "${projdir}",
            quickfix_matcher = "luacheck",
            depends_on = {},
        },
    },
    {
        name = "Build c++ file",
        task = {
            name = "Build",
            type = "build",
            command = { "g++", "-g", "-std=c++23", "${file:cpp}", "-o", "${fileroot}.out" },
            cwd = "${projdir}",
            quickfix_matcher = "gcc",
            depends_on = {},
        },
    }
}
