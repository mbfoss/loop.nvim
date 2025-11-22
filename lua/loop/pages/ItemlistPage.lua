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
---@field _index table<number,number>
local ItemListPage = class(Page)

---@param name string
---@param keymaps loop.pages.page.KeyMaps
function ItemListPage:init(name, keymaps)
    Page.init(self, "list", name, keymaps)
    self._items = {}
    self._index = {}
end

---@param items loop.pages.ItemListPage.Item[]
function ItemListPage:set_items(items)
    self._items = items
    self._index = {}
    for i, item in ipairs(items) do
        self._index[item.id] = i
    end
    self:_refresh_buffer(self:get_buf())
end

---@param item loop.pages.ItemListPage.Item
function ItemListPage:add_item(item)
    table.insert(self._items, item)
    self._index[item.id] = #self._items

    local buf = self:get_buf()
    if buf == -1 then return end

    vim.api.nvim_buf_set_lines(buf, #self._items - 1, #self._items - 1, false, { item.text })
    self:_highlight(#self._items, #self._items)
end

---@return number|nil  -- item id under cursor, or nil if buffer not active or no item
function ItemListPage:get_cur_item()
    local current_buf = vim.api.nvim_get_current_buf()
    local page_buf = self:get_buf()

    -- If this page's buffer is not the current buffer, return nil
    if current_buf ~= page_buf or page_buf == -1 then
        return nil
    end

    -- Get cursor position in the current window (which shows our buffer)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] -- 1-based line number

    local item = self._items[row]
    return item and item.id or nil
end

---@param id number
---@return any
function ItemListPage:get_item_data(id)
    local idx = self._index[id]
    local item = idx and self._items[idx]
    if item then
        return item.data
    end
    return nil
end

---@return any
function ItemListPage:get_cur_item_data()
    local id = self:get_cur_item()
    return id and self:get_item_data(id) or nil
end

---@param id number
function ItemListPage:remove_item(id)
    local idx = self._index[id]
    if not idx then return end

    local buf = self:get_buf()

    -- Remove from table
    table.remove(self._items, idx)
    self._index[id] = nil

    -- Update indices of items after removed item
    for i = idx, #self._items do
        self._index[self._items[i].id] = i
    end

    if buf == -1 then return end

    -- Delete buffer line and re-highlight remaining lines
    vim.api.nvim_buf_set_lines(buf, idx - 1, idx, false, {})
    vim.api.nvim_buf_clear_namespace(buf, _ns_id, idx - 1, -1)
    self:_highlight(idx, #self._items)
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
    for idx = from, to do
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
