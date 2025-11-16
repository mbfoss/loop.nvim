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
    self._filetype = filetype
    self._buf = -1
end

function Page:destroy()
    self._destroyed = true
    if self._buf > 0 then
        --vim.notify('deleting buffer')
        vim.api.nvim_buf_delete(self._buf, { force = true})
        assert(self._buf == -1)
    end
end

function Page:follow_last_line()
    self.follow_last_line = true
end

function Page:_on_buf_enter()
    self:_apply_keymaps()
    if self.follow_last_line then
        local last_line = vim.api.nvim_buf_line_count(self._buf)
        vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    end
end

---@param name string
function Page:set_name(name)
    self.name = name
end

---@return string|nil
function Page:get_name()
    return self.name
end

---@param bufnr number
function Page:assign_buf(bufnr)
    assert(not self._destroyed)
    assert(bufnr > 0)
    if self._buf ~= -1 then
        vim.api.nvim_buf_delete(self._buf, { force = true })
        assert(self._buf == -1)
    end
    self._buf = bufnr
    self:_setup_buf()
end

---@return number -- buffer number
function Page:get_buf()
    assert(not self._destroyed)
    return self._buf
end

---@return number -- buffer number
---@return boolean -- true if the call triggerered buffer creation
function Page:get_or_create_buf()
    assert(not self._destroyed)
    if self._buf ~= -1 then
        return self._buf, false
    end

    self._buf = vim.api.nvim_create_buf(false, true)

    vim.bo[self._buf].modifiable = false

    self:_setup_buf()
    return self._buf, true
end

function Page:_setup_buf()
    assert(self._buf > 0)

    vim.api.nvim_buf_set_var(self._buf, buffer_flag_key, 1)

    if vim.bo[self._buf].buftype == "" then
        vim.bo[self._buf].buftype = "nofile"
    end
    vim.bo[self._buf].bufhidden = "hide"
    vim.bo[self._buf].swapfile = false
    vim.bo[self._buf].filetype = self._filetype

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer = self._buf,
        once = true,
        callback = function(ev)
            assert(ev.buf == self._buf)
            self._buf = -1
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = self._buf,
        callback = function(ev)
            assert(ev.buf == self._buf)
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
    if self._buf ~= -1 then
        local modes = { "n", "t" }
        for _, mode in ipairs(modes) do
            local ok, err = pcall(vim.api.nvim_buf_del_keymap, self._buf, mode, key)
            --vim.notify(vim.inspect { 'remove keymap ', ok, err })
        end
        --vim.notify(vim.inspect { 'setting keymap', self._filetype, modes, key, self._buf})
        vim.keymap.set(modes, key, function()
            callback()
        end, { buffer = self._buf })
    end
end

return Page
