local M = {}

local vartools = require('loop.tools.vars')
local TermProc = require('loop.job.TermProc')
local quickfix = require('loop.tools.quickfix')
local strtools = require('loop.tools.strtools')
local window = require("loop.window")


---@class loop.runner.TaskChain
---@field tasks loop.Task[]
---@field interrupted boolean
---@field active_job loop.job.Job|nil
---@field next_chain loop.runner.TaskChain|nil

---@type loop.runner.TaskChain|nil
_current_task_chain = nil

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
---@return loop.job.Job|nil, string|nil
---@param on_exit_handler fun(code : number)
local function _start_one_task(task, on_exit_handler)
    if not task.command or #task.command == 0 then
        return nil, "Invalid or empty command"
    end

    local tasktype = task.type

    local output_handler = nil
    if tasktype == "build" then
        if task.problem_matcher then
            quickfix.clear()
            output_handler = function(category, text)
                quickfix.add(text, task.problem_matcher)
            end
        end
    end

    if tasktype == "build" or tasktype == "run" or tasktype == "test" then
        local buf = window.create_task_buffer(strtools.human_case(tasktype))
        if buf == -1 then
            return nil, "No output buffer for task"
        end
        local interactive = tasktype == "run"
        ---@type loop.TermProc.StartArgs
        local args = {
            bufnr = buf,
            interactive = interactive,
            name = task.name,
            command = task.command,
            command_env = task.env,
            command_cwd = task.cwd,
            output_handler = output_handler,
            on_exit_handler = on_exit_handler
        }
        local job = TermProc:new()
        local ok, err = job:start(args)
        if not ok then
            return nil, err
        end
        return job, nil
    end

    return nil, "Unhandled task type: " .. tasktype
end

---@param tasks loop.Task[]
local function _start_task_chain(tasks)
    ---@param chain loop.runner.TaskChain
    local function next_job(chain)
        if #chain.tasks == 0 then
            chain.active_job = nil
            if _current_task_chain == chain then
                _current_task_chain = nil
            end
            return
        end

        local task = table.remove(chain.tasks, 1)

        local job, job_err = _start_one_task(task, function(exit_code)
            if exit_code == 0 then
                window.add_events({ "Task ended: " .. task.name })
            else
                local action = chain.interrupted and "interrupted" or "failed"
                local level = chain.interrupted and "warn" or "error"
                window.add_events({ "Task " .. action .. ": " .. task.name .. ', exit code: ' .. tostring(exit_code) },
                    level)
            end
            local should_continue = exit_code == 0 and not chain.interrupted
            vim.schedule(function()
                if should_continue then
                    next_job(chain)
                else
                    if chain.next_chain then
                        next_job(chain.next_chain)
                    end
                end
            end)
        end)

        if job then
            chain.active_job = job
            ---@diagnostic disable-next-line: param-type-mismatch
            local cmd_descr = type(task.command) == 'table' and table.concat(task.command, ' ') or task.command
            window.add_events({ "Running " .. task.type .. " task", "  " .. cmd_descr, "  cwd: " .. (task.cwd or "?") })
            window.show_task_output()
        else
            window.add_events({ "Task creation failed: " .. task.name, "  " .. tostring(job_err) })
        end
    end

    if not tasks or #tasks == 0 then
        return
    end

    ---@type loop.runner.TaskChain
    local new_chain = {
        tasks = tasks,
        interrupted = false,
        next_chain = nil,
        active_job = nil
    }

    if _current_task_chain then
        if _current_task_chain.active_job and _current_task_chain.active_job:is_running() then
            _current_task_chain.interrupted = true
            _current_task_chain.next_chain = new_chain
            _current_task_chain.active_job:kill()
            return
        end
    end

    _current_task_chain = new_chain
    next_job(new_chain)
end

---@param all_tasks loop.Task[]
---@param main loop.Task
---@param proj_dir string
function M.start_task_with_deps(all_tasks, main, proj_dir)
    local chain, err = M.get_deps_chain(all_tasks, main)
    if not chain then
        window.add_events({ "Dependency error for task '" .. main.name .. "'", "  " .. err }, "error")
        return
    end

    --- copy to solve strings in the copy and keep the original intact
    chain = vim.deepcopy(chain)

    local variables = { proj_dir = proj_dir }
    local is_unresoved = false
    for _, task in ipairs(chain) do
        local expand_ok, unresolved = vartools.expand_strings(chain, variables)
        if not expand_ok then
            is_unresoved = true
            window.add_events({ "Failed to resolve variable(s) in task '" .. task.name .. "':", '  ' ..
            table.concat(unresolved, ', ') })
        end
    end
    if is_unresoved then
        return
    end

    _start_task_chain(chain)
end

return M
