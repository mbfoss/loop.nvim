-- loop/pages/ItemTreePage.lua
local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local Trackers = require("loop.tools.Trackers")

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemTreePage')

---@class loop.pages.ItemTreePage.Highlight
---@field group string
---@field start_col number 0-based
---@field end_col number 0-based

---@class loop.pages.ItemTreePage.Item
---@field id any
---@field data any?
---@field children loop.pages.ItemTreePage.Item[]?
---@field parent loop.pages.ItemTreePage.Item?
---@field expanded boolean?
---@field depth integer?

---@class loop.pages.ItemTreePage.InitArgs
---@field formatter fun(item:loop.pages.ItemTreePage.Item):string
---@field highlighter nil|fun(item:loop.pages.ItemTreePage.Item):loop.pages.ItemTreePage.Highlight[]

---@class loop.pages.ItemTreePage.TrackerCallbacks
---@field on_selection fun(item: loop.pages.ItemTreePage.Item|nil)

---@class loop.pages.ItemTreePage : loop.pages.Page
---@field new fun(self:loop.pages.ItemTreePage, name:string, args:loop.pages.ItemTreePage.InitArgs):loop.pages.ItemTreePage
---@field _args loop.pages.ItemTreePage.InitArgs
---@field _root_items loop.pages.ItemTreePage.Item[]
---@field _flat_items loop.pages.ItemTreePage.Item[]     -- currently visible lines
---@field _index table<any, number>                      -- id → flat index
---@field _trackers loop.tools.Trackers<loop.pages.ItemTreePage.TrackerCallbacks>
local ItemTreePage = class(Page)

---@param name string
---@param args loop.pages.ItemTreePage.InitArgs
function ItemTreePage:init(name, args)
    Page.init(self, "tree", name)
    self._args = args
    self._root_items = {}
    self._flat_items = {}
    self._index = {}                    -- id → 1-based index in _flat_items
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
    self:add_keymap('<CR>',         { callback = on_enter, desc = "Select or toggle" })
    self:add_keymap('<2-LeftMouse>',{ callback = on_enter, desc = "Select or toggle" })
    self:add_keymap('zo', { callback = function() self:expand_under_cursor() end,   desc = "Expand" })
    self:add_keymap('zc', { callback = function() self:collapse_under_cursor() end, desc = "Collapse" })
    self:add_keymap('za', { callback = function() self:toggle_under_cursor() end,  desc = "Toggle" })
    self:add_keymap('zM', { callback = function() self:collapse_all() end, desc = "Collapse all" })
    self:add_keymap('zR', { callback = function() self:expand_all() end,   desc = "Expand all" })
end

-- ===================================================================
-- Public API
-- ===================================================================

function ItemTreePage:add_tracker(cb)    return self._trackers:add_tracker(cb) end
function ItemTreePage:remove_tracker(id) return self._trackers:remove_tracker(id) end

function ItemTreePage:set_roots(roots)
    self._root_items = roots or {}
    self:_rebuild_flat()
    self:_refresh_buffer_full()
end

---@param item loop.pages.ItemTreePage.Item
function ItemTreePage:toggle_expand(item)
    if not item.children then return end
    item.expanded = not (item.expanded == true)
    self:_refresh_item_subtree(item)
end

function ItemTreePage:expand_under_cursor()   self:_toggle_under_cursor(true)  end
function ItemTreePage:collapse_under_cursor() self:_toggle_under_cursor(false) end
function ItemTreePage:toggle_under_cursor()   self:_toggle_under_cursor(nil)   end
function ItemTreePage:_toggle_under_cursor(expand_to)
    local item = self:get_cur_item()
    if item and item.children then
        if expand_to ~= nil then
            item.expanded = expand_to
        else
            item.expanded = not (item.expanded == true)
        end
        self:_refresh_item_subtree(item)
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
    self:_refresh_buffer_full()
end

function ItemTreePage:collapse_all()
    for _, r in ipairs(self._root_items) do r.expanded = false end
    self:_rebuild_flat()
    self:_refresh_buffer_full()
end

function ItemTreePage:get_cur_item()
    local buf = self:get_buf()
    if not buf or vim.api.nvim_get_current_buf() ~= buf then return nil end
    local row = vim.api.nvim_win_get_cursor(0)[1]  -- 1-based
    return self._flat_items[row]
end

function ItemTreePage:get_item(id)
    local idx = self._index[id]
    return idx and self._flat_items[idx] or nil
end

-- MAIN METHOD – now super fast for updates
---@param item loop.pages.ItemTreePage.Item
---@param parent_id any?
---@return loop.pages.ItemTreePage.Item|nil
function ItemTreePage:upsert_item(item, parent_id)
    assert(item and item.id ~= nil, "Item must have .id")

    local existing = self:get_item(item.id)
    if existing then
        existing.data = item.data
        self:_refresh_item_subtree(existing)   -- only affected lines
        return existing
    end

    -- INSERT NEW → full rebuild required
    local parent_node = nil
    if parent_id then
        parent_node = self:_find_node(self._root_items, parent_id)
        if not parent_node then return nil end
        parent_node.children = parent_node.children or {}
    end

    item.parent = parent_node
    if parent_node then
        table.insert(parent_node.children, item)
    else
        table.insert(self._root_items, item)
    end

    self:_rebuild_flat()
    self:_refresh_buffer_full()
    return item
end

function ItemTreePage:remove_item(id, recursive)
    if recursive == nil then recursive = true end
    local item = self:get_item(id)
    if not item then return false end

    if recursive and item.children then
        local function clear(node)
            if node.children then
                for _, c in ipairs(node.children) do clear(c) end
                node.children = nil
            end
        end
        clear(item)
    end

    -- Remove from parent
    if item.parent then
        for i, c in ipairs(item.parent.children) do
            if c == item then table.remove(item.parent.children, i); break end
        end
    else
        for i, r in ipairs(self._root_items) do
            if r == item then table.remove(self._root_items, i); break end
        end
    end

    self:_rebuild_flat()
    self:_refresh_buffer_full()
    return true
end

-- ===================================================================
-- Internal – the only places that touch the buffer
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

-- Full redraw (used only when structure changes)
function ItemTreePage:_refresh_buffer_full()
    local buf = self:get_buf()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)
    local lines = {}
    for _, item in ipairs(self._flat_items) do
        local indent = (" "):rep(item.depth or 0)
        local prefix = item.children and (item.expanded and "Down " or "Right ") or "  "
        local text = indent .. prefix .. self._args.formatter(item):gsub("\n", " ")
        table.insert(lines, text)
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- Apply highlights
    for idx, item in ipairs(self._flat_items) do
        if self._args.highlighter then
            local hls = self._args.highlighter(item) or {}
            local offset = #((" "):rep(item.depth or 0) .. (item.children and "x " or "  "))
            for _, hl in ipairs(hls) do
                vim.api.nvim_buf_set_extmark(buf, _ns_id, idx - 1, offset + hl.start_col, {
                    end_col = offset + hl.end_col,
                    hl_group = hl.group,
                    priority = 200,
                })
            end
        end
    end
end

-- Partial refresh – the star of the show
function ItemTreePage:_refresh_item_subtree(root_item)
    local buf = self:get_buf()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    local start_idx = self._index[root_item.id]
    if not start_idx then return end

    local new_lines = {}
    local extmarks = {}

    local function visit(node)
        local indent = (" "):rep(node.depth or 0)
        local prefix = node.children and (node.expanded and "Down " or "Right ") or "  "
        local text = indent .. prefix .. self._args.formatter(node):gsub("\n", " ")
        table.insert(new_lines, text)

        if self._args.highlighter then
            local hls = self._args.highlighter(node) or {}
            local offset = #indent + #prefix
            for _, hl in ipairs(hls) do
                table.insert(extmarks, {
                    row = #new_lines - 1,
                    start_col = hl.start_col and offset + hl.start_col or nil,
                    end_col   = hl.end_col and offset + hl.end_col or nil,
                    hl_group  = hl.group,
                })
            end
        end

        if node.expanded and node.children then
            for _, child in ipairs(node.children) do
                visit(child)
            end
        end
    end

    visit(root_item)

    local end_idx = start_idx + #new_lines - 1
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, start_idx - 1, end_idx - 1, false, new_lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, _ns_id, start_idx - 1, end_idx)
    for _, em in ipairs(extmarks) do
        vim.api.nvim_buf_set_extmark(buf, _ns_id, start_idx - 1 + em.row, em.start_col, {
            end_col = em.end_col,
            hl_group = em.hl_group,
            priority = 200,
        })
    end
end

-- Tiny helper used only once
function ItemTreePage:_find_node(nodes, id)
    for _, node in ipairs(nodes) do
        if node.id == id then return node end
        if node.children then
            local found = self:_find_node(node.children, id)
            if found then return found end
        end
    end
end

function ItemTreePage:get_or_create_buf()
    local buf, created = Page.get_or_create_buf(self)
    if created then self:_refresh_buffer_full() end
    return buf, created
end

return ItemTreePage