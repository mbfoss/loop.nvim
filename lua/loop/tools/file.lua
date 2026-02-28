local M = {}

---@param path string
function M.file_exists(path)
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.loop.fs_stat(path)
    return stat and stat.type == "file"
end

---@param path string
function M.dir_exists(path)
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.loop.fs_stat(path)
    return stat and stat.type == "directory"
end

---@param path string
---@return boolean
---@return string|nil
function M.make_dir(path)
    vim.fn.mkdir(path, "p")
    if not vim.fn.isdirectory(path) then
        local errmsg = vim.v.errmsg or ""
        return false, "Failed to create directory: " .. errmsg
    end
    return true
end

---@param filepath string
---@param data string
---@return boolean
---@return string | nil
function M.write_content(filepath, data)
    local fd = io.open(filepath, "w")
    if not fd then
        return false, "Cannot open file for write '" .. filepath or "" .. "'"
    end
    local ok, ret_or_err = pcall(function() fd:write(data) end)
    fd:close()
    return ok, ret_or_err
end

---@param filepath  string
---@return boolean success
---@return string content or error
function M.read_content(filepath)
    local fd = io.open(filepath, "r")
    if not fd then
        return false, "Cannot open file for read '" .. (filepath or "") .. "'"
    end
    local read_ok, content_or_err = pcall(function() return fd:read("*a") end)
    fd:close()
    if not content_or_err then
        return false, "failed to read from file '" .. (filepath or "") .. "'"
    end
    return read_ok, content_or_err
end

---@param path string: Path to the file
---@param opts { max_size: number?, timeout: number? }
---@param callback function: function(err, data)
---@return fun() is_aborted
function M.async_load_text_file(path, opts, callback)
    local max_size = (opts.max_size or 1024) * 1024 -- Default 1MB
    local timeout_ms = opts.timeout or 3000         -- Default 3s

    ---@diagnostic disable-next-line: undefined-field
    local timer = vim.uv.new_timer()
    local fd = nil
    local chunks = {}
    local total_read = 0
    local is_aborted = false

    -- Helper to clean up resources
    local function cleanup()
        if timer and timer:is_active() then
            timer:stop()
            timer:close()
            timer = nil
        end
        if fd then
            ---@diagnostic disable-next-line: undefined-field
            vim.uv.fs_close(fd)
            fd = nil
        end
    end

    -- Timeout logic
    timer:start(timeout_ms, 0, function()
        if not is_aborted then
            is_aborted = true
            vim.schedule(function()
                cleanup()
                callback("Timeout", nil)
            end)
        end
    end)
    
    -- Open the file
    ---@diagnostic disable-next-line: undefined-field
    vim.uv.fs_open(path, "r", 438, function(err, opened_fd)
        if err then
            if is_aborted then return end
            return vim.schedule(function()
                cleanup()
                callback("Could not open file: " .. err, nil)
            end)
        end

        fd = opened_fd

        -- Check file stats for size and binary check
        ---@diagnostic disable-next-line: undefined-field
        vim.uv.fs_fstat(fd, function(stat_err, stat)
            if is_aborted then return end
            if stat_err or is_aborted then return end

            if stat.size > max_size then
                return vim.schedule(function()
                    cleanup()
                    callback("File exceeds max size limit", nil)
                end)
            end

            -- Start recursive chunk reading
            local function read_next_chunk()
                if is_aborted then return end

                ---@diagnostic disable-next-line: undefined-field
                vim.uv.fs_read(fd, 8192, -1, function(read_err, data)
                    if read_err then
                        return vim.schedule(function()
                            cleanup()
                            callback("Read error: " .. read_err, nil)
                        end)
                    end

                    if data and #data > 0 then
                        -- Check for null bytes (basic binary detection)
                        if data:find("\0") then
                            return vim.schedule(function()
                                cleanup()
                                callback("Binary file", nil)
                            end)
                        end

                        table.insert(chunks, data)
                        total_read = total_read + #data
                        read_next_chunk() -- Tail call for next chunk
                    else
                        -- End of file reached successfully
                        vim.schedule(function()
                            local full_content = table.concat(chunks)
                            cleanup()
                            callback(nil, full_content)
                        end)
                    end
                end)
            end

            read_next_chunk()
        end)
    end)

    return function()
        is_aborted = true
        cleanup()
    end
end

return M
