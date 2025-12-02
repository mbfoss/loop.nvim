require('loop.task.taskdef')
local builtinmacros = require('loop.tools.macros')
local debugger_templates = require('loop.dbgtemplates')

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

    debuggers = debugger_templates,

    macros = {
        home      = builtinmacros.home,
        file      = builtinmacros.file,
        filename  = builtinmacros.filename,
        fileext   = builtinmacros.fileext,
        fileroot  = builtinmacros.fileroot,
        filedir   = builtinmacros.filedir,
        projdir   = builtinmacros.projdir,
        cwd       = builtinmacros.cwd,
        filetype  = builtinmacros.filetype,
        tmpdir    = builtinmacros.tmpdir,
        date      = builtinmacros.date,
        time      = builtinmacros.time,
        timestamp = builtinmacros.timestamp,
    }
}

return M
