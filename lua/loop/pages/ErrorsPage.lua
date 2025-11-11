local Page = require('loop.pages.page')
local class = require('loop.tools.class')

---@class loop.pages.ErrorsPage: loop.pages.Page
---@field new fun(self: loop.pages.ErrorsPage, filetype : string, on_buf_enter : fun(buf : number)) : loop.pages.ErrorsPage
local ErrorsPage = class(Page)

local function format_entry(entry)
    local severity = ''
    if entry.type then
        severity = (entry.type == 'E' and 'Error') or
            (entry.type == 'W' and 'Warning') or
            (entry.type == 'I' and 'Info') or
            (entry.type == 'N' and 'Note') or
            entry.type
        severity = '[' .. severity .. '] '
    end
    return string.format('%s%s:%d:%d: %s',
        severity,
        vim.fn.fnamemodify(entry.filename, ':.'),
        entry.lnum or 0,
        entry.col or 0,
        entry.text or '')
end

---@param filetype string
---@param on_buf_enter fun(buf: number)
function ErrorsPage:init(filetype, on_buf_enter)
    Page.init(self, filetype, on_buf_enter)
    self.state = {
        items = {},                                         -- list of quickfix entries
        idx   = 1,                                          -- current position (1-based)
        ns_id = vim.api.nvim_create_namespace('qf_module'), -- for extmarks
    }
end

-- ----------------------------------------------------------------------
-- Refresh the quickfix buffer content
-- ----------------------------------------------------------------------
function ErrorsPage:refresh_buffer()
    if not vim.api.nvim_buf_is_valid(self.state.bufnr) then return end

    local lines = {}
    for i, entry in ipairs(self.state.items) do
        lines[i] = format_entry(entry)
    end

    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

    -- highlight current line
    vim.api.nvim_buf_clear_namespace(self.state.bufnr, self.state.ns_id, 0, -1)
    if self.state.idx > 0 and self.state.idx <= #self.state.items then
        vim.api.nvim_buf_set_extmark(self.state.bufnr, self.state.ns_id, self.state.idx - 1, 0, {
            end_line = self.state.idx,
            hl_group = 'CursorLine',
            hl_eol = true,
        })
    end
end

--- Set the list of items (same shape as :caddexpr)
function ErrorsPage:setlist(items, action)
    if action == 'replace' or action == nil then
        self.state.items = {}
        self.state.idx   = 1
    end

    for _, entry in ipairs(items) do
        table.insert(self.state.items, vim.tbl_extend('keep', entry, {
            filename = entry.filename or '',
            lnum     = entry.lnum or 0,
            col      = entry.col or 0,
            text     = entry.text or '',
            type     = entry.type or '',
        }))
    end

    if #self.state.items > 0 and self.state.idx > #self.state.items then
        self.state.idx = #self.state.items
    end

    if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
        self:refresh_buffer()
    end
end

--- Append items (like :caddexpr)
function ErrorsPage:addlist(items)
    ErrorsPage:setlist(items, 'append')
end

--- Jump to the entry under the cursor (or to current idx)
function ErrorsPage:jump()
    local idx = self.state.idx
    if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
        idx = vim.api.nvim_win_get_cursor(self.state.winid)[1]
    end

    local entry = self.state.items[idx]
    if not entry then return end

    vim.cmd(string.format('edit %s', vim.fn.fnameescape(entry.filename)))
    vim.api.nvim_win_set_cursor(0, { entry.lnum ~= 0 and entry.lnum or 1, (entry.col or 1) - 1 })
end

--- Go to next entry
function ErrorsPage:next()
    if #self.state.items == 0 then return end
    self.state.idx = (self.state.idx % #self.state.items) + 1
    if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
        vim.api.nvim_win_set_cursor(self.state.winid, { self.state.idx, 0 })
    end
    ErrorsPage:jump()
end

--- Go to previous entry
function ErrorsPage:prev()
    if #self.state.items == 0 then return end
    self.state.idx = self.state.idx - 1
    if self.state.idx < 1 then self.state.idx = #self.state.items end
    if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
        vim.api.nvim_win_set_cursor(self.state.winid, { self.state.idx, 0 })
    end
    ErrorsPage:jump()
end

--- Go to first entry
function ErrorsPage:first()
    if #self.state.items == 0 then return end
    self.state.idx = 1
    if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
        vim.api.nvim_win_set_cursor(self.state.winid, { 1, 0 })
    end
    ErrorsPage:jump()
end

--- Go to last entry
function ErrorsPage:last()
    if #self.state.items == 0 then return end
    self.state.idx = #self.state.items
    if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
        vim.api.nvim_win_set_cursor(self.state.winid, { self.state.idx, 0 })
    end
    ErrorsPage:jump()
end

--  map('n', '<CR>',  [[<Cmd>lua require('qf').jump()<CR>]])
--  map('n', 'q',     [[<Cmd>lua require('qf').close()<CR>]])
--  map('n', '<Esc>', [[<Cmd>lua require('qf').close()<CR>]])


return ErrorsPage
