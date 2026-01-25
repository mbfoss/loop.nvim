
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
				jsoncodec.save_to_file(schemafilepath, _fullschema(schema))
				local configdata = {}
				configdata["$schema"] = './' .. schema_filename
				configdata["config"] = template
				jsoncodec.save_to_file(filepath, configdata)
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
			local decoded, data_or_err = jsoncodec.from_string(contents_or_err)
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
			local errors = jsonvalidator.validate(_fullschema(schema), data)
			if errors and #errors > 0 then
				return nil, jsonvalidator.errors_to_string(errors)
			end
			return data.config
		end
	}
end
