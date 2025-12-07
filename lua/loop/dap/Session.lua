local class = require('loop.tools.class')
local strtools = require('loop.tools.strtools')
local daptools = require('loop.dap.daptools')

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

---@class loop.dap.session.notify.Trace
---@field level nil|"warn"|"error"
---@field text string


---@class loop.dap.session.notify.BreakpointState
---@field breakpoint_id number
---@field verified boolean
---@field removed boolean|nil

---@alias loop.dap.session.notify.BreakpointsEvent loop.dap.session.notify.BreakpointState[]

---@class loop.dap.session.Args.DAP
---@field adapter_id string
---@field type "executable"|"server"
---@field host string|nil
---@field port number|nil
---@field name string
---@field command string|string[]|nil
---@field env table<string,string>|nil
---@field cwd string|nil

---@alias loop.session.TrackerEvent
---|"trace"
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
---@field request      "launch" | "attach"
---@field request_args  loop.dap.proto.AttachRequestArguments|loop.dap.proto.LaunchRequestArguments|nil
---@field launch_post_configure boolean|nil
---@field terminate_debuggee boolean|nil

---@class loop.dap.session.Args
---@field debug_args loop.dap.session.DebugArgs|nil
---@field tracker loop.session.Tracker
---@field exit_handler fun(code:number)

---@class loop.dap.session.notify.SubsessionRequest
---@field name string
---@field debug_args loop.dap.session.DebugArgs
---@field on_success fun(resp_body:any)
---@field on_failure fun(reason:string)

---@class loop.dap.session.notify.StateData
---@field state "initializing"|"starting"|"running"|"disconnecting"|"terminating"|"ended"

---@alias loop.dap.session.StackProvider fun(args:loop.dap.proto.StackTraceArguments, callback:fun(err:string|nil, data: loop.dap.proto.StackTraceResponse | nil))
---@alias loop.dap.session.ScopesProvider fun(args:loop.dap.proto.ScopesArguments, callback:fun(err:string|nil, data: loop.dap.proto.ScopesResponse | nil))
---@alias loop.dap.session.VariablesProvider fun(args:loop.dap.proto.VariablesArguments, callback:fun(err:string|nil, data: loop.dap.proto.VariablesResponse | nil))
---@alias loop.dap.session.EvaluateProvider fun(args:loop.dap.proto.EvaluateArguments, callback:fun(err:string|nil, data: loop.dap.proto.EvaluateResponse | nil))

---@class loop.dap.session.DataProvidersExpiry
---@field expired boolean

---@class loop.dap.session.DataProviders
---@field expiry_info loop.dap.session.DataProvidersExpiry
---@field stack_provider loop.dap.session.StackProvider
---@field scopes_provider loop.dap.session.ScopesProvider
---@field variables_provider loop.dap.session.VariablesProvider
---@field evaluate_provider loop.dap.session.EvaluateProvider

---@class loop.dap.session.notify.ThreadData
---@field thread_id number
---@field threads loop.dap.proto.Thread[]
---@field stack_provider loop.dap.session.StackProvider
---@field scopes_provider loop.dap.session.ScopesProvider
---@field variables_provider loop.dap.session.VariablesProvider
---@field evaluate_provider loop.dap.session.EvaluateProvider

---@class loop.dap.Session
---@field new fun(self: loop.dap.Session, name:string) : loop.dap.Session
---@field _name string
---@field _log loop.tools.Logger
---@field _args loop.dap.session.Args
---@field _capabilities table<string,string>
---@field _output_handler fun(msg_body:table)
---@field _on_exit fun(code:number)
---@field _tracker loop.session.Tracker
---@field _can_send_breakpoints boolean
---@field _source_breakpoints loop.dap.session.SourceBreakpointsData
---@field _stopped_thread number|nil
---@field _stopped_threads loop.dap.proto.Thread[]
---@field _subsession_id number
---@field _breakpoints_tracker_id number
---@field _data_providers loop.dap.session.DataProviders
local Session = class()

---@param name string
function Session:init(name)
    assert(name, "session name require")

    self._name = name
    self._log = require('loop.tools.Logger').create_logger("dap.session[" .. tostring(name) .. "]")

    self._started = false
    self._stopped_threads = {}
    self._subsession_id = 0

    self._can_send_breakpoints = false
    self._source_breakpoints = { by_location = {}, by_usr_id = {}, by_dap_id = {}, pending_files = {} }
    self._breakpoints_tracker_id = 0
end

---@param args loop.dap.session.Args
---@return boolean,string|nil
function Session:start(args)
    assert(not self._started)
    self._started = true
    self._args = args

    assert(args.debug_args)
    assert(args.debug_args.dap)

    local debuggername = args.debug_args.dap.name or "Debugger"

    self._log:debug("Starting - args: " .. vim.inspect(args))

    local dap = args.debug_args.dap

    self._capabilities = {}
    self._process_ended = false
    self._tracker = args.tracker
    self._on_exit = args.exit_handler

    local stderr_handler = function(text)
        self:_trace_notification("[" .. debuggername .. "] " .. tostring(text), "error")
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

    if dap.type ~= "server" then
        local cmd_and_args = strtools.cmd_to_string_array(dap.command)
        if #cmd_and_args == 0 then
            return false, "Missing DAP process command"
        end

        local dap_program = cmd_and_args[1]
        if dap_program == nil or dap_program == "" then
            return false, "Debugger command is missing"
        end

        local dap_path = vim.fn.exepath(dap_program)
        if dap_path == nil or dap_path == "" then
            return false, "Debugger program is not executable: " .. tostring(dap_program)
        end

        local dap_args = { unpack(cmd_and_args, 2) }

        self._base_session = BaseSession:new(self._name)
        self._base_session:start({
            dap_mode = "executable",
            dap_cmd = dap_path,  -- dap process
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
        self._base_session = BaseSession:new(self._name)
        self._base_session:start({
            dap_mode = "server",
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
        starting = function(_, _) self:_on_starting_state() end,
        running = function(_, _) self:_on_running_state() end,
        disconnecting = function(_, _) self:_on_disconnecting_state() end,
        terminating = function(_, _) self:_on_terminating_state() end,
        ended = function(_, _) self:_on_ended_state() end,
    }
    -- start the FSM
    self._fsm = FSM:new(self._name, fsmdata.create_fsm_data(state_handlers))

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
            self:_on_runInTerminal_request(req_args, on_success, on_failure)
        end
    )

    self._base_session:set_reverse_request_handler("startDebugging",
        function(req_args, on_success, on_failure)
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
    return self._name
end

function Session:_start_tracking_breakpoints()
    assert(not self._can_send_breakpoints)

    if self._breakpoints_tracker_id ~= 0 then
        return
    end
    self._breakpoints_tracker_id = breakpoints.add_tracker({
        on_added = function(bp) self:_set_source_breakpoint(bp) end,
        on_removed = function(bp) self:_remove_breakpoint(bp.id) end,
        on_all_removed = function(bpts) self:_remove_all_breakpoints(bpts) end
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
    if self._can_send_breakpoints then
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
    if self._can_send_breakpoints then
        self:_send_pending_breakpoints(function(success) end)
    end
end

---@param bpts loop.dap.SourceBreakpoint[]
function Session:_remove_all_breakpoints(bpts)
    local data = self._source_breakpoints
    for file, _ in pairs(data.by_location) do
        data.pending_files[file] = true
    end
    data.by_location = {}
    data.by_usr_id = {}
    data.by_dap_id = {}
    if self._can_send_breakpoints then
        self:_send_pending_breakpoints(function(success) end)
    end
end

---@param id number
---@return boolean|nil
function Session:get_breakpoint_state(id)
    local bp = self._source_breakpoints.by_usr_id[id]
    if bp then return bp.verified end
    return nil
end

---@param event loop.session.TrackerEvent
---@param data any
function Session:_notify_tracker(event, data)
    self._tracker(self, event, data)
end

function Session:_notify_about_state()
    local state = self._process_ended and "ended" or self._fsm:curr_state()
    ---@type loop.dap.session.notify.StateData
    local data = { state = state }
    self:_notify_tracker("state", data)
end

---@param text string
---@param level nil|"warn"|"error"
function Session:_trace_notification(text, level)
    ---@type loop.dap.session.notify.Trace
    local data = { text = text, level = level }
    self:_notify_tracker("trace", data)
end

---@return string
function Session:state()
    local state = self._process_ended and "ended" or self._fsm:curr_state()
    return state
end

function Session:debug_continue()
    local thread_id = self._stopped_thread
    if not thread_id then
        self._log:debug("no thread to continue")
        return
    end
    self._base_session:request_continue({ threadId = thread_id, singleThread = false },
        function(err, _)
            if err then
                self:_trace_notification("continue error: " .. tostring(err), "error")
                return
            end
            self:_reset_stopped_threads()
            self:_notify_tracker("threads_continued")
        end)
end

function Session:debug_stepIn()
    local thread_id = self._stopped_thread
    if not thread_id then
        self._log:debug("no thread to step-in")
        return
    end
    self._base_session:request_stepIn({ threadId = thread_id, singleThread = false }, function(err)
        if err then
            self:_trace_notification("stepIn error: " .. tostring(err), "error")
        end
    end)
end

function Session:debug_stepOut()
    local thread_id = self._stopped_thread
    if not thread_id then
        self._log:debug("no thread to step-out")
        return
    end
    self._base_session:request_stepOut({ threadId = thread_id, singleThread = false }, function(err)
        if err then
            self:_trace_notification("stepOut error: " .. tostring(err), "error")
        end
    end)
end

function Session:debug_stepOver()
    local thread_id = self._stopped_thread
    if not thread_id then
        self._log:debug("no thread to step-over")
        return
    end
    self._base_session:request_next({ threadId = thread_id, granularity = "line" }, function(err)
        if err then
            self:_trace_notification("stepOver error: " .. tostring(err), "error")
        end
    end)
end

function Session:debug_terminate()
    self._fsm:trigger(fsmdata.trigger.disconnect)
end

---@type fun(sef:loop.dap.Session, req_args:any, on_success:fun(resp_body:table), on_failure:fun(reason:string))
function Session:_on_runInTerminal_request(req_args, on_success, on_failure)
    if not req_args then
        on_failure('missing request args')
        return
    end
    ---@class loop.dap.session.notify.RunInTerminalReq
    local data = {
        ---@type loop.dap.proto.RunInTerminalRequestArguments
        args = req_args,
        on_success = function(pid) on_success({ processId = pid }) end,
        on_failure = on_failure
    }
    self:_notify_tracker("runInTerminal_request", data)
end

---@type fun(sef:loop.dap.Session, req_args: loop.dap.proto.StartDebuggingRequestArguments|nil, on_success:fun(resp_body:any), on_failure:fun(reason:string))
function Session:_on_startDebugging_request(req_args, on_success, on_failure)
    if not req_args then
        on_failure('missing request args')
        return
    end
    self._subsession_id = self._subsession_id + 1
    local name = self:name() .. ':' .. tostring(self._subsession_id)
    ---@type loop.dap.session.notify.SubsessionRequest
    local data = {
        name = name,
        debug_args = {
            dap = vim.deepcopy(self._args.debug_args.dap),
            request = req_args.request,
            request_args = req_args.configuration
        },
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
    self:_send_configuration(function(success)
        if success then
            self._fsm:trigger(fsmdata.trigger.configuration_done)
        else
            self:_trace_notification("session initialization failed", "error")
            self._fsm:trigger(fsmdata.trigger.disconnect)
        end
    end)
end

function Session:_reset_stopped_threads()
    if self._data_providers then
        self._data_providers.expiry_info.expired = true
    end
    self._stopped_thread = nil
    self._stopped_threads = {}
end

---@param event loop.dap.proto.StoppedEvent|nil
function Session:_on_stopped_event(event)
    if not event then
        self._log:error("stopped event with no data")
        return
    end
    local cur_state = self._fsm:curr_state()
    if cur_state == "disconnecting" or cur_state == "terminating" or cur_state == "ended" then
        self._log:error("unexpected stopped event")
        return
    end

    if event.threadId == self._stopped_thread then
        self._log:debug("dropped duplicate stopped event")
        return
    end

    self._stopped_thread = event and event.threadId or nil
    self._data_providers = Session:_create_data_providers(self._base_session)

    self._base_session:request_threads(function(err, resp)
        if err or not resp then
            self._log:error("Threads query error: " .. tostring(err))
        elseif resp.threads and type(resp.threads) == "table" and #resp.threads > 0 then
            ---@type loop.dap.session.notify.ThreadData
            local data = {
                thread_id = event.threadId,
                threads = resp.threads,
                stack_provider = self._data_providers.stack_provider,
                scopes_provider = self._data_providers.scopes_provider,
                variables_provider = self._data_providers.variables_provider,
                evaluate_provider = self._data_providers.evaluate_provider,
            }
            self._stopped_threads = resp.threads
            self:_notify_tracker("threads_paused", data)
        end
    end)
end

---@param event loop.dap.proto.ContinuedEvent|nil
function Session:_on_continued_event(event)
    if self._fsm:curr_state() ~= "running" then
        self._log:error("unexpected continued event")
    end
    self:_reset_stopped_threads()
    self:_notify_tracker("threads_continued")
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
        local data = { { breakpoint_id = bp.user_data.id, verified = bp.verified, removed = removed } }
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
    local adapter_id = self._args.debug_args.dap.adapter_id
    if type(adapter_id) ~= "string" or adapter_id == "" then
        self:_trace_notification("Missing or invalid adapter_id in debugger configuration")
        on_complete(false)
        return
    end
    ---@type loop.dap.proto.InitializeRequestArguments
    local req_args = {
        adapterID = adapter_id,
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
            on_complete(true)
        else
            self._log:error("initialize request error" .. tostring(err))
            on_complete(false)
        end
    end)
end

---@param on_complete fun(success:boolean)
function Session:_send_attach(on_complete)
    local target = self._args.debug_args
    assert(target)
    assert(target.request_args)
    self._log:info('attaching: ' .. vim.inspect(target.request_args))
    ---@type loop.dap.proto.AttachRequestArguments
    ---@diagnostic disable-next-line: assign-type-mismatch
    local attach_args = target.request_args
    self._base_session:request_attach(attach_args, function(err)
        if err then
            ---@type loop.dap.session.notify.Trace
            local data = { text = "attach request failed - " .. tostring(err), level = "error" }
            self:_notify_tracker("trace", data)
        end
        on_complete(err == nil)
    end)
end

---@param on_complete fun(success:boolean)
function Session:_send_launch(on_complete)
    local target = self._args.debug_args
    assert(target)
    assert(target.request_args)
    self._log:info('launching: ' .. vim.inspect(target.request_args))
    ---@type loop.dap.proto.LaunchRequestArguments
    ---@diagnostic disable-next-line: assign-type-mismatch
    local launch_args = target.request_args
    self._base_session:request_launch(launch_args, function(err)
        if err then
            ---@type loop.dap.session.notify.Trace
            local data = { text = "launch request failed - " .. tostring(err), level = "error" }
            self:_notify_tracker("trace", data)
        end
        on_complete(err == nil)
    end)
end

function Session:_on_initializing_state()
    self:_notify_about_state()

    self:_start_tracking_breakpoints() -- must be done before _can_send_breakpoints = true

    local on_complete = function(success)
        if not success then
            self._fsm:trigger(fsmdata.trigger.initialize_resp_err)
            return
        end
        if self._args.debug_args.launch_post_configure ~= true then
            self._fsm:trigger(fsmdata.trigger.start_before_initialized)
        end
    end

    self:_send_initialize(function(success)
        on_complete(success)
    end)
end

---@param on_complete fun(success:boolean)
function Session:_send_configuration(on_complete)
    self._can_send_breakpoints = true
    self:_send_pending_breakpoints(function(bpts_ok)
        if bpts_ok then
            self:_send_configurationDone(on_complete)
        else
            on_complete(false)
        end
    end)
end

---@param on_complete fun(success:boolean)
function Session:_send_pending_breakpoints(on_complete)
    if not self._can_send_breakpoints then
        self._log:debug('cannot send breakpoints')
        on_complete(false)
        return
    end

    local nb_sources = vim.tbl_count(self._source_breakpoints.pending_files)
    local nb_replies = 0
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

        self._log:debug('sending breakpoints for file: ' .. file .. ": " .. vim.inspect(dap_breakpoints))
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
                        local dap_id = bp.id or idx -- some dapters don't sent an id
                        local original = originals[idx]
                        original.verified = bp.verified
                        original.dap_id = dap_id
                        self._source_breakpoints.by_dap_id[dap_id] = original
                    end
                    ---@type loop.dap.session.notify.BreakpointsEvent
                    local data = {}
                    for _, bp in ipairs(originals) do
                        ---@type loop.dap.session.notify.BreakpointState
                        local state = { breakpoint_id = bp.user_data.id, verified = bp.verified }
                        table.insert(data, state)
                    end
                    self:_notify_tracker("breakpoints", data)
                end
                nb_replies = nb_replies + 1
                if err ~= nil or not resp then
                    nb_failures = nb_failures + 1
                    self._log:error("failed to set breakpoints")
                end
                if nb_replies == nb_sources then
                    on_complete(nb_failures == 0)
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

function Session:_on_starting_state()
    self:_notify_about_state()

    local target = self._args.debug_args
    assert(target)

    local on_complete = function(success)
        self._fsm:trigger(success and
            fsmdata.trigger.launch_resp_ok or
            fsmdata.trigger.launch_resp_error)
    end

    if target.request == "launch" then
        self:_send_launch(on_complete)
        return
    end

    if target.request == "attach" then
        self:_send_attach(on_complete)
        return
    end

    self._log:error("handled request type: " .. tostring(target.request))
    on_complete(false)
end

function Session:_on_running_state()
    self:_notify_about_state()
end

function Session:_on_disconnecting_state()
    local terminate_debuggee = self._args.debug_args.terminate_debuggee
    if terminate_debuggee == nil then terminate_debuggee = true end

    self._can_send_breakpoints = false
    self:_notify_about_state()
    self._base_session:request_disconnect({
        terminateDebuggee = terminate_debuggee
    }, function(err, body)
        self._fsm:trigger(err == nil and fsmdata.trigger.disconnect_resp_ok or fsmdata.trigger.disconnect_resp_err)
    end)
end

function Session:_on_terminating_state()
    self._can_send_breakpoints = false
    self:stop_tracking_breakpoints()
    self:_notify_about_state()
    self._base_session:kill()
end

function Session:_on_ended_state()
    self._can_send_breakpoints = false
    self._stopped_threads = {}
    self:stop_tracking_breakpoints()
    self:_notify_about_state()
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

---@param basesession loop.dap.BaseSession
---@return loop.dap.session.DataProviders
function Session:_create_data_providers(basesession)
    ---@type loop.dap.session.DataProvidersExpiry
    local expiry_info = { expired = false }

    ---@type loop.dap.session.StackProvider
    local stack_provider = function(req, callback)
        if expiry_info.expired then
            callback("stale data", nil)
            return
        end
        basesession:request_stackTrace(req, function(err, body)
            if expiry_info.expired then
                callback("stale data", nil)
            else
                callback(err, body)
            end
        end)
    end

    ---@type loop.dap.session.ScopesProvider
    local scopes_provider = function(req, callback)
        if expiry_info.expired then
            callback("stale data", nil)
            return
        end
        basesession:request_scopes(req, function(err, body)
            if expiry_info.expired then
                callback("stale data", nil)
            else
                callback(err, body)
            end
        end)
    end

    ---@type loop.dap.session.VariablesProvider
    local variables_provider = function(req, callback)
        if expiry_info.expired then
            callback("stale data", nil)
            return
        end
        basesession:request_variables(req, function(err, body)
            if expiry_info.expired then
                callback("stale data", nil)
            else
                callback(err, body)
            end
        end)
    end

    ---@type loop.dap.session.EvaluateProvider
    local evaluate_provider = function(req, callback)
        if expiry_info.expired then
            callback("stale data", nil)
            return
        end
        basesession:request_evaluate(req, function(err, body)
            if expiry_info.expired then
                callback("stale data", nil)
            else
                callback(err, body)
            end
        end)
    end

    ---@type loop.dap.session.DataProviders
    return {
        expiry_info = expiry_info,
        stack_provider = stack_provider,
        scopes_provider = scopes_provider,
        variables_provider = variables_provider,
        evaluate_provider = evaluate_provider,
    }
end

return Session
