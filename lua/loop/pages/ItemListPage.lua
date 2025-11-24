local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local uitools = require('loop.tools.uitools')

---@class loop.pages.ItemListPage.highlight
---@field group string
---@field start_col number 0-based
---@field end_col number 0-based

---@class loop.pages.ItemListPage.Item
---@field id any
---@field text string
---@field data any
---@field highlights loop.pages.ItemListPage.highlight[]|nil

local _ns_id = vim.api.nvim_create_namespace('LoopPluginPage')

---@class loop.pages.ItemListPage : loop.pages.Page
---@field new fun(self: loop.pages.ItemListPage, name:string, keymaps:loop.pages.page.KeyMaps): loop.pages.Page
---@field _items loop.pages.ItemListPage.Item[]
---@field _index table<any,number>
---@field _item_selection_handler fun(item:loop.pages.ItemListPage.Item|nil)
local ItemListPage = class(Page)

---@param name string
---@param keymaps loop.pages.page.KeyMaps
function ItemListPage:init(name, keymaps)
    Page.init(self, "list", name, keymaps)
    self._items = {}
    self._index = {}

    self:add_keymap('<CR>', { callback = function() self:_on_item_selected() end, desc = "Select item" })
    self:add_keymap('<2-LeftMouse>', { callback = function() self:_on_item_selected() end, desc = "Select item" })
end

---@param handler fun(item:loop.pages.ItemListPage.Item)
function ItemListPage:set_select_handler(handler)
    assert(not self._item_selection_handler)
    self._item_selection_handler = handler
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
function ItemListPage:set_item(item)
    assert(item and item.id and item.text and type(item.text) == "string")
    local pos = self._index[item.id] or (#self._items + 1)
    self._items[pos] = item
    self._index[item.id] = pos

    local buf = self:get_buf()
    if buf == -1 then return end

    local lines = {}
    lines[1] = item.text:gsub("\n", " ")
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, pos - 1, pos - 1, false, lines)
    vim.bo[buf].modifiable = false
    self:_highlight(pos, pos)
end

---@return loop.pages.ItemListPage.Item|nil  -- item id under cursor, or nil if buffer not active or no item
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
    if item then
        return vim.tbl_extend("force", {}, item) --shallow copy
    end
    return nil
end

---@param id any
---@return loop.pages.ItemListPage.Item|nil
function ItemListPage:get_item(id)
    local idx = self._index[id]
    local item = idx and self._items[idx]
    if item then
        return vim.tbl_extend("force", {}, item) --shallow copy
    end
    return nil
end

---@param id any
function ItemListPage:remove_item(id)
    local idx = self._index[id]
    if not idx then return end

    -- Remove from table
    table.remove(self._items, idx)
    self._index[id] = nil

    -- Update indices of items after removed item
    for i = idx, #self._items do
        self._index[self._items[i].id] = i
    end

    -- debounce the UI part
    if self._refresh_timer then
        self._refresh_timer:stop()
    end

    self._refresh_timer = vim.defer_fn(function()
        local buf = self:get_buf()
        if buf ~= -1 then
            vim.bo[buf].modifiable = true
            vim.api.nvim_buf_set_lines(buf, idx - 1, idx, false, {})
            vim.bo[buf].modifiable = false
            vim.api.nvim_buf_clear_namespace(buf, _ns_id, idx - 1, -1)
            self:_highlight(idx, #self._items)
        end
        self._refresh_timer = nil
    end, 100)
end

function ItemListPage:get_or_create_buf()
    local buf, created = Page.get_or_create_buf(self)
    if not created then
        return buf, false
    end
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
        if item.highlights then
            for _, hl in ipairs(item.highlights) do
                local endcol = math.min(hl.end_col, #item.text)
                vim.api.nvim_buf_set_extmark(self._buf, _ns_id, idx - 1, hl.start_col, {
                    end_col = endcol,
                    hl_group = hl.group,
                    --hl_eol = true,
                    priority = 200,
                })
            end
        end
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
        lines[#lines + 1] = item.text:gsub("\n", " ")
    end

    -- update buffer
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    self:_highlight(1, #self._items)
end

function ItemListPage:_on_item_selected()
    if self._item_selection_handler then
        self._item_selection_handler(self:get_cur_item())
    end
end

return ItemListPage
