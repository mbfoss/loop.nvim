require('loop.task.taskdef')
local builtin_macros = require('loop.task.macros')
local builtin_debuggers = require('loop.task.debuggers')
local builtin_qfmatchers = require("loop.task.qfmatchers")

---@class loop.Config.Debug
---@field stack_levels_limit number
---@field sign_priority table<string,number>

---@class loop.Config.Window.Symbols
---@field change string
---@field success string
---@field failure string
---@field running string
---@field paused string

---@class loop.Config.Window
---@field symbols loop.Config.Window.Symbols

---@class window loop.Config.Window
---@class loop.Config
---@field debug loop.Config.Debug
---@field window loop.Config.Window
---@field qfmatchers table<string,fun(line:string,context:table):loop.task.QuickFixItem>
---@field macros table<string,fun():any>
---@field debuggers table<string,loop.Config.Debugger>

local M = {}

---@type loop.Config
M.current = {
    window = {
        symbols = {
            change  = '•', -- bullet
            success = '✓', -- light check
            failure = '✗', -- light x
            running = '▶',
            paused  = '⏸',
        }
    },
    debug = {
        stack_levels_limit = 100,
        auto_switch_page = true,
        sign_priority = {
            breakpoints = 12,
            currentframe = 13
        },
    },
    qfmatchers = builtin_qfmatchers,
    macros = builtin_macros,
    debuggers = builtin_debuggers,
}

return M
