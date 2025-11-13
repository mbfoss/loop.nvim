local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local uitools = require('loop.tools.uitools')

---@class loop.pages.ErrorsPage : loop.pages.Page
---@field new fun(self: loop.pages.ErrorsPage, filetype: string, on_buf_enter: fun(buf: integer)): loop.pages.ErrorsPage
local ErrorsPage = class(Page)

local NS_ID = vim.api.nvim_create_namespace('loop-errors-hl')

local function format_entry(entry, project_dir)
	local filename = entry.filename or '[No File]'
	if project_dir then
		filename = vim.fn.fnamemodify(filename, ":." .. project_dir)
	end

	local lnum = entry.lnum or 0
	local col = entry.col or 0
	local text = entry.text or ""
	local type_char = entry.type or " " -- E, W, I, or blank

	return string.format("%s %s:%d:%d: %s", type_char, filename, lnum, col, text)
end

function ErrorsPage:init(filetype, on_buf_enter)
	Page.init(self, filetype, on_buf_enter)
	self._items = {}
end

function ErrorsPage:get_buf()
	local buf, created = Page.get_buf(self)
	if not created then
		return buf, false
	end

	self:_refresh_buffer()

	-- Jump to selected error on Enter
	vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
		callback = function()
			local entry = self:get_selected()
			if entry then
				uitools.smart_open_file(entry.filename, entry.lnum, entry.col)
			end
		end,
		desc = "Open error location",
	})

	-- Jump on double-click
	vim.api.nvim_buf_set_keymap(buf, 'n', '<2-LeftMouse>', '', {
		callback = function()
			local entry = self:get_selected()
			if entry then
				uitools.smart_open_file(entry.filename, entry.lnum, entry.col)
			end
		end,
		desc = "Open error location on double-click",
	})

	-- Track cursor moves to update quickfix index
	vim.api.nvim_create_autocmd('CursorMoved', {
		buffer = buf,
		callback = function()
			local idx = self:_get_curr_row()
			if idx >= 1 and idx <= #self._items then
				vim.fn.setqflist({}, 'r', { idx = idx })
			end
		end,
	})

	return buf, true
end

function ErrorsPage:_get_curr_row()
	local buf = self.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return 0
	end
	if vim.api.nvim_get_current_buf() ~= buf then
		return 0
	end
	return vim.api.nvim_win_get_cursor(0)[1] -- 1-based row
end

function ErrorsPage:_refresh_buffer()
	local buf = self.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local lines = {}
	for _, entry in ipairs(self._items) do
		lines[#lines + 1] = format_entry(entry, self.proj_dir)
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(buf, NS_ID, 0, -1)
	for idx, _ in ipairs(self._items) do
		vim.api.nvim_buf_set_extmark(buf, NS_ID, idx - 1, 0, {
			end_col = 1,
			hl_group = 'ErrorMsg',
			hl_eol = true,
			priority = 200,
		})
	end
end

function ErrorsPage:setlist(qflist, proj_dir)
	self.proj_dir = proj_dir
	self._items = {}
	self._idx = 1

	for _, entry in ipairs(qflist or {}) do
		if entry.lnum and entry.filename then
			table.insert(self._items, {
				filename = entry.filename,
				lnum = entry.lnum,
				col = entry.col or 0,
				text = entry.text or "",
				type = entry.type or " ",
			})
		end
	end

	if #self._items == 0 then
		self._idx = 1
	elseif self._idx > #self._items then
		self._idx = #self._items
	end

	self:get_buf()
	self:_refresh_buffer()
end

function ErrorsPage:get_selected()
	return self._items[self:_get_curr_row()]
end

return ErrorsPage
