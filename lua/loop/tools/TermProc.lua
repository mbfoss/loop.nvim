local class    = require('loop.tools.class')
local uitools  = require('loop.tools.uitools')
local strtools = require('loop.tools.strtools')

---@class loop.tools.TermProc
---@field new fun(self: loop.tools.TermProc) : loop.tools.TermProc
local TermProc = class()

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

function TermProc:get_pid()
    return vim.fn.jobpid(self.job_id)
end

---@class loop.tools.TermProc.StartArgs
---@field name string
---@field command string|string[]
---@field command_env table<string,string>|nil
---@field command_cwd string|nil
---@field output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@field on_exit_handler fun(code : number)

---Starts a new terminal job.
---@param winid number
---@param bufnr number
---@param args loop.tools.TermProc.StartArgs
---@return boolean success
---@return string|nil error msg or nil
function TermProc:start(winid, bufnr, args)
    if self.job_id ~= -1 then
        return false, "already started"
    end

    assert(args.on_exit_handler)
    assert(type(args.command) == 'string' or type(args.command) == 'table')
    assert(not args.command_env or type(args.command_env) == 'table')

    local command_cwd = args.command_cwd
    if not command_cwd or #command_cwd == 0 then
        command_cwd = vim.fn.getcwd()
    end

    if vim.fn.isdirectory(command_cwd) == 0 then
        return false, string.format("CWD: '%s' is not a valid directory", command_cwd)
    end

    -- get the real path (no symlinks etc...)
    command_cwd = vim.fn.fnamemodify(vim.fn.resolve(command_cwd), ':p')

    ---@type table<string,string>
    local command_env = vim.deepcopy(args.command_env or {})
    command_env.PWD = command_cwd -- required for commands to use cwd in all cases

    ---@type string[]
    local cmd_and_args = strtools.cmd_to_string_array(args.command)

    if #cmd_and_args == 0 then
        return false, "command is missing"
    end

    if vim.fn.executable(cmd_and_args[1]) == 0 then
        return false, "command is not an executable: " .. cmd_and_args[1]
    end

    vim.keymap.set('t', '<Esc>', function() vim.cmd('stopinsert') end, { buffer = bufnr })

    local previous_win = vim.api.nvim_get_current_win()
    local was_in_insert = vim.fn.mode():sub(1, 1) == 'i'
    if was_in_insert then
        vim.cmd.stopinsert()
    end

    local prev_buf = vim.api.nvim_win_get_buf(winid)
    vim.api.nvim_set_current_win(winid)
    vim.api.nvim_win_set_buf(winid, bufnr)

    local ok, err = self:_start_term_job(bufnr, cmd_and_args, command_env, command_cwd, args.output_handler,
        args.on_exit_handler)

    vim.api.nvim_win_set_cursor(winid, { vim.api.nvim_buf_line_count(bufnr), 0 })

    vim.api.nvim_win_set_buf(winid, prev_buf)
    vim.api.nvim_set_current_win(previous_win)

    if was_in_insert then
        vim.cmd.startinsert()
    end

    return ok, err
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
        pty = true,
        cwd = command_cwd,
        env = command_env,
        on_stdout = function(_, data, _)
            if output_handler then
                output_handler("stdout", data)
            end
        end,
        on_stderr = function(_, data, _)
            if output_handler then
                output_handler("stderr", data)
            end
        end,
        on_exit = function(_, code, _)
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
