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
    assert(type(opts.cmd) == "string", "cmd is required")

    self.cmd = opts.cmd
    self.args = opts.args or {}
    self.cwd = opts.cwd or vim.fn.getcwd()
    self.env = opts.env or {}

    self.env['PWD'] = self.cwd -- required for commands to use cwd in all cases

    self.on_output = opts.on_output
    self.on_exit = opts.on_exit

    self.exited = false
    self.killed = false

    self.stdin = uv.new_pipe(false)
    self.stdout = uv.new_pipe(false)
    self.stderr = uv.new_pipe(false)

    self:_spawn()

    return self
end

-------------------------------------------------
-- Spawn and IO reading
-------------------------------------------------
function Process:_spawn()
    local opts = {
        args = self.args,
        cwd = self.cwd,
        env = self:_env_list(),
        stdio = { self.stdin, self.stdout, self.stderr },
    }

    local handle, pid = uv.spawn(self.cmd, opts, function(code, signal)
        self.exited = true

        -- Stop readers BEFORE closing pipes
        if self.stdout and not self.stdout:is_closing() then
            self.stdout:read_stop()
        end
        if self.stderr and not self.stderr:is_closing() then
            self.stderr:read_stop()
        end

        local exit_err = nil
        -- RUN on_exit callback BEFORE cleanup
        if self.on_exit then
            local ok, err = pcall(self.on_exit, code, signal)
            if not ok then
                exit_err = err -- store for after cleanup
            end
        end

        -- Safe to close all handles now
        self:_close_all()

        if exit_err then
            error(exit_err)
        end
    end)

    assert(handle, "Failed to spawn process")

    self.handle = handle
    self.pid = pid

    -- Start reading stdout
    self.stdout:read_start(function(err, data)
        if err then
            vim.schedule(function() error(err) end)
            return
        end
        if data and self.on_output then
            self.on_output(data, false)
        end
    end)

    -- Start reading stderr
    self.stderr:read_start(function(err, data)
        if err then
            vim.schedule(function() error(err) end)
            return
        end
        if data and self.on_output then
            self.on_output(data, true)
        end
    end)
end

-- Convert env dict → {"KEY=value", ...}
function Process:_env_list()
    local out = {}
    for k, v in pairs(self.env) do
        table.insert(out, string.format("%s=%s", k, v))
    end
    return out
end

-------------------------------------------------
-- Writing to stdin
-------------------------------------------------
function Process:write(data)
    if self.exited then
        return false, "process exited"
    end
    if not self.stdin or self.stdin:is_closing() then
        return false, "stdin closed"
    end
    self.stdin:write(data)
    return true
end

-------------------------------------------------
-- Graceful kill: term → wait → kill
-------------------------------------------------
function Process:kill(timeout)
    if self.exited or self.killed then
        return
    end

    self.killed = true

    -- 1. Try SIGTERM first
    if self.handle and not self.handle:is_closing() then
        self.handle:kill("sigterm")
    end

    -- 2. Wait for graceful exit
    local timer = uv.new_timer()
    timer:start(timeout or 500, 0, function()
        timer:stop()
        timer:close()
        -- If still alive, SIGKILL it
        if not self.exited and self.handle and not self.handle:is_closing() then
            self.handle:kill("sigkill")
        end
    end)
end

-------------------------------------------------
-- Cleanup handles
-------------------------------------------------
function Process:_close_all()
    local function safe_close(h)
        if h and not h:is_closing() then
            h:close()
        end
    end

    safe_close(self.stdin)
    safe_close(self.stdout)
    safe_close(self.stderr)
    safe_close(self.handle)
end

return Process
