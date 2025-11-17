local class = require('loop.tools.class')
local strtools = require('loop.tools.strtools')

local BaseSession = require("loop.dap.BaseSession")
local FSM = require("loop.tools.FSM")

local fsmdata = require('loop.dap.fsmdata')
local strtools = require('loop.tools.strtools')

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

---@alias loop.session.TrackerEvent "state"|"output"
---@alias loop.session.Tracker fun(event:loop.session.TrackerEvent, args:any)

---@class loop.dap.session.Args
---@field name string
---@field dap loop.dap.session.Args.DAP
---@field target loop.dap.session.Args.Target
---@field tracker loop.session.Tracker
---@field exit_handler fun(code:number)

---@class loop.dap.Session
---@field new fun(self: loop.dap.Session, args:loop.dap.session.Args) : loop.dap.Session
---@field _name string
---@field _target loop.dap.session.Args.Target
---@field _capabilities table<string,string>
---@field _output_handler fun(msg_body:table)
---@field _on_exit fun(code:number)
---@field _tracker loop.session.Tracker
local Session = class()

---@param args loop.dap.session.Args
function Session:init(args)
    local name = args.name
    local dap = args.dap
    local target = args.target

    assert(name, "session name require")
    assert(dap.cmd, "dap command required")
    assert(target.cmd, "target command required")

    self.log = require('loop.tools.Logger').create_logger("dap.session[" .. name .. ']')

    self._name = name
    self._target = target
    self._capabilities = {}
    self._process_ended = false
    self._tracker = args.tracker
    self._on_exit = args.exit_handler

    local exit_handler = function(code, signal)
        vim.schedule(function ()
            self._process_ended = true
            self:_notify_about_state()
        end)
        if self._on_exit then
            self._on_exit(code)
        end
    end

    local cmd_and_args = strtools.cmd_to_string_array(dap.cmd)
    if #cmd_and_args == 0 then
        error("Missing DAP process command")
    end

    local dap_cmd      = cmd_and_args[1]
    local dap_args     = { unpack(cmd_and_args, 2) }

    self._base_session = BaseSession:new(name, {
        dap_cmd = dap_cmd,   -- dap process
        dap_args = dap_args, -- dap args
        dap_env = dap.env,
        dap_cwd = dap.cwd,
        on_exit = exit_handler,
    })

    self._base_session:set_event_handler("module", function() end)
    self._base_session:set_event_handler("output", function(msg_body) self:_on_output_event(msg_body) end)
    self._base_session:set_event_handler("initialized", function(msg_body) self:_on_initialized_event(msg_body) end)
    self._base_session:set_event_handler("stopped", function(msg_body) self:_on_stopped_event(msg_body) end)

    -- start the FSM
    self._fsm = FSM:new(name, fsmdata.create_fsm_data(self))
    vim.schedule(function()
        self._fsm:start()
    end)
end

function Session:kill()
    self._base_session:kill()
end

---@return string
function Session:name()
    return self._name or "(Unnamed session)"
end

---@param event loop.session.TrackerEvent
---@param args any
function Session:_notify_tracker(event, args)
    self._tracker(event, args)
end

---@return string
function Session:state()
    local state = self._process_ended and "ended" or self._fsm:curr_state() 
    return state
end

function Session:_notify_about_state()
    local state = self._process_ended and "ended" or self._fsm:curr_state() 
    self:_notify_tracker("state", { state = state })
end

function Session:_on_output_event(msg_body)
    self:_notify_about_state()
end

function Session:_on_initialized_event(msg_body)
    self:_notify_about_state()
end

function Session:_on_stopped_event(msg_body)
    self:_notify_about_state()
end

function Session:_on_initializing_state()
    self._base_session:request_initialize({}, function(response)
        if response.success and response.body then
            self._capabilities = response.body
        end
        if response and response.body and response.body.__lldb and response.body.__lldb.version then
            if response.body.__lldb.version:match("Apple") then
                self.log:info("detected apple lldb")
                self._is_apple_lldb = true
            end
        end
        local success_trigger = self._is_apple_lldb and "initialize_resp_ok_apple_lldb" or "initialize_resp_ok"
        self._fsm:trigger(response.success and success_trigger or "initialize_resp_err")
    end)
end

function Session:_on_configuring_state()
    local breakpoints = {} --TODO
    local nb_breakpoints = vim.tbl_count(breakpoints)
    local nb_success = 0
    local nb_failures = 0
    local success_trigger = self._is_apple_lldb and "configure_success_apple_lldb" or "configure_success"

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
            program = target_program,
            args = targe_args,
            cwd = target.cwd,
            env = target.env,
            runInTerminal = run_in_terminal,
            stopOnEntry = stop_on_entry,
        },
        function(response)
            local success_trigger = self._is_apple_lldb and "launch_resp_ok_apple_lldb" or "launch_resp_ok"
            self._fsm:trigger(response.success and success_trigger or "launch_resp_error")
        end)
end

function Session:_on_running_state()
    self:_notify_about_state()
end

function Session:_on_disconnecting_state()
    self:_notify_about_state()
end

return Session
