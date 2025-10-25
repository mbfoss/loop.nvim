local class = require('loop.tools.class')

---@class loop.job.Job
---@field new fun(self: loop.job.Job): loop.job.Job
local Job = class()

---Initializes the Job instance.
function Job:init()
end

---@return boolean
function Job:is_running()
    -- kill() must be implemented by a derived class
    error('abstract')
end

---Kills the running job, if any.
function Job:kill()
    -- kill() must be implemented by a derived class
    error('abstract')
end

function Job:kill_and_wait()
    -- kill() must be implemented by a derived class
    error('abstract')
end

return Job
