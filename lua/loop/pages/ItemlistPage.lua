local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local uitools = require('loop.tools.uitools')

---@class loop.pages.ItemListPage.Item
---@field id number
---@field text string

---@class loop.pages.ItemListPage : loop.pages.Page
---@field new fun(self: loop.pages.ItemListPage, name:string): loop.pages.Page
---@field _items loop.pages.ItemListPage.Item[]
local ItemListPage = class(Page)

---@param name string
function ItemListPage:init(name)
    Page.init(self, "task", name)
    self._items = {}
end

---@param items loop.pages.ItemListPage.Item[]
function ItemListPage:set_items(items)
    self._items = items
    self:_refresh_buffer(self:get_buf())
end

---@param id number
---@param name string
function ItemListPage:add_item(id, name)
    table.insert(self._items, { id = id, text = name })
    self:_refresh_buffer(self:get_buf())
end

---@param id number
function ItemListPage:remove_item(id)
    for idx, item in ipairs(self._items) do
        if item.id == id then
            self._items[idx] = nil
            self:_refresh_buffer(self:get_buf())
            break
        end
    end
end

function ItemListPage:get_or_create_buf()
    local buf, created = Page.get_or_create_buf(self)
    if not created then
        return buf, false
    end
    self:_refresh_buffer(buf)
    return buf, true
end

---@param buf number
function ItemListPage:_refresh_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    -- 1. Build lines
    local lines = {}
    for _, item in ipairs(self._items) do
        lines[#lines + 1] = item.text
    end
    -- 2. Update buffer
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
end

return ItemListPage
