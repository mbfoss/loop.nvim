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
        node = daptemplates.node,
        debugpy = daptemplates.debugpy,
        netcoredbg = daptemplates.netcoredbg,
        bashdb = daptemplates.bashdb,
        luajit_lldb = daptemplates.luajit_lldb,
        lua_local = daptemplates.lua_local,
        lua_remote = daptemplates.lua_remote,
        delve = daptemplates.delve,
        codelldb = daptemplates.codelldb,
        php = daptemplates.php,
        java = daptemplates.java,
        lldb_attach_proess = daptemplates.lldb_attach_proess,
    },
}

M.current = nil
return M
