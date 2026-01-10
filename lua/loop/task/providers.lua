local extensions = require("loop.extensions")

---@type table<string,string>  -- name -> module
local _builtin = {
    composite = "loop.coretasks.composite.provider",
    build     = "loop.coretasks.build.provider",
    run       = "loop.coretasks.run.provider",
    vimcmd    = "loop.coretasks.vimcmd.provider",
}

---@type string[]  -- keeps registration order
local _order = { "composite", "build", "run", "vimcmd" }

local M = {}

---@return boolean
function M.is_valid_provider(name)
    return _builtin[name] ~= nil
end

---@return string[]
function M.names()
    local lst = vim.list_extend({}, _order)
    vim.list_extend(lst, extensions.task_types())
    return lst
end
---@param name string
---@return loop.TaskProvider|nil
function M.get_provider(name)
    local builtin = _builtin[name]
    if builtin then 
        return require(builtin)
    end
    return extensions.get_task_provider(name)
end

return M
