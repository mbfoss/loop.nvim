local M = {}

---@class loop.Config.Debugger
---@field command string|string[]
---@field cwd string|nil
---@field env table<string,string>|nil

---@class loop.Config
---@field debuggers loop.Config.Debugger[]

---@type loop.Config
M.defaut_config = {
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
