local M = {}

local jsontools = require('loop.tools.json')
local filetools = require('loop.tools.file')
local uitools = require('loop.tools.uitools')
local strtools = require('loop.tools.strtools')
local jsonschema = require('loop.tools.jsonschema')
local logs = require("loop.logs")

---@param config_dir string
---@return table<string, string>|nil
---@return string[]|nil
function M.load_variables(config_dir)
    local filepath = vim.fs.joinpath(config_dir, "variables.json")

    -- Missing file is not an error, return empty table
    if not filetools.file_exists(filepath) then
        return {}, nil
    end

    local loaded, contents_or_err = uitools.smart_read_file(filepath)
    if not loaded then
        return nil, { contents_or_err }
    end

    local decoded, data_or_err = jsontools.from_string(contents_or_err)
    if not decoded or type(data_or_err) ~= 'table' then
        return nil, { data_or_err or "Parsing error" }
    end

    local data = data_or_err
    do
        local schema = require("loop.task.variablesschema").base_schema
        local errors = jsonschema.validate(schema, data)
        if errors and #errors > 0 then
            return nil, errors
        end
        if not data or not data.variables then
            return nil, { "Parsing error: missing 'variables' field" }
        end
    end

    return data.variables, nil
end

---@param config_dir string
---@param var_name string
---@param var_value string
---@param variables_schema table
---@return boolean
---@return string[]|nil
local function _add_variable(config_dir, var_name, var_value, variables_schema)
    local filepath = vim.fs.joinpath(config_dir, "variables.json")
    local winid, bufnr = uitools.smart_open_file(filepath)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false, { "failed to open variables file" }
    end

    -- Get all lines
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    local new_lines = nil
    if #content == 0 or content:match("^%s*$") then
        -- Create new file with schema and variable
        local schema_filepath = vim.fs.joinpath(config_dir, 'variablesschema.json')
        jsontools.save_to_file(schema_filepath, variables_schema)
        local file_data = {}
        file_data["$schema"] = './variablesschema.json'
        file_data["variables"] = {}
        file_data["variables"][var_name] = var_value
        local new_content = jsontools.to_string(file_data)
        new_lines = vim.split(new_content, "\n", { plain = true })
    else
        -- Parse existing content
        local decoded, data_or_err = jsontools.from_string(content)
        if not decoded or type(data_or_err) ~= 'table' then
            return false, { data_or_err or "Failed to parse existing variables.json" }
        end

        local data = data_or_err
        if not data.variables then
            data.variables = vim.empty_dict()
        end
        if not data["$schema"] then
            local schema_filepath = vim.fs.joinpath(config_dir, 'variablesschema.json')
            jsontools.save_to_file(schema_filepath, variables_schema)
            data["$schema"] = './variablesschema.json'
        end

        -- Add the new variable
        data.variables[var_name] = var_value

        -- Convert back to JSON and split into lines
        local new_content = jsontools.to_string(data)
        new_lines = vim.split(new_content, "\n", { plain = true })
    end

    if new_lines then
        -- Replace all lines in the buffer
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
        if vim.api.nvim_get_current_buf() == bufnr then
            uitools.move_to_last_occurence(winid, '"' .. var_name .. '": "')
        end
    end
    return true
end

---@param config_dir string
function M.configure_variables(config_dir)
    local filepath = vim.fs.joinpath(config_dir, "variables.json")
    local schema
    if not filetools.file_exists(filepath) then
        -- Create the file with schema reference and empty variables object
        local schema_filepath = vim.fs.joinpath(config_dir, 'variablesschema.json')
        schema = require("loop.task.variablesschema").base_schema
        jsontools.save_to_file(schema_filepath, schema)
        local file_data = {}
        file_data["$schema"] = './variablesschema.json'
        file_data["variables"] = {}
        jsontools.save_to_file(filepath, file_data)
    end
    --local editor = JsonEditor:new()
    --editor:open(0, filepath, schema)
    uitools.smart_open_file(filepath)
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
            local ok, errors = _add_variable(config_dir, var_name, var_value, schema)
            if not ok then
                vim.notify("Failed to add variable")
                logs.log(strtools.indent_errors(errors, "Failed to add variable"), vim.log.levels.ERROR)
            end
        end)
    end)
end

return M
