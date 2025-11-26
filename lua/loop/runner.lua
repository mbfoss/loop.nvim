local M = {}

require('loop.task.taskdef')
local qfparsers = require("loop.task.qfparsers")
local vartools = require('loop.tools.vars')
local strtools = require('loop.tools.strtools')
local TermJob = require('loop.job.TermJob')
local DebugJob = require('loop.job.DebugJob')
local VimCmdJob = require('loop.job.VimCmdJob')
local window = require('loop.window')
local config = require('loop.config')

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
    if task.type ~= "tool" or not task.quickfix_matcher then
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

---@param task loop.Task
---@return loop.dap.session.Args.DAP|nil
---@return string|nil
local function _get_dap_config(task)
    local dbg_type = task.debug_type or "local"
    if dbg_type ~= "local" and dbg_type ~= "remote" then
        return nil, "invalid debug_type: " .. tostring(dbg_type)
    end
    if  dbg_type == "local" and not task.debug_adapter then
        return nil, "Debug adapter name missing in task config (local mode)"
    end
    if  dbg_type == "remote" and (not task.debugger_host or not task.debugger_port) then
        return nil, "Debug host/port missing in task config (remote mode)"
    end
    local debugger = config.current.debuggers[task.debug_adapter]
    if  not debugger and dbg_type == "local" then
        return nil, "Invalid debugger name: " .. tostring(task.debug_adapter) .. "'"
    end
    ---@type loop.dap.session.Args.DAP
    local dap = {
        name = task.debug_adapter,
        type = task.debug_type,
        host = task.debugger_host,
        port = task.debugger_port,
        cmd = debugger and debugger.command or nil,
        cwd = debugger and debugger.cwd or nil,
        env = debugger and debugger.env or nil,
        init_commands = debugger and debugger.init_commands or nil,
        configure_post_launch = debugger and debugger.configure_post_launch or nil,
    }
    return dap, nil
end

---@param task loop.Task
---@param output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@param exit_handler fun(code : number)
local function _create_vimcmd_job(task, output_handler, exit_handler)
    ---@type loop.VimCmdJob.StartArgs
    local args = {
        command = task.command,
        on_exit_handler = exit_handler
    }
    local job = VimCmdJob:new()
    local ok, err = job:start(args)
    if not ok then
        return nil, err
    end
    return job, nil
end

---@param task loop.Task
---@param output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@param exit_handler fun(code : number)
local function _create_tool_job(task, output_handler, exit_handler)
    ---@type loop.tools.TermProc.StartArgs
    local args = {
        name = task.name,
        command = task.command,
        command_env = task.env,
        command_cwd = task.cwd,
        output_handler = output_handler,
        on_exit_handler = exit_handler,
    }
    local job = TermJob:new()
    local ok, err = job:start(args)
    if not ok then
        return nil, err
    end
    return job, nil
end

---@param task loop.Task
---@param output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@param exit_handler fun(code : number)
local function _create_debug_job(task, output_handler, exit_handler)
    ---@type loop.dap.session.Args.DAP|nil,string|nil
    local dap, dap_error = _get_dap_config(task)
    if not dap then
        return nil, dap_error or "Invalid debugger config"
    end

    ---@type loop.DebugJob.StartArgs
    local args = {
        name = task.name,
        dap = dap,
        cmd = task.command,
        cwd = task.cwd,
        env = task.env,
        run_in_terminal = task.run_in_terminal or false,
        stop_on_entry = task.stop_on_entry or false,
        output_handler = output_handler,
        on_exit_handler = exit_handler,
    }
    local job = DebugJob:new()
    local ok, err = job:start(args)
    if not ok then
        return nil, err
    end
    return job, nil
end

---@param task loop.Task
---@return loop.job.Job|nil, string|nil
---@param task_exit_handler fun(exit_code : number)
local function _start_one_task(task, task_exit_handler)
    if not task.command or #task.command == 0 then
        return nil, "Invalid or empty command"
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
        return _create_vimcmd_job(task, output_handler, exit_handler)
    elseif tasktype == "tool" or tasktype == "app" then
        return _create_tool_job(task, output_handler, exit_handler)
    elseif tasktype == "debug" then
        return _create_debug_job(task, output_handler, exit_handler)
    end
    return nil, "Unhandled task type: " .. tasktype
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
            window.delete_task_buffers()
            chain.started = true
        end

        local task = table.remove(chain.tasks, 1)
        _current_task_name = task.name
        local job, job_err = _start_one_task(task, function(exit_code)
            if type(exit_code) ~= "number" then
                window.add_events({ "Invalid task status for " .. task.name })
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

        if job then
            chain.active_job = job
            local cmd_descr = table.concat(strtools.cmd_to_string_array(task.command), ' ')
            window.add_events({ "Running " .. task.type .. " task", "  " .. cmd_descr })
            window.show_task_output()
        else
            window.add_events({ "Task creation failed: " .. task.name, "  " .. tostring(job_err) }, "error")
            chain.interrupted = true
            vim.schedule(function()
                if chain == _current_task_chain then
                    next_job(chain)
                end
            end)
        end
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

    if _current_task_chain then
        if _current_task_chain.active_job and not _current_task_chain.ended then
            window.add_events({ "Interrupting current task: " .. tostring(_current_task_name) })
            _current_task_chain.interrupted = true
            _current_task_chain.next_chain = new_chain
            if _current_task_chain.active_job then
                _current_task_chain.active_job:kill()
            end
            return
        end
    end

    _current_task_chain = new_chain
    next_job(new_chain)
end


---@param tasks loop.Task[]
---@param on_complete fun()|nil
function M.start_task_chain(tasks, on_complete)
    --- copy to solve strings in the copy and keep the original intact
    local chain = vim.deepcopy(tasks)

    local is_unresolved = false
    for _, task in ipairs(chain) do
        local name = task.name -- keep because the expand_strings may change it
        local expand_ok, unresolved, explanation = vartools.expand_strings(task)
        if not expand_ok then
            is_unresolved = true
            if explanation then
                window.add_events({ "Failed to resolve variable(s) in task '" .. name .. "', " .. explanation }, "error")
            else
                window.add_events({ "Failed to resolve variable(s) in task '" .. name .. "':", '  ' ..
                table.concat(unresolved or {}, ', ') }, "error")
            end
        end
    end
    if is_unresolved then
        return
    end
    _start_task_chain(chain, on_complete)
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
