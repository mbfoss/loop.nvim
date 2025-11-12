local M = {}

local jsontools = require('loop.tools.json')
local strtools = require('loop.tools.strtools')
local tasksstore = require("loop.tasksstore")
local runner = require("loop.runner")
local window = require("loop.window")
local selector = require("loop.selector")

---@params task loop.Task
---@return string
function _task_as_json(task)
    local function order_handler(path, attrs)
        return { "name", "type", "command", "cwd", "depends_on", "problem_matcher" }
    end
    return jsontools.to_string(task, order_handler)
end

---@param config_dir string
function M.add_task(config_dir)
    local templates = require('loop.tasktemplates')
    local choices = {}
    for index, template in pairs(templates) do
        ---@type loop.SelectorItem
        local item = {
            label = '[' .. template.type .. '] ' .. template.name,
            content = template,
            formatter = _task_as_json
        }
        table.insert(choices, item)
    end
    selector.select("Choose a task template", choices, function(item)
        if item then
            local template = item.content
            if not template then
                vim.notify("Loop.nvim: Failed to load project task template\n")
                return
            end
            local ok, errors = tasksstore.add_task(config_dir, template)
            if not ok then
                errors = errors or {}
                table.insert(errors, 1, "Failed to add task:")
                window.add_events(errors, "error")
                return
            end
        end
    end)
end

---@class loop.SelectTaskArgs
---@field tasks loop.Task[]
---@field prompt string

---@param args loop.SelectTaskArgs
---@param task_handler fun(task : loop.Task)
function _select_task(args, task_handler)
    if #args.tasks == 0 then
        return
    end
    local choices = {}
    for _, task in ipairs(args.tasks) do
        ---@type loop.SelectorItem
        local item = {
            label = task.name,
            content = task,
            formatter = _task_as_json
        }
        table.insert(choices, item)
    end
    selector.select(args.prompt, choices, function(item)
        if item then
            local task = item.content
            assert(task)
            task_handler(task)
        end
    end)
end

---@param config_dir string
---@param ext_name string
function M.create_extension_config(config_dir, ext_name)
    local ok, err = tasksstore.create_extension_config(config_dir, ext_name)
    if not ok then
        window.add_events({ "Failed to create configuration", "  " .. err }, "error")
    end
end

---@param config_dir string
---@param mode "task"|"extension"|"repeat"
---@param ext_name string|nil
---@param task_name string|nil
function M.run_task(config_dir, mode, ext_name, task_name)
    if mode == "repeat" then
        local chain, _ = tasksstore.load_last_chain(config_dir)
        if chain then
            runner.start_task_chain(chain)
            return
        end
    end

    local function main_task()
        local tasks, task_errors
        if mode == "extension" then
            tasks, task_errors = tasksstore.get_extension_tasks(config_dir, ext_name or "")
        else
            tasks, task_errors = tasksstore.load_tasks(config_dir)
        end
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
            runner.start_task_with_deps(tasks, task)
            return
        end

        if #tasks == 0 then
            window.add_events({"No tasks found"}, "warn")
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
            tasksstore.save_last_chain(chain, config_dir)
            runner.start_task_chain(chain)
        end)
    end

    local init_tasks = nil
    if ext_name then
        init_tasks, errors = tasksstore.get_extension_init_tasks(config_dir, ext_name)
        if not init_tasks then
            window.add_events(strtools.indent_errors(errors, "Failed to load ext '" .. ext_name .. "' init tasks"),
                "error")
            return
        end
    end

    if init_tasks then
        runner.start_task_chain(init_tasks, function()
            main_task()
        end)
    else
        main_task()
    end
end

return M
