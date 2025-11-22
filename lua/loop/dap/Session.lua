local class = require('loop.tools.class')
local strtools = require('loop.tools.strtools')

local BaseSession = require("loop.dap.BaseSession")
local FSM = require("loop.tools.FSM")

local fsmdata = require('loop.dap.fsmdata')
local strtools = require('loop.tools.strtools')

---@class loop.dap.session.notify.LogData
---@field level nil|"log"|"error"
---@field lines string[]

---@class loop.dap.session.Args.DAP
---@field name string
---@field cmd string|string[]
---@field env table<string,string>|nil
---@field cwd string
---@
---@class loop.dap.session.Args.Target
---@field name string
---@field cmd string|string[]
---@field env table<string,string>|nil
---@field cwd string
---@field run_in_terminal boolean
---@field stop_on_entry boolean

---@alias loop.session.TrackerEvent 
---|"log"
---|"state"
---|"output"
---|"runInTerminal_request"
---|"threads"
---|"stacktrace"
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
local Session = class()

function Session:init()
    self._started = false
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

    local stderr_handler = function (text)
        ---@type loop.dap.session.notify.LogData
        local data = { level = "error", lines = { "dap process error", text} }
        self:_notify_tracker("log", data)
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

---@return fun(response:any)
function Session:_simple_qery_resp_handler()
    return function(response)
        if not response.success then
            ---@type loop.dap.session.notify.LogData
            local data = { level = "error", lines = { "'" .. response.command .. "' error", response.message } }
            self:_notify_tracker("log", data)
        end
    end
end

---@return string
function Session:state()
    local state = self._process_ended and "ended" or self._fsm:curr_state()
    return state
end

function Session:debug_continue()
    self._base_session:request_continue({threadId = 0}, self:_simple_qery_resp_handler())
end

function Session:debug_stepIn()
    self._base_session:request_stepIn({threadId = 0}, self:_simple_qery_resp_handler())
end

function Session:debug_stepOut()
    self._base_session:request_stepOut({threadId = 0}, self:_simple_qery_resp_handler())
end

function Session:debug_stepBack()
    self._base_session:request_stepBack({threadId = 0}, self:_simple_qery_resp_handler())
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
    self._fsm:trigger("dap_stopped", event)
end

function Session:_on_initializing_state()
    local req_args = {
        adapterID = self._dap_name or "unknown",
        linesStartAt1 = true,
        columnsStartAt1 = true,
        pathFormat = "path",
    }
    self._base_session:request_initialize(req_args, function(response)
        if response.success and response.body then
            self._capabilities = response.body
        end
        if response and response.body and response.body.__lldb ~= nil then
            if vim.fn.has("mac") == 1 then
                self.log:info("macos lldb")
                self._is_macos_lldb = true
            end
        end
        local success_trigger = self._is_macos_lldb and "initialize_resp_ok_macos_lldb" or "initialize_resp_ok"
        self._fsm:trigger(response.success and success_trigger or "initialize_resp_err")
    end)
end

function Session:_on_configuring_state()
    local breakpoints = {} --TODO
    local nb_breakpoints = vim.tbl_count(breakpoints)
    local nb_success = 0
    local nb_failures = 0
    local success_trigger = self._is_macos_lldb and "configure_success_macos_lldb" or "configure_success"

    if nb_breakpoints == 0 then
        self._base_session:request_configurationDone(function(configdone_resp)
            self._fsm:trigger(configdone_resp.success and success_trigger or "configure_error")
        end)
        return
    end

    for file, bps in pairs(breakpoints) do
        self.log:debug('sending breakpoints for file: ' .. file .. ": " .. vim.inspect(bps))
        self._base_session:request_setBreakpoints({
                source = {
                    name = vim.fn.fnamemodify(file, ":t"),
                    path = file
                },
                breakpoints = bps
            },
            function(set_bp_resp)
                if set_bp_resp.success == true then
                    nb_success = nb_success + 1
                else
                    nb_failures = nb_failures + 1
                end
                if nb_success == nb_breakpoints then
                    self._base_session:request_configurationDone(function(configdone_resp)
                        self._fsm:trigger(configdone_resp.success and success_trigger or "configure_error")
                    end)
                elseif nb_failures > 0. and nb_success + nb_failures == nb_breakpoints then
                    self._fsm:trigger("configure_error")
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
        self._fsm:trigger("launch_resp_error")
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
        function(response)
            local success_trigger = self._is_macos_lldb and "launch_resp_ok_macos_lldb" or "launch_resp_ok"
            self._fsm:trigger(response.success and success_trigger or "launch_resp_error")
        end)
end

function Session:_on_running_state()
    self:_notify_about_state()
end

function Session:_on_disconnecting_state()
    self:_notify_about_state()
end

---@param trigger string
---@param trigger_data any
function Session:_on_stopped_state(trigger, trigger_data)
    self:_notify_about_state()
    if trigger == "dap_stopped" then
        ---@type loop.dap.proto.StoppedEvent   
        local stopped_event = trigger_data     
        self._base_session:request_threads(function(response)
            if not response.success then
                ---@type loop.dap.session.notify.LogData
                local logdata = { level = "error", lines = { "Failed to query threads", response.message } }
                self:_notify_tracker("log", logdata)
                return
            end
            ---@type loop.dap.proto.ThreadsResponse
            local data = response.body
            self:_notify_tracker("threads", data)
        end)
        self._base_session:request_stackTrace({
             threadId = stopped_event.threadId,  
             levels = 100, --TODO: make configurable
        },function(response)
            if not response.success then
                ---@type loop.dap.session.notify.LogData
                local logdata = { level = "error", lines = { "Failed to query stack trace", response.message } }
                self:_notify_tracker("log", logdata)
                return
            end
            ---@type loop.dap.proto.StackTraceResponse
            local data = response.body
            self:_notify_tracker("stacktrace", data)
        end)        
    end
end

return Session
