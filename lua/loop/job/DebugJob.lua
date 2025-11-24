local class       = require('loop.tools.class')
local config      = require('loop.config')
local Job         = require('loop.job.Job')
local strtools    = require('loop.tools.strtools')
local Session     = require('loop.dap.Session')
local TermProc    = require('loop.tools.TermProc')
local window      = require('loop.window')
local breakpoints = require('loop.breakpoints')
local selector    = require("loop.selector")
local uitools     = require('loop.tools.uitools')
local signs       = require('loop.signs')

---@alias loop.job.DebugJob.Command "continue"|"step_in"|"step_out"|"step_over"

---@class loop.job.DebugJob : loop.job.Job
---@field new fun(self: loop.job.DebugJob) : loop.job.DebugJob
---@field _sessions table<number,loop.dap.Session>
---@field _last_session_id number
---@field _breakpoints table<string,loop.dap.proto.SourceBreakpoint[]>
---@field _task_page loop.pages.OutputPage
---@field _output_pages table<number,loop.pages.OutputPage>
---@field _stacktrace_pages table<number,loop.pages.ItemListPage>
---@field _current_session loop.dap.Session|nil
local DebugJob    = class(Job)

---Initializes the DebugJob instance.
function DebugJob:init()
    ---@type table<number,loop.dap.Session>
    self._sessions = {}
    self._last_session_id = 0
    self._breakpoints = {}
    self._output_pages = {}
    self._stacktrace_pages = {}
end

---@return boolean
function DebugJob:is_running()
    return next(self._sessions) ~= nil
end

function DebugJob:kill()
    for _, s in pairs(self._sessions) do
        s:kill()
    end
    self._sessions = {}
end

---@class loop.DebugJob.StartArgs
---@field name string
---@field debugger loop.dap.session.Args.DAP
---@field target loop.dap.session.Args.Target
---@field on_exit_handler fun(code : number)

---Starts a new terminal job.
---@param args loop.DebugJob.StartArgs
---@return boolean, string|nil
function DebugJob:start(args)
    if #self._sessions > 0 then
        return false, "A debug job is already running"
    end

    assert(args.on_exit_handler)

    local cmd_parts = strtools.cmd_to_string_array(args.target.cmd)
    local name = vim.fn.fnamemodify(cmd_parts[1] or "", ":t")

    if vim.fn.executable(cmd_parts[1]) == 0 then
        return false, "Debug target is not an executable: " .. tostring(cmd_parts[1])
    end

    local session_id = self._last_session_id + 1
    self._last_session_id = session_id

    local function session_exit_handler(code)
        -- this runs in the fast event context, so use schedule
        vim.schedule(function()
            self._sessions[session_id] = nil
            if next(self._sessions) == nil then
                ---no more sessions
                args.on_exit_handler(code)
            end
            if self._task_page then
                self._task_page:add_lines({ "Session " ..
                tostring(session_id) .. " debugger exited (code " .. tostring(code) .. ")" })
            end
        end)
    end

    ---@param session loop.dap.Session
    ---@param event loop.session.TrackerEvent
    ---@param event_data any
    local tracker = function(session, event, event_data)
        self:_on_session_event(session_id, session, event, event_data)
    end

    ---@type loop.dap.session.Args
    local session_args = {
        name = name,
        dap = args.debugger,
        target = args.target,
        tracker = tracker,
        exit_handler = session_exit_handler
    }

    local session = Session:new()
    local started, start_err = session:start(session_args)
    if not started then
        return false, "Failed to start debug session, " .. start_err
    end

    self._sessions[session_id] = session

    session:set_breakpoints(self._breakpoints)

    self._task_page = window.add_debug_task_page(args.name)

    self._task_page:add_lines({ "New debug session started: " ..
    tostring(session_id) .. ' (' .. tostring(args.name) .. ')' })

    return true
end

---@param breakpoints table<string,loop.dap.proto.SourceBreakpoint[]>
function DebugJob:set_breakpoints(breakpoints)
    self._breakpoints = breakpoints
    for _, s in pairs(self._sessions) do
        s:set_breakpoints(breakpoints)
    end
end

---@param command loop.job.DebugJob.Command|nil
function DebugJob:debug_command(command)
    if not self._current_session then
        return
    end
    if command == 'continue' then
        for _, s in pairs(self._sessions) do
            s:debug_continue()
        end
    elseif command == "step_in" then
        self._current_session:debug_stepIn()
    elseif command == "step_out" then
        self._current_session:debug_stepOut()
    elseif command == "step_over" then
        self._current_session:debug_stopOver()
    else
        self._task_page:add_lines({ 'loop.nvim: Invalid debug command: ' .. tostring(command) }, "error")
    end
end

---@param sess_id number
---@param session loop.dap.Session
---@param event loop.session.TrackerEvent
---@param event_data any
function DebugJob:_on_session_event(sess_id, session, event, event_data)
    if event == "log" then
        ---@type loop.dap.session.notify.LogData
        local log = event_data
        self._task_page:add_lines(vim.list_extend({ "Session " .. sess_id .. " " .. log.level }, log.lines))
        return
    end
    if event == "state" then
        ---@type loop.dap.session.notify.StateData
        local state = event_data
        self._task_page:add_lines({ "Session " .. sess_id .. " " .. state.state })
        return
    end
    if event == "output" then
        ---@type loop.dap.proto.OutputEvent
        local output = event_data
        if output.category == "stdout" or output.category == "stderr" then
            self:add_debug_output(sess_id, session:name(), output.category, output.output)
        elseif output.category == "console" then
            self._task_page:add_lines({ "Session " .. tostring(sess_id) .. ": " .. tostring(output.output) })
        else
            self._task_page:add_lines({ "Session " ..
            tostring(sess_id) .. ": (" .. tostring(output.category) .. ") " .. tostring(output.output) })
        end
        return
    end
    if event == "runInTerminal_request" then
        ---@type loop.dap.session.notify.RunInTerminalReq
        local request = event_data
        self:add_debug_term(session:name(), request.args, request.on_success, request.on_failure)
        return
    end
    if event == "threads_paused" then
        self:_on_session_threads_event(sess_id, session, "pause", event_data.thread_id)
        return
    end
    if event == "threads_continued" then
        self:_on_session_threads_event(sess_id, session, "continue")
        return
    end
    if event == "breakpoints" then
        ---@type loop.dap.session.notify.BreakpointsEvent
        local data = event_data
        self:_on_session_breakpoints_event(sess_id, session, data)
        return
    end
    if event == "debuggee_exit" then
            breakpoints.clear_live_breakpoints()
        return
    end
    error("unhandled dap session event: " .. event)
end

---@param sess_id number
---@param sess_name string
---@param category string
---@param output string
function DebugJob:add_debug_output(sess_id, sess_name, category, output)
    ---@type loop.pages.OutputPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = self._output_pages[sess_id]
    if not page then
        page = window.add_debug_output_page(sess_name)
        self._output_pages[sess_id] = page
    end
    local level = category == "stderr" and "error" or nil
    page:add_lines({ output }, level)
end

---@param name string
---@param args loop.dap.proto.RunInTerminalRequestArguments
---@param on_success fun(pid:number)
---@param on_failure fun(reason:string)
function DebugJob:add_debug_term(name, args, on_success, on_failure)
    --vim.notify(vim.inspect{name, args, on_success, on_failure})

    assert(type(name) == "string")
    assert(type(args) == "table")
    assert(type(on_success) == "function")
    assert(type(on_failure) == "function")

    local proc = TermProc:new()
    local bufnr, proc_err = proc:start({
        name = name,
        command = args.args,
        env = args.env,
        cwd = args.cwd,
        on_exit_handler = function(code)
        end
    })
    if bufnr <= 0 then
        on_failure(proc_err or "target startup error")
        return
    end

    local pid = proc:get_pid()
    window.add_debug_term_page(name, bufnr)
    on_success(pid)
end

---@param page loop.pages.ItemListPage
---@param session loop.dap.Session
---@param thread_id number
function DebugJob:load_stack_trace(page, session, thread_id)
    local threads = session:stopped_threads()
    page:set_items({ { id = 0, text = "Loading stack trace..." } })
    window.show_stacktrace()
    session:request_stackTrace({
            threadId = thread_id,
            levels = config.current.debug.stack_levels_limit or 100,
        },
        function(err, resp)
            if not session:thread_is_stopped(thread_id) then
                --probaby continued while we were laoding the stack trace
                return
            end
            if err or not resp then
                page:set_items({
                    { id = 0, text = "Failed to load stack trace" },
                    { id = 1, text = tostring(err) }
                })
                return
            end
            local text = "Thread " .. tostring(thread_id)
            if threads and #threads > 1 then
                text = text .. string.format(" (%s paused threads)", #threads)
            end
            local items = { { id = 0, text = text } }
            for idx, frame in ipairs(resp.stackFrames) do
                if frame.source then
                    text = string.format("%d: %s - %s:%d:%d",
                        frame.id, frame.name, frame.source.name, frame.line, frame.column)
                else
                    text = string.format("%d: %s", frame.id, frame.name)
                end
                ---@type loop.pages.ItemListPage.Item
                local item = { id = idx, text = text, data = frame }
                table.insert(items, item)
            end
            if resp.stackFrames and #resp.stackFrames > 0 then
                local frame = resp.stackFrames[1]
                if frame.source and frame.source.path and frame.line then
                    signs.remove_signs("currentframe")
                    signs.place_file_sign(frame.source.path, frame.line, "currentframe", "currentframe")
                end
            end
            page:set_items(items)
            window.show_stacktrace()
        end)
end

---@param page loop.pages.ItemListPage
---@param session loop.dap.Session
function DebugJob:select_n_load_stacktrace(page, session)
    local threads = session:stopped_threads()
    if not threads then return end
    local choices = {}
    for _, thread in ipairs(threads) do
        ---@type loop.SelectorItem
        local item = {
            label = tostring(thread.id) .. ' - ' .. thread.name,
            data = thread.id,
        }
        table.insert(choices, item)
    end
    selector.select("Select a thread", choices, nil, function(thread_id)
        if thread_id and type(thread_id) == "number" then
            self:load_stack_trace(page, session, thread_id)
        end
    end)
end

---@param sess_id number
---@param session loop.dap.Session
---@param event "pause"|"continue"
---@param thread_id number|nil
function DebugJob:_on_session_threads_event(sess_id, session, event, thread_id)
    ---@type loop.pages.ItemListPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = self._stacktrace_pages[sess_id]
    if not page then
        page = window.add_stacktrace_page(session:name())
        self._stacktrace_pages[sess_id] = page
        page:set_select_handler(function(item)
            ---@type loop.pages.ItemListPage.Item
            if item then
                if item.id == 0 then
                    self:select_n_load_stacktrace(page, session)
                elseif item.data then
                    local data = item.data
                    ---@cast data loop.dap.proto.StackFrame
                    if data.source and data.source.path then
                        uitools.smart_open_file(data.source.path, data.line, data.column)
                    end
                end
            end
        end)
    end
    if event == "pause" then
        self._current_session = session
        if thread_id then
            self:load_stack_trace(page, session, thread_id)
        else
            self:select_n_load_stacktrace(page, session)
        end
    elseif event == "continue" then
        if self._current_session == session then
            self._current_session = nil
        end
        signs.remove_signs("currentframe")
        page:set_items({ { id = 0, text = "No paused threads" } })
    else
        self._task_page:add_lines({ "Unhandled event " .. event }, "error")
    end
end

---@param sess_id number
---@param session loop.dap.Session
---@param event loop.dap.session.notify.BreakpointsEvent
function DebugJob:_on_session_breakpoints_event(sess_id, session, event)
    if event.removed then
        for _, bp in ipairs(event.breakpoints) do
            if bp and bp.source and bp.source.path then
                breakpoints.remove_live_breakpoint(bp.source.path, bp.line)
            end
        end
    else
        for _, bp in ipairs(event.breakpoints) do
            if bp and bp.source and bp.source.path then
                breakpoints.set_live_breakpoint(bp.source.path, bp.line, bp.verified)
            end
        end
    end
end

return DebugJob
