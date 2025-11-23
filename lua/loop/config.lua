local M = {}
---@class loop.Config.Debug
---@field stack_levels_limit number

---@class loop.Config.Debugger
---@field command string|string[]
---@field cwd string|nil
---@field env table<string,string>|nil

---@class loop.Config
---@field debug loop.Config.Debug
---@field debuggers loop.Config.Debugger[]

---@type loop.Config
M.defaut_config = {
    debug = {
        stack_levels_limit = 100,
        auto_switch_page = true,
    },
    debuggers = {
        lldb = {
            command = "lldb-dap",
        },
        pthon = {
            command = "python -m debugpy.adapter"
        },
    }
}

---@type loop.Config
M.current = nil

return M
