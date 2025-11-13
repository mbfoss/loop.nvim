local M = {}

require('loop.config')
local Session = require('loop.dap.Session')

-- local sessions = {}
local session_id = 0

local function _start_session(args)
	if not args.debugger.cmd or #args.debugger.cmd == 0 then
		return false, "Loop.nvim: debugger program is missing"
	end
	if args.debugger.cwd and vim.fn.isdirectory(args.debugger.cwd) == 0 then
		return false, string.format("Loop.nvim: debugger CWD: '%s' is not a valid directory", args.target.cwd)
	end

	local dap = {
		cmd = args.debugger.cmd,
		args = args.debugger.args or {},
		cwd = args.debugger.cwd or vim.fn.getcwd(),
	}

	session_id = session_id + 1
	local name = (args.name or 'session') .. '[' .. tostring(session_id) .. ']'

	local session_args = {
		name = name,
		dap = dap,
		target = args.target,
		output_handler = args.output_handler,
		breakpoints_provider = nil
	}
	--local session =
	Session:new(session_args)
	--sessions[session_id] = session
	return true
end


function M.start_session(args)
	return _start_session(args)
end

---@param config loop.Config
function M.setup(config)
    --vim.notify('dap setup\n' .. vim.inspect(config))
end

return M
