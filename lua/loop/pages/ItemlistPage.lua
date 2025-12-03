local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local Trackers = require("loop.tools.Trackers")

---@class loop.pages.ItemListPage.Highlight
---@field group string
---@field start_col number|nil 0-based
---@field end_col number|nil 0-based

---@class loop.pages.ItemListPage.Item
---@field id any
---@field data any

---@class loop.pages.ItemListPage.TrackerCallbacks
---@field on_selection fun(item:loop.pages.ItemListPage.Item|nil)

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemListPage')

---@class loop.pages.ItemListPage.InitArgs
---@field formatter fun(item:loop.pages.ItemListPage.Item):string
---@field highlighter nil|fun(item:loop.pages.ItemListPage.Item):loop.pages.ItemListPage.Highlight[]

---@class loop.pages.ItemListPage : loop.pages.Page
---@field new fun(self: loop.pages.ItemListPage, name:string, args:loop.pages.ItemListPage.InitArgs): loop.pages.ItemListPage
---@field _args loop.pages.ItemListPage.InitArgs
---@field _items loop.pages.ItemListPage.Item[]
---@field _index table<any,number>
---@field _select_handler fun(item:loop.pages.ItemListPage.Item|nil)
---@field _trackers loop.tools.Trackers<loop.pages.ItemListPage.TrackerCallbacks>
local ItemListPage = class(Page)

---@param name string
---@param args loop.pages.ItemListPage.InitArgs
function ItemListPage:init(name, args)
    assert(args.formatter)
    Page.init(self, "list", name)
    self._args = args
    self._items = {}
    self._index = {}
    self._trackers = Trackers:new()

    local select_handler = function()
        self._trackers:invoke("on_selection", self:get_cur_item())
    end

    self:add_keymap('<CR>', { callback = select_handler, desc = "Select item" })
    self:add_keymap('<2-LeftMouse>', { callback = select_handler, desc = "Select item" })
end

---@param callbacks loop.pages.ItemListPage.TrackerCallbacks>
---@return number
function ItemListPage:add_tracker(callbacks)
    return self._trackers:add_tracker(callbacks)
end

---@param id number
---@return boolean
function ItemListPage:remove_tracker(id)
    return self._trackers:remove_tracker(id)
end

---@param items loop.pages.ItemListPage.Item[]
function ItemListPage:set_items(items)
    self._items = items
    self._index = {}
    for i, item in ipairs(items) do
        assert(not self._index[item.id], "duplicate item id")
        self._index[item.id] = i
    end

    self:_refresh_buffer(self:get_buf())
end

---@param item loop.pages.ItemListPage.Item
function ItemListPage:upsert_item(item)
    assert(item and item.id and item.data)
    local pos = self._index[item.id] or (#self._items + 1)
    self._items[pos] = item
    self._index[item.id] = pos

    local buf = self:get_buf()
    if buf == -1 then return end

    local lines = {}
    lines[1] = self._args.formatter(item):gsub("\n", " ")

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, pos - 1, pos, false, lines)
    vim.bo[buf].modifiable = false

    self:_highlight(pos, pos)
end

---@return loop.pages.ItemListPage.Item|nil  -- item under cursor, or nil if buffer not active or no item
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
        return item
    end
    return nil
end

---@param id any
---@return loop.pages.ItemListPage.Item|nil
function ItemListPage:get_item(id)
    local idx = self._index[id]
    local item = idx and self._items[idx]
    if item then
        return item
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
        self:_refresh_buffer(self:get_buf())
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

---@param from number 1-based start index in self._items
---@param to   number 1-based end index in self._items
function ItemListPage:_highlight(from, to)
    if from > to then return end
    local buf = self._buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    for idx = from, to do
        local item = self._items[idx]
        local highlights = self._args.highlighter and self._args.highlighter(item) or nil
        if highlights then
            -- Get the actual text of the current line (already rendered)
            local line_text = vim.api.nvim_buf_get_lines(buf, idx - 1, idx, false)[1] or ""
            local line_len  = #line_text

            for _, hl in ipairs(highlights) do
                local start_col = hl.start_col or 0
                local end_col   = hl.end_col or line_len
                start_col       = math.max(0, start_col)
                end_col         = math.max(start_col, math.min(end_col, line_len))
                if start_col < end_col then
                    vim.api.nvim_buf_set_extmark(buf, _ns_id, idx - 1, start_col, {
                        end_col  = end_col,
                        hl_group = hl.group,
                        priority = 200,
                        -- hl_eol = true,        -- uncomment if you want highlight to extend to EOL when end_col == line_len
                    })
                end
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
        lines[#lines + 1] = self._args.formatter(item):gsub("\n", " ")
    end

    -- update buffer
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    self:_highlight(1, #self._items)
end

function ItemListPage:refresh_content()
    self:_refresh_buffer(self:get_buf())
end

return ItemListPage
