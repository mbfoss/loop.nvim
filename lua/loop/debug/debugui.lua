local signs          = require('loop.debug.signs')
local window         = require('loop.window')
local Page           = require('loop.pages.Page')
local OutputPage     = require('loop.pages.OutputPage')
local ItemListPage   = require('loop.pages.ItemListPage')
local VariablesPage  = require('loop.pages.VariablesPage')
local VarWatchPage   = require('loop.pages.VarWatchPage')
local StackTracePage = require('loop.pages.StackTracePage')
local uitools        = require('loop.tools.uitools')
local notifications  = require('loop.notifications')
local TermProc       = require('loop.tools.TermProc')

local M              = {}

---@class loop.debugui.DebugJobData
---@field jobname string
---@field task_page loop.pages.ItemListPage
---@field output_pages loop.pages.OutputPage[]
---@field debugger_output_pages loop.pages.OutputPage[]
---@field stacktrace_pages loop.pages.StackTracePage[]
---@field variable_pages loop.pages.VariablesPage[]
---@field varwatch_page loop.pages.VarWatchPage|nil
---@field command fun(data:loop.debugui.DebugJobData,cmd:loop.job.DebugJob.Command)

---@type loop.debugui.DebugJobData|nil
local _current_job_data

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
---@param parent_id number|nil
---@param controller loop.job.DebugJob.SessionController
local function _on_session_added(jobdata, sess_id, sess_name, parent_id, controller)
    local task_page = jobdata.task_page
    local item = {
        id = sess_id,
        ---@class loop.debugui.TaskPageItemData
        data = {
            name = sess_name,
            state = 'starting',
            controller = controller
        }
    }
    task_page:upsert_item(item)
    if not task_page:get_current_item() then
        task_page:set_current_item(item)
    end
    if not jobdata.varwatch_page then
        jobdata.varwatch_page = VarWatchPage:new(jobdata.jobname)
        window.add_page("varwatch", jobdata.varwatch_page)
    end
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
local function _on_session_removed(jobdata, sess_id, sess_name)
    local task_page = jobdata.task_page
    vim.defer_fn(function()
        task_page:remove_item(sess_id)
    end, 3000)
end

---@param jobdata loop.debugui.DebugJobData
---@param command loop.job.DebugJob.Command
local function _on_debug_command(jobdata, command)
    if command == 'continue_all' or command == "terminate_all" then
        local is_continue = command == 'continue_all'
        for _, item in ipairs(jobdata.task_page:get_items()) do
            ---@type loop.debugui.TaskPageItemData
            local data = item.data
            if data.controller then
                if is_continue then
                    data.controller.continue()
                else
                    data.controller.terminate()
                end
            end
        end
        return
    end
    local item = jobdata.task_page:get_current_item()
    if not item then
        notifications.notify("No debug session selected", vim.log.levels.WARN)
        return
    end
    ---@type loop.debugui.TaskPageItemData
    local data = item.data
    if command == 'continue' then
        data.controller.continue()
    elseif command == "step_in" then
        data.controller.step_in()
    elseif command == "step_out" then
        data.controller.step_out()
    elseif command == "step_over" then
        data.controller.step_over()
    elseif command == "terminate" then
        data.controller.terminate()
    else
        return false, "Invalid debug command: " .. tostring(command)
    end
end

---@param jobdata loop.debugui.DebugJobData
local function _refresh_task_page(jobdata)
    local uiflags = ''
    local items = jobdata.task_page:get_items()
    for _, item in ipairs(items) do
        local flag = ''
        if item.data.state ~= 'ended' then
            if item.data.nb_paused_threads and item.data.nb_paused_threads > 0 then
                flag = '⏸'
            else
                flag = '▶'
            end
        end
        uiflags = uiflags .. flag
    end
    jobdata.task_page:set_ui_flags(uiflags)
    jobdata.task_page:refresh_content()
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
---@param data loop.dap.session.notify.StateData
local function _on_session_state_update(jobdata, sess_id, sess_name, data)
    do
        local item = jobdata.task_page:get_item(sess_id)
        if item then
            item.data.state = data.state
            _refresh_task_page(jobdata)
        end
    end
    if data.state == "ended" then
        signs.remove_signs("currentframe")
        if jobdata.varwatch_page then jobdata.varwatch_page:greyout_content() end
        do
            local stacktrace_page = jobdata.stacktrace_pages[sess_id]
            if stacktrace_page then
                stacktrace_page:greyout_content()
            end
        end
        do
            local variables_page = jobdata.variable_pages[sess_id]
            if variables_page then
                variables_page:greyout_content()
            end
        end
    end
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
---@param category string
---@param output string
local function _on_session_output(jobdata, sess_id, sess_name, category, output)
    ---@type loop.pages.OutputPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page
    if category == "stdout" or category == "stderr" then
        page = jobdata.output_pages[sess_id]
        if not page then
            page = OutputPage:new(sess_name)
            window.add_page("debugoutput", page)
            jobdata.output_pages[sess_id] = page
        end
    else
        page = jobdata.debugger_output_pages[sess_id]
        if not page then
            page = OutputPage:new(sess_name .. ' (debugger)')
            window.add_page("debugoutput", page)
            jobdata.debugger_output_pages[sess_id] = page
        end
    end
    local level = category == "stderr" and "error" or nil
    page:add_line(output, level)
end

---@param jobdata loop.debugui.DebugJobData
---@param name string
---@param args loop.dap.proto.RunInTerminalRequestArguments
---@param cb fun(pid: number|nil, err: string|nil)
local function _on_session_new_term_req(jobdata, name, args, cb)
    local page = Page:new("term", name)
    window.add_page("debugoutput", page)
    local proc = TermProc:new()
    local started, proc_err = proc:start(page:get_or_create_buf(), {
        name = name,
        command = args.args,
        env = args.env,
        cwd = args.cwd,
        on_exit_handler = function(_)
        end,
        output_handler = function(_, _)
            page:send_change_notification()
        end
    })
    if started then
        cb(proc:get_pid(), nil)
    else
        cb(nil, proc_err or "term err")
    end
end

---@param item loop.pages.ItemListPage.Item
local function _debug_session_item_formatter(item)
    local str = item.data.name .. ' - ' .. item.data.state
    if item.data.nb_paused_threads and item.data.nb_paused_threads > 0 then
        local s = item.data.nb_paused_threads > 1 and "s" or ""
        str = str .. (" ( %d paused thread%s)"):format(item.data.nb_paused_threads, s)
    end
    return str
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
---@param event_data loop.dap.session.notify.ThreadData
local function _on_session_thread_pause(jobdata, sess_id, sess_name, event_data)
    ---@type loop.pages.VariablesPage|nil
    local variables_page = jobdata.variable_pages[sess_id]

    ---@type loop.pages.StackTracePage|nil
    local stacktrace_page = jobdata.stacktrace_pages[sess_id]

    do
        local taskpage_item = jobdata.task_page:get_item(sess_id)
        if taskpage_item then
            taskpage_item.data.nb_paused_threads = #event_data.threads
            _refresh_task_page(jobdata)
        end
    end

    if not variables_page then
        variables_page = VariablesPage:new(sess_name)
        window.add_page("variables", variables_page)
        jobdata.variable_pages[sess_id] = variables_page
    end

    if not stacktrace_page then
        stacktrace_page = StackTracePage:new(sess_name)
        window.add_page("stacktrace", stacktrace_page)
        jobdata.stacktrace_pages[sess_id] = stacktrace_page
    end

    if not event_data.thread_id then return end
    local curframe
    -- handle current frame
    event_data.stack_provider({ threadId = event_data.thread_id, levels = 1 }, function(err, data)
        ---@type loop.dap.proto.StackFrame
        curframe = data and data.stackFrames[1] or nil
        if curframe and curframe.source and curframe.source.path then
            signs.place_file_sign(curframe.source.path, curframe.line, "currentframe", "currentframe")
            uitools.smart_open_file(curframe.source.path, curframe.line, curframe.column)
        end
        if curframe then
            variables_page:load_variables(event_data, curframe)
            -- update variable watchchers
            if jobdata.varwatch_page then
                jobdata.varwatch_page:update_data(event_data, curframe)
            end
        end
    end)
    -- handle stack trace page
    stacktrace_page:set_content(event_data)
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
local function _on_session_thread_continue(jobdata, sess_id, sess_name)
    ---@type loop.pages.VariablesPage|nil
    local variables_page = jobdata.variable_pages[sess_id]
    ---@type loop.pages.StackTracePage|nil
    local stacktrace_page = jobdata.stacktrace_pages[sess_id]
    signs.remove_signs("currentframe")
    do
        local taskpage_item = jobdata.task_page:get_item(sess_id)
        if taskpage_item then
            taskpage_item.data.nb_paused_threads = 0
            _refresh_task_page(jobdata)
        end
    end
    if jobdata.varwatch_page then
        jobdata.varwatch_page:greyout_content()
    end
    if variables_page then
        variables_page:greyout_content()
    end
    if stacktrace_page then
        stacktrace_page:greyout_content()
    end
end

---@param task_name string -- task name
---@return loop.job.debugjob.Tracker
function M.track_new_debugjob(task_name)
    assert(type(task_name) == "string")

    ---@type loop.debugui.DebugJobData
    local jobdata = {
        jobname = task_name,
        task_page = ItemListPage:new(task_name, {
            formatter = _debug_session_item_formatter,
            show_current_prefix = true,
        }),
        output_pages = {},
        debugger_output_pages = {},
        stacktrace_pages = {},
        variable_pages = {},
        command = function(jobdata, cmd)
            _on_debug_command(jobdata, cmd)
        end
    }

    _current_job_data = jobdata

    window.add_page("debug", jobdata.task_page)

    ---@type loop.job.debugjob.Tracker
    local tracker = {
        on_sess_added = function(id, name, parent_id, controller)
            _on_session_added(jobdata, id, name, parent_id, controller)
        end,
        on_sess_removed = function(id, name)
            _on_session_removed(jobdata, id, name)
        end,
        on_sess_state = function(sess_id, name, data)
            _on_session_state_update(jobdata, sess_id, name, data)
        end,
        on_output = function(sess_id, sess_name, category, output)
            _on_session_output(jobdata, sess_id, sess_name, category, output)
        end,

        on_new_term = function(name, args, cb)
            _on_session_new_term_req(jobdata, name, args, cb)
        end,

        on_thread_pause = function(sess_id, sess_name, thread_data)
            _on_session_thread_pause(jobdata, sess_id, sess_name, thread_data)
        end,
        on_thread_continue = function(sess_id, sess_name)
            _on_session_thread_continue(jobdata, sess_id, sess_name)
        end,

        on_exit = function(code)
            _current_job_data = nil
        end
    }
    return tracker
end

---@param command loop.job.DebugJob.Command|nil
function M.debug_command(command)
    local job = _current_job_data
    if not job then
        notifications.notify("No active debug task", vim.log.levels.WARN)
        return
    end
    if not command then
        notifications.notify("Debug command missing", vim.log.levels.WARN)
        return
    end
    job.command(job, command)
end

return M
