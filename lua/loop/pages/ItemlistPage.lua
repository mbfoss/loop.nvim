local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local uitools = require('loop.tools.uitools')

---@class loop.pages.ItemListPage.Item
---@field id number
---@field text string
---@field data any

local _ns_id = vim.api.nvim_create_namespace('LoopPluginPage')

---@class loop.pages.ItemListPage : loop.pages.Page
---@field new fun(self: loop.pages.ItemListPage, name:string, keymaps:loop.pages.page.KeyMaps): loop.pages.Page
---@field _items loop.pages.ItemListPage.Item[]
local ItemListPage = class(Page)

---@param name string
---@param keymaps loop.pages.page.KeyMaps
function ItemListPage:init(name, keymaps)
    Page.init(self, "task", name, keymaps)
    self._items = {}
end

---@param items loop.pages.ItemListPage.Item[]
function ItemListPage:set_items(items)
    self._items = items
    self:_refresh_buffer(self:get_buf())
end

---@param item loop.pages.ItemListPage.Item
function ItemListPage:add_item(item)
    table.insert(self._items, item)

    local buf = self:get_buf()
    if buf == -1 then
        return
    end

    local pos = #self._items
    -- If buffer is empty and first line is "", replace instead of append
    if pos == 1 then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { item.text })
        self:_highlight(1, 1)
    else
        vim.api.nvim_buf_set_lines(buf, pos, pos, false, { item.text })
        self:_highlight(pos, pos)
    end
end

---@param id number
function ItemListPage:remove_item(id)
    local buf = self:get_buf()
    if buf == -1 then
        -- still update items table even if buffer isn't visible
        for idx, item in ipairs(self._items) do
            if item.id == id then
                table.remove(self._items, idx)
                return
            end
        end
        return
    end

    for idx, item in ipairs(self._items) do
        if item.id == id then
            table.remove(self._items, idx)
            -- delete just the line (0-indexed)
            vim.api.nvim_buf_set_lines(buf, idx - 1, idx, false, {})
            -- clear all highlights below idx; easiest single-call:
            vim.api.nvim_buf_clear_namespace(buf, _ns_id, idx - 1, -1)
            -- re-highlight from current idx to end
            self:_highlight(idx, #self._items)
            return
        end
    end
end

---@return loop.pages.ItemListPage.Item
function ItemListPage:get_item(id)
    for idx, item in ipairs(self._items) do
        if item.id == id then
            return item
        end
    end
    return nil
end

function ItemListPage:get_or_create_buf()
    local buf, created = Page.get_or_create_buf(self)
    if not created then
        return buf, false
    end

    self:add_keymap('<CR>', {
        callback = function()
            vim.notify("Item selected")
        end,
        desc = "Select item",
    })

    self:add_keymap('<2-LeftMouse>', {
        callback = function()
            vim.notify("Item double click")
        end,
        desc = "Select item",
    })

    self:_refresh_buffer(buf)
    return buf, true
end

---@param from number from index 1-based
---@param to number to index 1-based
function ItemListPage:_highlight(from, to)
    if from > to then
        return
    end

    if not self._buf or not vim.api.nvim_buf_is_valid(self._buf) then
        return
    end
    -- set extmarks
    for idx in from, to do
        local item = self._items[idx]
        local endcol = math.min(2, #item.text)
        vim.api.nvim_buf_set_extmark(self._buf, _ns_id, idx - 1, 0, {
            end_col = endcol,
            hl_group = 'ErrorMsg',
            --hl_eol = true,
            priority = 200,
        })
    end
end

---@param buf number
function ItemListPage:_refresh_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    -- clear highlights
    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)

    -- build lines
    local lines = {}
    for _, item in ipairs(self._items) do
        lines[#lines + 1] = item.text
    end

    -- update buffer
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    self:_highlight(1, #self._items)
end

return ItemListPage
