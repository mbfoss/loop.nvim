local Job      = require('loop.job.Job')
local class    = require('loop.tools.class')
local TermProc = require('loop.tools.TermProc')

---@class loop.job.TermJob : loop.job.Job
---@field new fun(self: loop.job.TermJob, proc:loop.tools.TermProc) : loop.job.TermJob
---@field _proc loop.tools.TermProc
local TermJob  = class(Job)

---@param proc loop.tools.TermProc
function TermJob:init(proc)
    self._proc = proc
end

---@return boolean
function TermJob:is_running()
    return self._proc:is_running()
end

function TermJob:kill()
    self._proc:kill();
end

return TermJob
