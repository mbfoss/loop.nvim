local M = {}

local extensions = require('loop.extensions')
local filetools = require('loop.tools.file')
local jsontools = require('loop.tools.json')

---@type table<string,{state:any,store:loop.TaskProviderStore}>
local _storage = {}

---@param config_dir string
---@param name string
---@return table?
function _load_state(config_dir, name)
    assert(name and name:match("[_%a][_%w]*") ~= nil, "invalid input")
    local filepath = vim.fs.joinpath(config_dir, name .. ".state.json")
    if not filetools.file_exists(filepath) then
        return nil
    end
    local decoded, data_or_err = jsontools.load_from_file(filepath)
    assert(decoded, "failed to load state file for " .. name)
    return data_or_err
end

---@param config_dir string
---@param name string
---@param state table
function _save_state(config_dir, name, state)
    assert(name and name:match("[_%a][_%w]*") ~= nil, "invalid input")
    assert(state)
    local filepath = vim.fs.joinpath(config_dir, name .. ".state.json")
    jsontools.save_to_file(filepath, state)
end

---@param wsinfo loop.ws.WorkspaceInfo
function M.on_workspace_load(wsinfo)
    ---@type loop.Workspace
    local workspace = {
        name = wsinfo.name,
        root = wsinfo.root_dir,
    }
    local names = extensions.ext_names()
    for _, name in ipairs(names) do
        _storage[name] = nil
        local ext = extensions.get_extension(name)
        if ext and ext.on_workspace_load then
            local state = _load_state(wsinfo.config_dir, name) or {}
            ---@type loop.TaskProviderStore
            local store = {
                set = function(fieldname, fieldvalue) state[fieldname] = fieldvalue end,
                get = function(fieldname) return state[fieldname] end,
                keys = function() return vim.tbl_keys(state) end
            }
            _storage[name] = { state = state, store = store }
            ext.on_workspace_load(workspace, store)
        end
    end
end

---@param wsinfo loop.ws.WorkspaceInfo
function M.on_workspace_unload(wsinfo)
    ---@type loop.Workspace
    local workspace = {
        name = wsinfo.name,
        root = wsinfo.root_dir,
    }
    local names = extensions.ext_names()
    for _, name in ipairs(names) do
        _storage[name] = nil
        local ext = extensions.get_extension(name)
        if ext and ext.on_workspace_unload then
            ext.on_workspace_unload(workspace)
        end
    end
end

---@param wsinfo loop.ws.WorkspaceInfo
function M.save(wsinfo)
    ---@type loop.Workspace
    local workspace = {
        name = wsinfo.name,
        root = wsinfo.root_dir,
    }
    local names = extensions.ext_names()
    for _, name in ipairs(names) do
        local ext = extensions.get_extension(name)
        if ext then
            local storage = _storage[name]
            if storage then
                if ext.on_store_will_save then
                    ext.on_store_will_save(workspace, storage.store)
                end
                _save_state(wsinfo.config_dir, name, storage.state)
            end
        end
    end
end

--[[

---@param config_dir string
---@param name string
---@param config_schema table
---@param callback fun(config:table|nil,err:string[]|nil)
function M.load_provider_config(config_dir, name, config_schema, callback)
    assert(name and name:match("[_%a][_%w]*") ~= nil, "invalid input")
    assert(type(config_schema) == "table")

    local filepath = vim.fs.joinpath(config_dir, "task." .. name .. ".json")
    if not filetools.file_exists(filepath) then
        return callback(nil, { "Config file does not exist:", filepath }) -- not an error
    end

    local loaded, contents_or_err = uitools.smart_read_file(filepath)
    if not loaded then
        return callback(nil, { contents_or_err })
    end

    local decoded, data_or_err = jsontools.from_string(contents_or_err)
    if not decoded then
        return callback(nil, { data_or_err })
    end

    local data = data_or_err
    if not data then
        return callback(nil, { "Parsing error" })
    end

    local errors = jsonschema.validate(config_schema, data)
    if errors and #errors > 0 then
        return callback(nil, errors)
    end

    local cmake_config = data.config

    -- Build a minimal context for provider config resolution
    local wsinfo = require("loop.wsinfo")
    local ws_dir = wsinfo.get_ws_dir()
    local vars, _ = M.load_variables(config_dir)

    ---@type loop.TaskContext
    local task_ctx = {
        task_name = name,
        root_dir = ws_dir or config_dir,
        variables = vars or {}
    }

    resolver.resolve_macros(cmake_config, task_ctx, function(success, result_table, err)
        if not success or not result_table then
            callback(nil, { err or "failed to resolve macros" })
        else
            callback(result_table, nil)
        end
    end)
end

---@param config_dir string
---@param name string
---@param schema table
---@param template table
function M.open_provider_config(config_dir, name, schema, template)
    assert(name and name:match("[_%a][_%w]*") ~= nil, "invalid input")
    assert(type(schema) == "table")
    assert(type(template) == "table")

    if next(template) == nil then
        -- task does not require configuration
        return
    end

    local config_filepath = vim.fs.joinpath(config_dir, 'task.' .. name .. '.json')
    local bufnr = vim.fn.bufnr(config_filepath)
    if bufnr ~= -1 then
        uitools.smart_open_buffer(bufnr)
        return
    end
    if not filetools.file_exists(config_filepath) then
        local schemafilename = 'extschema.' .. name .. '.json'
        local schemafilepath = vim.fs.joinpath(config_dir, schemafilename)
        jsontools.save_to_file(schemafilepath, schema)
        template["$schema"] = './' .. schemafilename
        jsontools.save_to_file(config_filepath, template)
    end
    uitools.smart_open_file(config_filepath)
end


    ---@type fun(config: table|nil, err: string[]|nil)
    local on_config_ready = function(config, err)
        if err then
            logs.log(err, vim.log.levels.ERROR)
            vim.notify("Missing or Invalid configuration for " .. tostring(task_type))
            return
        end

    end
    local config_schema = provider.get_config_schema and provider.get_config_schema() or nil
    if config_schema then
        taskstore.load_provider_config(config_dir, task_type, config_schema, on_config_ready)
    else
        on_config_ready(nil)
        provider.get_task_templates(nil)
    end

]]--

return M
