local coreproviders = require("loop.coretasks.coreproviders")

---@type table<string,loop.TaskTypeProvider>
local _task_type_providers = {}

---@type table<string,loop.TaskTemplateProvider>
local _template_providers = {}

---@type string[]  -- keeps registration order
local _task_types = {}

---@type string[]  -- keeps registration order
local _template_categories = {}

local M = {}

function M.reset()
    _task_type_providers = {
        command   = coreproviders.get_command_task_provider(),
        composite = coreproviders.get_composite_task_provider(),
    }
    _task_types = { "command", "composite" }
    _template_providers = {
        composite = coreproviders.get_composite_templates_provider(),
        build     = coreproviders.get_build_templates_provider(),
        run       = coreproviders.get_run_templates_provider(),
    }
    _template_categories = { "composite", "build", "run" }
end

---@return string[]
function M.task_types()
    return _task_types
end

---@return string[]
function M.template_categories()
    return _template_categories
end

---@param task_type string
---@param provider loop.TaskTypeProvider
function M.register_task_provider(task_type, provider)
    assert(type(task_type) == 'string' and task_type:match("[_%a][_%w]*") ~= nil,
        "Invalid task type: " .. tostring(task_type))
    assert(not _task_type_providers[task_type], "task type is already registered: " .. task_type)
    assert(#task_type >= 2, "ext task type too short: " .. task_type)
    _task_type_providers[task_type] = provider
    table.insert(_task_types, task_type)
end

---@param category string
---@param provider loop.TaskTemplateProvider
function M.register_template_provider(category, provider)
    assert(type(category) == 'string' and category:match("[_%a][_%w]*") ~= nil,
        "Invalid task category: " .. tostring(category))
    assert(not _template_providers[category], "task category is already registered: " .. category)
    assert(#category >= 2, "ext task category too short: " .. category)
    _template_providers[category] = provider
    table.insert(_template_categories, category)
end

---@param name string
---@return loop.TaskTypeProvider|nil
function M.get_task_type_provider(name)
    return _task_type_providers[name]
end

---@param category string
---@return loop.TaskTemplateProvider|nil
function M.get_task_template_provider(category)
    return _template_providers[category]
end

return M
