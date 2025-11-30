-- loop/pages/ItemTreePage.lua
local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local Trackers = require("loop.tools.Trackers")

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemTreePage')

---@class loop.pages.ItemTreePage.Highlight
---@field group string
---@field start_col number 0-based
---@field end_col number 0-based

--
---@class loop.pages.ItemTreePage.Item
---@field id any
---@field text string
---@field data any?
---@field highlights loop.pages.ItemTreePage.Highlight[]|nil
---@field children loop.pages.ItemTreePage.Item[]?
---@field parent loop.pages.ItemTreePage.Item?
---@field expanded boolean?
---@field depth integer?

---@class loop.pages.ItemTreePage.TrackerCallbacks
---@field on_selection fun(item: loop.pages.ItemTreePage.Item|nil)

---@class loop.pages.ItemTreePage : loop.pages.Page
---@field new fun(self:loop.pages.ItemTreePage, name:string):loop.pages.ItemTreePage
---@field _root_items loop.pages.ItemTreePage.Item[]
---@field _flat_items loop.pages.ItemTreePage.Item[]     -- currently visible lines
---@field _index table<any, number>                      -- id → flat index
---@field _trackers loop.tools.Trackers<loop.pages.ItemTreePage.TrackerCallbacks>
local ItemTreePage = class(Page)

function ItemTreePage:init(name)
    Page.init(self, "tree", name)

    self._root_items = {}
    self._flat_items = {}
    self._index = {}
    self._trackers = Trackers:new()

    -- Keymaps
    local function on_enter()
        local item = self:get_cur_item()
        if item and item.children then
            self:toggle_expand(item)
        else
            self._trackers:invoke("on_selection", item)
        end
    end

    self:add_keymap('<CR>', { callback = on_enter, desc = "Select or toggle folder" })
    self:add_keymap('<2-LeftMouse>', { callback = on_enter, desc = "Select or toggle folder" })
    self:add_keymap('zo', { callback = function() self:expand_under_cursor() end, desc = "Expand folder" })
    self:add_keymap('zc', { callback = function() self:collapse_under_cursor() end, desc = "Collapse folder" })
    self:add_keymap('za', { callback = function() self:toggle_under_cursor() end, desc = "Toggle folder" })
    self:add_keymap('zM', { callback = function() self:collapse_all() end, desc = "Collapse all" })
    self:add_keymap('zR', { callback = function() self:expand_all() end, desc = "Expand all" })
end

-- ===================================================================
-- Public API
-- ===================================================================

---@param callbacks loop.pages.ItemTreePage.TrackerCallbacks
---@return number tracker_id
function ItemTreePage:add_tracker(callbacks)
    return self._trackers:add_tracker(callbacks)
end

---@param id number
---@return boolean
function ItemTreePage:remove_tracker(id)
    return self._trackers:remove_tracker(id)
end

---@param roots loop.pages.ItemTreePage.Item[]
function ItemTreePage:set_roots(roots)
    self._root_items = roots or {}
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

---@param item loop.pages.ItemTreePage.Item
function ItemTreePage:toggle_expand(item)
    if not item.children then return end
    item.expanded = not (item.expanded == true)
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

function ItemTreePage:expand_under_cursor()
    local item = self:get_cur_item()
    if item and item.children and not item.expanded then
        item.expanded = true
        self:_rebuild_flat()
        self:_refresh_buffer(self:get_buf())
    end
end

function ItemTreePage:collapse_under_cursor()
    local item = self:get_cur_item()
    if item and item.children and item.expanded then
        item.expanded = false
        self:_rebuild_flat()
        self:_refresh_buffer(self:get_buf())
    end
end

function ItemTreePage:toggle_under_cursor()
    local item = self:get_cur_item()
    if item and item.children then
        self:toggle_expand(item)
    end
end

function ItemTreePage:expand_all()
    local function rec(node)
        if node.children then
            node.expanded = true
            for _, c in ipairs(node.children) do rec(c) end
        end
    end
    for _, r in ipairs(self._root_items) do rec(r) end
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

function ItemTreePage:collapse_all()
    for _, r in ipairs(self._root_items) do
        r.expanded = false
    end
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

---@return loop.pages.ItemTreePage.Item|nil
function ItemTreePage:get_cur_item()
    local buf = self:get_buf()
    if vim.api.nvim_get_current_buf() ~= buf or buf == -1 then
        return nil
    end
    local row = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
    return self._flat_items[row]
end

---@param id any
---@return loop.pages.ItemTreePage.Item|nil
function ItemTreePage:get_item(id)
    local idx = self._index[id]
    return idx and self._flat_items[idx] or nil
end

--- Upserts (update or insert) an item in the tree.
--- • If item with same `id` exists → updates text/data/highlights in-place (preserves position, children, expanded state)
--- • Otherwise → adds as child of `parent_id` (or root if nil)
--- Returns the final item (existing or newly inserted), or nil if parent not found.
---@param item loop.pages.ItemTreePage.Item
---@param parent_id any?     -- nil = root level
---@return loop.pages.ItemTreePage.Item|nil
function ItemTreePage:upsert_item(item, parent_id)
    assert(item and item.id ~= nil and item.text ~= nil, "Invalid item: must have .id and .text")

    local existing = self:get_item(item.id)

    if existing then
        -- UPDATE existing node in-place
        existing.text       = item.text
        existing.data       = item.data
        existing.highlights = item.highlights or existing.highlights

        -- Preserve: parent, children, expanded state, depth, etc.
        self:_refresh_buffer(self:get_buf()) -- only need to redraw highlights + text
        return existing
    end

    -- INSERT new node
    local parent_node = nil

    if parent_id ~= nil then
        -- Find parent recursively
        local function find(node)
            if node.id == parent_id then return node end
            if node.children then
                for _, child in ipairs(node.children) do
                    local found = find(child)
                    if found then return found end
                end
            end
        end

        for _, root in ipairs(self._root_items) do
            parent_node = find(root)
            if parent_node then break end
        end

        if not parent_node then
            return nil
        end                -- parent not found
        parent_node.children = parent_node.children or {}
    else
        -- Adding as new root
        parent_node = nil
    end

    -- Actually insert
    item.parent = parent_node
    if parent_node then
        table.insert(parent_node.children, item)
    else
        table.insert(self._root_items, item)
    end

    -- Full rebuild needed for new node
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())

    return item
end

--- Removes an item (and optionally all its descendants) from the tree.
--- Returns true if the item was found and removed, false otherwise.
---@param id any                      -- item id to remove
---@param recursive boolean|nil        -- if true/nil, also remove all children (default: true)
---@return boolean removed
function ItemTreePage:remove_item(id, recursive)
    if recursive == nil then recursive = true end

    -- Helper: detach from parent’s children table
    local function detach_from_parent(item)
        if not item.parent then
            -- It's a root
            for i, root in ipairs(self._root_items) do
                if root == item then
                    table.remove(self._root_items, i)
                    return true
                end
            end
        else
            if item.parent.children then
                for i, child in ipairs(item.parent.children) do
                    if child == item then
                        table.remove(item.parent.children, i)
                        return true
                    end
                end
            end
        end
        return false
    end

    local item = self:get_item(id)
    if not item then return false end

    if recursive and item.children then
        -- Clear children recursively so we don't leave dangling references
        local function clear_children(node)
            if node.children then
                for _, child in ipairs(node.children) do
                    clear_children(child)
                end
                node.children = nil
            end
        end
        clear_children(item)
    end

    -- Actually remove from the tree structure
    detach_from_parent(item)

    -- Rebuild flat view and refresh buffer
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())

    return true
end

-- ===================================================================
-- Internal
-- ===================================================================

function ItemTreePage:_rebuild_flat()
    self._flat_items = {}
    self._index = {}

    local function visit(node, depth)
        node.depth = depth
        node.expanded = (node.expanded ~= false)

        table.insert(self._flat_items, node)
        self._index[node.id] = #self._flat_items

        if node.expanded and node.children then
            for _, child in ipairs(node.children) do
                child.parent = node
                visit(child, depth + 1)
            end
        end
    end

    for _, root in ipairs(self._root_items) do
        root.parent = nil
        visit(root, 0)
    end
end

---@param buf number
function ItemTreePage:_refresh_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)

    local lines = {}
    for _, item in ipairs(self._flat_items) do
        local indent = ("  "):rep(item.depth)
        local prefix = item.children and (item.expanded and "▼ " or "▶ ") or "  "
        local line = indent .. prefix .. item.text:gsub("\n", " ")
        table.insert(lines, line)
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- Apply highlights with correct offset
    for idx, item in ipairs(self._flat_items) do
        if item.highlights then
            local offset = #(("  "):rep(item.depth) .. (item.children and "x " or "  "))
            for _, hl in ipairs(item.highlights) do
                local start_col = hl.start_col + offset
                local end_col
                end_col = hl.end_col + offset
                vim.api.nvim_buf_set_extmark(buf, _ns_id, idx - 1, start_col, {
                    end_col = end_col,
                    hl_group = hl.group,
                    priority = 200,
                })
            end
        end
    end
end

function ItemTreePage:get_or_create_buf()
    local buf, created = Page.get_or_create_buf(self)
    if created then
        self:_refresh_buffer(buf)
    end
    return buf, created
end

return ItemTreePage
