---@meta
---@diagnostic disable: missing-fields

local Channel = require("loop.dap.Channel")
---@alias loop.dap.EventHandler fun(msg_body: table)
---@alias loop.dap.ReverseRequestHandler fun(req_args: table, on_success: fun(resp_body: table), on_failure: fun(reason: string))

local class = require('loop.tools.class')

---@class loop.dap.BaseSession.Opts
---@field dap_cmd string
---@field dap_args string[]|nil
---@field dap_env table<string,string>|nil
---@field dap_cwd string
---@field on_exit fun(code: number, signal: number)

---@class loop.dap.BaseSession
---@field log any
---@field request_seq integer
---@field callbacks table<integer, fun(response: DAP.Response)>
---@field event_handlers table<string, loop.dap.EventHandler>
---@field reverse_request_handlers table<string, loop.dap.ReverseRequestHandler>
---@field channel loop.dap.Channel
local BaseSession = class()

---@param name string
---@param opts loop.dap.BaseSession.Opts
function BaseSession:init(name, opts)
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
        on_exit = opts.on_exit,
    }
    self.channel = Channel:new(name, channel_opts)
    return self
end

---@return boolean
function BaseSession:running()
    return self.channel:running()
end

function BaseSession:_kill()
    self.channel:kill()
end

--- Register a per-event handler (e.g., "stopped", "output")
---@param event_name string
---@param handler loop.dap.EventHandler
function BaseSession:set_event_handler(event_name, handler)
    assert(not self.event_handlers[event_name], "another handler exists for events " .. event_name)
    self.event_handlers[event_name] = handler
end

--- Register a reverse request handler (e.g., "runInTerminal")
---@param command string
---@param handler loop.dap.ReverseRequestHandler
function BaseSession:set_reverse_request_handler(command, handler)
    assert(not self.reverse_request_handlers[command], "another handler exists for command " .. command)
    self.reverse_request_handlers[command] = handler
end

-- Private: handle parsed DAP messages
---@param msg DAP.ProtocolMessage
function BaseSession:_on_message(msg)
    if msg.type == "event" then
        ---@cast msg DAP.Event
        self:_handle_event(msg)
    elseif msg.type == "response" then
        ---@cast msg DAP.Response
        self:_handle_resp(msg)
    elseif msg.type == "request" then
        ---@cast msg DAP.Request
        self:_handle_rev_req(msg)
    else
        self.log:warn("Unknown DAP message type:" .. msg.type)
    end
end

---@param msg DAP.Event
function BaseSession:_handle_event(msg)
    local handler = self.event_handlers[msg.event]
    if not handler then
        self.log:warn("Unhandled DAP event: " .. msg.event)
        return
    end
    local cb_error = function(err)
        self.log:error("In event handler for " .. (msg.event or "?") .. "\n" .. debug.traceback("Error: " .. tostring(err) .. "\n", 2))
    end
    local ok, _ = xpcall(function() handler(msg.body) end, cb_error)
    if not ok then
        self.log:error({ "Error in event handler for ", msg.event })
    end
end

---@param msg DAP.Response
function BaseSession:_handle_resp(msg)
    local cb = self.callbacks[msg.request_seq]
    if not cb then
        self.log:log("Unhandled DAP response: " .. msg.command)
        return
    end
    local cb_error = function(err)
        self.log:error("In response handler for " .. (msg.command or "?") .. "\n" .. debug.traceback("Error: " .. tostring(err) .. "\n", 2))
    end
    self.callbacks[msg.request_seq] = nil
    local ok, _ = xpcall(function() cb(msg) end, cb_error)
    if not ok then
        self.log:error({ "Error in response handler for ", msg.command })
    end
end

---@param msg DAP.Request
function BaseSession:_handle_rev_req(msg)
    local resp_sent = false
    local on_success = function(resp_body)
        if not resp_sent then
            self:_response(msg.command, msg.seq, true, resp_body)
            resp_sent = true
        end
    end
    local on_failure = function(reason)
        if not resp_sent then
            self:_response(msg.command, msg.seq, false, reason)
            resp_sent = true
        end
    end
    local handler = self.reverse_request_handlers[msg.command]
    if not handler then
        on_failure("No handler for reverse request")
        return
    end
    local cb_error = function(err)
        self.log:error("In rev-request handler for " .. (msg.command or "?") .. "\n" .. debug.traceback("Error: " .. tostring(err) .. "\n", 2))
    end
    local ok = xpcall(function() handler(msg.arguments, on_success, on_failure) end, cb_error)
    if not ok then
        on_failure("Error in reverse request handler")
    end
end

---@param command string
---@param arguments table|nil
---@param callback fun(response: DAP.Response)|nil
function BaseSession:_request(command, arguments, callback)
    self.request_seq = self.request_seq + 1
    if callback then
        assert(type(callback) == "function")
        self.callbacks[self.request_seq] = callback
    end
    local request = {
        seq = self.request_seq,
        type = "request",
        command = command,
        arguments = arguments
    }
    self.channel:send_message(request)
end

---@param command string
---@param from_request_seq integer
---@param success boolean
---@param result_or_err table|string|nil
function BaseSession:_response(command, from_request_seq, success, result_or_err)
    self.request_seq = self.request_seq + 1
    local response = {
        type = "response",
        seq = self.request_seq,
        request_seq = from_request_seq,
        command = command,
        success = success
    }
    if success then
        response.body = result_or_err or {}
    else
        response.message = tostring(result_or_err)
    end
    self.channel:send_message(response)
end

function BaseSession:kill()
    self.channel:kill()
end

---@param args DAP.InitializeRequestArguments
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_initialize(args, callback)
    local default_args = {
        adapterID = "adapter",
        linesStartAt1 = true,
        columnsStartAt1 = true,
        pathFormat = "path",
    }
    default_args = vim.tbl_deep_extend("force", default_args, args or {})
    self:_request("initialize", default_args, callback)
end

---@param args table|nil
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_launch(args, callback)
    self:_request("launch", args, callback)
end

---@param args table|nil
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_attach(args, callback)
    self:_request("attach", args, callback)
end

---@param args table|nil
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_disconnect(args, callback)
    self:_request("disconnect", args or { restart = false }, callback)
end

---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_configurationDone(callback)
    self:_request("configurationDone", nil, callback)
end

---@param args DAP.SetBreakpointsArguments
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_setBreakpoints(args, callback)
    self:_request("setBreakpoints", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_setFunctionBreakpoints(args, callback)
    self:_request("setFunctionBreakpoints", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_setExceptionBreakpoints(args, callback)
    self:_request("setExceptionBreakpoints", args, callback)
end

---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_threads(callback)
    self:_request("threads", nil, callback)
end

---@param args DAP.StackTraceArguments
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_stackTrace(args, callback)
    self:_request("stackTrace", args, callback)
end

---@param args DAP.ScopesArguments
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_scopes(args, callback)
    self:_request("scopes", args, callback)
end

---@param args DAP.VariablesArguments
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_variables(args, callback)
    self:_request("variables", args, callback)
end

---@param args DAP.ContinueArguments
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_continue(args, callback)
    self:_request("continue", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_pause(args, callback)
    self:_request("pause", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_next(args, callback)
    self:_request("next", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_stepIn(args, callback)
    self:_request("stepIn", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_stepOut(args, callback)
    self:_request("stepOut", args, callback)
end

---@param args DAP.EvaluateArguments
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_evaluate(args, callback)
    self:_request("evaluate", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_source(args, callback)
    self:_request("source", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_setVariable(args, callback)
    self:_request("setVariable", args, callback)
end

---@param args table|nil
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_restart(args, callback)
    self:_request("restart", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_restartFrame(args, callback)
    self:_request("restartFrame", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_request_goto(args, callback)
    self:_request("goto", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_stepBack(args, callback)
    self:_request("stepBack", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_reverseContinue(args, callback)
    self:_request("reverseContinue", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_setExpression(args, callback)
    self:_request("setExpression", args, callback)
end

---@param args table|nil
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_loadedSources(args, callback)
    self:_request("loadedSources", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_breakpointLocations(args, callback)
    self:_request("breakpointLocations", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_exceptionInfo(args, callback)
    self:_request("exceptionInfo", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_dataBreakpointInfo(args, callback)
    self:_request("dataBreakpointInfo", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_setDataBreakpoints(args, callback)
    self:_request("setDataBreakpoints", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_readMemory(args, callback)
    self:_request("readMemory", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_writeMemory(args, callback)
    self:_request("writeMemory", args, callback)
end

---@param args table
---@param callback fun(response: DAP.Response)|nil
function BaseSession:request_disassemble(args, callback)
    self:_request("disassemble", args, callback)
end

return BaseSession