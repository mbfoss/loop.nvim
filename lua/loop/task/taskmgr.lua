local M = {}

local jsontools = require('loop.tools.json')
local strtools = require('loop.tools.strtools')
local taskstore = require("loop.task.taskstore")
local providers = require("loop.task.providers")
local selector = require("loop.tools.selector")
local logs = require("loop.logs")

---@params task loop.Task
---@return string,string
local function _task_preview(task)
    local provider = M.get_task_type_provider(task.type)
    if provider and provider.get_task_preview then
        return provider.get_task_preview(task)
    end
    return "", ""
end

---@return table
local function _build_taskfile_schema()
    local schema_data = require("loop.task.tasksschema")
    local base_schema = schema_data.base_schema
    local base_items = schema_data.base_items

    local schema = vim.deepcopy(base_schema)
    schema.properties.tasks.items = {}
    schema.properties.tasks.items.oneOf = {}
    local oneOf = schema.properties.tasks.items.oneOf

    local task_types = providers.task_types()
    for _, type in ipairs(task_types) do
        local provider = M.get_task_type_provider(type)
        if provider then
            assert(provider.get_task_schema, "get_task_schema() not implemented for: " .. type)
            local provider_schema = provider.get_task_schema()
            if provider_schema then
                local oneOfItem = {
                    type = "object",
                    properties = vim.tbl_extend("error", base_items.properties, provider_schema.properties or {}),
                    required = vim.deepcopy(base_items.required),
                }
                oneOfItem.properties.type = { const = type }
                oneOfItem.additionalProperties = provider_schema.additionalProperties or false
                for _, req in ipairs(provider_schema.required or {}) do
                    table.insert(oneOfItem.required, req)
                end
                table.insert(oneOf, oneOfItem)
            end
        end
    end
    return schema
end

---@param task_type  string
---@return table|nil
local function _get_single_task_schema(task_type)
    local provider = M.get_task_type_provider(task_type)
    if not provider then
        return nil
    end
    assert(provider.get_task_schema, "get_task_schema() not implemented for: " .. task_type)

    local base_items = require("loop.task.tasksschema").base_items

    local schema = vim.deepcopy(base_items)

    local provider_schema = provider.get_task_schema()
    if provider_schema then
        schema.properties = vim.tbl_extend("error", schema.properties, provider_schema.properties or {})
        schema.additionalProperties = provider_schema.additionalProperties or false
        for _, req in ipairs(provider_schema.required or {}) do
            table.insert(schema.required, req)
        end
    end
    return schema
end

---@param config_dir string
---@return loop.Task[]?,string[]?
local function _load_tasks(config_dir)
    local tasktype_to_schema = {}
    for _, tasktype in ipairs(providers.task_types()) do
        tasktype_to_schema[tasktype] = _get_single_task_schema(tasktype)
    end
    return taskstore.load_tasks(config_dir, tasktype_to_schema)
end

---@param config_dir string
---@param templates loop.taskTemplate[]
---@param prompt string
local function _select_and_add_task(config_dir, templates, prompt)
    local choices = {}
    for _, template in pairs(templates) do
        ---@type loop.SelectorItem
        local item = {
            label = template.name,
            data = template.task,
        }
        table.insert(choices, item)
    end
    selector.select(prompt, choices, _task_preview, function(task)
        if task then
            local ok, errors = taskstore.add_task(config_dir, task, _build_taskfile_schema())
            if not ok then
                vim.notify("Failed to add task")
                logs.log(strtools.indent_errors(errors, "Failed to add task"), vim.log.levels.ERROR)
                return
            end
        end
    end)
end

function M.reset_provider_list()
    providers.reset()
end

---@param name string
---@return loop.TaskTypeProvider|nil
function M.get_task_type_provider(name)
    return providers.get_task_type_provider(name)
end

function M.on_tasks_cleanup()
    local names = providers.task_types()
    for _, name in ipairs(names) do
        local provider = M.get_task_type_provider(name)
        if provider and provider.on_tasks_cleanup then
            provider.on_tasks_cleanup()
        end
    end
end

---@param config_dir string
function M.add_task(config_dir)
    local choices = {}
    for _, type in ipairs(providers.template_categories()) do
        ---@type loop.SelectorItem
        local item = {
            label = type,
            data = type,
        }
        table.insert(choices, item)
    end
    selector.select("Task category", choices, nil, function(category)
        if category then
            local provider = providers.get_task_template_provider(category)
            if not provider then
                vim.notify("Invalid task category: " .. tostring(category))
                return
            end
            assert(type(provider) == "table")

            local templates = provider.get_task_templates()
            _select_and_add_task(config_dir, templates, "Select template")
        end
    end)
end

---@param name string
---@param config_dir string
function M.save_last_task_name(name, config_dir)
    taskstore.save_last_task_name(name, config_dir)
end

---@param config_dir string
function M.configure_tasks(config_dir)
    taskstore.open_tasks_config(config_dir)
    local _, task_errors = _load_tasks(config_dir)
    if task_errors then
        vim.notify("Failed to load task configuration file", vim.log.levels.ERROR)
        logs.log(task_errors, vim.log.levels.ERROR)
        return
    end
end

---@param config_dir string
function M.add_variable(config_dir)
    -- Prompt for variable name
    vim.ui.input({ prompt = "Variable name: " }, function(var_name)
        if not var_name or var_name == "" then
            return
        end

        -- Validate variable name pattern: ^[A-Za-z_][A-Za-z0-9_]*$
        if not var_name:match("^[A-Za-z_][A-Za-z0-9_]*$") then
            vim.notify("Invalid variable name. Must match pattern: ^[A-Za-z_][A-Za-z0-9_]*$", vim.log.levels.ERROR)
            return
        end

        -- Prompt for variable value
        vim.ui.input({ prompt = "Variable value: " }, function(var_value)
            if not var_value then
                return
            end

            local schema = require("loop.task.variablesschema").base_schema
            local ok, errors = taskstore.add_variable(config_dir, var_name, var_value, schema)
            if not ok then
                vim.notify("Failed to add variable")
                logs.log(strtools.indent_errors(errors, "Failed to add variable"), vim.log.levels.ERROR)
            end
        end)
    end)
end

---@param config_dir string
function M.configure_variables(config_dir)
    taskstore.open_variables_config(config_dir)
end

---@class loop.SelectTaskArgs
---@field tasks loop.Task[]
---@field prompt string

---@param args loop.SelectTaskArgs
---@param task_handler fun(task : loop.Task)
local function _select_task(args, task_handler)
    if #args.tasks == 0 then
        return
    end
    local choices = {}
    for _, task in ipairs(args.tasks) do
        ---@type loop.SelectorItem
        local item = {
            label = tostring(task.name),
            data = task,
        }
        table.insert(choices, item)
    end
    selector.select(args.prompt, choices, _task_preview, function(task)
        if task then
            task_handler(task)
        end
    end)
end

---@param config_dir string
---@param mode "task"|"repeat"
---@param task_name string|nil
---@param handler fun(main_task:string|nil,all_tasks:loop.Task[]|nil)
function M.get_or_select_task(config_dir, mode, task_name, handler)
    if mode == "repeat" then
        task_name = taskstore.load_last_task_name(config_dir)
    end

    local tasks, task_errors = _load_tasks(config_dir)
    if (not tasks) or task_errors then
        vim.notify("Failed to load tasks")
        logs.log(task_errors or "Error while loading tasks", vim.log.levels.ERROR)
        handler(nil)
        return
    end

    if task_name and task_name ~= "" then
        local task = vim.iter(tasks):find(function(t) return t.name == task_name end)
        if not task then
            vim.notify("No task found with name: " .. task_name, vim.log.levels.ERROR)
            handler(nil)
            return
        end
        handler(task_name, tasks)
        return
    end

    ---@type loop.SelectTaskArgs
    local select_args = {
        tasks = tasks or {},
        prompt = "Select task"
    }
    _select_task(select_args, function(task)
        if not task then
            handler(nil)
            return
        end
        handler(task.name, tasks)
    end)
end

---@param task loop.Task
---@param page_manager loop.PageManager
---@param exit_handler loop.TaskExitHandler
---@return loop.TaskControl|nil, string|nil
function M.run_one_task(task, page_manager, exit_handler)
    assert(task.type)
    local provider = M.get_task_type_provider(task.type)
    if not provider then
        vim.notify("Invalid task type: " .. tostring(task.type))
        return nil, "Invalid task type"
    end
    return provider.start_one_task(task, page_manager, exit_handler)
end

return M
