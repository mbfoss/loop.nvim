local Job      = require('loop.job.Job')
local class    = require('loop.tools.class')
local TermProc = require('loop.tools.TermProc')
local window   = require('loop.window')

---@class loop.job.TermJob : loop.job.Job
---@field new fun(self: loop.job.TermJob) : loop.job.TermJob
---@field _proc loop.tools.TermProc
local TermJob  = class(Job)

---Initializes the TermJob instance.
function TermJob:init()
    self._proc = TermProc:new()
end

---@return boolean
function TermJob:is_running()
    return self._proc:is_running()
end

function TermJob:kill()
    self._proc:kill();
end

---@class loop.TermJob.StartArgs
---@field name string
---@field command string|string[]
---@field command_env table<string,string>|nil
---@field command_cwd string|nil
---@field output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@field on_exit_handler fun(code : number)

---Starts a new terminal job.
---@param args loop.tools.TermProc.StartArgs
---@return boolean success
---@return string|nil error msg or nil
function TermJob:start(args)
    local bufnr, err = self._proc:start(args)
    if bufnr == -1 then
        return false, err
    end
    window.add_term_task_page(args.name, bufnr)
    return true, nil
end

return TermJob
