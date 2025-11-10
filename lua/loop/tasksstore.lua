---@class loop.task.CustomProblemMatcher
---@field regexp string # non-empty regex pattern for error parsing
---@field file number # 1-based index in match groups for file path
---@field line number # 1-based index for line number
---@field column number # 1-based index for column number
---@field type_group number # 1-based index for severity (error/warning/info)
---@field message number # 1-based index for diagnostic message

---@alias loop.task.KnownProblemMatcher
---| "$gcc"
---| "$tsc-watch"
---| "$eslint-stylish"
---| "$msCompile"
---| "$lessCompile"

---@alias loop.task.ProblemMatcher loop.task.KnownProblemMatcher | loop.task.CustomProblemMatcher

---@alias loop.TaskType "build"|"run"|"test"|"test:junit"|"debug"|"debug:launch"|"debug:attach"|"lua"
---@
---@class loop.Task
---@field name string # non-empty task name (supports ${VAR} templates)
---@field type loop.TaskType # task category
---@field command string[]|string # non-empty executable command (supports templates)
---@field cwd string? # optional working directory (supports templates)
---@field env table<string,string>? # optional environment variables
---@field problem_matcher loop.task.ProblemMatcher | loop.task.ProblemMatcher[]? # optional error parser(s)
---@field depends_on string[]? # optional list of dependent task names

local M = {}

local jsontools = require('loop.tools.json')
local filetools = require('loop.tools.file')
local buftools = require('loop.tools.buffer')
local strtools = require('loop.tools.strtools')
local validate = require('loop.schema.validate')

---@param content string
---@return loop.Task[]|nil
---@return string[]|nil
local function _load_tasks_from_str(content)
    local loaded, data_or_err = jsontools.from_string(content)
    if not loaded or type(data_or_err) ~= 'table' then
        return nil, { data_or_err }
    end

    local schema = require("loop.schema.tasksschema")
    local data = data_or_err
    local errors = validate.validate(schema, data)
    if errors and #errors > 0 then
        return nil, errors
    end
    if not data or not data.tasks then
        return nil, { "Parsing error" }
    end
    return data.tasks, nil
end

---@param filepath string
---@return loop.Task[]|nil
---@return string[]|nil
local function _load_tasks_file(filepath)
    if not filetools.file_exists(filepath) then
        return {}, nil -- not an error
    end
    local loaded, contents_or_err = filetools.read_content(filepath)
    if not loaded then
        return nil, { contents_or_err }
    end
    return _load_tasks_from_str(contents_or_err)
end
local function order_handler(path, attrs)
    return { "name", "type", "command", "cwd", "depends_on", "problem_matcher" }
end

---@param config_dir string
---@param new_task loop.Task
---@return boolean
---@return string[]|nil
function M.add_task(config_dir, new_task)
    local filepath = vim.fs.joinpath(config_dir, "tasks.json")
    local _, bufnr = buftools.smart_open_file(filepath)

    -- Get all lines
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    local new_lines = nil
    if #content == 0 then
        local tasks = { new_task }
        local schema_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "loop.nvim")
        local schema_filepath = vim.fs.joinpath(schema_dir, 'tasksschema.json')
        vim.fn.mkdir(schema_dir, 'p')
        filetools.write_content(schema_filepath, require("loop.schema.tasksschema"))
        local file_data = {}
        file_data["$schema"] = 'file://' .. schema_filepath
        file_data.tasks = tasks
        local new_content = jsontools.to_string(file_data, order_handler)
        new_lines = vim.split(new_content, "\n", { plain = true })
    else
        local task_as_json = jsontools.to_string(new_task, order_handler)
        local positions = {}
        for i = 1, #content do
            if content:sub(i, i) == "}" then
                table.insert(positions, i)
            end
        end
        -- Need at least two braces
        if #positions >= 2 then
            -- Find position of second-to-last brace
            local insert_pos = positions[#positions - 1]
            -- Insert the new text right before it
            local prev_lines = vim.split(content:sub(1, insert_pos) .. ',', "\n", { plain = true })
            local mid_lines = vim.split(task_as_json, "\n", { plain = true, trimempty = true })
            local next_lines = vim.split(content:sub(insert_pos + 1), "\n", { plain = true, trimempty = true })
            for idx, line in ipairs(mid_lines) do
                mid_lines[idx] = "    " .. line
            end
            new_lines = vim.list_extend(vim.list_extend(prev_lines, mid_lines), next_lines)
        end
    end
    if new_lines then
        -- Replace all lines in the buffer
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
        if vim.api.nvim_get_current_buf() == bufnr then
            buftools.move_to_last_occurence('"name": "')
        end
    end
    return true
end

---@param config_dir string
---@return loop.Task[]|nil
---@return string[]|nil
function M.load_tasks(config_dir)
    local filepath = vim.fs.joinpath(config_dir, "tasks.json")
    local tasks, errors = _load_tasks_file(filepath)
    if not tasks then
        return nil, strtools.indent_errors(errors, "error(s) in: " .. filepath)
    end

    local byname = {}
    for _, task in ipairs(tasks) do
        if byname[task.name] ~= nil then
            return nil, { "error in: " .. filepath, "  duplicate task name: " .. task.name }
        end
        byname[task.name] = task
    end

    return tasks, nil
end

---@param task loop.Task
---@param config_dir string
function M.save_last_task(task, config_dir)
    local filepath = vim.fs.joinpath(config_dir, "task.last.json")
    jsontools.save_to_file(filepath, task)
end

---@param config_dir string
---@return boolean, loop.Task
function M.load_last_task(config_dir)
    local filepath = vim.fs.joinpath(config_dir, "task.last.json")
    return jsontools.load_from_file(filepath)
end

---@param task loop.Task
---@param config_dir string
function M.save_last_cmake_task(task, config_dir)
    local filepath = vim.fs.joinpath(config_dir, "cmake.last.json")
    jsontools.save_to_file(filepath, task)
end

---@param config_dir string
---@return boolean, loop.Task
function M.load_last_cmake_task(config_dir)
    local filepath = vim.fs.joinpath(config_dir, "cmake.last.json")
    return jsontools.load_from_file(filepath)
end

return M
