require('loop.task.taskdef')
local builtinmacros = require('loop.tools.macros')
local daptemplates = require('loop.daptemplates')

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

    debuggers = {
        lldb = daptemplates.lldb,
        ["lldb:attach"] = daptemplates["lldb:attach"],
        node = daptemplates.node,
        debugpy = daptemplates.debugpy,
        netcoredbg = daptemplates.netcoredbg,
        bashdb = daptemplates.bashdb,
        luajit_lldb = daptemplates.luajit_lldb,
        ["lua:local"] = daptemplates["lua:local"],
        ["lua:remote"] = daptemplates["lua:remote"],
        delve = daptemplates.delve,
        codelldb = daptemplates.codelldb,
        php = daptemplates.php,
        java = daptemplates.java,
    },

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
