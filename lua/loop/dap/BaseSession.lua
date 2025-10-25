local Channel = require("loop.dap.Channel")

local class = require('loop.tools.class')
local BaseSession = class()

---@class loop.dap.BaseSession.Opts
---@field dap_cmd string
---@field dap_args string[]|nil
---@field dap_env string[]|nil
---@field dap_cwd string
---@field on_exit fun(code:number, signal:number)

---@param name string
---@param opts loop.dap.BaseSession.Opts
function BaseSession:init(name, opts)
    self.log = require('loop.tools.Logger').create_logger("dap.basicsession[" .. name .. ']')
    self.request_seq = 0 -- incrementing request sequence number
    self.callbacks = {}  -- map request sequence -> callback function
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

    -- Create DAP channel
    self.channel = Channel:new(name, channel_opts)

    return self
end

function BaseSession:_kill()
    self.channel.kill()
end

--- Register a per-event handler (e.g., "stopped", "output")
---@param event_name string
---@param handler fun(msg_body:table)
function BaseSession:set_event_handler(event_name, handler)
    assert(not self.event_handlers[event_name], "another handler exists for events " .. event_name)
    self.event_handlers[event_name] = handler
end

--- Register a reverse request handler (e.g., "runInTerminal")
-- @param command string
-- @param handler function(arguments) => body
function BaseSession:set_reverse_request_handler(command, handler)
    assert(not self.event_handlers[command], "another handler exists for command " .. command)
    self.reverse_request_handlers[command] = handler
end

-- Private: handle parsed DAP messages
function BaseSession:_on_message(msg)
    if msg.type == "event" then
        self:_handle_event(msg)
    elseif msg.type == "response" then
        self:_handle_resp(msg)
    elseif msg.type == "request" then
        local ok, result_or_err = self:_handle_rev_req(msg)
        self:_response(msg.command, msg.seq, ok, result_or_err)
    else
        self.log:log("Unknown DAP message type:", msg.type)
    end
end

function BaseSession:_handle_event(msg)
    local handler = self.event_handlers[msg.event]
    if not handler then
        self.log:log("Unhandled DAP event: " .. msg.event)
        return
    end
    local cb_error = function(err)
        self.log:error("In event handler for " .. (msg.event or "?") .. "\n" .. debug.traceback(
            "Error: " .. tostring(err) .. "\n", 2))
    end
    local ok, _ = xpcall(function() handler(msg.body) end, cb_error)
    if not ok then
        self.log:error({ "Error in event handler for ", msg.event })
    end
end

function BaseSession:_handle_resp(msg)
    local cb = self.callbacks[msg.request_seq]
    if not cb then
        self.log:log("Unhandled DAP response: " .. msg.command)
        return
    end
    local cb_error = function(err)
        self.log:error("In response handler for " .. (msg.command or "?") .. "\n" .. debug.traceback(
            "Error: " .. tostring(err) .. "\n", 2))
    end
    self.callbacks[msg.request_seq] = nil
    local ok, _ = xpcall(function() cb(msg) end, cb_error)
    if not ok then
        self.log:error({ "Error in response handler for ", msg.command })
    end
end

function BaseSession:_handle_rev_req(msg)
    local handler = self.reverse_request_handlers[msg.command]
    local ok = false
    local result_or_err = nil
    if handler then
        local cb_error = function(err)
            self.log:error("In rev-request handler for " .. (msg.command or "?") .. "\n" .. debug.traceback(
                "Error: " .. tostring(err) .. "\n", 2))
        end
        ok, _ = xpcall(function() handler(msg.arguments) end, cb_error)
        if not ok then
            self.log:error({ "Error in response handler reverse request ", msg.command })
        end
    else
        ok = false
        result_or_err = "No handler for reverse request: " .. tostring(msg.command)
    end
    return ok, result_or_err
end

--- Public: send a DAP request
-- @param command string
-- @param arguments table
-- @param callback function(response)
function BaseSession:_request(command, arguments, callback)
    self.request_seq = self.request_seq + 1
    -- Register the callback
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

--- Public: terminate the debug adapter process
-- @param signal string (default: "sigterm")
function BaseSession:kill(signal)
    self.process:kill(signal or "sigterm")
end

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

function BaseSession:request_launch(args, callback)
    self:_request("launch", args, callback)
end

function BaseSession:request_attach(args, callback)
    self:_request("attach", args, callback)
end

function BaseSession:request_disconnect(args, callback)
    self:_request("disconnect", args or { restart = false }, callback)
end

function BaseSession:request_terminate(callback)
    self.base_session:terminate()
    if callback then callback() end
end

function BaseSession:request_configurationDone(callback)
    self:_request("configurationDone", nil, callback)
end

function BaseSession:request_setBreakpoints(args, callback)
    self:_request("setBreakpoints", args, callback)
end

function BaseSession:request_setFunctionBreakpoints(args, callback)
    self:_request("setFunctionBreakpoints", args, callback)
end

function BaseSession:request_setExceptionBreakpoints(args, callback)
    self:_request("setExceptionBreakpoints", args, callback)
end

function BaseSession:request_threads(callback)
    self:_request("threads", nil, callback)
end

function BaseSession:request_stackTrace(args, callback)
    self:_request("stackTrace", args, callback)
end

function BaseSession:request_scopes(args, callback)
    self:_request("scopes", args, callback)
end

function BaseSession:request_variables(args, callback)
    self:_request("variables", args, callback)
end

function BaseSession:request_continue(args, callback)
    self:_request("continue", args, callback)
end

function BaseSession:request_pause(args, callback)
    self:_request("pause", args, callback)
end

function BaseSession:request_next(args, callback)
    self:_request("next", args, callback)
end

function BaseSession:request_stepIn(args, callback)
    self:_request("stepIn", args, callback)
end

function BaseSession:request_stepOut(args, callback)
    self:_request("stepOut", args, callback)
end

function BaseSession:request_evaluate(args, callback)
    self:_request("evaluate", args, callback)
end

function BaseSession:request_source(args, callback)
    self:_request("source", args, callback)
end

function BaseSession:request_setVariable(args, callback)
    self:_request("setVariable", args, callback)
end

function BaseSession:request_restart(args, callback)
    self:_request("restart", args, callback)
end

function BaseSession:request_restartFrame(args, callback)
    self:_request("restartFrame", args, callback)
end

function BaseSession:request_request_goto(args, callback)
    self:_request("goto", args, callback)
end

function BaseSession:request_stepBack(args, callback)
    self:_request("stepBack", args, callback)
end

function BaseSession:request_reverseContinue(args, callback)
    self:_request("reverseContinue", args, callback)
end

function BaseSession:request_setExpression(args, callback)
    self:_request("setExpression", args, callback)
end

function BaseSession:request_loadedSources(args, callback)
    self:_request("loadedSources", args, callback)
end

function BaseSession:request_breakpointLocations(args, callback)
    self:_request("breakpointLocations", args, callback)
end

function BaseSession:request_exceptionInfo(args, callback)
    self:_request("exceptionInfo", args, callback)
end

function BaseSession:request_dataBreakpointInfo(args, callback)
    self:_request("dataBreakpointInfo", args, callback)
end

function BaseSession:request_setDataBreakpoints(args, callback)
    self:_request("setDataBreakpoints", args, callback)
end

function BaseSession:request_readMemory(args, callback)
    self:_request("readMemory", args, callback)
end

function BaseSession:request_writeMemory(args, callback)
    self:_request("writeMemory", args, callback)
end

function BaseSession:request_disassemble(args, callback)
    self:_request("disassemble", args, callback)
end

return BaseSession
