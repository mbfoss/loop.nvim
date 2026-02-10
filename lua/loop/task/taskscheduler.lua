local class = require("loop.tools.class")
local Scheduler = require("loop.tools.Scheduler")

---@alias loop.TaskScheduler.StartTaskFn fun(task: loop.Task, on_exit: fun(ok:boolean, reason:string|nil)): { terminate:fun() }|nil, string|nil
---@alias loop.TaskScheduler.TaskEventFn fun(taskname: string, event: loop.scheduler.NodeEvent, success:boolean,reason?:string)

---@class loop.TaskTreeNode
---@field name string                       -- Task name
---@field order "sequence"|"parallel"       -- Dependency execution order
---@field deps loop.TaskTreeNode[]           -- Child dependency nodes

local M = {}

---@alias loop.TaskScheduler.TaskData { control: loop.TaskControl, task: loop.Task, waiters:function[] }

---@type number
local _last_plan_id = 0

---@type number
local _last_task_id = 0

---@type table<number, loop.tools.Scheduler>
local _plan_schedulers = {}

---@type table<string, table<number, loop.TaskScheduler.TaskData>>
local _running_tasks = {}

---@param trigger  loop.scheduler.exit_trigger
---@param param string?
local function _get_failure_message(trigger, param)
    if trigger == "cycle" then
        return "Task dependency loop detected in task: " .. tostring(param)
    elseif trigger == "invalid_node" then
        return "Invalid task name: " .. tostring(param)
    elseif trigger == "interrupt" then
        return "Task interrupted"
    elseif trigger == "deps_failed" then
        return "Dependency task failed"
    else
        return param or "Task failed"
    end
end

---@param tasks loop.Task[]
---@param root string
---@return table<string, loop.Task>? name_to_task
---@return loop.scheduler.Node[]? nodes
---@return string? error_msg
local function _validate_and_build_nodes(tasks, root)
    local name_to_task = {}
    local nodes = {}

    for _, task in ipairs(tasks) do
        if name_to_task[task.name] then
            return nil, nil, "Duplicate task name: " .. task.name
        end
        name_to_task[task.name] = task
        table.insert(nodes, {
            id = task.name,
            deps = task.depends_on or {},
            order = task.depends_order or "sequence",
        })
    end

    if not name_to_task[root] then
        return nil, nil, "Root task '" .. root .. "' not found among provided tasks"
    end

    return name_to_task, nodes, nil
end

---@param task loop.Task
---@param start_task loop.TaskScheduler.StartTaskFn
---@param on_exit fun(ok:boolean, reason:string|nil)
---@return loop.TaskControl?, string?
local function _start_plan_task(task, start_task, on_exit)
    if task.concurrency == "refuse" then
        local data = _running_tasks[task.name]
        if data and not vim.tbl_isempty(data) then
            return nil, "Task refused (already running)"
        end
    end

    local task_name = task.name
    _last_task_id = _last_task_id + 1
    local task_id = _last_task_id

    ---@type loop.TaskScheduler.TaskData
    local task_data = nil

    local finalized = false
    local function finalize_and_wake(ok, reason)
        if finalized then return end
        finalized = true
        local task_runs = _running_tasks[task_name]
        if task_runs then
            task_runs[task_id] = nil
            if next(task_runs) == nil then
                _running_tasks[task_name] = nil
            end
            if task_data then
                -- We schedule this to remain thread-safe/async-safe for the UI
                vim.schedule(function()
                    on_exit(ok, reason)
                    local waiters = task_data.waiters
                    task_data.waiters = {}
                    for _, waiter in ipairs(waiters) do
                        waiter()
                    end
                end)
            end
        end
    end

    local control_ctx = {
        sub_control = nil,
        is_terminated = false,
        terminate_reason = nil,
    }
    ---@type loop.TaskControl
    local control = {
        terminate = function()
            if not control_ctx.is_terminated then
                control_ctx.is_terminated = true
                if control_ctx.sub_control then
                    control_ctx.sub_control.terminate()
                else
                    finalize_and_wake(false, control_ctx.terminate_reason or "Interrupted")
                end
            end
        end
    }

    local start_and_attach_control = function()
        local sub_err
        if not control_ctx.is_terminated then
            -- run the task now
            control_ctx.sub_control, sub_err = start_task(task, finalize_and_wake)
        end
        if not control_ctx.sub_control then
            control_ctx.terminate_reason = sub_err
            control.terminate()
        end
    end

    -- Register the control early so it can be waited on by others
    task_data = { control = control, task = task, waiters = {} }
    _running_tasks[task_name] = _running_tasks[task_name] or {}
    _running_tasks[task_name][task_id] = task_data

    ---@type loop.TaskScheduler.TaskData[]
    local tasks_to_wait = {}

    -- same task concurrency
    if task.concurrency ~= "parallel" then
        local instances = _running_tasks[task_name]
        if instances then
            for id, data in pairs(instances) do
                if task_id ~= id then
                    table.insert(tasks_to_wait, data)
                end
            end
        end
    end

    -- dependants that require stopping
    for _, instances in pairs(_running_tasks) do
        for id, data in pairs(instances) do
            if task_id ~= id and data.task.depends_on and vim.tbl_contains(data.task.depends_on, task_name) then
                table.insert(tasks_to_wait, data)
            end
        end
    end

    if #tasks_to_wait > 0 then
        local nb_running = #tasks_to_wait
        local on_task_ended = function()
            nb_running = nb_running - 1
            if nb_running == 0 then
                start_and_attach_control()
            end
        end
        for _, pt in ipairs(tasks_to_wait) do
            table.insert(pt.waiters, on_task_ended)
            if task.concurrency ~= "wait" then
                pt.control.terminate()
            end
        end
    else
        start_and_attach_control()
    end

    return control
end

---@param tasks loop.Task[]
---@param root string
---@param start_task loop.TaskScheduler.StartTaskFn
---@param on_task_event loop.TaskScheduler.TaskEventFn
---@param on_exit? fun(success:boolean, reason?:string)
function M.run_plan(tasks, root, start_task, on_task_event, on_exit)
    local call_on_exit = function(success, reason)
        if on_exit then on_exit(success, reason) end
    end

    local name_to_task, nodes, validation_err = _validate_and_build_nodes(tasks, root)
    if validation_err or not name_to_task or not nodes then
        vim.schedule_wrap(call_on_exit)(false, validation_err)
        return
    end

    _last_plan_id = _last_plan_id + 1
    local plan_id = _last_plan_id

    ---@type loop.scheduler.StartNodeFn
    local start_node = function(id, on_node_exit)
        local task = name_to_task[id] --[[@as loop.Task]]
        assert(task)
        return _start_plan_task(task, start_task, on_node_exit)
    end

    local scheduler = Scheduler:new()
    _plan_schedulers[plan_id] = scheduler

    ---@type loop.scheduler.NodeEventFn
    local function on_node_event(id, event, success, reason, param)
        local msg = success and "" or _get_failure_message(reason, param)
        on_task_event(id, event, success, msg)
    end

    ---@type loop.scheduler.exit_fn
    local on_schedule_end = function(success, trigger, param)
        local msg = success and "" or _get_failure_message(trigger, param)
        vim.schedule(function()
            _plan_schedulers[plan_id] = nil
            call_on_exit(success, msg)
        end)
    end

    scheduler:start(nodes, root, start_node, on_node_event, on_schedule_end)
end

function M.terminate()
    -- the schedules will terminate running tasks
    for _, ps in pairs(_plan_schedulers) do
        ps:terminate()
    end
end

---@return boolean
function M.is_running()
    for _, ps in pairs(_plan_schedulers) do
        if ps:is_running() then return true end
    end
    return false
end

return M
