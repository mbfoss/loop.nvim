-- Process.lua
local uv = require('luv')
local class = require('loop.tools.class')

---@class loop.dap.Process.Opts
---@field cmd string
---@field args string[]|nil
---@field env string[]|nil
---@field cwd string
---@field on_output fun(data:string, is_stderr:boolean)
---@field on_exit fun(code:number, signal:number)

---@class loop.dap.Process
---@field new fun(self: loop.dap.Process, name : string, opts : loop.dap.Process.Opts) : loop.dap.Process

local Process = class()

---@param name string
---@param opts loop.dap.Process.Opts
function Process:init(name, opts)
    assert(type(opts.cmd) == "string", "cmd required")
    self.log = require('loop.tools.Logger').create_logger("dap.proc[" .. name .. ']')
    self.cmd = opts.cmd
    self.args = opts.args or {}
    self.env = vim.deepcopy(opts.env or {})
    self.cwd = opts.cwd or vim.fn.getcwd()
    self.on_output = opts.on_output
    self.on_exit = opts.on_exit

    self.env['PWD'] = self.cwd -- required for commands to use cwd in all cases

    self.stdin_pipe = uv.new_pipe(false)
    self.stdout_pipe = uv.new_pipe(false)
    self.stderr_pipe = uv.new_pipe(false)

    self.handle = nil
    self.pid = nil
    self.exited = false

    self:_spawn()

    return self
end

function Process:_spawn()
    local stdio = {
        self.stdin_pipe,
        self.stdout_pipe,
        self.stderr_pipe,
    }

    local spawn_opts = {
        args = self.args,
        stdio = stdio,
        env = self.env,
        cwd = self.cwd,
        detached = false,
    }

    local handle, pid, err = uv.spawn(self.cmd, spawn_opts, function(code, signal)
        self.exited = true
        if self.on_exit then
            self.log:info("process exit");
            self.on_exit(code, signal)
        end
        -- cleanup handles
        self:_close_handles()
    end)

    assert(handle, "Failed to spawn process: " .. tostring(err))

    self.handle = handle
    self.pid = pid

    self:_start_reading()
end

function Process:_start_reading()
    local function read_cb(is_stderr)
        return function(err, data)
            assert(not err, err)
            if data then
                if self.on_output then
                    self.on_output(data, is_stderr)
                end
            else
                -- EOF reached
                if is_stderr then
                    self.stderr_pipe:read_stop()
                    self.stderr_pipe:close()
                else
                    self.stdout_pipe:read_stop()
                    self.stdout_pipe:close()
                end
            end
        end
    end

    self.stdout_pipe:read_start(read_cb(false))
    self.stderr_pipe:read_start(read_cb(true))
end

function Process:_close_handles()
    if self.stdin_pipe and not self.stdin_pipe:is_closing() then
        self.stdin_pipe:close()
    end
    if self.stdout_pipe and not self.stdout_pipe:is_closing() then
        self.stdout_pipe:close()
    end
    if self.stderr_pipe and not self.stderr_pipe:is_closing() then
        self.stderr_pipe:close()
    end
    if self.handle and not self.handle:is_closing() then
        self.handle:close()
    end
end

function Process:write(data)
    assert(not self.exited, "Process has exited, cannot write")
    self.stdin_pipe:write(data)
end

function Process:kill(signal)
    if self.handle and not self.exited then
        self.handle:kill(signal or "sigterm")
    end
    self:_close_handles()
end

return Process
