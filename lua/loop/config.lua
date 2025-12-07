require('loop.task.taskdef')
local builtin_macros = require('loop.macros')
local builtin_debuggers = require('loop.debuggers')

---@class loop.Config
---@field debug loop.Config.Debug
---@field debuggers loop.Config.Debugger[]
---@field macros table<string,fun():any>

local M = {}

---@type loop.Config
M.current = {
    debug = {
        stack_levels_limit = 100,
        auto_switch_page = true,
        sign_priority = {
            breakpoints = 12,
            currentframe = 13
        },
    },

    debuggers = builtin_debuggers,
    macros = builtin_macros
}

return M
