local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local uitools = require('loop.tools.uitools')


---@class loop.pages.BreakpointsPage : loop.pages.Page
---@field new fun(self: loop.pages.BreakpointsPage, filetype: string): loop.pages.BreakpointsPage
local BreakpointsPage = class(Page)

-- Static namespace for extmarks
local NS_ID = vim.api.nvim_create_namespace('loop-breakpoints-hl')

-- ----------------------------------------------------------------------
-- Helper: pick the right sign for a breakpoint
-- ----------------------------------------------------------------------
local function breakpoint_sign(entry)
	if entry.enabled == false then
		return " " -- disabled → no sign
	end
	if entry.logMessage and entry.logMessage ~= "" then
		return "▶" -- logpoint
	end
	if entry.condition and entry.condition ~= "" then
		return "◆" -- conditional
	end
	if entry.hitCondition and entry.hitCondition ~= "" then
		return "▲" -- hit-condition
	end
	return "●" -- plain breakpoint
end

-- ----------------------------------------------------------------------
-- Format a breakpoint entry for UI (e.g. Telescope, quickfix, etc.)
-- ----------------------------------------------------------------------
local function format_entry(entry, project_dir)
	local filename = entry.filename
	if project_dir then
		-- get relative path
		filename = vim.fn.fnamemodify(filename, ":." .. project_dir)
	end

	local parts = {}
	-- 1. Sign
	table.insert(parts, breakpoint_sign(entry))
	-- 2. File + line
	table.insert(parts, " ")
	table.insert(parts, filename)
	table.insert(parts, ":")
	table.insert(parts, tostring(entry.line))
	-- 3. Optional qualifiers
	if entry.condition and entry.condition ~= "" then
		table.insert(parts, " if " .. entry.condition)
	end
	if entry.hitCondition and entry.hitCondition ~= "" then
		table.insert(parts, " hits=" .. entry.hitCondition)
	end
	if entry.logMessage and entry.logMessage ~= "" then
		table.insert(parts, " log: " .. entry.logMessage:gsub("\n", " "))
	end
	return table.concat(parts, "")
end

function BreakpointsPage:init(filetype)
	Page.init(self, filetype)
	self._items = {}
end

function BreakpointsPage:get_buf()
	local buf, created = Page.get_buf(self)
	if not created then
		return buf, false
	end

	self:_refresh_buffer()

	-- Set up <Enter> keymap only once when buffer is created
	vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
		callback = function()
			local entry = self:get_selected()
			if entry then
				uitools.smart_open_file(entry.filename, entry.line)
			end
		end,
		desc = "Open breakpoint location",
	})

	vim.api.nvim_buf_set_keymap(buf, 'n', '<2-LeftMouse>', '', {
		callback = function()
			local entry = self:get_selected()
			if entry then
				uitools.smart_open_file(entry.filename, entry.line)
			end
		end,
		desc = "Open breakpoint location on double-click",
	})

	return buf, true
end

---@return number
function BreakpointsPage:_get_curr_row()
	local buf = self.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return 0
	end
	if vim.api.nvim_get_current_buf() ~= buf then
		return 0
	end
	return vim.api.nvim_win_get_cursor(0)[1] -- 1-based row
end

function BreakpointsPage:_refresh_buffer()
	local buf = self.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	-- 1. Build lines
	local lines = {}
	for _, entry in ipairs(self._items) do
		lines[#lines + 1] = format_entry(entry, self.proj_dir)
	end

	-- 2. Update buffer
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	-- 3. Highlight selected line using extmark
	vim.api.nvim_buf_clear_namespace(buf, NS_ID, 0, -1)

	for idx, _ in ipairs(self._items) do
		local line_idx = idx - 1
		vim.api.nvim_buf_set_extmark(buf, NS_ID, line_idx, 0, {
			end_col = 1,
			hl_group = 'Debug',
			hl_eol = true,
			priority = 200,
		})
	end
end

function BreakpointsPage:setlist(items, proj_dir)
	self.proj_dir = proj_dir
	self._items = {}
	self._idx = 1
	for file, bpts in pairs(items or {}) do
		for _, bp in ipairs(bpts) do
			if bp.line and type(bp.line) == 'number' then
				table.insert(self._items, {
					filename = file,
					line = bp.line,
					condition = bp.condition or '',
					hitCondition = bp.hitCondition or '',
					logMessage = bp.logMessage or '',
				})
			end
		end
	end

	-- Clamp index
	if #self._items == 0 then
		self._idx = 1
	elseif self._idx > #self._items then
		self._idx = #self._items
	end

	self:get_buf()
	self:_refresh_buffer()
end

function BreakpointsPage:get_selected()
	return self._items[self:_get_curr_row()]
end

return BreakpointsPage
