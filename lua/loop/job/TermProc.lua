local Job      = require('loop.job.Job')
local class    = require('loop.tools.class')
local uitools  = require('loop.tools.uitools')
local strtools = require('loop.tools.strtools')


---@class loop.job.TermProc : loop.job.Job
---@field new fun(self: loop.job.TermProc) : loop.job.TermProc
local TermProc = class(Job)

---@diagnostic disable-next-line: undefined-field
local main_thread_id = vim.loop.thread_self() -- capture at startup
local function assert_main_thread()
    ---@diagnostic disable-next-line: undefined-field
    assert(vim.loop.thread_self() == main_thread_id, "Not in main thread!")
end

---Initializes the TermProc instance.
function TermProc:init()
    ---@type number
    self.job_id = -1
end

---@return boolean
function TermProc:is_running()
    return self.job_id ~= -1
end

function TermProc:kill()
    if self.job_id ~= -1 then
        vim.fn.jobstop(self.job_id)
    end
end

---@class loop.TermProc.StartArgs
---@field name string
---@field command string|string[]
---@field command_env table<string,string>|nil
---@field command_cwd string|nil
---@field output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@field on_exit_handler fun(code : number)

---Starts a new terminal job.
---@param args loop.TermProc.StartArgs
---@return number buffer number or -1
---@return string|nil error msg or nil
function TermProc:start(args)
    if self.job_id ~= -1 then
        return -1, "A job is already running"
    end

    assert(args.on_exit_handler)
    assert(type(args.command) == 'string' or type(args.command) == 'table')
    assert(not args.command_env or type(args.command_env) == 'table')

    local command_cwd = args.command_cwd
    if not command_cwd or #command_cwd == 0 then
        command_cwd = vim.fn.getcwd()
    end

    if vim.fn.isdirectory(command_cwd) == 0 then
        return -1, string.format("CWD: '%s' is not a valid directory", command_cwd)
    end

    -- get the real path (no symlinks etc...)
    command_cwd = vim.fn.fnamemodify(vim.fn.resolve(command_cwd), ':p')

    ---@type table<string,string>
    local command_env = vim.deepcopy(args.command_env or {})
    command_env.PWD = command_cwd -- required for commands to use cwd in all cases

    ---@type string[]
    local cmd_and_args = strtools.cmd_to_string_array(args.command)

    if #cmd_and_args == 0 then
        return -1, "task command is missing"
    end

    if vim.fn.executable(cmd_and_args[1]) == 0 then
        return -1, "command is not an executable: " .. cmd_and_args[1]
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false
    vim.keymap.set('t', '<Esc>', function() vim.cmd('stopinsert') end, { buffer = bufnr })

    local previous_win = vim.api.nvim_get_current_win()
    local width = vim.api.nvim_win_get_width(0)
    local win_opts = { relative = "editor", width = width, height = 10, row = 0, col = 0, style = "minimal" }
    local temp_win = vim.api.nvim_open_win(bufnr, true, win_opts)
    vim.api.nvim_set_current_win(temp_win)

    -- Call risky_function safely
    local call_ok, result = xpcall(
        function()
            return { self:_start_term_job(bufnr, cmd_and_args, command_env, command_cwd, args.output_handler,
                args.on_exit_handler) }
        end,
        function(_)
            return debug.traceback()
        end
    )

    vim.api.nvim_set_current_win(previous_win)
    vim.api.nvim_win_close(temp_win, true)

    if not call_ok then
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return -1, result
    end
    local started, start_err = result[1], result[2]
    if not started then
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return -1, start_err
    end
    
    return bufnr, nil
end

---@param bufnr number
---@param cmd_and_args string[]
---@param command_env table<string,string>|nil
---@param command_cwd string|nil
---@param output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@param on_exit_handler fun(code : number)
---@return boolean, string|nil
function TermProc:_start_term_job(bufnr, cmd_and_args, command_env, command_cwd, output_handler, on_exit_handler)
    local buffer = bufnr
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer = bufnr,
        once = true,
        callback = function()
            buffer = -1
        end,
    })

    local function on_exit(code)
        if buffer ~= -1 then
            vim.api.nvim_buf_call(buffer, function() vim.cmd("stopinsert") end)
            uitools.disable_insert_mappings(buffer)
        end
        if on_exit_handler then
            on_exit_handler(code)
        end
    end

    assert(type(cmd_and_args) ~= 'string')
    self.job_id = vim.fn.jobstart(cmd_and_args, {
        term = true,
        cwd = command_cwd,
        env = command_env,
        on_stdout = function(_, data, _)
            assert_main_thread()
            if output_handler then
                output_handler("stdout", data)
            end
        end,
        on_stderr = function(_, data, _)
            assert_main_thread()
            if output_handler then
                output_handler("stderr", data)
            end
        end,
        on_exit = function(_, code, _)
            assert_main_thread()
            self.job_id = -1
            on_exit(code)
        end,
    })

    if self.job_id <= 0 then
        return false, "Failed to start terminal job"
    end

    return true, nil
end

return TermProc
