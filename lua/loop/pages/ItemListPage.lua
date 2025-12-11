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

---@class loop.pages.ItemListPage.Tracker : loop.pages.Pages.Tracker
---@field on_selection fun(item:loop.pages.ItemListPage.Item|nil)

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemListPage')

---@class loop.pages.ItemListPage.InitArgs
---@field formatter fun(item:loop.pages.ItemListPage.Item,out_highlights:loop.pages.ItemTreePage.Highlight[]):string
---@field show_current_prefix boolean|nil            # NEW: whether to show ">" prefix on current item
---@field current_prefix string|nil                  # NEW: custom prefix, defaults to "> "

---@class loop.pages.ItemListPage : loop.pages.Page
---@field new fun(self: loop.pages.ItemListPage, name:string, args:loop.pages.ItemListPage.InitArgs): loop.pages.ItemListPage
---@field _args loop.pages.ItemListPage.InitArgs
---@field _items loop.pages.ItemListPage.Item[]
---@field _index table<any,number>
---@field _select_handler fun(item:loop.pages.ItemListPage.Item|nil)
---@field _trackers loop.tools.Trackers<loop.pages.ItemListPage.Tracker>
---@field _current_item loop.pages.ItemListPage.Item|nil   # NEW: currently active item
---@field _current_prefix string                            # NEW: resolved prefix
local ItemListPage = class(Page)

---@param name string
---@param args loop.pages.ItemListPage.InitArgs
function ItemListPage:init(name, args)
    assert(args.formatter)
    Page.init(self, "list", name)
    self._args = args
    self._items = {}
    self._index = {}

    -- NEW: current item tracking
    self._current_item = nil
    if args.show_current_prefix then
        self._current_prefix = args.current_prefix or "> "
        self._noncurrent_prefix = (" "):rep(#self._current_prefix)
    end

    local select_handler = function()
        local item = self:get_item_under_cursor()
        self:set_current_item(item) -- will trigger prefix update if enabled
        self._trackers:invoke("on_selection", item)
    end

    self:add_keymap('<CR>', { callback = select_handler, desc = "Select item" })
    self:add_keymap('<2-LeftMouse>', { callback = select_handler, desc = "Select item" })
end

-- NEW: Public API to set current item (used by selection, or externally)
---@param item loop.pages.ItemListPage.Item|nil
function ItemListPage:set_current_item(item)
    if self._current_item == item then return end
    self._current_item = item
    if self._args.show_current_prefix then
        self:refresh_content() -- rebuild lines with updated prefixes
    end
end

-- NEW: Get current item (cursor fallback if none explicitly set)
---@return loop.pages.ItemListPage.Item|nil
function ItemListPage:get_current_item()
    return self._current_item
end

---@param callbacks loop.pages.ItemListPage.Tracker
---@return number
function ItemListPage:add_tracker(callbacks) return self._trackers:add_tracker(callbacks) end

---@return boolean
function ItemListPage:remove_tracker(id) return self._trackers:remove_tracker(id) end

function ItemListPage:set_items(items)
    self._items = items
    self._index = {}
    for i, item in ipairs(items) do
        assert(not self._index[item.id], "duplicate item id")
        self._index[item.id] = i
    end
    -- Reset current item if it's no longer in the list
    if self._current_item and not self._index[self._current_item.id] then
        self._current_item = nil
    end
    self:_refresh_buffer(self:get_buf())
    self:send_change_notification()
end

function ItemListPage:upsert_item(item)
    assert(item and item.id and item.data)
    local pos = self._index[item.id] or (#self._items + 1)
    self._items[pos] = item
    self._index[item.id] = pos

    local buf = self:get_buf()
    if buf == -1 then return end

    ---@type loop.pages.ItemTreePage.Highlight[]
    local highlights = {}
    local formatted = self._args.formatter(item, highlights):gsub("\n", " ")
    if self._args.show_current_prefix then
        if self._current_item and self._current_item.id == item.id then
            formatted = self._current_prefix .. formatted
        else
            formatted = self._noncurrent_prefix .. formatted
        end
    end

    local lines = { formatted }

    if buf then
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, pos - 1, pos, false, lines)
        vim.bo[buf].modifiable = false
    end

    self:_highlight(pos, highlights)
    self:send_change_notification()
end

function ItemListPage:get_item_under_cursor()
    local current_buf = vim.api.nvim_get_current_buf()
    local page_buf = self:get_buf()
    if not page_buf or current_buf ~= page_buf then
        return nil
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local item = self._items[row]
    return item or nil
end

---@return loop.pages.ItemListPage.Item[]
function ItemListPage:get_items()
    return self._items;
end

---@param id number
---@return loop.pages.ItemListPage.Item
function ItemListPage:get_item(id)
    local idx = self._index[id]
    return idx and self._items[idx] or nil
end

---@param id number
function ItemListPage:remove_item(id)
    local idx = self._index[id]
    if not idx then return end

    if self._current_item and self._current_item.id == id then
        self._current_item = nil
    end

    table.remove(self._items, idx)
    self._index[id] = nil
    for i = idx, #self._items do
        self._index[self._items[i].id] = i
    end

    if self._refresh_timer then
        self._refresh_timer:stop()
    end
    self._refresh_timer = vim.defer_fn(function()
        self:_refresh_buffer(self:get_buf())
        self._refresh_timer = nil
    end, 100)
end

function ItemListPage:get_or_create_buf()
    local buf, refresh = Page.get_or_create_buf(self)
    if refresh then
        self:_refresh_buffer(buf)
    end
    return buf, refresh
end

---@param idx number
---@param highlights loop.pages.ItemTreePage.Highlight[]
function ItemListPage:_highlight(idx, highlights)
    local buf = self._buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    local item = self._items[idx]
    if #highlights > 0 then
        local line_text = vim.api.nvim_buf_get_lines(buf, idx - 1, idx, false)[1] or ""
        local line_len = #line_text

        -- Adjust for current prefix if present
        local offset = 0
        if self._args.show_current_prefix then
            if self._current_item and self._current_item.id == item.id then
                offset = #self._current_prefix
            else
                offset = #self._noncurrent_prefix
            end
        end

        for _, hl in ipairs(highlights) do
            local start_col = (hl.start_col or 0) + offset
            local end_col = hl.end_col and (hl.end_col + offset) or (line_len)
            end_col = math.min(end_col, line_len)

            start_col = math.max(0, start_col)
            if start_col < end_col then
                vim.api.nvim_buf_set_extmark(buf, _ns_id, idx - 1, start_col, {
                    end_col = end_col,
                    hl_group = hl.group,
                    priority = 200,
                })
            end
        end
    end
end

-- MODIFIED: now respects current prefix
function ItemListPage:_refresh_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)

    ---@type loop.pages.ItemTreePage.Highlight[][]
    local all_highlights = {}
    local lines = {}
    for _, item in ipairs(self._items) do
        local highlights = {}
        local text = self._args.formatter(item, highlights):gsub("\n", " ")
        table.insert(all_highlights, highlights)
        if self._args.show_current_prefix then
            if self._current_item and self._current_item.id == item.id then
                text = self._current_prefix .. text
            else
                text = self._noncurrent_prefix .. text
            end
        end
        lines[#lines + 1] = text
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    assert(#all_highlights == #lines)
    for idx, highlights in ipairs(all_highlights) do
        self:_highlight(idx, highlights)
    end
end

function ItemListPage:refresh_content()
    self:_refresh_buffer(self:get_buf())
end

return ItemListPage
