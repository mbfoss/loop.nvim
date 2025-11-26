local M = {}
---@class loop.Config.Debug
---@field stack_levels_limit number
---@field sign_priority number

---@class loop.Config.Debugger
---@field command string|string[]
---@field cwd string|nil
---@field env table<string,string>|nil
---@field init_commands string[]|nil
---@field configure_post_launch boolean|nil

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
            init_commands = {},
        },
        python = {
            command = "python -m debugpy.adapter",
            configure_post_launch = true
        },
        dapjs = {
            command = "node /Users/Dev/Projects/js-debug/src/dapDebugServer.js",
            --configure_post_launch = true
        },
    }
}

---@type loop.Config
M.current = nil

return M
