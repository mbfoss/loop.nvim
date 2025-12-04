local M = {}

---@class loop.tools.ProcessInfo
---@field pid number
---@field name string

--- Returns a table of running processes: { pid = number, name = string }[]
--- Works on Linux, macOS, and Windows.
--- Falls back gracefully if some fields are unavailable.
---@return loop.tools.ProcessInfo[]
function M.get_running_processes()
    local processes = {}
    local handle

    local is_windows = package.config:sub(1, 1) == "\\" or os.getenv("OS") == "Windows_NT"

    if is_windows then
        -- Windows: use `wmic` or `tasklist` (wmic is more reliable in Lua)
        handle = io.popen('wmic process get ProcessId,Name /format:list 2>nul')
        if not handle then return processes end

        local current_pid, current_name
        for line in handle:lines() do
            if line:match("^Name=") then
                current_name = line:match("^Name=(.+)$") or line:match("^Name=(.*)$")
            elseif line:match("^ProcessId=") then
                current_pid = tonumber(line:match("^ProcessId=(%d+)$"))
                if current_pid and current_name then
                    table.insert(processes, {
                        pid = current_pid,
                        name = current_name:gsub("%s+$", ""), -- trim
                    })
                    current_pid = nil
                    current_name = nil
                end
            end
        end
    else
        -- Linux & macOS: use `ps`
        local cmd = "ps -e -o pid= -o comm= 2>/dev/null || ps -A -o pid= -o comm= 2>/dev/null"
        handle = io.popen(cmd)
        if not handle then return processes end

        for line in handle:lines() do
            local pid_str, name = line:match("^%s*(%d+)%s+(.+)$")
            if not pid_str then
                pid_str, name = line:match("^%s*(%d+)%s+(.-)%s*$")
            end
            local pid = tonumber(pid_str)
            if pid and name then
                table.insert(processes, {
                    pid = pid,
                    name = name,
                })
            end
        end
    end

    if handle then handle:close() end
    return processes
end

-- Example usage:
-- local procs = get_running_processes()
-- for _, p in ipairs(procs) do
--   print(p.pid, p.name)
-- end

return M
