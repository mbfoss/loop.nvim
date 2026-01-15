local M = {}

local extensions = require('loop.extensions')
local taskproviders = require('loop.task.providers')
local filetools = require('loop.tools.file')
local uitools = require('loop.tools.uitools')
local jsontools = require('loop.tools.json')
local jsonschema = require('loop.tools.jsonschema')


---@type table<string,table>
local _extension_states = {}

---@type table<string,loop.ExtensionData>
local _extension_data = {}

---@type table<string,loop.UserCommandProvider>
local _cmd_providers = {}
local _reserved_cmd_providers = {
	workspace = true,
	ui = true,
	page = true,
	logs = true,
	help = true,
	task = true,
	var = true
}

---@type table<string,string>
local _task_providers = {}
local _reserved_task_types = {
	composite = true, build = true, run = true
}

---@param config_dir string
---@param ext_name string
---@return loop.ExtensionConfig
local function _make_config_handler(config_dir, ext_name)
	local config_filename = ("%s.config.json"):format(ext_name)
	local schema_filename = ("%s.configschema.json"):format(ext_name)
	local filepath = vim.fs.joinpath(config_dir, config_filename)
	local _fullschema = function(schema)
		return {
			["$schema"] = "http://json-schema.org/draft-07/schema#",
			type = "object",
			properties = {
				["$schema"] = {
					type = "string"
				},
				config = schema
			}
		}
	end
	---@type loop.ExtensionConfig
	return {
		have_config_file = function()
			return filetools.file_exists(vim.fs.joinpath(config_dir, config_filename))
		end,
		init_config_file = function(template, schema)
			assert(type(schema) == "table")
			assert(type(template) == "table")
			local bufnr = vim.fn.bufnr(filepath)
			if bufnr ~= -1 then
				uitools.smart_open_buffer(bufnr)
				return
			end
			if not filetools.file_exists(filepath) then
				local schemafilepath = vim.fs.joinpath(config_dir, schema_filename)
				jsontools.save_to_file(schemafilepath, _fullschema(schema))
				local configdata = {}
				configdata["$schema"] = './' .. schema_filename
				configdata["config"] = template
				jsontools.save_to_file(filepath, configdata)
			end
			uitools.smart_open_file(filepath)
		end,
		load_config_file = function(schema)
			assert(type(schema) == "table")
			if not filetools.file_exists(filepath) then
				return nil, "Config file does not exist: " .. filepath -- not an error
			end
			local loaded, contents_or_err = uitools.smart_read_file(filepath)
			if not loaded then
				return nil, contents_or_err
			end
			local decoded, data_or_err = jsontools.from_string(contents_or_err)
			if not decoded then
				return nil, data_or_err
			end
			local data = data_or_err
			if not data then
				return nil, "Parsing error"
			end
			if not data.config then
				return nil, "'config' property missing in root object"
			end
			local errors = jsonschema.validate(_fullschema(schema), data)
			if errors and #errors > 0 then
				return nil, table.concat(errors, '\n')
			end
			return data.config
		end
	}
end

---@param ext_name  string
---@return loop.ExtensionState
local function _make_state_handler(ext_name)
	local data = _extension_states[ext_name]
	assert(data)
	---@type loop.ExtensionState
	local state = {
		set = function(fieldname, fieldvalue) data[fieldname] = fieldvalue end,
		get = function(fieldname) return data[fieldname] end,
		keys = function() return vim.tbl_keys(data) end
	}
	return state
end

---@param config_dir string
---@param ext_name string
local function _load_state(config_dir, ext_name)
	assert(ext_name and ext_name:match("[_%a][_%w]*") ~= nil, "invalid input")
	local data = {}
	local filepath = vim.fs.joinpath(config_dir, ext_name .. ".state.json")
	if filetools.file_exists(filepath) then
		local decoded, data_or_err = jsontools.load_from_file(filepath)
		assert(decoded, "failed to load state file for " .. ext_name)
		_extension_states[ext_name] = data_or_err or {}
	else
		_extension_states[ext_name] = {}
	end
end

---@param task_type string
---@param provider loop.TaskProvider
local function _register_task_provider(task_type, provider)
	taskproviders.register_task_provider(task_type, provider)
end

---@param lead_cmd string
---@param provider loop.UserCommandProvider
local function _register_cmd_provider(lead_cmd, provider)
	assert(type(lead_cmd) == 'string' and lead_cmd:match("[_%a][_%w]*") ~= nil,
		"Invalid cmd lead: " .. tostring(lead_cmd))
	assert(not _reserved_cmd_providers[lead_cmd], "cmd lead is reserved: " .. lead_cmd)
	assert(#lead_cmd >= 2, "cmd lead too short: " .. lead_cmd)
	_cmd_providers[lead_cmd] = provider
end

---@return string[]
function M.lead_commands()
	return vim.fn.sort(vim.tbl_keys(_cmd_providers))
end

---@param lead_cmd string
---@return loop.UserCommandProvider
function M.get_cmd_provider(lead_cmd)
	return _cmd_providers[lead_cmd]
end

---@param wsinfo loop.ws.WorkspaceInfo
function M.on_workspace_load(wsinfo)
	local names = extensions.ext_names()
	for _, name in ipairs(names) do
		_load_state(wsinfo.config_dir, name)
		---@type loop.ExtensionData
		local ext_data = {
			ws_name = wsinfo.name,
			ws_dir = wsinfo.ws_dir,
			config = _make_config_handler(wsinfo.config_dir, name),
			state = _make_state_handler(name),
			register_task_provider = _register_task_provider,
			register_cmd_provider = _register_cmd_provider,
		}
		_extension_data[name] = ext_data
		local ext = extensions.get_extension(name)
		if ext and ext.on_workspace_load then
			ext.on_workspace_load(ext_data)
		end
	end
end

---@param wsinfo loop.ws.WorkspaceInfo
function M.on_workspace_unload(wsinfo)
	local names = extensions.ext_names()
	for _, name in ipairs(names) do
		local ext_data = _extension_data[name]
		assert(ext_data)
		local ext = extensions.get_extension(name)
		if ext and ext.on_workspace_unload then
			ext.on_workspace_unload(ext_data)
		end
	end
	_extension_data = {}
	_extension_states = {}
end

---@param wsinfo loop.ws.WorkspaceInfo
function M.save(wsinfo)
	local names = extensions.ext_names()
	for _, name in ipairs(names) do
		local ext_data = _extension_data[name]
		local state = _extension_states[name]
		assert(ext_data)
		assert(state)
		local ext = extensions.get_extension(name)
		if ext and ext.on_state_will_save then
			ext.on_state_will_save(ext_data)
		end
		local filepath = vim.fs.joinpath(wsinfo.config_dir, name .. ".state.json")
		jsontools.save_to_file(filepath, state)
	end
end

return M
