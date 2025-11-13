local M = {}

local jsontools = require('loop.tools.json')
local strtools = require('loop.tools.strtools')
local taskstore = require("loop.task.taskstore")
local runner = require("loop.task.runner")
local window = require("loop.window")
local selector = require("loop.selector")
local quickfix = require('loop.tools.quickfix')

---@params task loop.Task
---@return string
local function _task_as_json(task)
    local function order_handler(_, _)
        return { "name", "type", "command", "cwd", "depends_on", "problem_matcher" }
    end
    return jsontools.to_string(task, order_handler)
end

---@param config_dir string
function M.add_task(config_dir)
    local templates = require('loop.task.tasktemplates')
    local choices = {}
    for _, template in pairs(templates) do
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
            local ok, errors = taskstore.add_task(config_dir, template)
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
local function _select_task(args, task_handler)
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
    local ok, err = taskstore.create_extension_config(config_dir, ext_name)
    if not ok then
        window.add_events({ "Failed to create configuration", "  " .. err }, "error")
    end
end

---@param proj_dir string
---@param config_dir string
---@param mode "task"|"extension"|"repeat"
---@param ext_name string|nil
---@param task_name string|nil
function M.run_task(proj_dir, config_dir, mode, ext_name, task_name)
    if mode == "repeat" then
        local chain, _ = taskstore.load_last_chain(config_dir)
        if chain then
            runner.start_task_chain(chain, function(qf_updated)
                if qf_updated then
                    window.show_errors(true, proj_dir)
                end
            end)
            return
        end
    end

    local tasks, task_errors
    if mode == "extension" then
        tasks, task_errors = taskstore.get_extension_tasks(config_dir, ext_name or "")
    else
        tasks, task_errors = taskstore.load_tasks(config_dir)
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
        taskstore.save_last_chain(chain, config_dir)
        runner.start_task_chain(chain, function(qf_updated)
            if qf_updated then
                window.show_errors(true, proj_dir)
            end
        end)
    end)
end

return M
