require('loop.dap.proto')

local Channel = require("loop.dap.Channel")

---@alias loop.dap.EventHandler fun(msg_body: table|nil)
---@alias loop.dap.ReverseRequestHandler fun(req_args: table|nil, on_success: fun(resp_body: table), on_failure: fun(reason: string))

local class = require('loop.tools.class')

---@class loop.dap.BaseSession.Opts
---@field dap_cmd string
---@field dap_args string[]|nil
---@field dap_env table<string,string>|nil
---@field dap_cwd string
---@field on_stderr fun(text:string)
---@field on_exit fun(code: number, signal: number)

---@class loop.dap.BaseSession
---@field new fun(self:loop.dap.BaseSession, name:string, opts:loop.dap.BaseSession.Opts) : loop.dap.BaseSession
---@field log any
---@field request_seq integer
---@field callbacks table<integer, fun(response: loop.dap.proto.Response)>
---@field event_handlers table<string, loop.dap.EventHandler>
---@field reverse_request_handlers table<string, loop.dap.ReverseRequestHandler>
---@field channel loop.dap.Channel
local BaseSession = class()

---@param name string
---@param opts loop.dap.BaseSession.Opts
function BaseSession:init(name, opts)
    assert(type(opts.on_stderr) == "function")
    assert(type(opts.on_exit) == "function")
    self.log = require('loop.tools.Logger').create_logger("dap.basicsession[" .. name .. ']')
    self.request_seq = 0
    self.callbacks = {}
    self.event_handlers = {}
    self.reverse_request_handlers = {}
    local channel_opts = {
        dap_cmd = opts.dap_cmd,
        dap_args = opts.dap_args,
        dap_env = opts.dap_env,
        dap_cwd = opts.dap_cwd,
        on_message = function(msg) self:_on_message(msg) end,
        on_stderr = function(text) opts.on_stderr(text) end,
        on_exit = opts.on_exit,
    }
    self.channel = Channel:new(name, channel_opts)
    return self
end

---@return boolean
function BaseSession:running()
    return self.channel:running()
end

function BaseSession:kill()
    self.channel:kill()
end

---@param event_name string
---@param handler loop.dap.EventHandler
function BaseSession:set_event_handler(event_name, handler)
    assert(not self.event_handlers[event_name], "another handler exists for events " .. event_name)
    self.event_handlers[event_name] = handler
end

---@param command string
---@param handler loop.dap.ReverseRequestHandler
function BaseSession:set_reverse_request_handler(command, handler)
    assert(not self.reverse_request_handlers[command], "another handler exists for command " .. command)
    self.reverse_request_handlers[command] = handler
end

---@param msg loop.dap.proto.ProtocolMessage
function BaseSession:_on_message(msg)
    if msg.type == "event" then
        ---@cast msg loop.dap.proto.Event
        self:_handle_event(msg)
    elseif msg.type == "response" then
        ---@cast msg loop.dap.proto.Response
        self:_handle_resp(msg)
    elseif msg.type == "request" then
        ---@cast msg loop.dap.proto.Request
        self:_handle_rev_req(msg)
    else
        self.log:warn("Unknown DAP message type:" .. msg.type)
    end
end

---@param msg loop.dap.proto.Event
function BaseSession:_handle_event(msg)
    local handler = self.event_handlers[msg.event]
    if not handler then
        self.log:warn("Unhandled DAP event: " .. msg.event)
        return
    end
    --- schedule to avoid processing in the fast event context
    vim.schedule(function() 
        local cb_error = function(err)
            self.log:error("Error in event handler for " .. msg.event ..
                debug.traceback("Error: " .. tostring(err) .. "\n", 2))
        end
        xpcall(function() handler(msg.body) end, cb_error)
    end)
end

---@param msg loop.dap.proto.Response
function BaseSession:_handle_resp(msg)
    local cb = self.callbacks[msg.request_seq]
    if not cb then
        self.log:log("Unhandled DAP response: " .. msg.command)
        return
    end
    self.callbacks[msg.request_seq] = nil
    --- schedule to avoid processing in the fast event context
    vim.schedule(function() 
        local error_cb = function(err)
            self.log:error("Error in response handler for " .. tostring(msg.command) ..
                debug.traceback("Error: " .. tostring(err) .. "\n", 2))
        end    
        xpcall(function() cb(msg) end, error_cb)
    end)
end

---@param msg loop.dap.proto.Request
function BaseSession:_handle_rev_req(msg)
    local resp_sent = false
    local send_success = function(body)
        if not resp_sent then
            self:_response(msg.command, msg.seq, true, body)
            resp_sent = true
        end
    end
    local send_failure = function(reason)
        if not resp_sent then
            self:_response(msg.command, msg.seq, false, reason)
            resp_sent = true
        end
    end

    local handler = self.reverse_request_handlers[msg.command]
    if not handler then
        send_failure("No handler registered for reverse request: " .. msg.command)
        return
    end
    --- schedule to avoid processing in the fast event context
    vim.schedule(function() 
        local error_cb = function(err)
            self.log:error("Error in reverse request handler for " .. tostring(msg.command) ..
                debug.traceback("Error: " .. tostring(err) .. "\n", 2))
        end
        local ok = xpcall(function() handler(msg.arguments or {}, send_success, send_failure) end, error_cb)
        if not ok then
            send_failure("Error in reverse request handler")
        end
    end)
end

---@param command string
---@param arguments table|nil
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:_request(command, arguments, callback)
    self.request_seq = self.request_seq + 1
    if callback then
        self.callbacks[self.request_seq] = callback
    end
    local req = {
        seq = self.request_seq,
        type = "request",
        command = command,
        arguments = arguments
    }
    self.channel:send_message(req)
end

---@param command string
---@param from_request_seq integer
---@param success boolean
---@param payload table|string|nil
function BaseSession:_response(command, from_request_seq, success, payload)
    self.request_seq = self.request_seq + 1
    local resp = {
        seq = self.request_seq,
        type = "response",
        request_seq = from_request_seq,
        command = command,
        success = success,
    }
    if success then
        resp.body = payload or {}
    else
        resp.message = tostring(payload)
    end
    self.channel:send_message(resp)
end

-- ===================================================================
-- Public request API – fully typed, VSCode-ready, NO intersections
-- ===================================================================

---@param args loop.dap.proto.InitializeRequestArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_initialize(args, callback)
    self:_request("initialize", args, callback)
end

---@param args loop.dap.proto.LaunchRequestArguments|nil
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_launch(args, callback) self:_request("launch", args, callback) end

---@param args loop.dap.proto.AttachRequestArguments|nil
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_attach(args, callback) self:_request("attach", args, callback) end

---@param args loop.dap.proto.DisconnectArguments|nil
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_disconnect(args, callback)
    self:_request("disconnect", args or { restart = false }, callback)
end

---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_configurationDone(callback) self:_request("configurationDone", nil, callback) end

---@param args loop.dap.proto.SetBreakpointsArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_setBreakpoints(args, callback) self:_request("setBreakpoints", args, callback) end

---@param args loop.dap.proto.SetFunctionBreakpointsArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_setFunctionBreakpoints(args, callback) self:_request("setFunctionBreakpoints", args,
        callback) end

---@param args loop.dap.proto.SetExceptionBreakpointsArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_setExceptionBreakpoints(args, callback) self:_request("setExceptionBreakpoints", args,
        callback) end

---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_threads(callback) self:_request("threads", nil, callback) end

---@param args loop.dap.proto.StackTraceArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_stackTrace(args, callback) self:_request("stackTrace", args, callback) end

---@param args loop.dap.proto.ScopesArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_scopes(args, callback) self:_request("scopes", args, callback) end

---@param args loop.dap.proto.VariablesArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_variables(args, callback) self:_request("variables", args, callback) end

---@param args loop.dap.proto.ContinueArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_continue(args, callback) self:_request("continue", args, callback) end

---@param args loop.dap.proto.PauseArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_pause(args, callback) self:_request("pause", args, callback) end

---@param args loop.dap.proto.NextArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_next(args, callback) self:_request("next", args, callback) end

---@param args loop.dap.proto.StepInArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_stepIn(args, callback) self:_request("stepIn", args, callback) end

---@param args loop.dap.proto.StepOutArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_stepOut(args, callback) self:_request("stepOut", args, callback) end

---@param args loop.dap.proto.StepBackArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_stepBack(args, callback) self:_request("stepBack", args, callback) end

---@param args loop.dap.proto.ReverseContinueArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_reverseContinue(args, callback) self:_request("reverseContinue", args, callback) end

---@param args loop.dap.proto.EvaluateArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_evaluate(args, callback) self:_request("evaluate", args, callback) end

---@param args loop.dap.proto.SourceArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_source(args, callback) self:_request("source", args, callback) end

---@param args loop.dap.proto.SetVariableArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_setVariable(args, callback) self:_request("setVariable", args, callback) end

---@param args loop.dap.proto.SetExpressionArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_setExpression(args, callback) self:_request("setExpression", args, callback) end

---@param args loop.dap.proto.RestartFrameArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_restartFrame(args, callback) self:_request("restartFrame", args, callback) end

---@param args loop.dap.proto.GotoArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_goto(args, callback) self:_request("goto", args, callback) end

---@param args loop.dap.proto.RestartArguments|nil
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_restart(args, callback) self:_request("restart", args, callback) end

---@param args table|nil
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_loadedSources(args, callback) self:_request("loadedSources", args, callback) end

---@param args loop.dap.proto.BreakpointLocationsArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_breakpointLocations(args, callback) self:_request("breakpointLocations", args, callback) end

---@param args loop.dap.proto.ExceptionInfoArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_exceptionInfo(args, callback) self:_request("exceptionInfo", args, callback) end

-- Optional / advanced requests (still perfectly typed)
---@param args loop.dap.proto.DataBreakpointInfoArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_dataBreakpointInfo(args, callback) self:_request("dataBreakpointInfo", args, callback) end

---@param args loop.dap.proto.SetDataBreakpointsArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_setDataBreakpoints(args, callback) self:_request("setDataBreakpoints", args, callback) end

---@param args loop.dap.proto.ReadMemoryArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_readMemory(args, callback) self:_request("readMemory", args, callback) end

---@param args loop.dap.proto.WriteMemoryArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_writeMemory(args, callback) self:_request("writeMemory", args, callback) end

---@param args loop.dap.proto.DisassembleArguments
---@param callback fun(response: loop.dap.proto.Response)|nil
function BaseSession:request_disassemble(args, callback) self:_request("disassemble", args, callback) end

return BaseSession
