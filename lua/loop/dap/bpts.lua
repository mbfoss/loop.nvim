local M = {}

local breakpoints = {}

function M.get_breakpoint_files()
    local files = {}
    for f,_ in pairs(breakpoints) do
        table.insert(files, f)
    end
    return files
end

function M.get_file_breakpoints(file)
    return vim.deepcopy(breakpoints[file])
end

function M.set_file_breakpoints(file, bps)
    breakpoints[file] = vim.deepcopy(bps)
end

function M.remove_file_breakpoints(file)
    breakpoints[file] = nil
end

function M.have_file_breakpoint(file, line)
    local bps = breakpoints[file]
    if not bps then
        return false
    end
    for _, v in pairs(bps) do
        if line == v.line then
            return true
        end
    end
    return false
end

function M.add_file_breakpoint(file, line, condition, hitCondition, logMessage)
    if M.have_file_breakpoint(file, line) then
        return false
    end
    if not breakpoints[file] then
        breakpoints[file] = {}
    end
    table.insert(breakpoints[file], {
        line = line,
        condition = condition,
        hitCondition = hitCondition,
        logMessage = logMessage,
    })
    return true
end

function M.remove_file_breakpoint(file, line)
    local bps = breakpoints[file]
    if not bps then
        return false
    end
    local new_bps = {}
    for _, v in pairs(bps) do
        if v.line ~= line then
            table.insert(new_bps, v)
        end
    end
    breakpoints[file] = new_bps
    return #bps ~= #new_bps
end


return M