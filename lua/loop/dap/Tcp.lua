-- Tcp.lua
local uv = require('luv')
local class = require('loop.tools.class')

---@class loop.dap.Tcp.Opts
---@field host string
---@field port number
---@field on_output fun(data:string, is_stderr:boolean|nil)
---@field on_exit fun()

---@class loop.dap.Tcp
---@field new fun(self: loop.dap.Tcp, name:string, opts:loop.dap.Tcp.Opts): loop.dap.Tcp
local Tcp = class()

---@param name string
---@param opts loop.dap.Tcp.Opts
function Tcp:init(name, opts)
    assert(type(opts.host) == "string", "host required")
    assert(type(opts.port) == "number", "port required")

    self.name = name
    self.host = opts.host
    self.port = opts.port
    self.on_output = opts.on_output
    self.on_exit = opts.on_exit
    self.exited = false
    self.killed = false
    self.socket = uv.new_tcp()

    -- Resolve host → IP if it's not already an IP address
    self:_resolve_and_connect()
    return self
end

-- Internal: resolve host and connect
function Tcp:_resolve_and_connect()
    local host = self.host

    -- Fast path: already an IP address (IPv4 or IPv6)
    if uv.net.is_ip(host) then
        self.ip = host
        self:_connect()
        return
    end

    -- Otherwise: resolve hostname
    self.log:debug("Resolving host: " .. host)
    uv.getaddrinfo(host, nil, { family = "inet" }, function(err, res)
        if err or not res or #res == 0 then
            self.log:error("Failed to resolve host '" .. host .. "': " .. (err or "no addresses"))
            if self.on_exit then
                vim.schedule(function()
                    self.on_exit(1, 0)
                end)
            end
            return
        end

        -- Use first IPv4 address (you can prefer IPv6 if you want)
        local addr = res[1]
        if addr.family == "inet6" then
            for _, r in ipairs(res) do
                if r.family == "inet" then
                    addr = r
                    break
                end
            end
        end

        self.ip = addr.addr
        self.log:info("Resolved " .. host .. " → " .. self.ip)

        -- Now connect using resolved IP
        vim.schedule(function()
            if not self.killed then
                self:_connect()
            end
        end)
    end)
end

-- Optional: graceful shutdown
function Tcp:kill()
    self.killed = true
    if self.socket then
        self.socket:close()
    end
end

function Tcp:_close()
    if not self.exited then
        self.exited = true
        if self.on_exit then
            vim.schedule(function()
                self.on_exit(0, 0)
            end)
        end
    end
end

-------------------------------------------------
-- Connect + read loop
-------------------------------------------------
function Tcp:_connect()
    self.socket:connect(self.host, self.port, function(err)
        if err then
            self:_fail_and_close("connect error: " .. tostring(err))
            return
        end
        self:_start_read()
    end)
end

function Tcp:_start_read()
    self.socket:read_start(function(err, data)
        if err then
            self:_fail_and_close("read error: " .. tostring(err))
            return
        end
        if data and self.on_output then
            -- is_stderr = false (TCP has no stderr)
            self.on_output(data, false)
        end
        if not data then
            -- EOF
            self:_finish()
        end
    end)
end

-------------------------------------------------
-- Writing
-------------------------------------------------
function Tcp:write(data)
    if self.exited then
        return false, "socket closed"
    end
    if not self.socket or self.socket:is_closing() then
        return false, "socket closing"
    end
    self.socket:write(data)
    return true
end

function Tcp:running()
    return self.socket and not self.socket:is_closing()
end

-------------------------------------------------
-- Graceful close + forced kill
-------------------------------------------------
function Tcp:close(timeout)
    if self.exited or self.killed then
        return
    end

    self.killed = true

    if self.socket and not self.socket:is_closing() then
        -- graceful shutdown
        self.socket:shutdown(function()
            self:_finish()
        end)
    end

    -- optional forced close if needed
    if timeout then
        local timer = uv.new_timer()
        timer:start(timeout or 500, 0, function()
            timer:stop()
            timer:close()
            if not self.exited and self.socket and not self.socket:is_closing() then
                self:_force_close()
            end
        end)
    end
end

-------------------------------------------------
-- Helpers
-------------------------------------------------
function Tcp:_finish()
    if self.exited then return end
    self.exited = true
    self:_force_close()
    if self.on_exit then
        pcall(self.on_exit)
    end
end

function Tcp:_fail_and_close(msg)
    if not self.exited then
        self.exited = true
        if self.on_output then
            self.on_output(msg .. "\n", true)
        end
        self:_force_close()
        if self.on_exit then
            pcall(self.on_exit)
        end
    end
end

function Tcp:_force_close()
    if self.socket and not self.socket:is_closing() then
        self.socket:close()
    end
    self.socket = nil
end

return Tcp
