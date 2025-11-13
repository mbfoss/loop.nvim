local M = {}

require('loop.task.taskdef')
local vartools = require('loop.tools.vars')
local TermProc = require('loop.job.TermProc')
local LuaFunc = require('loop.job.LuaFunc')
local quickfix = require('loop.tools.quickfix')
local strtools = require('loop.tools.strtools')
local window = require("loop.window")


---@class loop.runner.TaskChain
---@field tasks loop.Task[]
---@field interrupted boolean
---@field ended boolean
---@field active_job loop.job.Job|nil
---@field qf_errors boolean
---@field on_complete fun(qf_errors : boolean)|nil
---@field next_chain loop.runner.TaskChain|nil

---@type loop.runner.TaskChain|nil
local _current_task_chain = nil

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

---@class loop.task.ExitStatus
---@field exit_code number
---@field qf_errors boolean

---@param task loop.Task
---@return loop.job.Job|nil, string|nil
---@param task_exit_handler fun(status : loop.task.ExitStatus)
local function _start_one_task(task, task_exit_handler)
    if not task.command or #task.command == 0 then
        return nil, "Invalid or empty command"
    end

    local tasktype = task.type

    local output_handler = nil
    local qf_errors = false
    if tasktype == "tool" then
        if task.problem_matcher then
            if type(task.problem_matcher) == 'string' and not quickfix.is_builtin_matcher(task.problem_matcher) then
                return nil, "Unknown problem matcher: " .. task.problem_matcher
            end
            quickfix.clear()
            output_handler = function(_, text)
                local added = quickfix.add(text, task.problem_matcher)
                if added > 0 then
                    qf_errors = true
                end
            end
        end
    end

    local exit_handler = function(exit_code)
        ---@type loop.task.ExitStatus
        local exit_status = {
            exit_code = exit_code,
            qf_errors = qf_errors
        }
        task_exit_handler(exit_status)
    end

    if tasktype == "tool" or tasktype == "app" then
        local buf = window.create_task_buffer()
        if buf == -1 then
            return nil, "No output buffer for task"
        end
        ---@type loop.TermProc.StartArgs
        local args = {
            bufnr = buf,
            name = task.name,
            command = task.command,
            command_env = task.env,
            command_cwd = task.cwd,
            output_handler = output_handler,
            on_exit_handler = exit_handler,
        }
        local job = TermProc:new()
        local ok, err = job:start(args)
        if not ok then
            return nil, err
        end
        return job, nil
    elseif tasktype == "lua" then
        ---@type loop.LuaFunc.StartArgs
        local args = {
            command = task.command,
            on_exit_handler = exit_handler
        }
        local job = LuaFunc:new()
        local ok, err = job:start(args)
        if not ok then
            return nil, err
        end
        return job, nil
    end

    return nil, "Unhandled task type: " .. tasktype
end

---@param tasks loop.Task[]
---@param on_complete fun(qf_errors : boolean)|nil
local function _start_task_chain(tasks, on_complete)
    ---@param chain loop.runner.TaskChain
    local function next_job(chain)
        if chain.interrupted or not chain.tasks or #chain.tasks == 0 then
            chain.ended = true
            if chain.on_complete then
                chain.on_complete(chain.qf_errors)
            end
            vim.schedule(function()
                if chain.next_chain then
                    _current_task_chain = chain.next_chain
                    next_job(chain.next_chain)
                elseif chain == _current_task_chain then
                    _current_task_chain = nil
                end
            end)
            return
        end

        local task = table.remove(chain.tasks, 1)
        local job, job_err = _start_one_task(task, function(status)
            if type(status.exit_code) ~= "number" then
                window.add_events({ "Invalid task status for " .. task.name })
                chain.interrupted = true
            elseif status.exit_code == 0 then
                window.add_events({ "Task ended: " .. task.name })
            else
                local action = chain.interrupted and "interrupted" or "failed"
                chain.interrupted = true -- after the line above the distinguish requested interruption
                window.add_events({ "Task " ..
                action .. ": " .. task.name .. ', exit code: ' .. tostring(status.exit_code) })
            end
            if status.qf_errors == true then
                chain.qf_errors = true
            end
            vim.schedule(function()
                if chain == _current_task_chain then
                    next_job(chain)
                end
            end)
        end)

        if job then
            chain.active_job = job
            ---@diagnostic disable-next-line: param-type-mismatch
            local cmd_descr = type(task.command) == 'table' and table.concat(task.command, ' ') or task.command
            window.add_events({ "Running " .. task.type .. " task", "  " .. cmd_descr })
            window.show_task_output()
        else
            window.add_events({ "Task creation failed: " .. task.name, "  " .. tostring(job_err) })
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
        interrupted = false,
        ended = false,
        active_job = nil,
        qf_errors = false,
        on_complete = on_complete,
        next_chain = nil,
    }

    if _current_task_chain then
        if _current_task_chain.active_job and not _current_task_chain.ended then
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
        local expand_ok, unresolved = vartools.expand_strings(task)
        if not expand_ok then
            is_unresolved = true
            window.add_events({ "Failed to resolve variable(s) in task '" .. task.name .. "':", '  ' ..
            table.concat(unresolved or {}, ', ') }, "error")
        end
    end
    if is_unresolved then
        return
    end
    _start_task_chain(chain, on_complete)
end

return M
