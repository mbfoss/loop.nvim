local M = {}

local JsonEditor = require('loop.tools.JsonEditor')
local floatwin = require('loop.tools.floatwin')
local jsontools = require('loop.tools.json')
local filetools = require('loop.tools.file')
local uitools = require('loop.tools.uitools')
local strtools = require('loop.tools.strtools')
local jsonschema = require('loop.tools.jsonschema')

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
        local schema = require("loop.task.variablesschema")
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
function M.show_variables(config_dir)
    local vars, var_errors = M.load_variables(config_dir)
    if var_errors then
        vim.notify("error(s) loading variables.json")
    end
    local text = jsontools.to_string(vars)
    floatwin.show_floatwin(text, {
        title = "Variables"
    })
end

---@param config_dir string
function M.configure_variables(config_dir)
    local schema = require("loop.task.variablesschema")
    local filepath = vim.fs.joinpath(config_dir, "variables.json")

    local editor = JsonEditor:new({
        name = "Variables editor",
        filepath = filepath,
        schema = schema,
        on_data_open = function(data)
            if not data or not data.variables or not data["$schema"] then
                local schema_filepath = vim.fs.joinpath(config_dir, 'variablesschema.json')
                if not filetools.file_exists(schema_filepath) then
                    jsontools.save_to_file(schema_filepath, schema)
                end
                data = {}
                data["$schema"] = './variablesschema.json'
                data["variables"] = vim.empty_dict()
                return data
            end
        end,
    })

    editor:open(uitools.get_regular_window())
end

return M
