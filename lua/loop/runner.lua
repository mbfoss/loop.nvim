local M = {}

require('loop.task.taskdef')
local qfparsers = require("loop.task.qfparsers")
local vartools = require('loop.tools.vars')
local TermProc = require('loop.job.TermProc')
local LuaFunc = require('loop.job.LuaFunc')
local window = require('loop.window')

---@class loop.runner.TaskChain
---@field tasks loop.Task[]
---@field interrupted boolean
---@field ended boolean
---@field active_job loop.job.Job|nil
---@field on_complete fun()|nil
---@field next_chain loop.runner.TaskChain|nil

---@type loop.runner.TaskChain|nil
local _current_task_chain = nil

---@param tasks loop.Task[] all available tasks
---@param main loop.Task main task
---@return loop.Task[]|nil list of tasks ordered by dependency or nil if errors
---@return string|nil error message or nil
function M.get_deps_chain(tasks, main)
    if type(tasks) ~= "table" or type(main) ~= "table" then
        return nil, "invalid arguments"
    end
    -- Build a map from task name to task object
    local task_map = {}
    for _, t in ipairs(tasks) do
        if not t.name or t.name == "" then
            return nil, "task with empty name"
        end
        if task_map[t.name] then
            return nil, ("duplicate task name: '%s'"):format(t.name)
        end
        task_map[t.name] = t
    end
    if not main.name or not task_map[main.name] then
        return nil, ("main task '%s' not found"):format(main.name or "<nil>")
    end
    -- Depth-first traversal to resolve dependencies
    local ordered = {}
    local visiting = {} -- stack of currently visiting nodes
    local visited = {}  -- completed tasks
    ---@param task loop.Task
    local function visit(task)
        if visited[task.name] then
            return true
        end
        if visiting[task.name] then
            return false, ("cyclic dependency detected at '%s'"):format(task.name)
        end
        visiting[task.name] = true
        if task.depends_on then
            for _, dep_name in ipairs(task.depends_on) do
                local dep = task_map[dep_name]
                if not dep then
                    return false, ("missing dependency '%s' required by '%s'"):format(dep_name, task.name)
                end
                local ok, err = visit(dep)
                if not ok then return false, err end
            end
        end
        visiting[task.name] = nil
        visited[task.name] = true
        table.insert(ordered, task)
        return true
    end
    local ok, err = visit(main)
    if not ok then return nil, err end
    return ordered, nil
end

---@param line string
---@return string
local function _normalize_string(line)
    --ansi color codes
    local pattern = "\27%[%d*;?%d*;?%d*[mGKHK]"
    line = line:gsub("\r\n?", "\n")
    line = line:gsub(pattern, "")
    return line
end

local function _clear_quickfix()
    vim.fn.setqflist({}, "r")
    --_errors_page:clear()
end

---@param items loop.task.QuickFixItem
local function _add_quickfix_items(items)
    if #items > 0 then
        vim.fn.setqflist(items, "a")
    end
end

---@param task loop.Task
---@return loop.job.Job|nil, string|nil
---@param task_exit_handler fun(exit_code : number)
local function _start_one_task(task, task_exit_handler)
    if not task.command or #task.command == 0 then
        return nil, "Invalid or empty command"
    end

    local tasktype = task.type

    local quickfix_parser
    local parser_context = {}
    local function parse_output_lines(lines)
        if not quickfix_parser then
            return
        end
        local issues = {}
        for _, line in ipairs(lines) do
            local issue = quickfix_parser(_normalize_string(line), parser_context)
            if issue then
                table.insert(issues, issue)
            end
        end
        _add_quickfix_items(issues)
    end

    if task.quickfix_matcher then
        quickfix_parser = qfparsers.get_parser(task.quickfix_matcher)
        if not quickfix_parser then
            return nil, "Invalid quickfix matcher: " .. task.quickfix_matcher
        end
        _clear_quickfix()
    end

    ---@param lines string[]
    local output_handler = function(_, lines)
        parse_output_lines(lines)
    end

    local exit_handler = function(exit_code)
        parse_output_lines({ "" })
        task_exit_handler(exit_code)
    end

    if tasktype == "tool" or tasktype == "app" then
        local buf = window.create_task_buffer()
        if buf == -1 then
            return nil, "No output buffer for task"
        end
        ---@type loop.TermProc.StartArgs
        local args = {
            bufnr = buf,
            name = task.name,
            command = task.command,
            command_env = task.env,
            command_cwd = task.cwd,
            output_handler = output_handler,
            on_exit_handler = exit_handler,
        }
        local job = TermProc:new()
        local ok, err = job:start(args)
        if not ok then
            return nil, err
        end
        return job, nil
    elseif tasktype == "lua" then
        ---@type loop.LuaFunc.StartArgs
        local args = {
            command = task.command,
            on_exit_handler = exit_handler
        }
        local job = LuaFunc:new()
        local ok, err = job:start(args)
        if not ok then
            return nil, err
        end
        return job, nil
    end

    return nil, "Unhandled task type: " .. tasktype
end

---@param tasks loop.Task[]
---@param on_complete fun()|nil
local function _start_task_chain(tasks, on_complete)
    ---@param chain loop.runner.TaskChain
    local function next_job(chain)
        if chain.interrupted or not chain.tasks or #chain.tasks == 0 then
            chain.ended = true
            if chain.on_complete then
                chain.on_complete()
            end
            vim.schedule(function()
                if chain.next_chain then
                    _current_task_chain = chain.next_chain
                    next_job(chain.next_chain)
                elseif chain == _current_task_chain then
                    _current_task_chain = nil
                end
            end)
            return
        end

        local task = table.remove(chain.tasks, 1)
        local job, job_err = _start_one_task(task, function(exit_code)
            if type(exit_code) ~= "number" then
                window.add_events({ "Invalid task status for " .. task.name })
                chain.interrupted = true
            elseif exit_code == 0 then
                window.add_events({ "Task ended: " .. task.name })
            else
                local action = chain.interrupted and "interrupted" or "failed"
                chain.interrupted = true -- set after checking, to distinguish requested interruption
                window.add_events({ "Task " ..
                action .. ": " .. task.name .. ', exit code: ' .. tostring(exit_code) })
            end
            vim.schedule(function()
                if chain == _current_task_chain then
                    next_job(chain)
                end
            end)
        end)

        if job then
            chain.active_job = job
            ---@diagnostic disable-next-line: param-type-mismatch
            local cmd_descr = type(task.command) == 'table' and table.concat(task.command, ' ') or task.command
            window.add_events({ "Running " .. task.type .. " task", "  " .. cmd_descr })
            window.show_task_output()
        else
            window.add_events({ "Task creation failed: " .. task.name, "  " .. tostring(job_err) })
            chain.interrupted = true
            vim.schedule(function()
                if chain == _current_task_chain then
                    next_job(chain)
                end
            end)
        end
    end

    ---@type loop.runner.TaskChain
    local new_chain = {
        tasks = tasks,
        interrupted = false,
        ended = false,
        active_job = nil,
        on_complete = on_complete,
        next_chain = nil,
    }

    if _current_task_chain then
        if _current_task_chain.active_job and not _current_task_chain.ended then
            _current_task_chain.interrupted = true
            _current_task_chain.next_chain = new_chain
            if _current_task_chain.active_job then
                _current_task_chain.active_job:kill()
            end
            return
        end
    end

    _current_task_chain = new_chain
    next_job(new_chain)
end


---@param tasks loop.Task[]
---@param on_complete fun()|nil
function M.start_task_chain(tasks, on_complete)
    --- copy to solve strings in the copy and keep the original intact
    local chain = vim.deepcopy(tasks)

    local is_unresolved = false
    for _, task in ipairs(chain) do
        local expand_ok, unresolved = vartools.expand_strings(task)
        if not expand_ok then
            is_unresolved = true
            window.add_events({ "Failed to resolve variable(s) in task '" .. task.name .. "':", '  ' ..
            table.concat(unresolved or {}, ', ') }, "error")
        end
    end
    if is_unresolved then
        return
    end
    _start_task_chain(chain, on_complete)
end

return M
