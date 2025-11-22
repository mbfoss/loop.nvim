local M = {}

local jsontools = require('loop.tools.json')
local strtools = require('loop.tools.strtools')
local taskstore = require("loop.task.taskstore")
local runner = require("loop.runner")
local window = require("loop.window")
local selector = require("loop.selector")

---@params task loop.Task
---@return string
local function _task_as_json(task)
    local function order_handler(_, _)
        return { "name", "type", "command", "cwd", "depends_on", "quickfix_matcher" }
    end
    return jsontools.to_string(task, order_handler)
end

---@param config_dir string
---@param templates loop.Task[]
---@param prompt string
local function _add_task(config_dir, templates, prompt)
    local choices = {}
    for _, template in pairs(templates) do
        ---@type loop.SelectorItem
        local item = {
            label = '[' .. template.type .. '] ' .. template.name,
            data = template,
        }
        table.insert(choices, item)
    end
    selector.select(prompt, choices, _task_as_json, function(template)
        if template then
            local ok, errors = taskstore.add_task(config_dir, template)
            if not ok then
                window.add_events(strtools.indent_errors(errors, "Failed to add task"), "error")
                return
            end
        end
    end)
end

---@param config_dir string
function M.add_task(config_dir)
    local templates = require('loop.task.tasktemplates')
    _add_task(config_dir, templates, "Choose a task template")
end

---@param config_dir string
function M.open_task_config(config_dir)
    taskstore.open_config(config_dir)
end

---@param config_dir string
---@param source string
function M.import_task(config_dir, source)
    local tasks, errors = taskstore.get_extension_tasks(config_dir, source)
    if not tasks then
        window.add_events(strtools.indent_errors(errors, "Failed to import tasks"), "error")
        return
    end
    _add_task(config_dir, tasks, "Choose a task to import")
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
            label = task.name,
            data = task,
        }
        table.insert(choices, item)
    end
    selector.select(args.prompt, choices, _task_as_json, function(task)
        if task then
            task_handler(task)
        end
    end)
end

---@param proj_dir string
---@param config_dir string
---@param mode "task"|"repeat"
---@param task_name string|nil
function M.run_task(proj_dir, config_dir, mode, task_name)
    if mode == "repeat" then
        task_name = taskstore.load_last_task_name(config_dir)
    end

    local tasks, task_errors = taskstore.load_tasks(config_dir)
    if not tasks or task_errors then
        window.add_events(strtools.indent_errors(task_errors, "Errors while loading tasks"), "error")
    end

    if not tasks then
        return
    end

    if task_name and task_name ~= "" then
        local task = vim.iter(tasks):find(function(t) return t.name == task_name end)
        if not task then
            window.add_events({ "No task found with name: " .. task_name }, "error")
            return
        end
        local chain, err = runner.get_deps_chain(tasks, task)
        if not chain then
            window.add_events({ "Dependency error for task '" .. task.name .. "'", "  " .. err }, "error")
            return
        end
        runner.start_task_chain(chain)
        return
    end

    if #tasks == 0 then
        window.add_events({ "No tasks found" }, "warn")
        return
    end

    ---@type loop.SelectTaskArgs
    local select_args = {
        tasks = tasks,
        prompt = "Select task"
    }
    _select_task(select_args, function(task)
        local chain, err = runner.get_deps_chain(tasks, task)
        if not chain then
            window.add_events({ "Dependency error for task '" .. task.name .. "'", "  " .. err }, "error")
            return
        end
        taskstore.save_last_task_name(task.name, config_dir)
        runner.start_task_chain(chain)
    end)
end

---@param config_dir string
---@param ext_name string
function M.create_extension_config(config_dir, ext_name)
    local ok, err = taskstore.create_extension_config(config_dir, ext_name)
    if not ok then
        window.add_events({ "Failed to create configuration", "  " .. err }, "error")
    end
end

---@param config_dir string
---@param ext_name string
function M.run_extension_task(config_dir, ext_name)
    local tasks, task_errors = taskstore.get_extension_tasks(config_dir, ext_name or "")
    if not tasks or task_errors then
        window.add_events(strtools.indent_errors(task_errors, "Errors while loading tasks"), "error")
    end
    if not tasks then
        return
    end
    ---@type loop.SelectTaskArgs
    local select_args = {
        tasks = tasks,
        prompt = "Select task"
    }
    _select_task(select_args, function(task)
        local chain, err = runner.get_deps_chain(tasks, task)
        if not chain then
            window.add_events({ "Dependency error for task '" .. task.name .. "'", "  " .. err }, "error")
            return
        end
        taskstore.save_last_chain(chain, config_dir)
        runner.start_task_chain(chain)
    end)
end

---@param command string|nil
function M.debug_task_command(command)
    runner.debug_task_command(command)
end

return M
