local class = require('loop.tools.class')
local strtools = require('loop.tools.strtools')

local BaseSession = require("loop.dap.BaseSession")
local FSM = require("loop.tools.FSM")

local fsmdata = require('loop.dap.fsmdata')

---@class loop.dap.session.Breakpoint
---@field id number
---@field verified boolean
---@field file string
---@field source_breakpoint loop.dap.proto.SourceBreakpoint

---@alias loop.dap.session.Breakpoints loop.dap.session.Breakpoint[]

---@class loop.dap.session.notify.LogData
---@field level nil|"warn"|"error"
---@field lines string[]

---@class loop.dap.session.notify.BreakpointsEvent
---@field breakpoints loop.dap.session.Breakpoints
---@field removed boolean|nil

---@class loop.dap.session.Args.DAP
---@field name string
---@field cmd string|string[]
---@field env table<string,string>|nil
---@field cwd string

---@class loop.dap.session.Args.Target
---@field name string
---@field cmd string|string[]
---@field env table<string,string>|nil
---@field cwd string
---@field run_in_terminal boolean
---@field stop_on_entry boolean
---@field terminate_on_disconnect boolean|nil

---@alias loop.session.TrackerEvent
---|"log"
---|"state"
---|"output"
---|"runInTerminal_request"
---|"threads_paused"
---|"threads_continued"
---|"breakpoints"
---|"debuggee_exit"
---@alias loop.session.Tracker fun(session:loop.dap.Session, event:loop.session.TrackerEvent, args:any)

---@class loop.dap.session.Args
---@field name string
---@field dap loop.dap.session.Args.DAP
---@field target loop.dap.session.Args.Target
---@field tracker loop.session.Tracker
---@field exit_handler fun(code:number)

---@class loop.dap.Session
---@field new fun(self: loop.dap.Session) : loop.dap.Session
---@field _name string
---@field _target loop.dap.session.Args.Target
---@field _capabilities table<string,string>
---@field _output_handler fun(msg_body:table)
---@field _on_exit fun(code:number)
---@field _tracker loop.session.Tracker
---@field _breakpoints loop.dap.session.Breakpoints
---@field _breakpoints_by_dap_id table<number,loop.dap.session.Breakpoint>
---@field _stopped_threads loop.dap.proto.Thread[]|nil
---@field _stopped_thread_id number|nil
local Session = class()

function Session:init()
    self._started = false
    self._breakpoints = {}
    self._breakpoints_by_dap_id = {}
end

---@param args loop.dap.session.Args
---@return boolean,string|nil
function Session:start(args)
    assert(not self._started)
    self._started = true

    local name = args.name
    local dap = args.dap
    local target = args.target

    assert(name, "session name require")
    assert(dap.cmd, "dap command required")
    assert(target.cmd, "target command required")

    self.log = require('loop.tools.Logger').create_logger("dap.session[" .. name .. ']')

    self._name = name
    self._dap_name = dap.name
    self._target = target
    self._capabilities = {}
    self._process_ended = false
    self._tracker = args.tracker
    self._on_exit = args.exit_handler

    local stderr_handler = function(text)
        self:_notify_about_log("error", { "dap process error", text })
    end

    local exit_handler = function(code, signal)
        vim.schedule(function()
            self._process_ended = true
            self:_notify_about_state()
        end)
        if self._on_exit then
            self._on_exit(code)
        end
    end

    local cmd_and_args = strtools.cmd_to_string_array(dap.cmd)
    if #cmd_and_args == 0 then
        return false, "Missing DAP process command"
    end

    local dap_cmd = vim.fn.exepath(cmd_and_args[1])
    if dap_cmd == "" then
        return false, "Debugger command is not executable: " .. tostring(cmd_and_args[1])
    end

    local dap_args = { unpack(cmd_and_args, 2) }

    assert(dap_cmd ~= "")
    self._base_session = BaseSession:new(name, {
        dap_cmd = dap_cmd,   -- dap process
        dap_args = dap_args, -- dap args
        dap_env = dap.env,
        dap_cwd = dap.cwd,
        on_stderr = stderr_handler,
        on_exit = exit_handler,
    })

    if not self._base_session:running() then
        return false, "Failed to start debuger process: " .. tostring(cmd_and_args[1])
    end

    self._base_session:set_event_handler("module", function() end)
    self._base_session:set_event_handler("output", function(msg_body) self:_on_output_event(msg_body) end)
    self._base_session:set_event_handler("initialized", function(msg_body) self:_on_initialized_event(msg_body) end)
    self._base_session:set_event_handler("stopped", function(msg_body) self:_on_stopped_event(msg_body) end)
    self._base_session:set_event_handler("continued", function(msg_body) self:_on_continued_event(msg_body) end)
    self._base_session:set_event_handler("breakpoint", function(msg_body) self:_on_breakpoint_event(msg_body) end)
    self._base_session:set_event_handler("exited", function(msg_body) self:_on_exited_event(msg_body) end)
    self._base_session:set_event_handler("terminated", function(msg_body) self:_on_terminated_event(msg_body) end)

    self._base_session:set_reverse_request_handler("runInTerminal",
        function(req_args, on_success, on_failure)
            assert(req_args)
            self:_on_runInTerminal_request(req_args, on_success, on_failure)
        end
    )

    -- start the FSM
    self._fsm = FSM:new(name, fsmdata.create_fsm_data(self))
    vim.schedule(function()
        self._fsm:start()
    end)

    return true
end

function Session:kill()
    self._base_session:kill()
end

---@return string
function Session:name()
    return self._name or "(Unnamed session)"
end

---@param breakpoints loop.dap.session.Breakpoints
function Session:set_breakpoints(breakpoints)
    self._breakpoints = breakpoints
end

---@param event loop.session.TrackerEvent
---@param data any
function Session:_notify_tracker(event, data)
    self._tracker(self, event, data)
end

function Session:_notify_about_state()
    local state = self._process_ended and "ended" or self._fsm:curr_state()
    ---@class loop.dap.session.notify.StateData
    local data = { state = state }
    self:_notify_tracker("state", data)
end

---@param level nil|"warn"|"error"
---@param lines string[]
function Session:_notify_about_log(level, lines)
    ---@type loop.dap.session.notify.LogData
    local data = { level = level, lines = lines }
    self:_notify_tracker("log", data)
end

---@return string
function Session:state()
    local state = self._process_ended and "ended" or self._fsm:curr_state()
    return state
end

function Session:debug_continue()
    self._base_session:request_continue({ threadId = 0, singleThread = false },
        function(err, resp)
            if err or not resp then
                self:_notify_about_log("error", { "continue error", tostring(err) })
                return
            end
            if resp.allThreadsContinued == false then
                self:_notify_about_log("error", { "unsupported single thread continue" })
            end
            self._stopped_thread_id = nil
            if self._stopped_threads then
                self._stopped_threads = nil
                self:_notify_tracker("threads_continued")
            end
        end)
end

function Session:debug_stepIn()
    self._base_session:request_stepIn({ threadId = self._stopped_thread_id, singleThread = false }, function(err)
        if err then
            self:_notify_about_log("error", { "stepIn error", tostring(err) })
        end
    end)
end

function Session:debug_stepOut()
    self._base_session:request_stepOut({ threadId = self._stopped_thread_id, singleThread = false }, function(err)
        if err then
            self:_notify_about_log("error", { "stepOut error", tostring(err) })
        end
    end)
end

function Session:debug_stopOver()
    self._base_session:request_next({ threadId = self._stopped_thread_id, granularity = "line" }, function(err)
        if err then
            self:_notify_about_log("error", { "stepOver error", tostring(err) })
        end
    end)
end

function Session:debug_terminate()
    self._fsm:trigger(fsmdata.trigger.disconnect)
end

---@type fun(sef:loop.dap.Session, req_args:table, on_success:fun(resp_body:table), on_failure:fun(reason:string))
function Session:_on_runInTerminal_request(req_args, on_success, on_failure)
    ---@class loop.dap.session.notify.RunInTerminalReq
    local data = {
        ---@type loop.dap.proto.RunInTerminalRequestArguments
        args = req_args,
        on_success = function(pid) on_success({ processId = pid }) end,
        on_failure = on_failure
    }
    self:_notify_tracker("runInTerminal_request", data)
end

---@param event loop.dap.proto.OutputEvent|nil
function Session:_on_output_event(event)
    self:_notify_tracker("output", event)
end

function Session:_on_initialized_event(event)
end

---@param event loop.dap.proto.StoppedEvent|nil
function Session:_on_stopped_event(event)
    if self._fsm:curr_state() ~= "running" then
        self:_notify_about_log("error", { "unexpected stopped event" })
        return
    end
    assert(event)
    self._stopped_thread_id = event.threadId
    if event.allThreadsStopped == false then
        self._stopped_threads = { { id = event.threadId, name = "current" } }
        self:_notify_tracker("threads_paused", { thread_id = event.threadId })
    else
        self._base_session:request_threads(function(err, resp)
            if err or not resp then
                self:_notify_about_log("error", { "Threads query error: " .. tostring(err) })
            elseif resp.threads and type(resp.threads) == "table" and #resp.threads > 0 then
                self._stopped_threads = resp.threads
                self:_notify_tracker("threads_paused", { thread_id = event.threadId })
            end
        end)
    end
end

---@param event loop.dap.proto.ContinuedEvent|nil
function Session:_on_continued_event(event)
    if self._fsm:curr_state() ~= "running" then
        self:_notify_about_log("error", { "unexpected continued event" })
        return
    end
    assert(event)
    if event.allThreadsContinued == false then
        self:_notify_about_log("error", { "unsupported single thread continue" })
    end
    self._stopped_thread_id = nil
    if self._stopped_threads then
        self._stopped_threads = nil
        self:_notify_tracker("threads_continued")
    end
end

---@param event loop.dap.proto.BreakpointEvent|nil
function Session:_on_breakpoint_event(event)
    assert(event and event.breakpoint)
    local breakpoint = self._breakpoints_by_dap_id[event.breakpoint.id]
    if not breakpoint then return end

    local removed = event.reason == "removed"
    ---@type loop.dap.session.notify.BreakpointsEvent
    local data = { breakpoints = { breakpoint }, removed = removed }
    self:_notify_tracker("breakpoints", data)
end

---@param event loop.dap.proto.ExitedEvent|nil
function Session:_on_exited_event(event)
    self:_notify_tracker("debuggee_exit", event)    
end

---@param event loop.dap.proto.TerminatedEvent|nil
function Session:_on_terminated_event(event)
    if not event or event.restart ~= true then
        self._fsm:trigger(fsmdata.trigger.disconnect)
    end
end

function Session:_on_initializing_state()
    local req_args = {
        adapterID = self._dap_name or "unknown",
        linesStartAt1 = true,
        columnsStartAt1 = true,
        pathFormat = "path",
    }
    self._base_session:request_initialize(req_args, function(err, resp)
        if resp then
            self._capabilities = resp.capabilities
            ---@diagnostic disable-next-line: undefined-field
            local is_lldb = resp.__lldb ~= nil
            if is_lldb and vim.fn.has("mac") == 1 then
                self.log:info("macos lldb")
                self._is_macos_lldb = true
            end
        end
        local success_trigger = self._is_macos_lldb and fsmdata.trigger.initialize_resp_ok_macos_lldb or
            fsmdata.trigger.initialize_resp_ok
        self._fsm:trigger(err == nil and success_trigger or fsmdata.trigger.initialize_resp_err)
    end)
end

function Session:_on_configuring_state()

    ---@type table<string, loop.dap.session.Breakpoints>
    local breakpoints_by_source = {}
    for _,bp in ipairs(self._breakpoints) do
        if bp.file and bp.source_breakpoint then
            breakpoints_by_source[bp.file] = breakpoints_by_source[bp.file] or {}
            table.insert(breakpoints_by_source[bp.file], bp)
        end
    end

    local nb_sources = vim.tbl_count(breakpoints_by_source)
    local nb_success = 0
    local nb_failures = 0
    local success_trigger = self._is_macos_lldb and fsmdata.trigger.configure_success_macos_lldb or
        fsmdata.trigger.configure_success

    if nb_sources == 0 then
        self._base_session:request_configurationDone(function(err, resp)
            self._fsm:trigger(err == nil and success_trigger or fsmdata.trigger.configure_error)
        end)
        return
    end

    for file, source_breakpoints in pairs(breakpoints_by_source) do
        ---@type loop.dap.proto.SourceBreakpoint[]
        local dap_breakpoints = {}
        for _,bpts in ipairs(source_breakpoints) do
            table.insert(dap_breakpoints, bpts.source_breakpoint)
        end
        self.log:debug('sending breakpoints for file: ' .. file .. ": " .. vim.inspect(dap_breakpoints))
        self._base_session:request_setBreakpoints({
                source = {
                    name = vim.fn.fnamemodify(file, ":t"),
                    path = file
                },
                breakpoints = dap_breakpoints
            },
            function(err, resp)
                if err == nil and resp then
                    nb_success = nb_success + 1
                else
                    nb_failures = nb_failures + 1
                end
                if nb_success == nb_sources then
                    self._base_session:request_configurationDone(function(config_err)
                        self._fsm:trigger(config_err == nil and success_trigger or fsmdata.trigger.configure_error)
                    end)
                elseif nb_failures > 0. and nb_success + nb_failures == nb_sources then
                    self._fsm:trigger(fsmdata.trigger.configure_error)
                end
                if resp then
                    for idx, bp in ipairs(resp.breakpoints) do
                        self._breakpoints_by_dap_id[bp.id] = source_breakpoints[idx]
                        source_breakpoints[idx].verified = bp.verified
                    end
                    ---@type loop.dap.session.notify.BreakpointsEvent
                    local data = { breakpoints = vim.deepcopy(source_breakpoints) }                    
                    self:_notify_tracker("breakpoints", data)   
                end
            end)
    end
end

function Session:_on_launching_state()
    local target          = self._target
    local cmdparts        = strtools.cmd_to_string_array(target.cmd)
    local target_program  = cmdparts[1]
    local targe_args      = unpack(cmdparts, 2)
    local run_in_terminal = target.run_in_terminal
    local stop_on_entry   = target.stop_on_entry

    if run_in_terminal and not self._capabilities["supportsRunInTerminalRequest"] then
        self.log:error('run_in_terminal not supported by this adapter')
        self._fsm:trigger(fsmdata.trigger.launch_resp_error)
        return
    end

    self.log:info('launching: ' .. vim.inspect(target))
    self._base_session:request_launch({
            adapterID = self._dap_name,
            columnsStartAt1 = true,
            linesStartAt1 = true,
            pathFormat = "path",
            program = target_program,
            args = targe_args,
            cwd = target.cwd,
            env = target.env,
            runInTerminal = run_in_terminal,
            stopOnEntry = stop_on_entry,
        },
        function(err)
            local success_trigger = self._is_macos_lldb and fsmdata.trigger.launch_resp_ok_macos_lldb or
                fsmdata.trigger.launch_resp_ok
            self._fsm:trigger(err == nil and success_trigger or fsmdata.trigger.launch_resp_error)
        end)
end

function Session:_on_running_state()
    self:_notify_about_state()
end

function Session:_on_disconnecting_state()
    self:_notify_about_state()
    self._base_session:request_disconnect({
        terminateDebuggee = self._target.terminate_on_disconnect
    }, function(err, body)
        self._fsm:trigger(err == nil and fsmdata.trigger.disconnect_resp_ok or fsmdata.trigger.disconnect_resp_err)
    end)
end

function Session:_on_kill_state()
    self:_notify_about_state()
    self._base_session:kill()
end

function Session:_on_ended_state()
    self._fsm:trigger(fsmdata.trigger.killed)
end

---@return loop.dap.proto.Thread[]|nil
function Session:stopped_threads()
    return self._stopped_threads
end

---@param thread_id number
---@return boolean
function Session:thread_is_stopped(thread_id)
    if not self._stopped_threads then return false end
    for _, t in ipairs(self._stopped_threads) do
        if thread_id == t.id then
            return true
        end
    end
    return false
end

---@param args loop.dap.proto.StackTraceArguments
---@param callback fun(err: string|nil, body: loop.dap.proto.StackTraceResponse|nil)|nil
function Session:request_stackTrace(args, callback)
    self._base_session:request_stackTrace(args, callback)
    self._base_session:request_stackTrace(args, callback)
end

return Session
