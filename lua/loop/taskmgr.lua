local M = {}

local filetools = require('loop.tools.file')
local jsontools = require('loop.tools.json')
local buftools = require('loop.tools.buffer')
local tasksstore = require("loop.tasksstore")
local runner = require("loop.runner")
local cmake = require("loop.cmake")
local window = require("loop.window")
local selector = require("loop.selector")

---@param config_dir string
function M.create_cmake_config(config_dir)
    local function _order_handler(path, attrs)
        if path == '/' then
            return { "$schema", "name" }
        elseif path == '/config/' then
            return { "cmake_path" }
        elseif path == '/config/profiles/[]/' then
            return { "name", "build_type", "source_dir", "build_dir", "configure_args", "build_tool_args", "prob_matcher" }
        end
    end

    local config_filepath = vim.fs.joinpath(config_dir, 'cmake.json')
    if not filetools.file_exists(config_filepath) then
        local schema_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "loop.nvim")
        local schema_filepath = vim.fs.joinpath(schema_dir, 'cmake.schema.json')
        vim.fn.mkdir(schema_dir, 'p')
        filetools.write_content(schema_filepath, require("loop.schema.cmakeconf"))

        local file_data = {}
        file_data["$schema"] = 'file://' .. schema_filepath
        file_data.config = require('loop.templates.cmakeconf')

        filetools.write_content(config_filepath, jsontools.to_string(file_data, _order_handler))
    end

    buftools.smart_open_file(config_filepath)
    buftools.move_to_first_occurence('"cmake_path": "')
end

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
    local templates = require('loop.templates.tasks')
    local selector = require("loop.selector")
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
                window.show_events()
                return
            end
        end
    end)
end

---@class loop.SelectTaskArgs
---@field tasks loop.Task[]
---@field prompt string
---@field project_dir string

---@param args loop.SelectTaskArgs
---@param task_handler fun(task : loop.Task)
function _select_task(args, task_handler)
    if #args.tasks == 0 then
        return
    end
    ---@type loop.tools.ProjectVars
    local variables = {
        proj_dir = args.project_dir
    }
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

---@param project_dir string
---@param config_dir string
---@param name string|nil
---@param repeat_last boolean
local function _run_task(project_dir, config_dir, name, repeat_last)
    local tasks, errors = tasksstore.load_tasks(config_dir)
    if not tasks or errors then
        errors = errors or {}
        for i, _ in ipairs(errors) do
            errors[i] = '  ' .. errors[i]
        end
        table.insert(errors, 1, "Errors while loading tasks")
        window.add_events(errors, "error")
    end
    
    if not tasks then
        return
    end

    if name then
        local task = vim.iter(tasks):find(function(t) return t.name == name end)
        if not task then
            window.add_events({ "No task found with name: " .. name }, "error")
            return
        end
        runner.start_task_with_deps(tasks, task, project_dir)
        return
    end

    if repeat_last then
        local loaded, task = tasksstore.load_last_task(config_dir)
        if loaded then
            runner.start_task_with_deps(tasks, task, project_dir)
            return
        end
    end

    if #tasks == 0 then
        return
    end
    
    ---@type loop.SelectTaskArgs
    local select_args = {
        tasks = tasks,
        prompt = "Select task",
        project_dir = project_dir
    }
    _select_task(select_args, function(task)
        tasksstore.save_last_task(task, config_dir)
        runner.start_task_with_deps(tasks, task, project_dir)
    end)
end

---@param project_dir string
---@param config_dir string
---@param name string|nil
---@param repeat_last boolean
local function _run_cmake_task(project_dir, config_dir, name, repeat_last)
    
    local tasks, errors = cmake.get_cmake_tasks(project_dir, config_dir)
    if not tasks or errors then
        errors = errors or {}
        for i, _ in ipairs(errors) do
            errors[i] = '  ' .. errors[i]
        end
        table.insert(errors, 1, "Errors while generating CMake tasks")
        window.add_events(errors, "error")
    end
    
    if not tasks then
        return
    end

    if name then
        local task = vim.iter(tasks):find(function(t) return t.name == name end)
        if not task then
            window.add_events({ "No CMake task found with name: " .. name }, "error")
            return
        end
        runner.start_task_with_deps(tasks, task, project_dir)
        return
    end
    
    if repeat_last then
        local loaded, task = tasksstore.load_last_cmake_task(config_dir)
        if loaded then
            runner.start_task_with_deps(tasks, task, project_dir)
            return
        end
    end

    if #tasks == 0 then
        return
    end

    ---@type loop.SelectTaskArgs
    local select_args = {
        tasks = tasks,
        prompt = "Select CMake task",
        project_dir = project_dir
    }
    _select_task(select_args, function(task)
        tasksstore.save_last_cmake_task(task, config_dir)
        runner.start_task_with_deps(tasks, task, project_dir)
    end)
end

---@param project_dir string
---@param config_dir string
---@param name string|nil
---@param repeat_last boolean
function M.run_task(project_dir, config_dir, name, repeat_last)
    _run_task(project_dir, config_dir, name, repeat_last)
end

---@param project_dir string
---@param config_dir string
---@param name string|nil
---@param repeat_last boolean
function M.run_cmake_task(project_dir, config_dir, name, repeat_last)
    _run_cmake_task(project_dir, config_dir, name, repeat_last)
end

return M
