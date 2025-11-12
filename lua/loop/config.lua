
local M = {}

---@class loop.Config
M.defaut_config = {
    debuggers = {
        lldb = {
            command = "/Library/Developer/CommandLineTools/usr/bin/lldb-dap",
            args = "",
        },
        pthon = {
            command = "python",
            args = "-m debugpy.adapter",
        },
    }
}

return M