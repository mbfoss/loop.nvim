---@class loop.tasks.CMakeRunApp
---@field cwd string
---@field args string[]|nil
---@field env string[]|nil

---@class loop.tasks.CMakeProfile
---@field name string
---@field build_type '"Debug"'|'"Release"'|'"RelWithDebInfo"'|'"MinSizeRel"' # required
---@field source_dir string # required, non-empty
---@field build_dir string # required, non-empty
---@field configure_args string[]|nil
---@field build_tool_args string[]|nil
---@field prob_matcher loop.task.ProblemMatcher # required
---@field run table<string, loop.tasks.CMakeRunApp> -- target → { cwd, args }


---@class loop.tasks.CMakeConfig
---@field cmake_path string # required, non-empty
---@field profiles loop.tasks.CMakeProfile[] # required, at least one item

local M         = {}

local filetools = require('loop.tools.file')
local strtools  = require('loop.tools.strtools')
local vartools  = require('loop.tools.vars')
local jsontools = require('loop.tools.json')
local validate  = require('loop.schema.validate')

local json      = vim.json

-- ----------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------
local function realpath(p)
    return vim.fn.fnamemodify(vim.fn.resolve(p), ':p')
end

local function readfile(p)
    local ok, content = filetools.read_content(p)
    return ok and content or nil
end
-- ----------------------------------------------------------------------
-- Safe JSON decoder – patches CMake's "v:null" key
-- ----------------------------------------------------------------------
local function safe_json_decode(str)
    if not str or str == "" then
        return nil, "empty input"
    end
    local ok, res = pcall(json.decode, str)
    if not ok then
        return nil, "JSON decode failed: " .. tostring(res)
    end
    if res == nil then
        return nil, "decoded result is nil"
    end
    local t = type(res)
    if t ~= "table" and t ~= "string" and t ~= "number" and t ~= "boolean" then
        return nil, string.format("unexpected decoded type: %s", t)
    end
    return res, nil
end


-- ----------------------------------------------------------------------
-- Ensure CMake API query exists (MUST be called BEFORE configure)
-- ----------------------------------------------------------------------
local function ensure_cmake_api_query(build_dir)
    local query_dir = vim.fs.joinpath(build_dir, ".cmake", "api", "v1", "query")

    local function make_marker(subpath)
        local path = vim.fs.joinpath(query_dir, subpath)
        local ok, err = filetools.make_dir(path)
        if not ok then error("Failed to create dir: " .. (err or "")) end
        local marker = vim.fs.joinpath(path, "request")
        local ok2, err2 = filetools.write_content(marker, "")
        if not ok2 then error("Failed to write marker: " .. (err2 or "")) end
    end

    -- Request codemodel (for targets)
    make_marker("codemodel-v2")

    -- Also request test info
    make_marker("test-v1")
end

-- ----------------------------------------------------------------------
-- 1. CMake File-Based API → list of *real* targets
-- ----------------------------------------------------------------------
---@param build_dir string
---@return table<string,string>|nil, string[]|nil
local function query_cmake_api_targets(build_dir)
    local reply_dir = vim.fs.joinpath(build_dir, ".cmake", "api", "v1", "reply")
    if not filetools.dir_exists(reply_dir) then
        return nil, { "API reply directory missing – run CMake configure first" }
    end

    ------------------------------------------------------------------
    -- 1. Find index-*.json
    ------------------------------------------------------------------
    local index_file
    for entry in vim.fs.dir(reply_dir) do
        if entry:match("^index%-.+%.json$") then
            index_file = vim.fs.joinpath(reply_dir, entry)
            break
        end
    end
    if not index_file then
        return nil, { "No index-*.json in reply directory" }
    end

    local idx_content = readfile(index_file)
    if not idx_content then
        return nil, { "Failed to read index file: " .. index_file }
    end

    local idx, err = safe_json_decode(idx_content)
    if not idx then
        return nil, { "Failed to parse index JSON: " .. (err or "") }
    end

    ------------------------------------------------------------------
    -- 2. Locate codemodel entry (reply or query)
    ------------------------------------------------------------------
    local codemodel_entry
    if idx.reply and idx.reply["codemodel-v2"] then
        codemodel_entry = idx.reply["codemodel-v2"]
    elseif idx.query then
        codemodel_entry = idx.query["codemodel-v2"] or idx.query["codemodel-v1"]
    end

    if not codemodel_entry or not codemodel_entry.jsonFile then
        return nil, { "No codemodel entry found in index file (checked reply and query)" }
    end

    ------------------------------------------------------------------
    -- 3. Read codemodel file – it only contains *references* to targets
    ------------------------------------------------------------------
    local codemodel_file = vim.fs.joinpath(reply_dir, codemodel_entry.jsonFile)
    local codemodel_content = readfile(codemodel_file)
    if not codemodel_content then
        return nil, { "Failed to read codemodel file: " .. codemodel_file }
    end

    local codemodel, err2 = safe_json_decode(codemodel_content)
    if not codemodel then
        return nil, { "Failed to parse codemodel JSON: " .. (err2 or "") }
    end

    ------------------------------------------------------------------
    -- 4. Walk every target reference and load the real target file
    ------------------------------------------------------------------
    local targets = {}
    local target_errors = {}

    for _, cfg in ipairs(codemodel.configurations or {}) do
        for _, tgt_ref in ipairs(cfg.targets or {}) do
            local tgt_name = tgt_ref.name
            local tgt_file = tgt_ref.jsonFile
            if not tgt_name or not tgt_file then goto continue end

            local full_tgt_path = vim.fs.joinpath(reply_dir, tgt_file)
            local tgt_content = readfile(full_tgt_path)
            if not tgt_content then
                table.insert(target_errors, " could not read target file: " .. full_tgt_path)
                goto continue
            end

            local tgt_obj, err3 = safe_json_decode(tgt_content)
            if not tgt_obj then
                table.insert(target_errors, "failed to parse target JSON: " .. full_tgt_path .. " - " .. (err3 or ""))
                goto continue
            end

            targets[tgt_name] = tgt_obj.type

            ::continue::
        end
    end

    if not next(targets) then
        return nil, { "No executable targets found in CMake API" }
    end

    return targets, target_errors
end

---@param build_dir string
---@return table[]|nil,string|nil
local function query_cmake_api_tests(build_dir)
    -- Try CTest JSON interface first (CMake ≥3.29)
    local ctest_exe = "ctest"
    local handle = io.popen(ctest_exe .. " --show-only=json-v1 --test-dir " .. vim.fn.shellescape(build_dir))
    if not handle then
        return nil, "Failed to run ctest"
    end
    local content = handle:read("*a")
    handle:close()

    if not content or content == "" then
        return nil, "CTest JSON output empty"
    end

    local data, err = safe_json_decode(content)
    if not data then
        return nil, "Failed to parse CTest JSON: " .. err
    end

    if not data.tests or not next(data.tests) then
        return nil, "No tests found in CTest JSON"
    end

    return data.tests, nil
end


-- ----------------------------------------------------------------------
-- Core task generator
-- ----------------------------------------------------------------------
---@param tasks loop.Task[]
---@param cmake_path string
---@param cfg loop.tasks.CMakeProfile
---@return boolean, string[]|nil
local function get_profile_tasks(tasks, cmake_path, cfg)
    local profile_name = cfg.name
    src_root = realpath(cfg.source_dir) or cfg.source_dir
    local build_dir = realpath(cfg.build_dir) or cfg.build_dir
    local prob_matcher = cfg.prob_matcher or "$gcc"
    local cmake_file = vim.fs.joinpath(src_root, "CMakeLists.txt")

    if not filetools.file_exists(cmake_file) then
        return false, { "CMakeLists.txt not found (" .. cmake_file .. ")" }
    end

    -- ------------------------------------------------------------------
    -- 1. API Query
    -- ------------------------------------------------------------------
    do
        local ok, err = pcall(ensure_cmake_api_query, build_dir)
        if not ok then
            return false, { "Failed to setup CMake API query: " .. err }
        end
    end

    local all_targets, targets_errors = query_cmake_api_targets(build_dir)
    if not all_targets then
        return false, targets_errors
    end

    -- ------------------------------------------------------------------
    -- 2. Build All
    -- ------------------------------------------------------------------
    do
        local cmd = { cmake_path, "--build", build_dir }
        if cfg.build_tool_args then
            table.insert(cmd, "--")
            vim.list_extend(cmd, cfg.build_tool_args)
        end
        ---@type loop.Task
        local task = {
            name = "[" .. profile_name .. "] Build All",
            type = "build",
            command = cmd,
            cwd = src_root,
            problem_matcher = prob_matcher,
        }
        table.insert(tasks, task)
    end

    function build_task_name(tgt, tgt_type)
        local name = "[" .. profile_name .. "] Build "
        if tgt_type ~= "UTILITY" then
            name = name .. strtools.human_case(tgt_type)
        else
            name = name .. 'Target'
        end
        return name .. ': ' .. tgt
    end

    -- ------------------------------------------------------------------
    -- 2½. Build specific targets (optional cfg.build_targets)
    -- ------------------------------------------------------------------
    do
        for tgt, tgt_type in pairs(all_targets) do
            local cmd = { cmake_path, "--build", build_dir, "--target", tgt }
            if cfg.build_tool_args then
                table.insert(cmd, "--")
                vim.list_extend(cmd, cfg.build_tool_args)
            end
            ---@type loop.Task
            local task = {
                name = build_task_name(tgt, tgt_type),
                type = "build",
                command = cmd,
                cwd = src_root,
                problem_matcher = prob_matcher,
                depends_on = { "[" .. profile_name .. "] Configure" }
            }
            table.insert(tasks, task)
        end
    end
    -- ------------------------------------------------------------------
    -- 3. Run Targets
    -- ------------------------------------------------------------------
    for tgt, tgt_type in pairs(all_targets) do
        -- Only keep *real* executables (skip UTILITY, INTERFACE, etc.)
        if tgt_type == "EXECUTABLE" or tgt_type == "MACOSX_BUNDLE" then
            local name = "[" .. profile_name .. "] Run: " .. tgt
            local exec_path = vim.fs.joinpath(build_dir, tgt)
            local app = (cfg.run and cfg.run[tgt]) or {}
            local cmd = { exec_path }
            if app.args then
                vim.list_extend(cmd, app.args)
            end
            local env = app.env
            local cwd = app.cwd and realpath(app.cwd) or build_dir
            ---@type loop.Task
            local task =
            {
                name = name,
                type = "run",
                command = cmd,
                cwd = cwd,
                env = env,
                depends_on = { build_task_name(tgt, tgt_type) }
            }
            table.insert(tasks, task);
        end
    end
    ----------------------------------------------------------------------
    -- 4. CTest API
    ----------------------------------------------------------------------
    do
        local tests, err = query_cmake_api_tests(build_dir)
        --vim.notify(vim.inspect(tests))
        if not tests then
            return false, { err }
        end
        for _, t in ipairs(tests) do
            if t.name and t.command then
                ---@type loop.Task
                local task = {
                    name    = "[" .. profile_name .. "] CTest: " .. t.name,
                    type    = "test",
                    command = t.command,
                    cwd     = build_dir
                }
                table.insert(tasks, task)
            end
        end
        do
            -- Add a meta-task to run all tests
            ---@type loop.Task
            local all_tests_task = {
                name    = "[" .. profile_name .. "] CTest All",
                type    = "test",
                command = { "ctest", "--output-on-failure" },
                cwd     = build_dir
            }
            table.insert(tasks, all_tests_task)
        end
        do
            -- Add a meta-task to run all tests
            ---@type loop.Task
            local all_tests_task = {
                name    = "[" .. profile_name .. "] CTest Rerun Failed",
                type    = "test",
                command = { "ctest", "--rerun-failed", "--output-on-failure" },
                cwd     = build_dir
            }
            table.insert(tasks, all_tests_task)
        end        
        return true
    end
end

-- ----------------------------------------------------------------------
-- Core task generator
-- ----------------------------------------------------------------------
---@param src_root string
---@param cfg loop.tasks.CMakeConfig
---@return loop.Task[]
local function get_configure_tasks(src_root, cfg)
    local tasks = {}
    for _, prof in ipairs(cfg.profiles or {}) do
        local build_type = prof.build_type

        local profile_name = prof.name
        src_root = realpath(prof.source_dir) or prof.source_dir
        local build_dir = realpath(prof.build_dir) or prof.build_dir

        local cmd = { cfg.cmake_path }
        if prof.configure_args then
            vim.list_extend(cmd, prof.configure_args)
        end
        vim.list_extend(cmd, { "-B", build_dir, "-S", src_root, "-DCMAKE_BUILD_TYPE=" .. build_type })

        ---@type loop.Task
        local task = {
            name = "[" .. profile_name .. "] Configure",
            type = "build",
            command = cmd,
            cwd = src_root,
        }
        table.insert(tasks, task)
    end
    if #tasks > 1 then
        ---@type loop.Task
        local task = {
            name = "Configure All",
            type = "build",
            command = "true",
            cwd = src_root,
            depends_on = {}
        }
        for _, t in ipairs(tasks) do
            table.insert(task.depends_on, t.name)
        end
        table.insert(tasks, 1, task)
    end
    return tasks
end

---@param cfg loop.tasks.CMakeConfig
---@eturn boolean,string[]
function _check_params(cfg)
    local errors = {}
    if vim.fn.executable(cfg.cmake_path) == 0 then
        return table.insert(errors, "cmake_path not executable: " .. cfg.cmake_path)
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

---@param configdir string
---@return loop.tasks.CMakeConfig|nil
---@return string[]|nil
function _load_cmake_config(configdir)
    local filepath = vim.fs.joinpath(configdir, "cmake.json")
    if not filetools.file_exists(filepath) then
        return nil, nil -- not an error
    end
    local loaded, contents_or_err = filetools.read_content(filepath)
    if not loaded then
        return nil, { contents_or_err }
    end

    local decoded, data_or_err = jsontools.from_string(contents_or_err)
    if not decoded or type(data_or_err) ~= 'table' then
        return nil, { data_or_err }
    end

    local data = data_or_err
    local schema = require('loop.schema.cmakeconf')

    local errors = validate.validate(schema, data)
    if errors and #errors > 0 then
        return nil, errors
    end
    if not data or not data.config then
        return nil, { "Parsing error" }
    end
    return data.config, nil
end

-- ----------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------
---@param proj_dir string
---@param configdir string
---@return loop.Task[]|nil, string[]|nil
function M.get_cmake_tasks(proj_dir, configdir)
    local cmake_config, cfg_errors = _load_cmake_config(configdir)
    if not cmake_config then
        cfg_errors = cfg_errors or {}
        for i, v in ipairs(cfg_errors) do v[i] = '  ' .. v[i] end
        table.insert(cfg_errors, 1, "Failed to load CMake config file")
        return nil, cfg_errors
    end

    -- resolve variables in the cmake config
    ---@type loop.tools.ProjectVars
    local variables = {
        proj_dir = proj_dir
    }
    local vars_ok, var_errors = vartools.expand_strings(cmake_config, variables)
    if not vars_ok then
        cmake_config = nil
        for i, v in ipairs(var_errors) do v[i] = '  ' .. v[i] end
        table.insert(var_errors, 1, "Failed to resolve variables in cmake config")
        return nil, var_errors
    end

    local params_ok, params_errors = _check_params(cmake_config)
    if not params_ok then
        for i, v in ipairs(params_errors) do v[i] = '  ' .. v[i] end
        table.insert(params_errors, 1, "Invalid cmake config")
        return nil, params_errors
    end

    local tasks = get_configure_tasks(proj_dir, cmake_config)

    local all_errors = {}
    for _, prof in ipairs(cmake_config.profiles or {}) do
        local _, prof_errs = get_profile_tasks(tasks, cmake_config.cmake_path, prof)
        if prof_errs and #prof_errs > 0 then
            table.insert(all_errors, "While loading profile '" .. (prof.name or '(unkown)') .. "'")
            for _, err in ipairs(prof_errs) do
                table.insert(all_errors, '  ' .. err)
            end
        end
    end

    return tasks, #all_errors > 0 and all_errors or nil
end

return M
