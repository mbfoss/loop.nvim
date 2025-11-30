local class       = require('loop.tools.class')
local config      = require('loop.config')
local Trackers    = require("loop.tools.Trackers")
local Job         = require('loop.job.Job')
local Session     = require('loop.dap.Session')
local TermProc    = require('loop.tools.TermProc')
local selector    = require("loop.selector")
local signs       = require('loop.signs')
local breakpoints = require('loop.dap.breakpoints')

---@alias loop.job.DebugJob.Command "continue"|"step_in"|"step_out"|"step_over"|"terminate"|"terminate_all"


---@class loop.job.debugjob.Tracker
---@field on_exit fun(code : number)|nil
---@field on_trace fun(text:string,level:"error"|"warn"|nil)|nil
---@field on_sess_added fun(id:number,name:string)|nil
---@field on_sess_removed fun(id:number, name:string)|nil
---@field on_sess_state fun(id:number, name:string, data:loop.dap.session.notify.StateData)|nil
---@field on_new_term fun(name:string, bufnr:number)|nil|nil
---@field on_output fun(sess_id:number, sess_name:string, category:string, output:string)|nil
---@field on_thread_pause fun(sess_id:number, sess_name:string, data:loop.dap.session.notify.ThreadData)|nil
---@field on_thread_continue fun(sess_id:number, sess_name:string)|nil

---@class loop.job.DebugJob : loop.job.Job
---@field new fun(self: loop.job.DebugJob, name:string) : loop.job.DebugJob
---@field _sessions table<number,loop.dap.Session>
---@field _last_session_id number
---@field _trackers loop.tools.Trackers<loop.job.debugjob.Tracker>
local DebugJob    = class(Job)

---Initializes the DebugJob instance.
---@param name string
function DebugJob:init(name)
    self._log = require('loop.tools.Logger').create_logger("DebugJob[" .. tostring(name) .. "]")
    ---@type table<number,loop.dap.Session>
    self._sessions = {}
    self._last_session_id = 0
    self._output_pages = {}
    self._stacktrace_pages = {}
    self._trackers = Trackers:new()
end

---@param callbacks loop.job.debugjob.Tracker>
---@return number
function DebugJob:add_tracker(callbacks)
    return self._trackers:add_tracker(callbacks)
end

---@param id number
---@return boolean
function DebugJob:remove_tracker(id)
    return self._trackers:remove_tracker(id)
end

---@return boolean
function DebugJob:is_running()
    return next(self._sessions) ~= nil
end

function DebugJob:kill()
    for _, s in pairs(self._sessions) do
        s:kill()
    end
end

---@class loop.DebugJob.StartArgs
---@field name string
---@field debug_args loop.dap.session.DebugArgs

---Starts a new terminal job.
---@param args loop.DebugJob.StartArgs
---@return boolean, string|nil
function DebugJob:start(args)
    if #self._sessions > 0 then
        return false, "A debug job is already running"
    end
    return self:add_new_session(args.name, args.debug_args)
end

---@param name string
---@param debug_args loop.dap.session.DebugArgs
---@param parent_sess_id number|nil
---@return boolean,string|nil
function DebugJob:add_new_session(name, debug_args, parent_sess_id)
    local session_id      = self._last_session_id + 1
    self._last_session_id = session_id

    ---@param session loop.dap.Session
    ---@param event loop.session.TrackerEvent
    ---@param event_data any
    local tracker         = function(session, event, event_data)
        self:_on_session_event(session_id, session, event, event_data)
    end

    local exit_handler    = function(code)
        self:_session_exit_handler(session_id, code)
    end


    ---@type loop.dap.session.Args
    local session_args = {
        debug_args = debug_args,
        tracker = tracker,
        exit_handler = exit_handler,
    }

    -- start new session
    local session = Session:new(name)

    local started, start_err = session:start(session_args)
    if not started then
        return false, "Failed to start debug session, " .. start_err
    end

    self:_update_allbreakpoints_status()
    self._sessions[session_id] = session

    self._trackers:invoke("on_sess_added", session_id, name)

    return true, nil
end

function DebugJob:_session_exit_handler(session_id, code)
    vim.schedule(function()
        if self._sessions[session_id] then
            local session = self._sessions[session_id]
            self._trackers:invoke("on_sess_removed", session_id, session:name())
            self._sessions[session_id] = nil

            self._trackers:invoke("on_trace",
                "[" .. tostring(session:name()) .. "] debugger exited (code " .. tostring(code) .. ")")

            self:_update_allbreakpoints_status()
            if next(self._sessions) == nil then
                breakpoints.reset_verified_status()
                self._trackers:invoke("on_exit", code)
            end
        end
    end)
end

---@param command loop.job.DebugJob.Command|nil
function DebugJob:debug_command(command)
    local active_session = 1 -- TODO: make this selectable from the UI
    local session = self._sessions[active_session]
    if not session then
        return
    end
    if command == 'continue' then
        for _, s in pairs(self._sessions) do
            s:debug_continue()
        end
    elseif command == "step_in" then
        session:debug_stepIn()
    elseif command == "step_out" then
        session:debug_stepOut()
    elseif command == "step_over" then
        session:debug_stepOver()
    elseif command == "terminate" then
        session:debug_terminate()
    elseif command == "terminate_all" then
        for _, s in pairs(self._sessions) do
            s:debug_terminate()
        end
    else
        self._trackers:invoke("on_trace", 'loop.nvim: Invalid debug command: ' .. tostring(command), "error")
    end
end

---@param sess_id number
---@param session loop.dap.Session
---@param event loop.session.TrackerEvent
---@param event_data any
function DebugJob:_on_session_event(sess_id, session, event, event_data)
    if event == "trace" then
        ---@type loop.dap.session.notify.Trace
        local trace = event_data
        self._trackers:invoke("on_trace", "[" .. tostring(session:name()) .. "] " .. (trace.text or ""), trace.level)
        return
    end
    if event == "state" then
        ---@type loop.dap.session.notify.StateData
        local state = event_data
        self._trackers:invoke("on_sess_state", sess_id, session:name(), state)
        return
    end
    if event == "output" then
        ---@type loop.dap.proto.OutputEvent
        local output = event_data
        if output.category == "stdout" or output.category == "stderr" then
            self:add_debug_output(sess_id, session:name(), output.category, output.output)
        elseif output.category == "console" then
            self._trackers:invoke("on_trace", "[" .. tostring(session:name()) .. "] " .. tostring(output.output))
        elseif output.category ~= "telemetry" then
            self._trackers:invoke("on_trace",
                "[" .. tostring(session:name()) .. "] (" .. tostring(output.category) .. ") " .. tostring(output.output))
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
        self:_on_session_threads_pause(sess_id, session, event_data)
        return
    end
    if event == "threads_continued" then
        self._trackers:invoke("on_thread_continue", sess_id, session:name())
        return
    end
    if event == "breakpoints" then
        ---@type loop.dap.session.notify.BreakpointsEvent
        local data = event_data
        self:_on_session_breakpoints_event(sess_id, session, data)
        return
    end
    if event == "debuggee_exit" then
        self:_on_session_debuggee_exit(sess_id, session)
        return
    end
    if event == "subsession_request" then
        ---@type loop.dap.session.notify.SubsessionRequest
        local request = event_data
        self:_on_subsession_request(sess_id, session, request)
        return
    end
    error("unhandled dap session event: " .. event)
end

---@param sess_id number
---@param sess_name string
---@param category string
---@param output string
function DebugJob:add_debug_output(sess_id, sess_name, category, output)
    self._trackers:invoke("on_output", sess_id, sess_name, category, output)
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

    self._trackers:invoke("on_new_term", name, bufnr)
    local pid = proc:get_pid()
    on_success(pid)
end

---@param sess_id number
---@param session loop.dap.Session
---@param event_data loop.dap.session.notify.ThreadData
function DebugJob:_on_session_threads_pause(sess_id, session, event_data)

    self._trackers:invoke("on_thread_pause", sess_id, session:name(), event_data)
end

---@param sess_id number
---@param session loop.dap.Session
---@param event loop.dap.session.notify.BreakpointsEvent
function DebugJob:_on_session_breakpoints_event(sess_id, session, event)
    for _, state in ipairs(event) do
        self:_update_breakpoint_status(state.id)
    end
end

---@param sess_id number
---@param session loop.dap.Session
function DebugJob:_on_session_debuggee_exit(sess_id, session)
end

---@param sess_id number
---@param session loop.dap.Session
---@param request loop.dap.session.notify.SubsessionRequest
function DebugJob:_on_subsession_request(sess_id, session, request)
    self._log:debug("Starting subsession via startDebugging: " .. vim.inspect(request))

    local ok, err = self:add_new_session(request.name, request.debug_args)
    if not ok then
        return request.on_failure("failed to startup child session, " .. tostring(err))
    end

    request.on_success({})
end

function DebugJob:_update_allbreakpoints_status()
    local ids = breakpoints.get_ids()
    for _, id in ipairs(ids) do
        self:_update_breakpoint_status(id)
    end
end

function DebugJob:_update_breakpoint_status(id)
    local verified = next(self._sessions) == nil
    for _, session in pairs(self._sessions) do
        local state = session:get_breakpoint_state(id)
        verified = verified or (state or false)
    end
    breakpoints.update_verified_status(id, verified)
end

return DebugJob
