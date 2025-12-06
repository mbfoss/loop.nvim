local M = {}

local jsontools = require('loop.tools.json')
local strtools = require('loop.tools.strtools')
local taskstore = require("loop.task.taskstore")
local runner = require("loop.runner")
local selector = require("loop.selector")
local notifications = require("loop.notifications")

---@params task loop.Task
---@return string
local function _task_as_json(task)
    local function order_handler(_, _)
        return { "name", "type", "command", "cwd",
            "env", "quickfix_matcher", "debug_adapter", "debug_request", "debug_args", "depends_on" }
    end
    return jsontools.to_string(task, order_handler)
end

---@param config_dir string
---@param templates loop.Task[]
---@param prompt string
local function _select_and_add_task(config_dir, templates, prompt)
    local choices = {}
    for _, template in pairs(templates) do
        ---@type loop.SelectorItem
        local item = {
            label = template.name,
            data = template,
        }
        table.insert(choices, item)
    end
    selector.select(prompt, choices, _task_as_json, function(template)
        if template then
            local ok, errors = taskstore.add_task(config_dir, template)
            if not ok then
                notifications.notify(strtools.indent_errors(errors, "Failed to add task"), vim.log.levels.ERROR)
                return
            end
        end
    end)
end

---@param config_dir string
function M.add_build_task(config_dir)
    local templates = require('loop.task.buildtemplates')
    _select_and_add_task(config_dir, templates, "Choose a task template")
end

---@param config_dir string
function M.add_run_task(config_dir)
    ---@type loop.Task
    local template = {
        name = "",
        type = "run",
        command = "",
        depends_on = {}
    }
    local ok, errors = taskstore.add_task(config_dir, template)
    if not ok then
        notifications.notify(strtools.indent_errors(errors, "Failed to add task"), vim.log.levels.ERROR)
        return
    end
end

---@param config_dir string
function M.add_vimcmd_task(config_dir)
    ---@type loop.Task
    local template = {
        name = "",
        type = "vimcmd",
        command = "",
        depends_on = {}
    }
    local ok, errors = taskstore.add_task(config_dir, template)
    if not ok then
        notifications.notify(strtools.indent_errors(errors, "Failed to add task"), vim.log.levels.ERROR)
        return
    end
end

---@param config_dir string
function M.add_debug_task(config_dir)
    local templates = require('loop.task.debugtemplates')
    _select_and_add_task(config_dir, templates, "Choose a task template")
end

---@param config_dir string
function M.open_task_config(config_dir)
    taskstore.open_config(config_dir)
end

---@param config_dir string
---@param source string
function M.import_task(config_dir, source)
    taskstore.get_extension_tasks(config_dir, source, function(tasks, errors)
        if not tasks then
            notifications.notify(strtools.indent_errors(errors, "Failed to import tasks"), vim.log.levels.ERROR)
            return
        end
        _select_and_add_task(config_dir, tasks, "Choose a task to import")
    end)
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
            label = '[' .. tostring(task.type) .. '] ' .. tostring(task.name),
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
        notifications.notify(strtools.indent_errors(task_errors, "Errors while loading tasks"), vim.log.levels.ERROR)
    end

    if not tasks then
        return
    end

    if task_name and task_name ~= "" then
        local task = vim.iter(tasks):find(function(t) return t.name == task_name end)
        if not task then
            notifications.notify({ "No task found with name: " .. task_name }, vim.log.levels.ERROR)
            return
        end
        local chain, err = runner.get_deps_chain(tasks, task)
        if not chain then
            notifications.notify({ "Dependency error for task '" .. task.name .. "'", "  " .. err }, vim.log.levels.ERROR)
            return
        end
        runner.start_task_chain(chain)
        return
    end

    if #tasks == 0 then
        notifications.notify({ "No tasks found" }, "warn")
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
            notifications.notify({ "Dependency error for task '" .. task.name .. "'", "  " .. err }, vim.log.levels.ERROR)
            return
        end
        taskstore.save_last_task_name(task.name, config_dir)
        runner.start_task_chain(chain)
    end)
end

function M.terminate_task()
    runner.terminate_task_chain()
end

---@param config_dir string
---@param ext_name string
function M.create_extension_config(config_dir, ext_name)
    local ok, err = taskstore.create_extension_config(config_dir, ext_name)
    if not ok then
        notifications.notify({ "Failed to create configuration", "  " .. err }, vim.log.levels.ERROR)
    end
end

---@param config_dir string
---@param ext_name string
function M.run_extension_task(config_dir, ext_name)
    taskstore.get_extension_tasks(config_dir, ext_name or "", function(tasks, errors)
        if not tasks or errors then
            notifications.notify(strtools.indent_errors(errors, "Errors while loading tasks"), vim.log.levels.ERROR)
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
                notifications.notify({ "Dependency error for task '" .. task.name .. "'", "  " .. err }, vim.log.levels.ERROR)
                return
            end
            runner.start_task_chain(chain)
        end)
    end)
end

---@param command loop.job.DebugJob.Command|nil
function M.debug_task_command(command)
    runner.debug_task_command(command)
end

return M
