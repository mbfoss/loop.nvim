local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local Trackers = require("loop.tools.Trackers")

---@class loop.pages.ItemTreePage.Highlight
---@field group string
---@field start_col number|nil 0-based
---@field end_col number|nil 0-based

---@class loop.pages.ItemTreePage.Item
---@field id number
---@field data any
---@field parent number|nil
---@field children nil|loop.pages.ItemTreePage.Item[]
---@field children_callback nil|fun(cb:fun(items:loop.pages.ItemTreePage.Item[]))
---@field expanded boolean|nil
---@field formatter_override string|nil

---@class loop.pages.ItemTreePage.TrackerCallbacks
---@field on_selection fun(item:loop.pages.ItemTreePage.Item|nil)

---@class loop.pages.ItemTreePage.InitArgs
---@field formatter fun(item:loop.pages.ItemTreePage.Item):string
---@field highlighter nil|fun(item:loop.pages.ItemTreePage.Item):loop.pages.ItemTreePage.Highlight[]
---@field expand_char string?
---@field collapse_char string?
---@field indent_string string?
---@field loading_text string?

---@class loop.pages.ItemTreePage : loop.pages.Page
---@field new fun(self: loop.pages.ItemTreePage, name:string, args:loop.pages.ItemTreePage.InitArgs): loop.pages.ItemTreePage
local ItemTreePage = class(Page)

local NS = vim.api.nvim_create_namespace('LoopPluginItemTreePage')

---@param name string
---@param args loop.pages.ItemTreePage.InitArgs
function ItemTreePage:init(name, args)
    assert(args.formatter, "formatter is required")
    Page.init(self, "tree", name)

    self.formatter = args.formatter
    self.highlighter = args.highlighter
    self.expand_char = args.expand_char or "▸"
    self.collapse_char = args.collapse_char or "▾"
    self.indent_string = args.indent_string or " "
    self.loading_text = args.loading_text or "Loading..."

    self._trackers = Trackers:new()
    self._items = {} -- array
    self._by_id = {} -- id -> item
    self._flat = {}  -- flattened visible items

    local function on_select()
        local item = self:get_cur_item()
        if item and (item.children or item.children_callback) then
            self:toggle_expand(item.id)
        else
            self._trackers:invoke("on_selection", item)
        end
    end

    local function on_toggle()
        local item = self:get_cur_item()
        if item and (item.children or item.children_callback) then
            self:toggle_expand(item.id)
        end
    end

    self:add_keymap('<CR>', { callback = on_select, desc = "Select or expand/collapse" })
    self:add_keymap('<2-LeftMouse>', { callback = on_select, desc = "Select or expand/collapse" })
    self:add_keymap('zo', { callback = on_toggle, desc = "Expand node" })
    self:add_keymap('zc', { callback = on_toggle, desc = "Collapse node" })
    self:add_keymap('za', { callback = on_toggle, desc = "Toggle expand/collapse" })
end

---------------------------------------------------------
-- TRACKERS
---------------------------------------------------------
function ItemTreePage:add_tracker(cb) return self._trackers:add_tracker(cb) end

function ItemTreePage:remove_tracker(id) return self._trackers:remove_tracker(id) end

---------------------------------------------------------
-- ITEM MANAGEMENT
---------------------------------------------------------
function ItemTreePage:set_items(items)
    self._items = {}
    self._by_id = {}
    for _, item in ipairs(items) do
        assert(not self._by_id[item.id])
        self._by_id[item.id] = item
        table.insert(self._items, item)
    end
    self:_rebuild_flat()
    self:render()
end

-- Add or update an item
function ItemTreePage:insert_item(item)

    assert(not self._by_id[item.id])
    -- Store in flat items table
    self._by_id[item.id] = item
    table.insert(self._items, item)

    -- Attach to parent if it exists
    if item.parent then
        local parent = self._by_id[item.parent]
        if parent then
            parent.children = parent.children or {}
            local exists = false
            for _, c in ipairs(parent.children) do
                if c.id == item.id then exists = true end
            end
            if not exists then
                table.insert(parent.children, item)
            end
        end
    end

    -- Rebuild tree and render
    self:_rebuild_flat()
    self:render()
end

-- Flatten the tree into _flat for rendering
function ItemTreePage:_rebuild_flat()
    self._flat = {}

    local function walk(item, depth)
        item._depth = depth
        table.insert(self._flat, item)

        if item.expanded then
            -- If async children not loaded yet
            if item.children_callback and not item.children then
                local loading_item = { data = self.loading_text, _depth = depth + 1 }
                table.insert(self._flat, loading_item)

                -- Load children asynchronously
                item.children_callback(function(children)
                    -- Ensure children are properly attached to parent
                    item.children = children
                    for _, c in ipairs(children) do
                        assert(not self._by_id[c.id])
                        c.parent = item.id
                        self._by_id[c.id] = c
                        table.insert(self._items, c)
                    end
                    self:_rebuild_flat()
                    self:render()
                end)
            elseif item.children then
                -- Walk all children recursively
                for _, child in ipairs(item.children) do
                    walk(child, depth + 1)
                end
            end
        end
    end

    -- Only start from top-level items
    for _, item in ipairs(self._items) do
        if not item.parent then
            walk(item, 0)
        end
    end
end

---------------------------------------------------------
-- EXPAND / COLLAPSE
---------------------------------------------------------
function ItemTreePage:toggle_expand(id)
    local item = self:get_item(id)
    if not item then return end
    item.expanded = not item.expanded
    self:_rebuild_flat()
    self:render()
end

function ItemTreePage:expand(id)
    local item = self:get_item(id)
    if item then
        item.expanded = true
        self:_rebuild_flat()
        self:render()
    end
end

function ItemTreePage:collapse(id)
    local item = self:get_item(id)
    if item then
        item.expanded = false
        self:_rebuild_flat()
        self:render()
    end
end

---------------------------------------------------------
-- GETTERS
---------------------------------------------------------
function ItemTreePage:get_item(id)
    return self._by_id[id]
end

function ItemTreePage:get_all_items()
    return self._items
end

function ItemTreePage:get_cur_item()
    local row = vim.fn.line('.') - 1
    return self._flat[row + 1]
end

---------------------------------------------------------
-- RENDER
---------------------------------------------------------
function ItemTreePage:render()
    local buf = self:get_buf()
    if not buf then return end

    local lines = {}
    local extmarks = {}

    for i, item in ipairs(self._flat) do
        local prefix = ""
        if item.id and (item.children or item.children_callback) then
            prefix = item.expanded and self.collapse_char or self.expand_char
        end
        local indent = string.rep(self.indent_string, item._depth or 0)
        local text = item.formatter_override or (item.id and self.formatter(item) or item.data or "")
        lines[i] = indent .. prefix .. " " .. text

        if item.id and self.highlighter then
            local hl_items = self.highlighter(item)
            if hl_items then
                for _, hl in ipairs(hl_items) do
                    table.insert(extmarks, {
                        row = i - 1,
                        col_start = hl.start_col or 0,
                        col_end = hl.end_col or #text,
                        group = hl.group,
                    })
                end
            end
        end
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    for _, mark in ipairs(extmarks) do
        vim.api.nvim_buf_add_highlight(buf, NS, mark.group, mark.row, mark.col_start, mark.col_end)
    end
end

function ItemTreePage:get_or_create_buf()
    local buf, created = Page.get_or_create_buf(self)
    if not created then
        return buf, false
    end
    self:render()
    return buf, true
end

return ItemTreePage
