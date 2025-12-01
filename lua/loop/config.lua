local M = {}

require('loop.task.taskdef')
local daptemplates = require('loop.daptemplates')

---@class loop.Config
---@field debug loop.Config.Debug
---@field debuggers loop.Config.Debugger[]

---@type loop.Config
M.defaut_config = {
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
}

M.current = nil
return M
