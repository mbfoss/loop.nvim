local json = (vim and vim.json) or require('dkjson')
local strtools = require("loop.tools.strtools")
local Process = require("loop.dap.Process")

local class = require('loop.tools.class')

---@class loop.dap.Channel
---@field new fun(self: loop.dap.Channel, name:string, opts:table): loop.dap.Channel
local Channel = class()

---@diagnostic disable-next-line: undefined-field

local msg_log_enabled = (vim.env.NVIM_LOOP_PLUGIN_ENBALE_DAP_LOGS == "1")
local msg_log_file = nil

local function log_msg_content(line)
    if msg_log_enabled then
        if not msg_log_file then
            local msg_log_file_path = vim.fs.joinpath(vim.fn.stdpath("log"), "loop.nvim.dap.log")
            msg_log_file = assert(io.open(msg_log_file_path, "w"))
        end
        msg_log_file:write(line)
        msg_log_file:flush()
    end
end

function Channel:init(name, opts)
    self.on_message = opts.on_message -- function(msg: table) called for non-response messages
    self.on_stderr = opts.on_stderr
    assert(type(self.on_message) == "function")
    assert(type(self.on_stderr) == "function")
    self.process = self:_create_process(name, opts)
    return self
end

function Channel:running()
    return self.process:running()
end

function Channel:kill()
    self.process:kill()
end

function Channel:_create_process(name, opts)
    -- used by the uv async thread
    local buffer = {}
    buffer.data = ""

    -- Create the DAP process
    return Process:new(name, {
        cmd = opts.dap_cmd,
        args = opts.dap_args or {},
        env = opts.dap_env,
        cwd = opts.dap_cwd,
        on_output = function(data, is_stderr)
            if not is_stderr then
                self:_on_data(buffer, data)
            elseif self.on_stderr then
                self.on_stderr(tostring(data))
            end
        end,
        on_exit = function(code, signal)
            if opts.on_exit then
                opts.on_exit(code, signal)
            end
        end
    })
end

function Channel:send_message(msg)
    assert(msg)
    if msg_log_enabled then
        log_msg_content("\n========\nSending msg: " .. strtools.to_pretty_str(msg))
    end

    local body, encode_err = json.encode(msg)
    assert(body, encode_err)
    local header = "Content-Length: " .. #body .. "\r\n\r\n"
    local packet = header .. body

    self.process:write(packet)
end

function Channel:_on_data(buffer, data)
    -- Append new incoming data to the buffer
    buffer.data = (buffer.data or "") .. data

    while true do
        -- 1. Locate end of header section
        local header_end = buffer.data:find("\r\n\r\n", 1, true)
        if not header_end then
            -- Header not complete yet
            return
        end

        -- 2. Parse the header
        local header = buffer.data:sub(1, header_end)
        local content_length_str = header:match("Content%-Length:%s*(%d+)")
        if not content_length_str then
            error("Invalid DAP message: missing Content-Length")
        end

        local content_length = tonumber(content_length_str)
        if not content_length or content_length < 0 then
            error("Invalid Content-Length: " .. tostring(content_length_str))
        end

        -- 3. Compute body start and end
        local body_start = header_end + 4 -- 4 bytes for \r\n\r\n
        local body_end = body_start + content_length - 1

        -- 4. Ensure full body is available
        if #buffer.data < body_end then
            -- Wait for the rest of the message
            return
        end

        -- 5. Extract body
        local body = buffer.data:sub(body_start, body_end)

        -- 6. Remove processed message from buffer
        buffer.data = buffer.data:sub(body_end + 1)

        -- 7. Decode the JSON body
        local message, pos, err = json.decode(body)
        if not message or err then
            error("JSON decode error at position " .. tostring(pos) .. ": " .. err)
        end

        if msg_log_enabled then
            log_msg_content("\n========\nReceived msg: " .. strtools.to_pretty_str(message) .. '\n\n')
        end

        -- 8. Dispatch the message (in the nvim main thread)
        self.on_message(message)
    end
end

return Channel
