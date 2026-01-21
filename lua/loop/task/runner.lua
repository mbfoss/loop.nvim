local M             = {}

local taskmgr       = require("loop.task.taskmgr")
local resolver      = require("loop.tools.resolver")
local logs          = require("loop.logs")
local TaskScheduler = require("loop.task.TaskScheduler")
local StatusComp    = require("loop.task.StatusComp")
local config        = require("loop.config")
local variablesmgr  = require("loop.task.variablesmgr")
local strtools      = require("loop.tools.strtools")
local wsinfo        = require("loop.wsinfo")

---@type loop.task.TasksStatusComp?,loop.PageController?,loop.PageGroup?
local _status_comp, _status_page, _status_pagegroup

---@type loop.TaskScheduler
local _scheduler    = TaskScheduler:new()

---@param node table Task node from generate_task_plan_tree
---@param prefix? string Internal use for indentation
---@param is_last? boolean Internal use to determine tree branch
local function print_task_tree(node, prefix, is_last)
    prefix = prefix or ""
    is_last = is_last or true

    local branch = is_last and "└─ " or "├─ "
    local line = prefix .. branch .. node.name .. " (" .. (node.order or "sequence") .. ")"
    local new_prefix = prefix .. (is_last and "   " or "│  ")
    if node.deps then
        for i, child in ipairs(node.deps) do
            line = line .. '\n' .. print_task_tree(child, new_prefix, i == #node.deps)
        end
    end
    return line
end

---@param page_manager_fact loop.PageManagerFactory
---@return loop.task.TasksStatusComp,loop.PageController,loop.PageGroup
local function _create_status_page(page_manager_fact)
    local group = page_manager_fact().add_page_group("status", "Status")
    assert(group, "page mgr error")
    local page_data = group.add_page({
        id = "status",
        type = "comp",
        label = "Status",
        buftype = "status",
        activate = true,
    })
    assert(page_data)
    page_data.comp_buf.disable_change_events()
    local comp = StatusComp:new()
    comp:link_to_buffer(page_data.comp_buf)
    return comp, page_data.page, group
end

---@param config_dir string
---@return table<string, string>|nil variables, string[]|nil errors
local function _load_variables(config_dir)
    -- Load variables after loading tasks (errors are logged but don't block task loading)
    local vars, var_errors = variablesmgr.load_variables(config_dir)
    if var_errors then
        vim.notify("error(s) loading variables.json")
        logs.log(strtools.indent_errors(var_errors, "Error(s) loading variables.json"),
            vim.log.levels.WARN)
    end
    return vars, var_errors
end

---@param config_dir string
---@param page_manager_fact loop.PageManagerFactory
---@param mode "task"|"repeat"
---@param task_name string|nil
function M.load_and_run_task(config_dir, page_manager_fact, mode, task_name)
    taskmgr.get_or_select_task(config_dir, mode, task_name, function(root_name, all_tasks)
        if not root_name or not all_tasks then
            return
        end
        taskmgr.save_last_task_name(root_name, config_dir)
        M.run_task(config_dir, page_manager_fact, all_tasks, root_name)
    end)
end

---@param config_dir string
---@param page_manager_fact loop.PageManagerFactory
---@param all_tasks loop.Task[]
---@param root_name string
function M.run_task(config_dir, page_manager_fact, all_tasks, root_name)
    if not _status_comp then
        assert(not _status_page)
        assert(not _status_pagegroup)
        _status_comp, _status_page, _status_pagegroup = _create_status_page(page_manager_fact)
    end
    assert(_status_comp and _status_page and _status_pagegroup)
    -- Log task start
    logs.user_log("Task started: " .. root_name, "task")
    local symbols = config.current.window.symbols
    _status_page.set_ui_flags(symbols.waiting)

    _status_comp:add_task(root_name)
    local function report_failure(msg)
        logs.user_log(msg, "task")
        _status_page.set_ui_flags(symbols.failure)
        _status_comp:set_task_status(root_name, "stop", false, msg)
    end

    if #all_tasks == 0 then
        logs.user_log("No tasks found")
        return
    end

    local node_tree, used_tasks, plan_error_msg = _scheduler:generate_task_plan(all_tasks, root_name)
    if not node_tree or not used_tasks then
        report_failure(plan_error_msg or "Failed to build task plan")
        return
    end

    logs.user_log("Scheduling tasks:\n" .. print_task_tree(node_tree))

    for _, task in ipairs(used_tasks) do
        if task.name ~= root_name then
            _status_comp:add_task(task.name)
        end
    end
    _status_pagegroup.activate_page("status")

    local vars, _ = _load_variables(config_dir)
    local ws_dir = wsinfo.get_ws_dir()

    assert(ws_dir)

    -- Build task context
    ---@type loop.TaskContext
    local task_ctx = {
        ws_dir = ws_dir,
        variables = vars or vim.empty_dict()
    }

    -- Resolve macros only on the tasks that will be used
    resolver.resolve_macros(used_tasks, task_ctx, function(resolve_ok, resolved_tasks, resolve_error)
        if not resolve_ok or not resolved_tasks then
            local err_msg = resolve_error or "Failed to resolve macros in tasks"
            report_failure(err_msg)
            return
        end

        -- Check if any task in the chain requires saving buffers
        local needs_save = false
        for _, task in ipairs(resolved_tasks) do
            if task.save_buffers == true then
                needs_save = true
                break
            end
        end

        -- Save workspace buffers if any task requires it
        if needs_save then
            local workspace = require("loop.workspace")
            local saved_count = workspace.save_workspace_buffers()
            if saved_count > 0 then
                logs.user_log(
                    string.format("Saved %d file%s before running task", saved_count, saved_count == 1 and "" or "s"),
                    "save")
            end
        end

        -- Start the real execution
        _scheduler:start(
            resolved_tasks,
            root_name,
            page_manager_fact,
            function() -- on start
                _status_page.set_ui_flags(config.current.window.symbols.running)
            end,
            function(name, event, success, reason) -- on task event
                logs.user_log(("%s: %s"):format(name, reason ~= "" and reason or event), "task")
                _status_comp:set_task_status(name, event, success, reason)
            end,
            function(success, reason) -- on exit
                _status_page.set_ui_flags(success and symbols.success or symbols.failure)
                -- Log task completion
                if success then
                    logs.user_log("Task completed: " .. root_name, "task")
                else
                    local error_msg = reason or "Unknown error"
                    logs.user_log("Task failed: " .. root_name .. " - " .. error_msg, "task")
                end
            end
        )
    end)
end

--- Check if a task plan is currently running or terminating
---@return boolean
function M.have_running_task()
    return _scheduler:is_running() or _scheduler:is_terminating()
end

--- Terminate the currently running task plan (if any)
function M.terminate_tasks()
    if _scheduler:is_running() or _scheduler:is_terminating() then
        _scheduler:terminate()
        logs.user_log("Task terminated by user", "task")
    end
end

return M
