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

---@class loop.dap.session.Args
---@field name string
---@field dap loop.dap.session.Args.DAP
---@field target loop.dap.session.Args.Target
---@field output_handler fun(msg_body:table)
---@field exit_handler fun(code:number)

---@class loop.dap.Session
---@field new fun(self: loop.dap.Session, args:loop.dap.session.Args) : loop.dap.Session
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
    self._output_handler = args.output_handler
    self._on_exit = args.exit_handler

    local cmd_and_args = strtools.cmd_to_string_array(dap.cmd)
    if #cmd_and_args == 0 then
        error("Missing DAP process command")
    end

    local dap_cmd  = cmd_and_args[1]
    local dap_args = { unpack(cmd_and_args, 2) }

    self._base_session = BaseSession:new(name, {
        dap_cmd = dap_cmd, -- dap process
        dap_args = dap_args, -- dap args
        dap_env = dap.env,
        dap_cwd = dap.cwd,
        on_exit = function(code, signal)
            if self._on_exit then
                self._on_exit(code)
            end
        end,
    })

    self._base_session:set_event_handler("output", function(msg_body) self._output_handler(msg_body) end)
    self._base_session:set_event_handler("initialized", function() self._fsm:trigger("initialized") end)
    self._base_session:set_event_handler("stopped", function() self._fsm:trigger("stopped") end)

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

function Session:_send_initialize(on_response)
    self._base_session:request_initialize({}, function(response)
        if response and response.body and response.body.__lldb and response.body.__lldb.version then
            if response.body.__lldb.version:match("Apple") then
                self.log:info("detecting apple lldb")
                self.is_apple_lldb = true
            end
        end
        on_response(response.success)
    end)
end

function Session:_send_configuration(on_response)
    local breakpoints = {} --TODO
    for file, bps in pairs(breakpoints) do
        self.log:debug('sending breakpoints for file: ' .. file .. ": " .. vim.inspect(bps))
        self._base_session:request_setBreakpoints({
                source = {
                    name = vim.fn.fnamemodify(file, ":t"),
                    path = file
                },
                breakpoints = bps
            },
            function( --[[response]])
                -- breakpoints_response(response.success)    // send the status to the user
            end)
    end
    self._base_session:request_configurationDone(function(response)
        on_response(response.success)
    end)
end

function Session:_send_launch(on_response, pre_initialize)
    if pre_initialize then
        if not self.is_apple_lldb then
            on_response(true)
            return
        end
    else
        if self.is_apple_lldb then
            on_response(true)
            return
        end
    end
    if self.launched then
        self.log:error("Unexpected launch request")
        on_response(false)
        return
    end
    self.launched                    = true
    local target                     = self._target
    local target_program, targe_args = strtools.get_program_and_args(target.cmd)
    self.log:info('launching: ' .. vim.inspect(target))
    self._base_session:request_launch({
            program = target_program,
            args = targe_args,
            cwd = target.cwd,
            env = target.env,
            -- runInTerminal = true, -- TODO
            stopOnEntry = false,
        },
        function(response)
            on_response(response.success)
        end)
end

function Session:_send_terminate()
    self._base_session:request_terminate(function(response)
        if response.success then
            self._fsm:trigger("resp_terminate_ok")
        else
            self.log:log("DAP termination error: " .. response.message)
            self._fsm:trigger("resp_terminate_err")
        end
    end)
end

function Session:_send_disconnect()
    self._base_session:request_disconnect(function(response)
        if response.success then
            self._fsm:trigger("resp_disconnect_ok")
        else
            self.log:log("DAP termination error: " .. response.message)
            self._fsm:trigger("resp_disconnect_err")
        end
    end)
end

function Session:_kill()
    self._base_session.kill()
end

function Session:current_state()
    return self._fsm.current
end

return Session
