local M = {}
---@class loop.Config.Debug
---@field stack_levels_limit number
---@field sign_priority number

---@class loop.Config.Debugger
---@field command string|string[]
---@field cwd string|nil
---@field env table<string,string>|nil
---@field init_commands string[]|nil

---@class loop.Config
---@field debug loop.Config.Debug
---@field debuggers loop.Config.Debugger[]

---@type loop.Config
M.defaut_config = {
    debug = {
        sign_priority = 12,
        stack_levels_limit = 100,
        auto_switch_page = true,
    },
    debuggers = {
        lldb = {
            command = "lldb-dap",
            init_commands = {
                -- follow BOTH parent and child
                "settings set target.process.follow-fork-mode both",
                -- Linux: catch clone
                "settings set target.process.attach-on-fork true",
                "settings set target.process.attach-on-clone true",
                -- macOS: catch fork
                "settings set target.process.attach-on-fork true",
            },
        },
        pthon = {
            command = "python -m debugpy.adapter"
        },
    }
}

---@type loop.Config
M.current = nil

return M
