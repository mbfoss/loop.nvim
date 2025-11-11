local log = require('loop.tools.Logger').create_logger("page")

local class = require('loop.tools.class')

---@class loop.pages.Page
---@field new fun(self: loop.pages.Page, filetype : string, on_buf_enter : fun(buf : number)): loop.pages.Page
local Page = class()

local buffer_flag_key = "loopplugin_page_efc0bed4-145b"

function Page.is_page(buf)
    local have_var, _ = pcall(vim.api.nvim_buf_get_var, buf, buffer_flag_key)
    return have_var
end

---@param filetype string
---@param on_buf_enter fun(page : loop.pages.Page)
function Page:init(filetype, on_buf_enter)
    assert(on_buf_enter)
    self.filetype = filetype
    self.on_buf_enter = on_buf_enter
    self.buf = -1
    self.is_used = false
end

function Page:_on_buf_enter()
    local last_line = vim.api.nvim_buf_line_count(self.buf)
    vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    self.on_buf_enter(self)
end

---@return boolean
function Page:used()
    return self.is_used
end

function Page:get_buf()
    if self.buf ~= -1 then
        return self.buf, false
    end

    self.is_used = true -- buffer may be unloaded, but used remain true
    self.buf = vim.api.nvim_create_buf(false, true)

    log:log('buffer created ' .. self.filetype)

    local buf = self.buf
    vim.api.nvim_buf_set_var(buf, buffer_flag_key, 1)

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = self.filetype
    vim.bo[buf].modifiable = false

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer = buf,
        once = true,
        callback = function(ev)
            assert(ev.buf == self.buf)
            log:log('buffer deleted ' .. self.filetype)
            self.buf = -1
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = buf,
        callback = function(ev)
            assert(ev.buf == self.buf)
            self:_on_buf_enter()
        end
    })

    return buf, true
end

---@param key string
---@param callback fun()
function Page:set_keymap(key, callback)
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
