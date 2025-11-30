---@class MyModule
local M = {}

local project = require('loop.project')
local config = require('loop.config')

-- Command completion: suggest subcommands first
local function _loop_complete(func_names, arg_lead, cmd_line)
	local function filter(strs)
		local arr = {}
		for _, s in ipairs(strs) do
			if vim.startswith(s, arg_lead) then
				table.insert(arr, s)
			end
		end
		return arr
	end
	local args = vim.split(cmd_line, "%s+")
	if #args == 2 then
		return filter(func_names)
	elseif #args >= 3 then
		local cmd = args[2]
		local rest = { unpack(args, 3) }
		rest[#rest] = nil
		if cmd == "task" then
			return filter(project.task_subcommands(rest))
		elseif cmd == "ext" then
			return filter(project.extension_subcommands(rest))
		elseif cmd == "breakpoint" then
			return filter(project.breakpoints_subcommands(rest))
		elseif cmd == "debug" then
			return filter(project.debug_subcommands(rest))
		end
	end
	return {}
end

-- Command handler
local function _loop_command(calls, opts)
	local args = vim.split(opts.args, "%s+")
	local subcmd = args[1]
	if not subcmd or subcmd == "" then
		vim.notify("Usage: :Loop <command> [args...]", vim.log.levels.WARN)
		return
	end
	local fn = calls[subcmd]
	if not fn then
		vim.notify("Invalid command: " .. subcmd, vim.log.levels.ERROR)
		return
	end
	-- Pass any remaining arguments to the function
	local rest = { unpack(args, 2) }
	local ok, err = pcall(fn, unpack(rest))
	if not ok then
		vim.notify("Loop " .. subcmd .. " failed: " .. tostring(err), vim.log.levels.ERROR)
	end
end

local function _setup_user_command(func_table)
	local func_names = vim.tbl_keys(func_table)
	func_names = vim.tbl_filter(function(n) return not vim.startswith(n, '_') end, func_names)
	table.sort(func_names)

	local calls = {}
	for _, n in ipairs(func_names) do
		calls[n] = func_table[n]
	end
	vim.api.nvim_create_user_command("Loop",
		function(opts)
			return _loop_command(calls, opts)
		end, {
			nargs = "*",
			complete = function(arg_lead, cmd_line, _)
				return _loop_complete(func_names, arg_lead, cmd_line)
			end,
			desc = "Loop.nvim management commands",
		})
end

local setup_done = false

---@param args loop.Config?
M.setup = function(args)
	assert(not setup_done, "Loop.nvim: setup() already done")
	setup_done = true
	if vim.fn.has("nvim-0.10") ~= 1 then
		error("loop.nvim requires Neovim >= 0.10")
	end

	config.current = vim.tbl_deep_extend("force", config.defaut_config, args or {})
	project.setup(config.current)

	_G.LoopProject =
	{
		_winbar_click = project.winbar_click,
		create_project = project.create_project,
		open_project = project.open_project,
		close_project = project.close_project,
		toggle = project.toggle_window,
		show = project.show_window,
		hide = project.hide_window,

		task = project.task_command,
		ext = project.extension_command,
		debug = project.debug_command,
		breakpoint = project.breakpoints_command,
	}

	_setup_user_command(_G.LoopProject)

vim.keymap.set("n", "<F5>",  ":Loop debug continue<CR>")
vim.keymap.set("n", "<F6>",  ":Loop debug step_in<CR>")
vim.keymap.set("n", "<F7>",  ":Loop debug step_out<CR>")
vim.keymap.set("n", "<F8>",  ":Loop debug step_over<CR>")
vim.keymap.set("n", "<F9>",  ":Loop debug terminate<CR>")
vim.keymap.set("n", "<F10>", ":Loop debug terminate_all<CR>")


end

return M
