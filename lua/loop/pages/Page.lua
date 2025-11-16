local log = require('loop.tools.Logger').create_logger("page")

local class = require('loop.tools.class')

---@class loop.pages.Page
---@field new fun(self: loop.pages.Page, filetype : string): loop.pages.Page
local Page = class()

local buffer_flag_key = "loopplugin_page_efc0bed4-145b"

function Page.is_page(buf)
    local have_var, _ = pcall(vim.api.nvim_buf_get_var, buf, buffer_flag_key)
    return have_var
end

---@param filetype string
function Page:init(filetype)
    self.filetype = filetype
    self.buf = -1
end

function Page:follow_last_line()
    self.follow_last_line = true
end

function Page:_on_buf_enter()
    self:_apply_keymaps()
    if self.follow_last_line then
        local last_line = vim.api.nvim_buf_line_count(self.buf)
        vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    end
end

---@param bufnr number
function Page:assign_buf(bufnr)
    assert(bufnr > 0)
    if self.buf ~= -1 then
        vim.api.nvim_buf_delete(self.buf, { force = true })
        assert(self.buf == -1)
    end
    self.buf = bufnr
    self:_setup_buf()
end

---@return number -- buffer number
---@return boolean -- true if the call triggerered buffer creation
function Page:get_buf()
    if self.buf ~= -1 then
        return self.buf, false
    end

    self.buf = vim.api.nvim_create_buf(false, true)
    log:log('buffer created ' .. self.filetype)

    vim.bo[self.buf].modifiable = false

    self:_setup_buf()
    return self.buf, true
end

function Page:_setup_buf()
    assert(self.buf > 0)

    vim.api.nvim_buf_set_var(self.buf, buffer_flag_key, 1)

    if vim.bo[self.buf].buftype == "" then
        vim.bo[self.buf].buftype = "nofile"
    end
    vim.bo[self.buf].bufhidden = "hide"
    vim.bo[self.buf].swapfile = false
    vim.bo[self.buf].filetype = self.filetype

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer = self.buf,
        once = true,
        callback = function(ev)
            assert(ev.buf == self.buf)
            log:log('buffer deleted ' .. self.filetype)
            self.buf = -1
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = self.buf,
        callback = function(ev)
            assert(ev.buf == self.buf)
            self:_on_buf_enter()
        end
    })
end

---@param keymaps table<string,function>
function Page:set_keymaps(keymaps)
    self.keymaps = keymaps
    self:_apply_keymaps()
end

function Page:_apply_keymaps()
    if self.keymaps then
        for key, callback in pairs(self.keymaps) do
            self:_apply_keymap(key, callback)
        end
    end
end

---@param key string
---@param callback fun()
function Page:_apply_keymap(key, callback)
    if self.buf ~= -1 then
        local modes = { "n", "t" }
        for _, mode in ipairs(modes) do
            local ok, err = pcall(vim.api.nvim_buf_del_keymap, self.buf, mode, key)
            --vim.notify(vim.inspect { 'remove keymap ', ok, err })
            log:log({ 'remove keymap ', ok, err })
        end
        --vim.notify(vim.inspect { 'setting keymap', self.filetype, modes, key, self.buf})
        vim.keymap.set(modes, key, function()
            callback()
        end, { buffer = self.buf })
    end
end

return Page
