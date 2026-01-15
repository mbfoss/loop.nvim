local extensions = require("loop.extensions")

---@type table<string,loop.TaskProvider>
local _providers = {}

---@type string[]  -- keeps registration order
local _ordered = {}

local M = {}

function M.reset()
    _providers = {
        composite = require("loop.coretasks.composite.provider"),
        build     = require("loop.coretasks.build.provider"),
        run       = require("loop.coretasks.run.provider"),
    }
    _ordered = { "composite", "build", "run" }
end

---@return string[]
function M.names()
    return _ordered
end

---@param task_type string
---@param provider loop.TaskProvider
function M.register_task_provider(task_type, provider)
    assert(type(task_type) == 'string' and task_type:match("[_%a][_%w]*") ~= nil,
        "Invalid task type: " .. tostring(task_type))
    assert(not _providers[task_type], "task type is already registered: " .. task_type)
    assert(#task_type >= 2, "ext task type too short: " .. task_type)
    _providers[task_type] = provider
    table.insert(_ordered, task_type)
end

---@param name string
---@return loop.TaskProvider|nil
function M.get_provider(name)
    return _providers[name]
end

return M
