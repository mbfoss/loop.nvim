local class = require("loop.tools.class")
local Scheduler = require("loop.tools.Scheduler")

---@alias loop.TaskScheduler.StartTaskFn fun(task: loop.Task, on_exit: fun(ok:boolean, reason:string|nil)): { terminate:fun() }|nil, string|nil
---@alias loop.TaskScheduler.TaskEventFn fun(taskname: string, event: loop.scheduler.NodeEvent, success:boolean,reason?:string)

---@class loop.TaskTreeNode
---@field name string                       -- Task name
---@field order "sequence"|"parallel"       -- Dependency execution order
---@field deps loop.TaskTreeNode[]           -- Child dependency nodes

local M = {}

---@type table<number, loop.tools.Scheduler>
local _base_schedulers = {}

---@type number
local _last_base_scheduler_id = 0

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

---@param tasks loop.Task[]
---@param root string
---@param start_task loop.TaskScheduler.StartTaskFn
---@param on_task_event loop.TaskScheduler.TaskEventFn
---@param on_exit? fun(success:boolean, reason?:string)
function M.start(tasks, root, start_task, on_task_event, on_exit)
    local on_plan_exit = function(success, reason)
        if on_exit then on_exit(success, reason) end
    end

    local name_to_task, nodes, err = _validate_and_build_nodes(tasks, root)
    if err or not name_to_task or not nodes then
        vim.schedule_wrap(on_plan_exit)(false, err)
        return
    end

    ---@type loop.scheduler.StartNodeFn
    local function start_node(id, on_node_exit)
        local task = name_to_task[id] --[[@as loop.Task]]
        return start_task(task, on_node_exit)
    end

    local scheduler = Scheduler:new(nodes, start_node)
    _last_base_scheduler_id = _last_base_scheduler_id + 1
    _base_schedulers[_last_base_scheduler_id] = scheduler

    local final_cb = vim.schedule_wrap(on_plan_exit)

    ---@type loop.scheduler.NodeEventFn
    local function on_node_event(id, event, success, reason, param)
        local msg = success and "" or _get_failure_message(reason, param)
        on_task_event(id, event, success, msg)
    end

    ---@type loop.scheduler.exit_fn
    local on_plan_end = function(success, trigger, param)
        local msg = success and "" or _get_failure_message(trigger, param)
        final_cb(success, msg)
    end

    scheduler:start(root, on_node_event, on_plan_end)
end

function M.terminate()
    for _, s in pairs(_base_schedulers) do
        s:terminate()
    end
end

---@return boolean
function M.is_running()
    for _, s in pairs(_base_schedulers) do
        if s:is_running() then return true end
    end
    return false
end

return M
