local class = require('loop.tools.class')
local strtools = require('loop.tools.strtools')

local BaseSession = require("loop.dap.BaseSession")
local FSM = require("loop.tools.FSM")

local fsmdata = require('loop.dap.fsmdata')
local breakpoints = require('loop.dap.breakpoints')

---@class loop.dap.session.SourceBPData
---@field user_data loop.dap.SourceBreakpoint
---@field verified boolean
---@field dap_id number|nil

---@class loop.dap.session.SourceBreakpointsData
---@field by_location table<string, table<number, loop.dap.session.SourceBPData>>
---@field by_usr_id table<number, loop.dap.session.SourceBPData>
---@field by_dap_id table<number, loop.dap.session.SourceBPData>
---@field pending_files table<string,boolean>

---@class loop.dap.session.notify.LogData
---@field level nil|"warn"|"error"
---@field lines string[]


---@class loop.dap.session.notify.BreakpointState
---@field id number
---@field verified boolean
---@field removed boolean|nil

---@alias loop.dap.session.notify.BreakpointsEvent loop.dap.session.notify.BreakpointState[]

---@class loop.dap.session.Args.DAP
---@field type "local"|"remote"
---@field host string|nil
---@field port number|nil
---@field name string
---@field cmd string|string[]|nil
---@field env table<string,string>|nil
---@field cwd string|nil
---@field configure_post_launch boolean|nil

---@alias loop.session.TrackerEvent
---|"log"
---|"state"
---|"output"
---|"runInTerminal_request"
---|"threads_paused"
---|"threads_continued"
---|"breakpoints"
---|"debuggee_exit"
---|"subsession_request"
---@alias loop.session.Tracker fun(session:loop.dap.Session, event:loop.session.TrackerEvent, args:any)

---@class loop.dap.session.DebugArgs
---@field dap          loop.dap.session.Args.DAP
---@field request      "launch" | "attach"          -- mandatory
---@field launch_args  loop.dap.proto.LaunchRequestArguments | nil                   -- used only for launch
---@field attach_args  loop.dap.proto.AttachRequestArguments | nil                   -- used only for attach
---@field terminate_debuggee boolean|nil

---@class loop.dap.session.Args
---@field name string
---@field debug_args loop.dap.session.DebugArgs|nil
---@field tracker loop.session.Tracker
---@field exit_handler fun(code:number)

---@class loop.dap.Session
---@field new fun(self: loop.dap.Session) : loop.dap.Session
---@field _args loop.dap.session.Args
---@field _dap_configure_post_launch boolean|nil
---@field _capabilities table<string,string>
---@field _output_handler fun(msg_body:table)
---@field _on_exit fun(code:number)
---@field _tracker loop.session.Tracker
---@field _can_sent_breakpoints boolean
---@field _source_breakpoints loop.dap.session.SourceBreakpointsData
---@field _stopped_threads loop.dap.proto.Thread[]|nil
---@field _stopped_thread_id number|nil
---@field _subsession_id number
---@field _breakpoints_tracker_id number
local Session = class()

function Session:init()
    self._started = false
    self._subsession_id = 0

    self._can_sent_breakpoints = false
    self._source_breakpoints = { by_location = {}, by_usr_id = {}, by_dap_id = {}, pending_files = {} }
    self._breakpoints_tracker_id = 0
end

---@param args loop.dap.session.Args
---@return boolean,string|nil
function Session:start(args)
    assert(not self._started)
    self._started = true
    self._args = args

    assert(args.name, "session name require")
    assert(args.debug_args)
    assert(args.debug_args.dap)

    local dap = args.debug_args.dap

    self.log = require('loop.tools.Logger').create_logger("dap.session[" .. args.name .. ']')

    self._dap_configure_post_launch = dap.configure_post_launch

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

    if dap.type ~= "remote" then
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
        self._base_session = BaseSession:new(args.name, {
            dap_mode = "local",
            dap_cmd = dap_cmd,   -- dap process
            dap_args = dap_args, -- dap args
            dap_env = dap.env,
            dap_cwd = dap.cwd,
            on_stderr = stderr_handler,
            on_exit = exit_handler,
        })
    else
        if not dap.host or dap.host == "" or not dap.port then
            return false, "Missing remote DAP host name or port"
        end
        self._base_session = BaseSession:new(args.name, {
            dap_mode = "remote",
            dap_host = dap.host,
            dap_port = dap.port,
            on_stderr = stderr_handler,
            on_exit = exit_handler,
        })
    end

    if not self._base_session:running() then
        return false, "debug adapter initialization error"
    end

    ---@type loop.dap.fsmdata.StateHandlers
    local state_handlers = {
        initializing = function(_, _) self:_on_initializing_state() end,
        waiting_initialized = function(_, _) self:_on_waiting_initialized_state() end,
        configuring1 = function(_, _) self:_on_configuring1_state() end,
        launching = function(_, _) self:_on_launching_state() end,
        configuring2 = function(_, _) self:_on_configuring2_state() end,
        running = function(_, _) self:_on_running_state() end,
        disconnecting = function(_, _) self:_on_disconnecting_state() end,
        kill = function(_, _) self:_on_kill_state() end,
        ended = function(_, _) self:_on_ended_state() end,
    }
    -- start the FSM
    self._fsm = FSM:new(args.name, fsmdata.create_fsm_data(state_handlers))

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

    self._base_session:set_reverse_request_handler("startDebugging",
        function(req_args, on_success, on_failure)
            assert(req_args)
            self:_on_startDebugging_request(req_args, on_success, on_failure)
        end
    )

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
    return self._args.name or "(Unnamed session)"
end

function Session:_start_tracking_breakpoints()
    
    assert(not self._can_sent_breakpoints) 

    if self._breakpoints_tracker_id ~= 0 then
        return
    end
    breakpoints.add_tracker({
        on_added = function (bp)
            self:_set_source_breakpoint(bp)            
        end,
        on_removed = function (bp)
            self:_remove_breakpoint(bp.id)
        end,
         on_all_removed = function ()
            self:_remove_all_breakpoints()
         end
    })
end

function Session:stop_tracking_breakpoints()
    if self._breakpoints_tracker_id ~= 0 then
        local removed = breakpoints.remove_tracker(self._breakpoints_tracker_id)
        assert(removed)
        self._breakpoints_tracker_id = 0
    end
end

---@param breakpoint loop.dap.SourceBreakpoint
function Session:_set_source_breakpoint(breakpoint)
    local data = self._source_breakpoints
    ---@type loop.dap.session.SourceBPData
    local pbdata = { user_data = breakpoint, verified = false, dap_id = nil }
    data.by_usr_id[breakpoint.id] = pbdata
    data.by_location[breakpoint.file] = data.by_location[breakpoint.file] or {}
    data.by_location[breakpoint.file][breakpoint.line] = pbdata
    data.pending_files[breakpoint.file] = true
    if self._can_sent_breakpoints then
        self:_send_pending_breakpoints(function(success) end)
    end
end

---@param id number
function Session:_remove_breakpoint(id)
    local data = self._source_breakpoints
    local bp = data.by_usr_id[id]
    if bp then
        data.by_usr_id[id] = nil
        if bp.dap_id then
            data.by_dap_id[bp.dap_id] = nil
        end
        if data.by_location[bp.user_data.file] then
            local byline = data.by_location[bp.user_data.file]
            byline[bp.user_data.line] = nil
            if next(byline) == nil then
                data.by_location[bp.user_data.file] = nil
            end
        end
        data.pending_files[bp.user_data.file] = true
    end
    if self._can_sent_breakpoints then
        self:_send_pending_breakpoints(function(success) end)
    end
end

function Session:_remove_all_breakpoints()
    local data = self._source_breakpoints
    for file,_ in pairs(data.by_location) do 
        data.pending_files[file] = true
    end
    data.by_location = {}
    data.by_usr_id = {}
    data.by_dap_id = {}
end

---@param id number
---@return boolean|nil
function Session:get_breakpoint_state(id)
    local bp = self._source_breakpoints.by_usr_id[id]
    return bp and bp.verified or nil
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

---@type fun(sef:loop.dap.Session, req_args, on_success:fun(resp_body:any), on_failure:fun(reason:string))
function Session:_on_startDebugging_request(req_args, on_success, on_failure)
    self._subsession_id = self._subsession_id + 1
    local name = self:name() .. '/' .. tostring(self._subsession_id)
    ---@class loop.dap.session.notify.SubsessionRequest
    local data = {
        name = name,
        dap_config = vim.deepcopy(self._args.debug_args.dap),
        dap_request = req_args,
        on_success = on_success,
        on_failure = on_failure
    }
    self:_notify_tracker("subsession_request", data)
end

---@param event loop.dap.proto.OutputEvent|nil
function Session:_on_output_event(event)
    self:_notify_tracker("output", event)
end

function Session:_on_initialized_event(event)
    self._fsm:trigger(fsmdata.trigger.initialized)
end

---@param event loop.dap.proto.StoppedEvent|nil
function Session:_on_stopped_event(event)
    local cur_state = self._fsm:curr_state()
    if cur_state == "disconnecting" or cur_state == "kill" or cur_state == "ended" then
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
    local dapid = event.breakpoint.id
    if not dapid then return end
    local bp = self._source_breakpoints.by_dap_id[dapid]
    if bp then
        bp.verified = event.breakpoint.verified
        local removed = event.reason == "removed"
        ---@type loop.dap.session.notify.BreakpointsEvent
        local data = { { id = bp.user_data.id, verified = bp.verified, removed = removed } }
        self:_notify_tracker("breakpoints", data)
        if removed then
            self._source_breakpoints.by_dap_id[dapid] = nil
        end
    end
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

---@param on_complete fun(success:boolean)
function Session:_send_initialize(on_complete)
    local req_args = {
        linesStartAt1 = true,
        columnsStartAt1 = true,
        pathFormat = "path",
        supportsStartDebuggingRequest = true,
        supportsRunInTerminalRequest = true,
        supportsArgsCanBeInterpretedByShell = false,
        supportsANSIStyling = true
    }
    self._base_session:request_initialize(req_args, function(err, resp)
        if resp then
            self._capabilities = resp
            if not self._dap_configure_post_launch then
                -- heureustic
                ---@diagnostic disable-next-line: undefined-field
                local is_lldb = resp.__lldb ~= nil
                if is_lldb and vim.fn.has("mac") == 1 then
                    self.log:info("macos lldb")
                    self._dap_configure_post_launch = true
                end
            end
            on_complete(true)
        else
            self:_notify_about_log("error", { "initialize request error", tostring(err) })
            on_complete(false)
        end
    end)
end

---@param on_complete fun(success:boolean)
function Session:_send_attach(on_complete)
    local target = self._args.debug_args
    assert(target)

    if target.request ~= "attach" then
        on_complete(true)
        return
    end

    assert(target.attach_args)
    self.log:info('attaching: ' .. vim.inspect(target.attach_args))
    self._base_session:request_attach(target.attach_args, function(err) on_complete(err == nil) end)
end

function Session:_on_initializing_state()
    self:_start_tracking_breakpoints() -- must be done before _can_sent_breakpoints = true

    local on_complete = function(success)
        self._fsm:trigger(success and
            fsmdata.trigger.initialize_resp_ok or
            fsmdata.trigger.initialize_resp_err)
    end

    self:_send_initialize(function(success)
        on_complete(success)
    end)
end

function Session:_on_waiting_initialized_state()
    self:_notify_about_state()
    -- workaround for macos lldb (intialized not sent)
    local is_lldb = self._capabilities.__lldb ~= nil
    if is_lldb and vim.fn.has("mac") == 1 then
        self.log:info("macos lldb")
        self._dap_configure_post_launch = true
        self._fsm:trigger(fsmdata.trigger.initialized)
    end
end

---@param on_complete fun(success:boolean)
function Session:_send_configuration(on_complete)
    self._can_sent_breakpoints = true
    self:_send_pending_breakpoints(function(bpts_ok)
        if bpts_ok then
            self:_send_configurationDone(on_complete)
        else
            on_complete(false)
        end
    end)
end

function Session:_on_configuring1_state()
    local on_complete = function(success)
        self._fsm:trigger(success and
            fsmdata.trigger.configure1_success or
            fsmdata.trigger.configure1_error)
    end
    self:_send_attach(function(attach_ok)
        if not attach_ok then
            on_complete(false)
            return
        end
        if self._dap_configure_post_launch == true then
            on_complete(true)
            return
        end
        self:_send_configuration(on_complete)
    end)
end

function Session:_on_configuring2_state()
    local on_complete = function(success)
        self._fsm:trigger(success and fsmdata.trigger.configure2_success or fsmdata.trigger.configure2_error)
    end

    if self._dap_configure_post_launch == true then
        self:_send_configuration(on_complete)
    else
        on_complete(true)
    end
end

---@param on_complete fun(success:boolean)
function Session:_send_pending_breakpoints(on_complete)
    
    if not self._can_sent_breakpoints then
        self.log:debug('cannot send breakpoints')
        on_complete(false)
        return
    end

    local nb_sources = vim.tbl_count(self._source_breakpoints.pending_files)
    local nb_success = 0
    local nb_failures = 0

    if nb_sources == 0 then
        on_complete(true)
        return
    end

    for file, _ in pairs(self._source_breakpoints.pending_files) do
        self._source_breakpoints.pending_files[file] = nil

        ---@type loop.dap.proto.SourceBreakpoint[]
        local dap_breakpoints = {}
         ---@type loop.dap.session.SourceBPData[]
        local originals = {}
        do
            local lines = self._source_breakpoints.by_location[file]
            if lines then
                for line, bp in pairs(lines) do
                    ---@type loop.dap.proto.SourceBreakpoint
                    local dapbp = {
                        line = bp.user_data.line,
                        column = bp.user_data.column,
                        condition = bp.user_data.condition,
                        hitCondition = bp.user_data.hitCondition,
                        logMessage = bp.user_data.logMessage
                    }
                    table.insert(dap_breakpoints, dapbp)
                    table.insert(originals, bp)
                end
            end
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
                if resp then
                    for idx, bp in ipairs(resp.breakpoints) do
                        assert(bp.id)
                        local original = originals[idx]
                        original.verified = bp.verified
                        original.dap_id = bp.id
                        self._source_breakpoints.by_dap_id[bp.id] = original
                    end
                    ---@type loop.dap.session.notify.BreakpointsEvent
                    local data = {}
                    for _, bp in ipairs(originals) do
                        ---@type loop.dap.session.notify.BreakpointState
                        state = { id = bp.user_data.id, verified = bp.verified }
                        table.insert(data, state)
                    end
                    self:_notify_tracker("breakpoints", data)
                end

                if err == nil and resp then
                    nb_success = nb_success + 1
                else
                    nb_failures = nb_failures + 1
                    self:_notify_about_log("error", { "failed to set breakpoints", err or "" })
                end
                if nb_success == nb_sources then
                    on_complete(true)
                elseif nb_failures > 0 and nb_success + nb_failures == nb_sources then
                    on_complete(false)
                end
            end)
    end
end

---@param on_complete fun(success:boolean)
function Session:_send_configurationDone(on_complete)
    self._base_session:request_configurationDone(function(err, _)
        on_complete(err == nil)
    end)
end

function Session:_on_launching_state()
    local target = self._args.debug_args
    assert(target)

    if target.request ~= "launch" then
        self._fsm:trigger(fsmdata.trigger.launch_resp_ok)
        return
    end

    --vim.notify(vim.inspect(target.launch_args))
    if not target.launch_args or next(target.launch_args) == nil then
        -- node-js subsession have empty launch request
        -- launch should not be sent
        self._fsm:trigger(fsmdata.trigger.launch_resp_ok)
        return
    end

    assert(target.launch_args)
    self.log:info('launching: ' .. vim.inspect(target))
    self._base_session:request_launch(target.launch_args,
        function(err)
            self._fsm:trigger(err == nil and fsmdata.trigger.launch_resp_ok or fsmdata.trigger.launch_resp_error)
        end)
end

function Session:_on_running_state()
    self:_notify_about_state()
end

function Session:_on_disconnecting_state()
    local terminate_debuggee = self._args.debug_args.terminate_debuggee

    self._can_sent_breakpoints = false
    self._stopped_threads = {}
    self:_notify_about_state()
    self._base_session:request_disconnect({
        terminateDebuggee = terminate_debuggee
    }, function(err, body)
        self._fsm:trigger(err == nil and fsmdata.trigger.disconnect_resp_ok or fsmdata.trigger.disconnect_resp_err)
    end)
end

function Session:_on_kill_state()
    self._can_sent_breakpoints = false
    self:stop_tracking_breakpoints()
    self._stopped_threads = {}
    self:_notify_about_state()
    self._base_session:kill()
end

function Session:_on_ended_state()
    self._can_sent_breakpoints = false
    self:stop_tracking_breakpoints()
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
end

return Session
