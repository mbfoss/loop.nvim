local class = require("loop.tools.class")
local Scheduler = require("loop.tools.Scheduler")
local taskmgr = require("loop.task.taskmgr")
local logs = require('loop.logs')

---@alias loop.TaskScheduler.TaskEventFn fun(taskname: string, event: loop.scheduler.NodeEvent, success:boolean,reason?:string)

---@class loop.TaskPlan
---@field tasks loop.Task[]
---@field root string
---@field on_start fun()
---@field on_task_event loop.TaskScheduler.TaskEventFn
---@field on_exit fun(success:boolean, reason?:string)

---@class loop.TaskTreeNode
---@field name string                       -- Task name
---@field order "sequence"|"parallel"       -- Dependency execution order
---@field deps loop.TaskTreeNode[]           -- Child dependency nodes

---@class loop.TaskScheduler
---@field new fun(self:loop.TaskScheduler):loop.TaskScheduler
---@field _schedulers table<number,loop.tools.Scheduler> -- run id --> scheduler
---@field _schedule_id number
local TaskScheduler = class()

---@param trigger  loop.scheduler.exit_trigger
---@param param string?
local function _get_failure_message(trigger, param)
    local reason
    if trigger == "cycle" then
        reason = "Task dependency loop detected in task: " .. tostring(param)
    elseif trigger == "invalid_node" then
        reason = "Invalid task name: " .. tostring(param)
    elseif trigger == "interrupt" then
        reason = "Task interrupted"
    elseif trigger == "deps_failed" then
        reason = "Dependency task failed"
    elseif trigger == "node" then
        reason = param or "Task failed"
    else
        reason = "Task failed (" .. tostring(reason) .. ")"
    end
    return reason
end

---@param plan loop.TaskPlan
---@return table<string, loop.Task>? name_to_task
---@return loop.scheduler.Node[]? nodes
---@return string? error_msg
local function _validate_and_build_nodes(plan)
    local name_to_task = {}
    local nodes = {}

    for _, task in ipairs(plan.tasks) do
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

    if not name_to_task[plan.root] then
        return nil, nil, "Root task '" .. plan.root .. "' not found among provided tasks"
    end

    return name_to_task, nodes, nil
end

---@param plan loop.TaskPlan
---@return loop.tools.Scheduler?
local function _run_plan(plan)
    local name_to_task, nodes, err = _validate_and_build_nodes(plan)
    if err or not name_to_task or not nodes then
        vim.schedule_wrap(plan.on_exit)(false, err)
        return
    end

    ---@type loop.scheduler.StartNodeFn
    local function start_node(id, on_node_exit)
        local task = name_to_task[id] --[[@as loop.Task]]

        logs.user_log("Starting task:\n" .. vim.inspect(task), "task")

        local provider = taskmgr.get_task_type_provider(task.type)
        if not provider then
            return nil, "No provider registered for task type: " .. task.type
        end

        local exit_handler = vim.schedule_wrap(function(success, reason)
            on_node_exit(success, reason)
        end)

        local control, start_err = provider.start_one_task(task, exit_handler)
        if not control then
            return nil, start_err or ("Failed to start task '" .. task.name .. "'")
        end

        return control
    end

    local scheduler = Scheduler:new(nodes, start_node)

    local final_cb = vim.schedule_wrap(plan.on_exit)

    ---@type loop.scheduler.NodeEventFn
    local function on_node_event(id, event, success, reason, param)
        local msg = success and "" or _get_failure_message(reason, param)
        plan.on_task_event(id, event, success, msg)
    end

    ---@type loop.scheduler.exit_fn
    local on_plan_end = function(success, trigger, param)
        local msg = success and "" or _get_failure_message(trigger, param)
        final_cb(success, msg)
    end

    plan.on_start()

    scheduler:start(plan.root, on_node_event, on_plan_end)

    return scheduler
end

--- Create a new TaskScheduler
function TaskScheduler:init()
    self._schedulers = {}
    self._schedule_id = 0
end

---@param tasks loop.Task[]
---@param root string
---@param on_start fun()
---@param on_task_event loop.TaskScheduler.TaskEventFn
---@param on_exit? fun(success:boolean, reason?:string)
function TaskScheduler:start(tasks, root, on_start, on_task_event, on_exit)
    self._schedule_id = self._schedule_id + 1
    local schedule_id = self._schedule_id

    local on_plan_exit = function(success, reason)
        self._schedulers[schedule_id] = nil
        if on_exit then on_exit(success, reason) end
    end

    ---@type loop.TaskPlan
    local task_plan = {
        tasks = tasks,
        root = root,
        on_start = on_start,
        on_task_event = on_task_event,
        on_exit = on_plan_exit,
    }

    local scheduler = _run_plan(task_plan)
    if scheduler then
        self._schedulers[schedule_id] = scheduler
    end
end

function TaskScheduler:terminate()
    for _, scheduler in self._schedulers do
        scheduler:terminate()
    end
end

---@return boolean
function TaskScheduler:is_running()
    return not vim.tbl_isempty(self._schedulers)
end

return TaskScheduler
