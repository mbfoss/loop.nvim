local M = {}

require('loop.task.taskdef')
local jsontools = require('loop.tools.json')
local filetools = require('loop.tools.file')
local uitools = require('loop.tools.uitools')
local strtools = require('loop.tools.strtools')
local vartools = require('loop.tools.vars')
local jsonschema = require('loop.tools.jsonschema')
local extensions = require('loop.ext.extensions')

---@param content string
---@return loop.Task[]|nil
---@return string[]|nil
local function _load_tasks_from_str(content)
    local loaded, data_or_err = jsontools.from_string(content)
    if not loaded or type(data_or_err) ~= 'table' then
        return nil, { data_or_err }
    end

    local schema = require("loop.task.tasksschema")
    local data = data_or_err
    local errors = jsonschema.validate(schema, data)
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
    local loaded, contents_or_err = uitools.smart_read_file(filepath)
    if not loaded then
        return nil, { contents_or_err }
    end
    return _load_tasks_from_str(contents_or_err)
end
local function order_handler(path, attrs)
    if path == "/" then
        return { "$schema", "tasks" }
    end
    return { "name", "type", "command", "cwd", "depends_on",
        "quickfix_matcher", "debugger", "debugger_args" }
end

local function task_order_handler(path, attrs)
    return { "name", "type", "command", "cwd", "depends_on",
        "quickfix_matcher", "debugger", "debugger_args" }
end

---@param config_dir string
---@param new_task loop.Task
---@return boolean
---@return string[]|nil
function M.add_task(config_dir, new_task)
    vim.fn.mkdir(config_dir, "p")
    local filepath = vim.fs.joinpath(config_dir, "tasks.json")
    local _, bufnr = uitools.smart_open_file(filepath)

    -- Get all lines
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    local new_lines = nil
    if #content == 0 then
        local tasks = { new_task }
        local schema_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "loop.nvim")
        local schema_filepath = vim.fs.joinpath(schema_dir, 'tasksschema.json')
        vim.fn.mkdir(schema_dir, 'p')
        filetools.write_content(schema_filepath, require("loop.task.tasksschema"))
        local file_data = {}
        file_data["$schema"] = 'file://' .. schema_filepath
        file_data["tasks"] = tasks
        local new_content = jsontools.to_string(file_data, order_handler)
        new_lines = vim.split(new_content, "\n", { plain = true })
    else
        local task_as_json = jsontools.to_string(new_task, task_order_handler)
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
            uitools.move_to_last_occurence('"name": "')
        end
    end
    return true
end

---@param config_dir string
function M.open_config(config_dir)
    local filepath = vim.fs.joinpath(config_dir, "tasks.json")
    uitools.smart_open_file(filepath)
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

---@param name string
---@param config_dir string
function M.save_last_task_name(name, config_dir)
    local filepath = vim.fs.joinpath(config_dir, "last.json")
    local data = { task = name }
    jsontools.save_to_file(filepath, data)
end

---@param config_dir string
---@return string|nil
function M.load_last_task_name(config_dir)
    local filepath = vim.fs.joinpath(config_dir, "last.json")
    local ok, payload = jsontools.load_from_file(filepath)
    if not ok then
        return nil
    end
    return payload and payload.task or nil
end

---@param ext_name string
---@return table|nil,string|nil
local function _get_extension_mod(ext_name)
    if not ext_name or ext_name == "" then
        return nil, "Extension name required"
    end
    if type(ext_name) ~= "string" or not ext_name:match("^[%a%d_-]+$") then
        return nil, "Invalid extension name: " .. ext_name "'"
    end
    local exists = false
    for _, v in ipairs(extensions.ext_names()) do if v == ext_name then exists = true end end
    if not exists then
        return nil, "Invalid extension name '" .. ext_name
    end
    local mod_loaded, mod = pcall(require, 'loop.ext.' .. ext_name .. '.extension')
    if not mod_loaded then
        return nil, "Failed to load extension '" .. ext_name .. "' " .. mod
    end
    if type(mod.get_config_schema) ~= "function" or
        type(mod.get_config_template) ~= "function" or
        type(mod.get_tasks) ~= "function" then
        return nil, "Missing function in extension: " .. ext_name
    end
    return mod
end

---@param config_dir string
---@param ext_name string
---@return table|nil,string[]|nil
local function _load_extension_config(config_dir, ext_name)
    local mod, mod_err = _get_extension_mod(ext_name)
    if not mod then
        return nil, { mod_err }
    end

    local filepath = vim.fs.joinpath(config_dir, "ext." .. ext_name .. ".json")
    if not filetools.file_exists(filepath) then
        return nil, { "Config file does not exist:", filepath } -- not an error
    end

    local loaded, contents_or_err = uitools.smart_read_file(filepath)
    if not loaded then
        return nil, { contents_or_err }
    end

    local decoded, data_or_err = jsontools.from_string(contents_or_err)
    if not decoded then
        return nil, { data_or_err }
    end

    local data = data_or_err
    if not data then
        return nil, { "Parsing error" }
    end

    local schema_str = mod.get_config_schema()
    assert(type(schema_str) == "string")

    local errors = jsonschema.validate(schema_str, data)
    if errors and #errors > 0 then
        return nil, errors
    end

    local cmake_config = data.config

    local vars_ok, var_errors = vartools.expand_strings(cmake_config)
    if not vars_ok then
        return nil, strtools.indent_errors(var_errors, "Failed to resolve variables in cmake config")
    end

    return data.config, nil
end

---@param config_dir string
---@param ext_name string
---@return loop.Task[]|nil,string[]|nil
function M.get_extension_tasks(config_dir, ext_name)
    local mod, mod_err = _get_extension_mod(ext_name)
    if not mod then
        return nil, { mod_err }
    end
    local config, config_err = _load_extension_config(config_dir, ext_name)
    if not config then
        return nil, config_err
    end
    return mod.get_tasks(config)
end

---@param config_dir string
---@param ext_name string
---@return boolean,string|nil
function M.create_extension_config(config_dir, ext_name)
    local mod, mod_err = _get_extension_mod(ext_name)
    if not mod then
        return false, mod_err
    end

    local schema_str = mod.get_config_schema()
    assert(type(schema_str) == "string")

    local template_str = mod.get_config_template()
    assert(type(template_str) == "string")

    local config_filepath = vim.fs.joinpath(config_dir, 'ext.' .. ext_name .. '.json')

    if not filetools.file_exists(config_filepath) then
        if schema_str then
            local schema_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "loop.nvim")
            local schema_filepath = vim.fs.joinpath(schema_dir, 'extschema-' .. ext_name .. '.json')
            vim.fn.mkdir(schema_dir, 'p')
            filetools.write_content(schema_filepath, schema_str)
            local schema_url = 'file://' .. schema_filepath
            template_str = string.gsub(template_str, "__SCHEMA_FILE_URL__", schema_url)
        end
        vim.fn.mkdir(config_dir, "p")
        filetools.write_content(config_filepath, template_str)
    end

    uitools.smart_open_file(config_filepath)
    return true
end

return M
