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
---@field parent any|nil           -- parent item id (nil for root items)
---@field children loop.pages.ItemTreePage.Item[]|nil
---@field expanded boolean|nil    -- true if expanded, false if collapsed, nil if leaf

---@class loop.pages.ItemTreePage.TrackerCallbacks
---@field on_selection fun(item:loop.pages.ItemTreePage.Item|nil)

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemTreePage')

---@class loop.pages.ItemTreePage.InitArgs
---@field formatter fun(item:loop.pages.ItemTreePage.Item, depth:integer, is_expanded:boolean, has_children:boolean):string
---@field highlighter nil|fun(item:loop.pages.ItemTreePage.Item, depth:integer):loop.pages.ItemTreePage.Highlight[]
---@field expand_char string?     -- default: "▸"
---@field collapse_char string?   -- default: "▾"
---@field indent_string string?   -- default: "  "

---@class loop.pages.ItemTreePage : loop.pages.Page
---@field new fun(self: loop.pages.ItemTreePage, name:string, args:loop.pages.ItemTreePage.InitArgs): loop.pages.ItemTreePage
local ItemTreePage = class(Page)

---@param name string
---@param args loop.pages.ItemTreePage.InitArgs
function ItemTreePage:init(name, args)
    assert(args.formatter, "formatter is required")
    Page.init(self, "tree", name)

    self._args         = args
    self._items        = {} -- flat list of all items by id
    self._roots        = {} -- ordered root items
    self._flat         = {} -- currently visible lines (in display order)

    self._trackers     = Trackers:new()

    -- Configurable icons/strings
    self.expand_char   = args.expand_char or "▸"
    self.collapse_char = args.collapse_char or "▾"
    self.indent_string = args.indent_string or "  "

    -- Keymaps
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

---@param callbacks loop.pages.ItemTreePage.TrackerCallbacks
---@return number
function ItemTreePage:add_tracker(callbacks)
    return self._trackers:add_tracker(callbacks)
end

---@param id number
---@return boolean
function ItemTreePage:remove_tracker(id)
    return self._trackers:remove_tracker(id)
end

-- Internal: rebuild flat list from current expansion state
function ItemTreePage:_rebuild_flat()
    local flat = {}
    local idx = 1
    local visited = {}

    local function visit(item, depth)
        if visited[item] then return end
        visited[item] = true

        flat[idx] = { item = item, depth = depth }
        idx = idx + 1

        local has_children = item.children and #item.children > 0
        if has_children and item.expanded then
            for _, child in ipairs(item.children) do
                visit(child, depth + 1)
            end
        end
    end

    for _, root in ipairs(self._roots or {}) do
        visit(root, 0)
    end

    self._flat = flat
end

---@param items loop.pages.ItemTreePage.Item[]
function ItemTreePage:set_items(items)
    self._items = {}
    self._roots = {}
    local by_id = {}

    -- First pass: register items
    for _, item in ipairs(items) do
        item.children = item.children or nil

        if item.children and item.expanded == nil then
            item.expanded = false
        end

        self._items[item.id] = item
        by_id[item.id] = item

        if not item.parent then
            table.insert(self._roots, item)
        end
    end

    -- Second pass: build children arrays
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
function ItemTreePage:upsert_item(item, exp)
    assert(item and item.id)
    local old = self._items[item.id]
    self._items[item.id] = item

    if not old or old.parent ~= item.parent then
        self:set_items(self:get_all_items())
    else
        self:_rebuild_flat()
        self:_refresh_buffer(self:get_buf())
    end
end

---@return loop.pages.ItemTreePage.Item[]
function ItemTreePage:get_all_items()
    local items = {}
    for _, item in pairs(self._items) do
        table.insert(items, item)
    end
    return items
end

---@param id any
function ItemTreePage:expand(id)
    local item = self._items[id]
    if item and item.children then
        item.expanded = true
        self:_rebuild_flat()
        self:_refresh_buffer(self:get_buf())
    end
end

---@param id any
function ItemTreePage:collapse(id)
    local item = self._items[id]
    if item and item.children then
        item.expanded = false
        self:_rebuild_flat()
        self:_refresh_buffer(self:get_buf())
    end
end

---@param id any
function ItemTreePage:toggle_expand(id)
    local item = self._items[id]
    if item and item.children then
        item.expanded = not item.expanded
        self:_rebuild_flat()
        self:_refresh_buffer(self:get_buf())
    end
end

---@return loop.pages.ItemTreePage.Item|nil
function ItemTreePage:get_cur_item()
    local buf = self:get_buf()
    if not buf or buf ~= vim.api.nvim_get_current_buf() or buf == -1 then
        return nil
    end
    local row = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
    local entry = self._flat[row]
    return entry and entry.item or nil
end

---@param id any
---@return loop.pages.ItemTreePage.Item|nil
function ItemTreePage:get_item(id)
    return self._items[id]
end

function ItemTreePage:get_or_create_buf()
    local buf, created = Page.get_or_create_buf(self)
    if created then
        self:_refresh_buffer(buf)
    end
    return buf, created
end

---@param buf number
function ItemTreePage:_refresh_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)

    local lines = {}

    for _, entry in ipairs(self._flat) do
        local item = entry.item
        local depth = entry.depth
        local has_children = item.children and #item.children > 0
        local is_expanded = has_children and item.expanded

        local prefix = self.indent_string:rep(depth)
        if has_children then
            prefix = prefix .. (is_expanded and self.collapse_char or self.expand_char) .. " "
        else
            prefix = prefix .. "  "
        end

        local text = self._args.formatter(item, depth, is_expanded, has_children)
        lines[#lines + 1] = prefix .. text:gsub("\n", " ")
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    if self._args.highlighter then
        for i, entry in ipairs(self._flat) do
            local item       = entry.item
            local depth      = entry.depth
            local highlights = self._args.highlighter(item, depth) or {}

            local line_text  = lines[i]
            local line_len   = #line_text

            local prefix_len = #self.indent_string * depth + 2

            for _, hl in ipairs(highlights) do
                local start_col = prefix_len + (hl.start_col or 0)
                local end_col   = prefix_len + (hl.end_col or line_len)

                start_col = math.max(0, start_col)
                end_col   = math.min(math.max(start_col, end_col), line_len)

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

function ItemTreePage:refresh_content()
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

return ItemTreePage
