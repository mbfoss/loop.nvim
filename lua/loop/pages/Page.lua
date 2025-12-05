local class = require('loop.tools.class')

---@alias loop.pages.page.KeyMaps table<string,loop.pages.page.KeyMap>

---@class loop.pages.page.KeyMap
---@field callback fun()
---@field desc string

---@class loop.pages.Page
---@field new fun(self: loop.pages.Page, type : string, name:string): loop.pages.Page
local Page = class()

local buffer_flag_key = "loopplugin_page_efc0bed4-145b"

function Page.is_page(buf)
    local have_var, _ = pcall(vim.api.nvim_buf_get_var, buf, buffer_flag_key)
    return have_var
end

---@param type string
---@param name string
function Page:init(type, name)
    self._type = type
    self._name = name
    self._keymaps = {}
    self._buf = -1
end

function Page:destroy()
    self._destroyed = true
    if self._buf > 0 then
        --vim.notify('deleting buffer')
        vim.api.nvim_buf_delete(self._buf, { force = true })
        assert(self._buf == -1)
    end
end

function Page:follow_last_line()
    self._follow = true
end

function Page:_on_buf_enter()
    self:_apply_keymaps()
    if self._follow then
        local last_line = vim.api.nvim_buf_line_count(self._buf)
        vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    end
end

function Page:_on_buf_leave()
    if self._follow then
        local last_line = vim.api.nvim_buf_line_count(self._buf)
        vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    end
end

---@return string|nil
function Page:get_name()
    return self._name
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
    self:_setup_buf(false)
end

---@return number |nil -- buffer number
function Page:get_buf()
    if self._destroyed then
        return nil
    end
    return self._buf
end

---@return number -- buffer number
---@return boolean -- true if the call triggerered buffer creation
function Page:get_or_create_buf()
    assert(not self._destroyed)
    if self._buf ~= -1 then
        local unloaded = not vim.api.nvim_buf_is_loaded(self._buf)
        if unloaded then
            self:_setup_buf(true)
        end
        return self._buf, unloaded
    end

    self._buf = vim.api.nvim_create_buf(false, true)
    self:_setup_buf(true)
    return self._buf, true
end

---@param own_buf boolean
function Page:_setup_buf(own_buf)
    assert(self._buf > 0)
    local buf = self._buf

    vim.api.nvim_buf_set_var(buf, buffer_flag_key, 1)

    local bufname = "loop://" .. tostring(buf) .. '/' .. self._type
    if self._name and #self._name > 0 then
        bufname = bufname .. '/' .. self._name
    end
    --vim.notify(bufname)
    vim.api.nvim_buf_set_name(buf, bufname)

    do
        local b = vim.bo[buf]
        if own_buf then
            b.buftype = "nofile"
            b.modifiable = false
        end
        b.bufhidden = "hide"
        b.swapfile = false
        b.undolevels = -1   -- buffer can't become "modified"
        b.buflisted = false -- hide from :ls
        b.filetype = "loop-" .. self._type
    end

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer = buf,
        once = true,
        callback = function(ev)
            assert(ev.buf == buf)
            self._buf = -1
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = buf,
        callback = function(ev)
            assert(ev.buf == buf)
            self:_on_buf_enter()
        end
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function(ev)
            assert(ev.buf == buf)
            self:_on_buf_leave()
        end
    })
end

---@param key string
---@param keymap loop.pages.page.KeyMap
function Page:add_keymap(key, keymap)
    assert(not self._keymaps[key])
    self._keymaps[key] = keymap
    self:_apply_keymap(key, keymap)
end

---@param keymaps table<string, loop.pages.page.KeyMap>
function Page:add_keymaps(keymaps)
    for key, keymap in pairs(keymaps) do
        assert(not self._keymaps[key])
        self._keymaps[key] = keymap
        self:_apply_keymap(key, keymap)
    end
end

function Page:_apply_keymaps()
    if self._keymaps then
        for key, item in pairs(self._keymaps) do
            self:_apply_keymap(key, item)
        end
    end
end

---@param key string
---@param item loop.pages.page.KeyMap
function Page:_apply_keymap(key, item)
    if self._buf ~= -1 then
        local modes = { "n" }
        --local ok =
        pcall(function() vim.keymap.del(modes, key, { buffer = self._buf }) end)
        --vim.notify("keymap removed " .. tostring(ok))
        vim.keymap.set(modes, key, function() item.callback() end, { buffer = self._buf, desc = item.desc })
    end
end

return Page
