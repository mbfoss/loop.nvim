local M = {}

require('loop.task.taskdef')
local qfparsers = require("loop.task.qfparsers")
local resolver = require('loop.tools.resolver')
local strtools = require('loop.tools.strtools')
local TermJob = require('loop.job.TermJob')
local DebugJob = require('loop.job.DebugJob')
local VimCmdJob = require('loop.job.VimCmdJob')
local window = require('loop.window')
local debugui = require('loop.debugui')
local Page = require('loop.pages.Page')
local config = require("loop.config")

---@class loop.runner.TaskChain
---@field tasks loop.Task[]
---@field started boolean
---@field interrupted boolean
---@field ended boolean
---@field active_job loop.job.Job|nil
---@field on_complete fun()|nil
---@field next_chain loop.runner.TaskChain|nil

---@type loop.runner.TaskChain|nil
local _current_task_chain = nil
---@type string|nil
local _current_task_name

---@param tasks loop.Task[] all available tasks
---@param main loop.Task main task
---@return loop.Task[]|nil list of tasks ordered by dependency or nil if errors
---@return string|nil error message or nil
function M.get_deps_chain(tasks, main)
    if type(tasks) ~= "table" or type(main) ~= "table" then
        return nil, "invalid arguments"
    end
    -- Build a map from task name to task object
    local task_map = {}
    for _, t in ipairs(tasks) do
        if not t.name or t.name == "" then
            return nil, "task with empty name"
        end
        if task_map[t.name] then
            return nil, ("duplicate task name: '%s'"):format(t.name)
        end
        task_map[t.name] = t
    end
    if not main.name or not task_map[main.name] then
        return nil, ("main task '%s' not found"):format(main.name or "<nil>")
    end
    -- Depth-first traversal to resolve dependencies
    local ordered = {}
    local visiting = {} -- stack of currently visiting nodes
    local visited = {}  -- completed tasks
    ---@param task loop.Task
    local function visit(task)
        if visited[task.name] then
            return true
        end
        if visiting[task.name] then
            return false, ("cyclic dependency detected at '%s'"):format(task.name)
        end
        visiting[task.name] = true
        if task.depends_on then
            for _, dep_name in ipairs(task.depends_on) do
                local dep = task_map[dep_name]
                if not dep then
                    return false, ("missing dependency '%s' required by '%s'"):format(dep_name, task.name)
                end
                local ok, err = visit(dep)
                if not ok then return false, err end
            end
        end
        visiting[task.name] = nil
        visited[task.name] = true
        table.insert(ordered, task)
        return true
    end
    local ok, err = visit(main)
    if not ok then return nil, err end
    return ordered, nil
end

---@param task loop.Task
---@return function|nil
---@return string|nil
local function _make_output_parser(task)
    if task.type ~= "build" or not task.quickfix_matcher then
        return nil
    end
    ---@param line string
    ---@return string
    local function normalize_string(line)
        --ansi color codes
        local pattern = "\27%[%d*;?%d*;?%d*[mGKHK]"
        line = line:gsub("\r\n?", "\n")
        line = line:gsub(pattern, "")
        return line
    end

    local quickfix_parser = qfparsers.get_parser(task.quickfix_matcher)
    if not quickfix_parser then
        return nil, "Invalid quickfix matcher: " .. task.quickfix_matcher
    end

    local first = true
    local parser_context = {}
    return function(lines)
        if first then
            vim.fn.setqflist({}, "r")
            first = false
        end
        local issues = {}
        for _, line in ipairs(lines) do
            local issue = quickfix_parser(normalize_string(line), parser_context)
            if issue then
                table.insert(issues, issue)
            end
        end
        if #issues > 0 then
            vim.fn.setqflist(issues, "a")
        end
    end
end


---@param obj table
---@param task_cpy loop.Task
---@return boolean success
---@return string? error_message
local function _resolve_functions_inplace(obj, task_cpy)
    if type(obj) ~= "table" then
        return false, "resolve_functions_inplace: obj must be a table"
    end
    local function recurse(t, path)
        path = path or ""
        for k, v in pairs(t) do
            local current_path = path ~= "" and (path .. "." .. k) or tostring(k)

            if type(v) == "function" then
                local ok, result = pcall(v, task_cpy)
                if not ok then
                    return false, ("failed to resolve debug.%s: %s"):format(current_path, result)
                end

                -- Replace the function with its result
                t[k] = result

                -- If the result is a table, recursively resolve inside it
                if type(result) == "table" then
                    local deep_ok, deep_err = recurse(result, current_path)
                    if not deep_ok then
                        return false, deep_err
                    end
                end
            elseif type(v) == "table" then
                -- Dive into nested tables
                local deep_ok, deep_err = recurse(v, current_path)
                if not deep_ok then
                    return false, deep_err
                end
            end
        end
        return true
    end

    return recurse(obj)
end

---@param task loop.Task
---@param startup_callback fun(job: loop.job.VimCmdJob|nil, err: string|nil)
---@param exit_handler fun(code : number)
local function _create_vimcmd_job(task, startup_callback, _, exit_handler)
    ---@type loop.VimCmdJob.StartArgs
    local args = {
        command = task.command,
        on_exit_handler = exit_handler
    }
    --vim.notify("Starting job:\n" .. vim.inspect(args))
    local job = VimCmdJob:new()
    local ok, err = job:start(args)
    if not ok then
        return startup_callback(nil, err or "failed to start vimcmd job")
    end
    startup_callback(job, nil)
    exit_handler(0)
end

---@param task loop.Task
---@param startup_callback fun(job: loop.job.TermJob|nil, err: string|nil)
---@param output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@param exit_handler fun(code: number, signal?: number)
local function _create_tool_job(task, startup_callback, output_handler, exit_handler)
    -- Basic validation
    if not task or type(task) ~= "table" then
        return startup_callback(nil, "task is required and must be a table")
    end
    if not task.command then
        return startup_callback(nil, "task.command is required")
    end

    local to_resolve = vim.deepcopy(task)

    resolver.resolve_macros(to_resolve, function(ok, resolved, resolve_err)
        if not ok or not resolved then
            return startup_callback(nil, "macro resolution failed: " .. tostring(resolve_err))
        end

        -- Your original args — unchanged, just using the resolved values
        ---@type loop.tools.TermProc.StartArgs
        local start_args = {
            name = task.name or "Unnamed Tool Task",
            command = resolved.command,
            command_env = resolved.env,
            command_cwd = resolved.cwd,
            output_handler = output_handler,
            on_exit_handler = exit_handler,
        }

        --vim.notify("Starting job:\n" .. vim.inspect(start_args))
        local job = TermJob:new()
        local bufnr, err = job:start(start_args)
        if not bufnr or bufnr == -1 then
            return startup_callback(nil, err or "failed to start terminal job")
        end

        -- Create and register the page
        local page = Page:new("term", task.name or "Tool Task")
        page:assign_buf(bufnr)

        -- Optional: only add to window if it's visible or desired
        local success = pcall(window.add_page, "task", page)
        if not success then
            vim.api.nvim_buf_delete(bufnr, { force = true })
            return startup_callback(nil, "failed to add page to window manager")
        end

        startup_callback(job, nil)
    end)
end

---@param task loop.Task
---@param startup_callback fun(job: loop.job.DebugJob|nil, err: string|nil)
---@param output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@param exit_handler fun(code: number)
local function _create_debug_job(task, startup_callback, output_handler, exit_handler)
    -- Early validation
    if not task or type(task) ~= "table" then
        return startup_callback(nil, "task is required and must be a table")
    end
    if task.type ~= "debug" then
        return startup_callback(nil, "task.type must be 'debug'")
    end
    if not task.debug_adapter or task.debug_adapter == "" then
        return startup_callback(nil, "task.debug_adapter is required for debug tasks")
    end
    if task.debug_request ~= "launch" and task.debug_request ~= "attach" then
        return startup_callback(nil, "task.debug_request must be 'launch' or 'attach'")
    end

    local debugger = config.current.debuggers[task.debug_adapter]
    if not debugger then
        return startup_callback(nil, ("no debug_adapter config found for '%s'"):format(tostring(task.debug_adapter)))
    end

    -- Resolve default args based on request type
    local default_args = (task.debug_request == "launch") and debugger.launch_args or debugger.attach_args or {}
    local request_args = vim.tbl_deep_extend("force", {}, default_args)

    -- Resolve functions first
    local task_copy = vim.deepcopy(task)
    local func_ok, func_err = _resolve_functions_inplace(request_args, task_copy)
    if not func_ok then
        return startup_callback(nil, func_err or "failed to resolve functions in debug args")
    end

    -- Merge task-specific args (override defaults)
    request_args = vim.tbl_deep_extend("force", request_args, task.debug_args or {})

    -- Now resolve macros asynchronously
    resolver.resolve_macros(request_args, function(success, resolved_args, macro_err)
        if not success then
            return startup_callback(nil, "Failed to resolve macro(s) in debugger arguments: " .. tostring(macro_err))
        end

        -- Final DAP type validation
        if debugger.dap.type ~= "executable" and debugger.dap.type ~= "server" then
            return startup_callback(nil,
                ("invalid dap.type '%s' — must be 'executable' or 'server'"):format(tostring(debugger.dap.type)))
        end

        -- Build final start args
        ---@type loop.DebugJob.StartArgs
        local start_args = {
            name = task.name,
            debug_args = {
                dap = debugger.dap,
                request = task.debug_request,
                request_args = resolved_args,
                terminate_debuggee = debugger.terminate_debuggee,
                launch_post_configure = debugger.launch_post_configure,
            },
        }

        --vim.notify("Starting job:\n" .. vim.inspect(start_args))
        local job = DebugJob:new(task.name)

        -- Add trackers
        job:add_tracker(debugui.track_new_debugjob(task.name))
        job:add_tracker({ on_exit = exit_handler })

        if output_handler then
            job:add_tracker({ on_stdout = function(data) output_handler("stdout", data) end })
            job:add_tracker({ on_stderr = function(data) output_handler("stderr", data) end })
        end

        -- Start the debug job
        local ok, err = job:start(start_args)
        if not ok then
            return startup_callback(nil, err or "failed to start debug job")
        end

        -- Success!
        startup_callback(job, nil)
    end)
end

---@param task loop.Task
---@return loop.job.Job|nil, string|nil
---@param startup_callback fun(job: loop.job.DebugJob|nil, err: string|nil)
---@param task_exit_handler fun(exit_code : number)
local function _start_one_task(task, startup_callback, task_exit_handler)
    --vim.notify("Starting task:\n" .. vim.inspect(task))

    if task.type ~= "debug" then
        if not task.command or #task.command == 0 then
            return nil, "Invalid or empty command"
        end
    end

    local output_parser = _make_output_parser(task)

    ---@param lines string[]
    local output_handler = function(_, lines)
        if output_parser then
            output_parser(lines)
        end
    end

    local exit_handler = function(exit_code)
        if output_parser then
            output_parser({ "" })
        end
        task_exit_handler(exit_code)
    end

    local tasktype = task.type
    if tasktype == "vimcmd" then
        return _create_vimcmd_job(task, startup_callback, output_handler, exit_handler)
    elseif tasktype == "build" or tasktype == "run" then
        return _create_tool_job(task, startup_callback, output_handler, exit_handler)
    elseif tasktype == "debug" then
        return _create_debug_job(task, startup_callback, output_handler, exit_handler)
    end
    return nil, "Unhandled task type: " .. tasktype
end


---@param new_chain loop.runner.TaskChain|nil
---@return boolean scheduled
local function _kill_current_chain(new_chain)
    if _current_task_chain then
        if _current_task_chain.active_job and not _current_task_chain.ended then
            window.add_events({ "Interrupting current task: " .. tostring(_current_task_name) })
            _current_task_chain.interrupted = true
            _current_task_chain.next_chain = new_chain
            if _current_task_chain.active_job then
                _current_task_chain.active_job:kill()
            end
            return true
        end
    end
    return false
end

---@param tasks loop.Task[]
---@param on_complete fun()|nil
local function _start_task_chain(tasks, on_complete)
    ---@param chain loop.runner.TaskChain
    local function next_job(chain)
        if chain.interrupted or not chain.tasks or #chain.tasks == 0 then
            chain.ended = true
            if chain.on_complete then
                chain.on_complete()
            end
            vim.schedule(function()
                if chain.next_chain then
                    _current_task_chain = chain.next_chain
                    next_job(chain.next_chain)
                elseif chain == _current_task_chain then
                    _current_task_chain = nil
                    _current_task_name = nil
                end
            end)
            return
        end

        if not chain.started then
            window.remove_task_pages()
            chain.started = true
        end

        local task = table.remove(chain.tasks, 1)
        _current_task_name = task.name
        _start_one_task(task,
            function(job, err)
                if job then
                    chain.active_job = job
                    local cmd_descr = table.concat(strtools.cmd_to_string_array(task.command), ' ')
                    window.add_events({ "Running " .. task.type .. " task", "  " .. cmd_descr })
                    window.show_task_output()
                else
                    window.add_events({ "Task creation failed: " .. task.name, "  " .. tostring(err) }, "error")
                    chain.interrupted = true
                    vim.schedule(function()
                        if chain == _current_task_chain then
                            next_job(chain)
                        end
                    end)
                end
            end
            , function(exit_code)
                if type(exit_code) ~= "number" then
                    window.add_events({ "Invalid task status for " .. task.name }, "error")
                    chain.interrupted = true
                elseif exit_code == 0 then
                    window.add_events({ "Task ended: " .. task.name })
                else
                    chain.interrupted = true
                    window.add_events({ "Task ended: " .. task.name .. ', exit code: ' .. tostring(exit_code) })
                end
                vim.schedule(function()
                    if chain == _current_task_chain then
                        next_job(chain)
                    end
                end)
            end)
    end

    ---@type loop.runner.TaskChain
    local new_chain = {
        tasks = tasks,
        started = false,
        interrupted = false,
        ended = false,
        active_job = nil,
        on_complete = on_complete,
        next_chain = nil,
    }

    local scheduled = _kill_current_chain(new_chain)
    if not scheduled then
        _current_task_chain = new_chain
        next_job(new_chain)
    end
end


---@param tasks loop.Task[]
---@param on_complete fun()|nil
function M.start_task_chain(tasks, on_complete)
    if not tasks or #tasks == 0 then
        if on_complete then vim.schedule(on_complete) end
        return
    end

    -- Work on a deep copy so original config stays clean
    local chain = vim.deepcopy(tasks)

    local pending = #chain
    local had_error = false

    for i, task in ipairs(tasks) do
        local original_name = task.name or ("task#" .. i)

        resolver.resolve_macros(task, function(success, resolved_task, err)
            if had_error then
                pending = pending - 1
                return
            end

            if not success then
                had_error = true
                window.add_events({
                    "Failed to resolve macro(s) in task '" .. original_name .. "'",
                    tostring(err)
                }, "error")
                pending = pending - 1
                if pending == 0 and on_complete then
                    vim.schedule(on_complete)
                end
                return
            end

            -- Replace the task with the fully resolved one
            chain[i] = resolved_task

            pending = pending - 1
            if pending == 0 then
                if not had_error then
                    _start_task_chain(chain, on_complete)
                end
            end
        end)
    end
end

function M.terminate_task_chain()
    _kill_current_chain(nil)
end

---@param command loop.job.DebugJob.Command|nil
function M.debug_task_command(command)
    if not _current_task_chain or not _current_task_chain.active_job or getmetatable(_current_task_chain.active_job) ~= DebugJob then
        window.add_events({ "Debug command not usable, no debut task is currently running" })
        return
    end
    ---@type loop.job.DebugJob
    ---@diagnostic disable-next-line: assign-type-mismatch
    local job = _current_task_chain.active_job
    job:debug_command(command)
end

return M
