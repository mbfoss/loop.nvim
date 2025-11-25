local Job     = require('loop.job.Job')
local class   = require('loop.tools.class')

---@class loop.job.VimCmdJob : loop.job.Job
---@field new fun(self: loop.job.VimCmdJob) : loop.job.VimCmdJob
local VimCmdJob = class(Job)

---Initializes the VimCmdJob instance.
function VimCmdJob:init()
end

---@return boolean
function VimCmdJob:is_running()
	return false
end

function VimCmdJob:kill()
end

---@class loop.VimCmdJob.StartArgs
---@field command string|string[]
---@field on_exit_handler fun(code : number)

---Starts a new terminal job.
---@param args loop.VimCmdJob.StartArgs
---@return boolean, string|nil
function VimCmdJob:start(args)
	if type(args.command) ~= 'string' then
		return false, "invalid vimcmd command value type '" .. type(args.command) .. "', must be a string"
	end

    vim.cmd()
	-- require the module
	local call_ok, payload = pcall(function() vim.cmd(args.command) end)

	if not call_ok then
		return false, "vim command error, " .. tostring(payload)
	end

    if args.on_exit_handler then
		vim.schedule(function()
			args.on_exit_handler(0)
		end)
	end

    return true, nil
end

return VimCmdJob
