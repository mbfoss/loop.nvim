local M = {}

require('loop.Task')
local generator = require('loop.ext.cmake.generator')
local strtools = require('loop.tools.strtools')
local filetools = require('loop.tools.file')

local function realpath(p)
	return vim.fn.fnamemodify(vim.fn.resolve(p), ':p')
end

---@param cfg loop.ext.cmake.CMakeConfig
---@eturn boolean,string[]
local function _check_params(cfg)
	local errors = {}
	if vim.fn.executable(cfg.cmake_path) == 0 then
		return table.insert(errors, "cmake_path not executable: '" .. (cfg.cmake_path or "") .. "'")
	end
	if vim.fn.executable(cfg.ctest_path) == 0 then
		return table.insert(errors, "ctest_path not executable: '" .. (cfg.ctest_path or "") .. "'")
	end
	for idx, prof in ipairs(cfg.profiles or {}) do
		if not prof.name or prof.name == "" then
			return table.insert(errors, "profile " .. tostring(idx) .. " name is required")
		end

		if not prof.build_type or prof.build_type == "" then
			return table.insert(errors, "In profile: " .. prof.name .. ", build_type is required")
		end

		if not prof.source_dir or prof.source_dir == "" then
			return table.insert(errors, "In profile: " .. prof.name .. ", source_dir is required")
		end

		if not prof.build_dir or prof.build_dir == "" then
			return table.insert(errors, "In profile: " .. prof.name .. ", build_dir is required")
		end
	end
	return #errors == 0, errors
end

---@param config loop.ext.cmake.CMakeConfig
local function _init_cmake_api(config)
	for _, prof in ipairs(config.profiles or {}) do
		local build_dir = realpath(prof.build_dir) or prof.build_dir
		generator.ensure_cmake_api_query(build_dir)
	end
end

function M.get_config_schema()
	return require('loop.ext.cmake.configschema')
end

function M.get_config_template()
	return require('loop.ext.cmake.configtemplate')
end

---@param config loop.ext.cmake.CMakeConfig
---@param ingore_configured boolean
---@return loop.Task[]|nil,string[]|nil
function _get_configure_tasks(config, ingore_configured)
	local params_ok, params_errors = _check_params(config)
	if not params_ok then
		return nil, strtools.indent_errors(params_errors, "Invalid cmake config")
	end
	_init_cmake_api(config)
	local tasks = {}
	for _, prof in ipairs(config.profiles or {}) do
		local build_type = prof.build_type

		local profile_name = prof.name
		src_root = realpath(prof.source_dir) or prof.source_dir
		local build_dir = realpath(prof.build_dir) or prof.build_dir
		local cmakecache_path = vim.fs.joinpath(build_dir, "CMakeCache.txt")
		if not (ingore_configured and filetools.file_exists(cmakecache_path)) then
			do
				local cmd = { config.cmake_path }
				if prof.configure_args then
					vim.list_extend(cmd, prof.configure_args)
				end
				vim.list_extend(cmd, { "-B", build_dir, "-S", src_root, "-DCMAKE_BUILD_TYPE=" .. build_type })
				---@type loop.Task
				local task = {
					name = "[" .. profile_name .. "] Configure",
					type = "build",
					command = cmd,
					cwd = src_root
				}
				table.insert(tasks, task)
			end
		end
	end

	return tasks
end

-- ----------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------
---@param config loop.ext.cmake.CMakeConfig
---@return loop.Task[]|nil,string[]|nil
function M.get_tasks(config)
	local params_ok, params_errors = _check_params(config)
	if not params_ok then
		return nil, strtools.indent_errors(params_errors, "Invalid cmake config")
	end
	_init_cmake_api(config)
	local tasks, configure_tasks_errs = _get_configure_tasks(config, false)
	if not tasks then
		return nil, configure_tasks_errs
	end
	if #tasks > 1 then
		---@type loop.Task
		local task = {
			name = "Configure All",
			type = "build",
			command = { "true" },
			cwd = src_root,
			depends_on = {}
		}
		for _, t in ipairs(tasks) do
			table.insert(task.depends_on, t.name)
		end
		table.insert(tasks, 1, task)
	end

	local all_errors = {}
	for _, prof in ipairs(config.profiles or {}) do
		local _, prof_errs = generator.get_profile_tasks(tasks, config.cmake_path, config.ctest_path, prof)
		if prof_errs and #prof_errs > 0 then
			vim.list_extend(all_errors,
				strtools.indent_errors(prof_errs, "While loading profile '" .. (prof.name or '(unkown)') .. "'"))
		end
	end

	return tasks, #all_errors > 0 and all_errors or nil
end

return M
