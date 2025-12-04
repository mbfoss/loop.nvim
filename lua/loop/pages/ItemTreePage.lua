local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local Trackers = require("loop.tools.Trackers")

---@class loop.pages.ItemTreePage.Highlight
---@field group string
---@field start_col number|nil 0-based
---@field end_col number|nil 0-based

---@class loop.pages.ItemTreePage.Item
---@field id any
---@field data any
---@field parent any|nil
---@field children nil|loop.pages.ItemTreePage.Item[]|fun(cb:fun(items:loop.pages.ItemTreePage.Item[])) -- ← now also accepts function
---@field expanded boolean|nil
---@field formatter_override string|nil  -- internal temporary override for loading/error messages

---@class loop.pages.ItemTreePage.TrackerCallbacks
---@field on_selection fun(item:loop.pages.ItemTreePage.Item|nil)

local NS = vim.api.nvim_create_namespace('LoopPluginItemTreePage')

---@class loop.pages.ItemTreePage.InitArgs
---@field formatter fun(item:loop.pages.ItemTreePage.Item, depth:integer, is_expanded:boolean, has_children:boolean):string
---@field highlighter nil|fun(item:loop.pages.ItemTreePage.Item, depth:integer):loop.pages.ItemTreePage.Highlight[]
---@field expand_char string?
---@field collapse_char string?
---@field indent_string string?
---@field loading_text string?  -- ← new optional field

---@class loop.pages.ItemTreePage : loop.pages.Page
---@field new fun(self: loop.pages.ItemTreePage, name:string, args:loop.pages.ItemTreePage.InitArgs): loop.pages.ItemTreePage
local ItemTreePage = class(Page)

---@param name string
---@param args loop.pages.ItemTreePage.InitArgs
function ItemTreePage:init(name, args)
    assert(args.formatter, "formatter is required")
    Page.init(self, "tree", name)

    self._args = args
    self._items = {}
    self._order = {}
    self._roots = {}
    self._nodes = {} -- incremental renderer state
    self._pending_loaders = {}

    self.expand_char = args.expand_char or "▸"
    self.collapse_char = args.collapse_char or "▾"
    self.indent_string = args.indent_string or " "
    self.loading_text = args.loading_text or "Loading..."

    self._trackers = Trackers:new()

    -- keymaps unchanged
    local function on_select()
        local item = self:get_cur_item()
        if item and item.children then
            self:toggle_expand(item.id)
        else
            self._trackers:invoke("on_selection", item)
        end
    end

    local function on_toggle()
        local item = self:get_cur_item()
        if item and item.children then
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
-- PUBLIC TRACKER API (unchanged)
---------------------------------------------------------

function ItemTreePage:add_tracker(cb) return self._trackers:add_tracker(cb) end

function ItemTreePage:remove_tracker(id) return self._trackers:remove_tracker(id) end

---------------------------------------------------------
-- INTERNAL HELPERS
---------------------------------------------------------

-- get row number of an id (0-based)
function ItemTreePage:_row_of(id)
    local entry = self._nodes[id]
    if not entry then return nil end
    local row = vim.api.nvim_buf_get_extmark_by_id(self:get_or_create_buf(), NS, entry.mark, {})[1]
    return row
end

-- delete N lines starting at row
function ItemTreePage:_delete_lines(row, count)
    if count <= 0 then return end

    local buf = self:get_or_create_buf()

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, row, row + count, false, {})
    vim.bo[buf].modifiable = false
end

-- insert N blank lines and return the starting row
function ItemTreePage:_insert_lines(row, count)
    if count <= 0 then return end
    local blanks = {}
    for _ = 1, count do blanks[#blanks + 1] = "" end

    local buf = self:get_or_create_buf()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, row, row, false, blanks)
    vim.bo[buf].modifiable = false
end

-- render a single node line at a specific row (replaces flat rebuild)
function ItemTreePage:_render_node_line(node, depth, row)
    local buf = self:get_or_create_buf()
    local item = node.item

    local has_children =
        item.children and
        (type(item.children) == "function" or (type(item.children) == "table" and #item.children > 0))

    local is_expanded = has_children and item.expanded

    local prefix = self.indent_string:rep(depth)
    if has_children then
        prefix = prefix .. (is_expanded and self.collapse_char or self.expand_char) .. " "
    else
        prefix = prefix .. "  "
    end

    local text
    if item.formatter_override then
        text = item.formatter_override
    else
        text = self._args.formatter(item, depth, is_expanded, has_children)
    end

    local line = prefix .. text:gsub("\n", " ")

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { line })
    vim.bo[buf].modifiable = false

    -- ensure extmark exists
    if node.mark then
        node.mark = vim.api.nvim_buf_set_extmark(buf, NS, row, 0, { id = node.mark })
    else
        node.mark = vim.api.nvim_buf_set_extmark(buf, NS, row, 0, {})
    end

    -- call highlighter incrementally
    if self._args.highlighter and not item.formatter_override then
        local highlights = self._args.highlighter(item, depth) or {}
        local text_len = #line
        local prefix_len = #self.indent_string * depth + (has_children and 2 or 2)
        for _, hl in ipairs(highlights) do
            local s = prefix_len + (hl.start_col or 0)
            local e = prefix_len + (hl.end_col or text_len)
            s = math.max(s, 0)
            e = math.max(e, s)
            if s < e then
                vim.api.nvim_buf_set_extmark(buf, NS, row, s, {
                    end_col = e,
                    hl_group = hl.group,
                    priority = 200,
                })
            end
        end
    end
end

---------------------------------------------------------
-- INTERNAL: Recursive expand — inserts children lines
---------------------------------------------------------

function ItemTreePage:_insert_subtree(item, depth, start_row)
    local rows_added = 0

    local children = item.children
    if not children or type(children) ~= "table" or #children == 0 then
        return 0
    end

    -- insert lines first
    self:_insert_lines(start_row, #children)

    for index, child in ipairs(children) do
        local row = start_row + index - 1

        self._nodes[child.id] = self._nodes[child.id] or { item = child }
        self._nodes[child.id].item = child
        self._nodes[child.id].depth = depth + 1

        self:_render_node_line(self._nodes[child.id], depth + 1, row)

        rows_added = rows_added + 1

        -- if the child is already expanded, recursively expand its subtree
        if child.expanded then
            rows_added = rows_added + self:_insert_subtree(child, depth + 1, row + 1)
        end
    end

    return rows_added
end

---------------------------------------------------------
-- INTERNAL: Remove a subtree (collapse)
---------------------------------------------------------

function ItemTreePage:_count_subtree(item)
    local children = item.children
    if not children or type(children) ~= "table" then return 0 end

    local count = 0
    for _, child in ipairs(children) do
        count = count + 1
        if child.expanded then
            count = count + self:_count_subtree(child)
        end
    end
    return count
end

function ItemTreePage:_delete_subtree(item)
    local row = self:_row_of(item.id)
    if not row then return end

    local start = row + 1
    local count = self:_count_subtree(item)

    self:_delete_lines(start, count)
end

---------------------------------------------------------
-- PUBLIC: set_items (unchanged API, new internals)
---------------------------------------------------------

function ItemTreePage:set_items(items)
    -- rebuild items, parents, roots (same as your version)
    self._items = {}
    self._order = {}
    self._roots = {}
    local by_id = {}

    for _, item in ipairs(items) do
        self._items[item.id] = item
        by_id[item.id] = item
        table.insert(self._order, item.id)
        if not item.parent then
            table.insert(self._roots, item)
        end
    end

    for _, item in ipairs(items) do
        if item.parent then
            local parent = by_id[item.parent]
            if parent then
                parent.children = parent.children or {}
                table.insert(parent.children, item)
            end
        end
    end

    -- reset rendering state entirely
    self._nodes = {}

    local buf = self:get_or_create_buf()
    
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.bo[buf].modifiable = false

    -- render roots
    for i, root in ipairs(self._roots) do
        self._nodes[root.id] = { item = root, depth = 0 }
        self:_insert_lines(i - 1, 1)
        self:_render_node_line(self._nodes[root.id], 0, i - 1)

        if root.expanded then
            local added = self:_insert_subtree(root, 0, i) -- insert after root
            i = i + added
        end
    end
end

---------------------------------------------------------
-- PUBLIC: upsert_item (same API, optimized render)
---------------------------------------------------------

function ItemTreePage:upsert_item(item)
    local old = self._items[item.id]
    self._items[item.id] = item

    -- preserve expanded flag
    if old and old.expanded and item.expanded == nil then
        item.expanded = true
    end

    if not old then
        table.insert(self._order, item.id)
    end

    if not old or old.parent ~= item.parent then
        self:set_items(self:get_all_items())
        return
    end

    -- incremental update: only rerender the node line
    local entry = self._nodes[item.id]
    if not entry then
        -- Item might be new in the subtree
        self:set_items(self:get_all_items())
        return
    end

    entry.item = item

    local row = self:_row_of(item.id)
    if row then
        self:_render_node_line(entry, entry.depth, row)
    end
end

---------------------------------------------------------
-- PUBLIC: expand/collapse/toggle (same API)
---------------------------------------------------------

function ItemTreePage:toggle_expand(id)
    local item = self._items[id]
    if not item or not item.children then return end

    if item.expanded then
        -- collapse
        item.expanded = false
        self:_delete_subtree(item)

        -- rerender header line
        local row = self:_row_of(id)
        if row then
            self:_render_node_line(self._nodes[id], self._nodes[id].depth, row)
        end
        return
    end

    -- expand
    if type(item.children) == "function" then
        -- async loader same as your version (with minimal changes)
        local loader = item.children
        item.expanded = true

        item.children = {
            {
                id = "__loading_" .. tostring(id),
                data = nil,
                parent = id,
                formatter_override = self.loading_text,
            }
        }

        -- insert placeholder
        local row = self:_row_of(id)
        local depth = self._nodes[id].depth
        local insert_at = row + 1

        self:_insert_lines(insert_at, 1)

        local loading = item.children[1]
        self._nodes[loading.id] = { item = loading, depth = depth + 1 }
        self:_render_node_line(self._nodes[loading.id], depth + 1, insert_at)

        -- async resolve
        vim.schedule(function()
            local finished = false
            local done = function(children)
                if finished or not item.expanded then return end
                finished = true

                -- delete placeholder
                self:_delete_lines(insert_at, 1)
                self._nodes[loading.id] = nil

                children = children or {}
                for _, child in ipairs(children) do
                    child.parent = id
                    self._items[child.id] = child
                    table.insert(self._order, child.id)
                end
                item.children = children

                -- insert real subtree
                self:_insert_subtree(item, depth, insert_at)
            end

            local ok = pcall(loader, done)
            if not ok then
                done({
                    {
                        id = "__error_" .. tostring(id),
                        formatter_override = "Error loading children",
                        parent = id,
                    }
                })
            end
        end)

        return
    end

    -- normal children table
    item.expanded = true

    local row = self:_row_of(id)
    self:_insert_subtree(item, self._nodes[id].depth, row + 1)

    -- rerender header
    self:_render_node_line(self._nodes[id], self._nodes[id].depth, row)
end

function ItemTreePage:expand(id)
    local item = self._items[id]
    if not item or not item.children or item.expanded then return end
    self:toggle_expand(id)
end

function ItemTreePage:collapse(id)
    local item = self._items[id]
    if not item or not item.children or not item.expanded then return end
    self:toggle_expand(id)
end

---------------------------------------------------------
-- Public API: getters (unchanged)
---------------------------------------------------------

function ItemTreePage:get_item(id)
    return self._items[id]
end

function ItemTreePage:get_all_items()
    local items = {}
    for _, id in ipairs(self._order) do
        items[#items + 1] = self._items[id]
    end
    return items
end

-- Find current item using extmarks (instead of _flat)
function ItemTreePage:get_cur_item()
    local buf = self:get_or_create_buf()
    
    if not buf or buf ~= vim.api.nvim_get_current_buf() then return nil end
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1

    -- naive search (can be optimized with row→id map if needed)
    for id, entry in pairs(self._nodes) do
        local erow = self:_row_of(id)
        if erow == row then
            return self._items[id]
        end
    end
    return nil
end

---------------------------------------------------------
-- Public refresh_content() → full re-render
---------------------------------------------------------

function ItemTreePage:refresh_content()
    self:set_items(self:get_all_items())
end

return ItemTreePage
