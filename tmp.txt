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

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemTreePage')

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
    self._flat = {}
    self._trackers = Trackers:new()

    self.expand_char = args.expand_char or "▸"
    self.collapse_char = args.collapse_char or "▾"
    self.indent_string = args.indent_string or " "
    self.loading_text = args.loading_text or "Loading..."

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

function ItemTreePage:add_tracker(callbacks) return self._trackers:add_tracker(callbacks) end
function ItemTreePage:remove_tracker(id) return self._trackers:remove_tracker(id) end

function ItemTreePage:_rebuild_flat()
    local flat = {}
    local idx = 1
    local visited = {}
    local function visit(item, depth)
        if visited[item] then return end
        visited[item] = true
        flat[idx] = { item = item, depth = depth }
        idx = idx + 1
        local has_children = item.children and (type(item.children) == "table" and #item.children > 0 or type(item.children) == "function")
        if has_children and item.expanded then
            if type(item.children) == "table" then
                for _, child in ipairs(item.children) do
                    visit(child, depth + 1)
                end
            end
        end
    end
    for _, root in ipairs(self._roots or {}) do
        visit(root, 0)
    end
    self._flat = flat
end

function ItemTreePage:set_items(items)
    self._items = {}
    self._roots = {}
    self._order = {}
    local by_id = {}

    for _, item in ipairs(items) do
        item.children = item.children or nil
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

    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

---@param item loop.pages.ItemTreePage.Item
function ItemTreePage:upsert_item(item)
    assert(item and item.id)
    local old = self._items[item.id]

    if old and old.expanded ~= nil and item.expanded == nil then
        item.expanded = old.expanded
    end

    self._items[item.id] = item

    if not old then
        -- new item → maintain insertion order
        table.insert(self._order, item.id)
    end

    if not old or old.parent ~= item.parent then
        self:set_items(self:get_all_items())
    else
        self:_rebuild_flat()
        self:_refresh_buffer(self:get_buf())
    end
end

function ItemTreePage:get_all_items() -- unchanged
    local items = {}
    for _, id in ipairs(self._order) do
        table.insert(items, self._items[id])
    end
    return items
end

-- ═══════════════════════════════════════════════════════════
-- REPLACE your current :toggle_expand() with this exact version
-- ═══════════════════════════════════════════════════════════
function ItemTreePage:toggle_expand(id)
    local item = self._items[id]
    if not item or not item.children then return end

    if item.expanded then
        -- Normal collapse
        item.expanded = false

        -- Cancel any pending load for this node
        if self._pending_loaders and self._pending_loaders[id] then
            self._pending_loaders[id] = nil
        end
    else
        -- Trying to expand
        if type(item.children) == "function" then
            item.expanded = true
            -- Save the loader function
            local loader_fn = item.children
            
            -- Show loading placeholder immediately
            item.children = { {
                id = "__loading_" .. tostring(id),
                data = nil,
                parent = id,
                formatter_override = self.loading_text or "Loading...",
            } }

            self:_rebuild_flat()
            self:_refresh_buffer(self:get_buf())
            item.children = nil

            -- Mark as pending (so collapse can cancel it)
            if not self._pending_loaders then self._pending_loaders = {} end
            local finished = false
            self._pending_loaders[id] = true

            -- The callback the user will call with the real children
            local done = function(children)
                if finished or not item.expanded then return end
                finished = true
                self._pending_loaders[id] = nil

                children = children or {}

                -- Register new items properly (id tracking + insertion order)
                for _, child in ipairs(children) do
                    child.parent = id
                    self._items[child.id] = child
                    table.insert(self._order, child.id)
                end

                item.children = children
                self:_rebuild_flat()
                self:_refresh_buffer(self:get_buf())
            end

            -- Run the user's async function
            vim.schedule(function()
                local ok, _ = pcall(loader_fn, done)
                if not ok and not finished then
                    -- User's loader threw an error
                    done({ {
                        id = "__error_" .. tostring(id),
                        formatter_override = "Error loading children",
                    } })
                end
            end)

            return
        else
            -- Normal pre-loaded children table
            item.expanded = true
        end
    end

    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

-- ═══════════════════════════════════════════════════════════
-- REPLACE your current :expand() with this tiny version
-- (it just forwards to toggle_expand when needed)
-- ═══════════════════════════════════════════════════════════
function ItemTreePage:expand(id)
    local item = self._items[id]
    if not item or not item.children or item.expanded then return end

    if type(item.children) == "function" then
        self:toggle_expand(id) -- handles async case
    else
        item.expanded = true
        self:_rebuild_flat()
        self:_refresh_buffer(self:get_buf())
    end
end

function ItemTreePage:collapse(id)
    local item = self._items[id]
    if item and item.children then
        item.expanded = false
        self:_rebuild_flat()
        self:_refresh_buffer(self:get_buf())
    end
end



function ItemTreePage:get_cur_item() -- unchanged
    local buf = self:get_buf()
    if not buf or buf ~= vim.api.nvim_get_current_buf() or buf == -1 then return nil end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local entry = self._flat[row]
    return entry and entry.item or nil
end

function ItemTreePage:get_item(id) return self._items[id] end

function ItemTreePage:get_or_create_buf() -- unchanged
    local buf, created = Page.get_or_create_buf(self)
    if created then self:_refresh_buffer(buf) end
    return buf, created
end

-- ONLY THIS PART CHANGED: respect formatter_override
function ItemTreePage:_refresh_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)
    local lines = {}

    for _, entry in ipairs(self._flat) do
        local item = entry.item
        local depth = entry.depth
        local has_children = item.children and (type(item.children) == "table" and #item.children > 0 or type(item.children) == "function")
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

        lines[#lines + 1] = prefix .. text:gsub("\n", " ")
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    if self._args.highlighter then
        for i, entry in ipairs(self._flat) do
            local item = entry.item
            local depth = entry.depth
            if not item.formatter_override then  -- don't highlight loading/error lines unless you want to
                local highlights = self._args.highlighter(item, depth) or {}
                local line_text = lines[i]
                local line_len = #line_text
                local prefix_len = #self.indent_string * depth + (item.children and 2 or 2)

                for _, hl in ipairs(highlights) do
                    local start_col = prefix_len + (hl.start_col or 0)
                    local end_col = prefix_len + (hl.end_col or line_len)
                    start_col = math.max(0, start_col)
                    end_col = math.min(math.max(start_col, end_col), line_len)
                    if start_col < end_col then
                        vim.api.nvim_buf_set_extmark(buf, _ns_id, i - 1, start_col, {
                            end_col = end_col,
                            hl_group = hl.group,
                            priority = 200,
                        })
                    end
                end
            end
        end
    end
end

function ItemTreePage:refresh_content()
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

return ItemTreePage