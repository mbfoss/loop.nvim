local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local Trackers = require("loop.tools.Trackers")
local Tree = require("loop.tools.Tree")

---@class loop.pages.ItemTreePage.Highlight
---@field group string
---@field start_col number|nil 0-based
---@field end_col number|nil 0-based

---@class loop.pages.ItemTreePage.Item
---@field id any
---@field data any
---@field parent_id any
---@field children_callback nil|fun(cb:fun(items:loop.pages.ItemTreePage.ItemData[]))
---@field expanded boolean|nil

---@class loop.pages.ItemTreePage.ItemData
---@field userdata any
---@field children_callback nil|fun(cb:fun(items:loop.pages.ItemTreePage.Item[]))
---@field expanded boolean|nil
---@field reload_children boolean|nil
---@field children_loading boolean|nil
---@field is_loading boolean|nil

---@class loop.pages.ItemTreePage.TrackerCallbacks
---@field on_selection fun(id:any,data:any)

---@class loop.pages.ItemTreePage.InitArgs
---@field formatter fun(id:any,data:any,out_highlights:loop.pages.ItemTreePage.Highlight[]):string
---@field expand_char string?
---@field collapse_char string?
---@field indent_string string?
---@field loading_text string?
---@field render_delay_ms number|nil

---@class loop.pages.ItemTreePage : loop.pages.Page
---@field new fun(self: loop.pages.ItemTreePage, name:string, args:loop.pages.ItemTreePage.InitArgs): loop.pages.ItemTreePage
local ItemTreePage = class(Page)

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemTreePage')

---@param item loop.pages.ItemTreePage.Item
---@return loop.pages.ItemTreePage.ItemData
local function _item_to_itemdata(item)
    ---@type loop.pages.ItemTreePage.ItemData
    return {
        userdata = item.data,
        children_callback = item.children_callback,
        expanded = item.expanded,
        reload_children = true,
    }
end

---@param tree loop.tools.Tree
---@param async_update fun()
---@return loop.tools.Tree.Node[]
---@return boolean have loading nodes
local function _refresh_tree(tree, async_update)
    ---@type loop.tools.Tree.Node[]
    local flat = {}
    local have_loading_nodes = false
    -- Get all nodes in depth-first order
    local nodes = tree:flatten(nil, function(data)
        return not data.expanded
    end)

    for _, flat_node in ipairs(nodes) do
        table.insert(flat, flat_node)
        ---@type loop.pages.ItemTreePage.ItemData
        local item = flat_node.data
        -- Only show children if node is expanded
        if item.expanded then
            local item_id = flat_node.id
            -- Lazy loading
            if item.children_callback and item.reload_children ~= false and not item.children_loading then
                item.children_loading = true
                have_loading_nodes = true

                ---@type loop.pages.ItemTreePage.ItemData
                local loading_item = {
                    ---@diagnostic disable-next-line: undefined-field
                    id = "loading_" .. vim.loop.hrtime(),
                    is_loading = true
                }
                ---@type loop.tools.Tree.FlatNode
                table.insert(flat, {
                    id = loading_item.id,
                    data = loading_item,
                    depth = flat_node.depth + 1,
                })

                vim.schedule(function()
                    -- Trigger async load
                    item.children_callback(function(loaded_children)
                        ---@type loop.tools.Tree.Item[]
                        local treeitems = {}
                        for _, child in ipairs(loaded_children or {}) do
                            ---@type loop.tools.Tree.Item
                            local basetreeitem = { id = child.id, data = _item_to_itemdata(child) }
                            table.insert(treeitems, basetreeitem)
                        end
                        tree:set_children(item_id, treeitems)
                        item.reload_children = false
                        item.children_loading = false
                        async_update()
                    end)
                end)
            end
        end
    end
    return flat, have_loading_nodes
end


---@param name string
---@param args loop.pages.ItemTreePage.InitArgs
function ItemTreePage:init(name, args)
    assert(args.formatter, "formatter is required")
    Page.init(self, "tree", name)

    self._formatter = args.formatter
    self._expand_char = args.expand_char or "▸"
    self._collapse_char = args.collapse_char or "▾"
    self._indent_string = args.indent_string or " "
    self._loading_text = args.loading_text or "Loading..."
    self._render_delay_ms = args.render_delay_ms or 100

    self._trackers = Trackers:new()

    self._tree = Tree:new()

    ---@type loop.tools.Tree.FlatNode[]
    self._flat = {}

    local function on_select()
        local id, itemdata = self:_cur_item_data()
        if not id or not itemdata then return end
        local have_children = self._tree:have_children(id)
        if have_children or itemdata.children_callback then
            self:toggle_expand(id)
        else
            self._trackers:invoke("on_selection", id, itemdata.userdata)
        end
    end

    local function on_toggle()
        local id, itemdata = self:_cur_item_data()
        if not id or not itemdata then return end
        local have_children = self._tree:have_children(id)
        if have_children or itemdata.children_callback then
            self:toggle_expand(id)
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

function ItemTreePage:clear_items()
    self._tree = Tree:new()
    self:_render()
end

---@param items loop.pages.ItemTreePage.Item[]
function ItemTreePage:upsert_items(items)
    for _, item in ipairs(items) do
        self._tree:upsert_item(item.parent_id, item.id, _item_to_itemdata(item))
    end
    self:_render()
end

---@param item loop.pages.ItemTreePage.Item
function ItemTreePage:upsert_item(item)
    self._tree:upsert_item(item.parent_id or nil, item.id, _item_to_itemdata(item))
    self:_render()
end

---@param ids any[]
function ItemTreePage:remove_items(ids)
    for _, id in ipairs(ids) do
        self._tree:remove_item(id)
    end
    self:_render()
    return true
end

function ItemTreePage:remove_item(id)
    self._tree:remove_item(id)
    self:_render()
    return true
end

function ItemTreePage:_render()
    if self._is_render_throttling then
        self._is_render_pending = true
        return
    end

    local rendered = self:_immediate_render()
    if rendered then
        self._is_render_throttling = true
    end

    vim.defer_fn(function()
        self._is_render_throttling = false
        if self._is_render_pending then
            self._is_render_pending = false
            self:_immediate_render()
        end
    end, self._render_delay_ms)
end

---@return boolean rendered
function ItemTreePage:_immediate_render()
    local buf = self:get_buf()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return true end

    local lines = {}
    local extmarks = {}

    local have_loading_nodes
    self._flat, have_loading_nodes = _refresh_tree(self._tree, function()
        vim.schedule(function()
            self:_render()
        end)
    end)
    if have_loading_nodes then
        return false
    end

    for i, flatnode in ipairs(self._flat) do
        local item_id = flatnode.id
        ---@type loop.pages.ItemTreePage.ItemData
        local item = flatnode.data

        local prefix = ""
        local have_children = self._tree:have_children(item_id)
        if item_id and (have_children or item.children_callback) then
            prefix = item.expanded and self._collapse_char or self._expand_char
        end

        local indent = string.rep(self._indent_string, flatnode.depth or 0)

        ---@type loop.pages.ItemTreePage.Highlight[]
        local highlights = {}
        local text
        if item.is_loading then
            text = self._loading_text
        else
            text = (item_id and self._formatter(item_id, item.userdata, highlights) or ""):gsub('\n', ' ')
        end

        local full_prefix = indent .. prefix .. " "

        lines[i] = full_prefix .. text

        if #highlights > 0 then
            local prefix_offset = #full_prefix
            local text_len = #text
            for _, hl in ipairs(highlights) do
                local start_col = hl.start_col or 0
                local end_col = hl.end_col or text_len
                start_col = math.max(0, math.min(start_col, text_len))
                end_col = math.max(start_col, math.min(end_col, text_len))

                table.insert(extmarks, {
                    row = i - 1,
                    col_start = prefix_offset + start_col,
                    col_end = prefix_offset + end_col,
                    group = hl.group,
                })
            end
        end
    end

    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    for _, mark in ipairs(extmarks) do
        vim.api.nvim_buf_set_extmark(buf, _ns_id, mark.row, mark.col_start, {
            end_col = mark.col_end,
            hl_group = mark.group,
        })
    end

    return true
end

---------------------------------------------------------
-- EXPAND / COLLAPSE
---------------------------------------------------------
function ItemTreePage:toggle_expand(id)
    local item = self._tree:get_item(id)
    if item then
        item.expanded = not item.expanded
        self:_render()
    end
end

function ItemTreePage:expand(id)
    local item = self._tree:get_item(id)
    if item then
        item.expanded = true
        self:_render()
    end
end

function ItemTreePage:collapse(id)
    local item = self._tree:get_item(id)
    if item then
        item.expanded = false
        self:_render()
    end
end

---@return loop.pages.ItemTreePage.ItemData
function ItemTreePage:_get_item(id)
    return self._tree:get_item(id)
end

---@return loop.pages.ItemTreePage.Item[]
function ItemTreePage:get_items()
    local items = {}
    for _, treeitem in ipairs(self._tree:get_items()) do
        ---@type loop.pages.ItemTreePage.ItemData
        local data = treeitem.data
        ---@type loop.pages.ItemTreePage.Item
        local item = {
            id = treeitem.id,
            data = data.userdata,
            expanded = data.expanded,
        }
        table.insert(items, item)
    end
    return items
end

---@return loop.pages.ItemTreePage.Item|nil
function ItemTreePage:get_cur_item()
    local id, item = self:_cur_item_data()
    if not item then return nil end
    ---@type loop.pages.ItemTreePage.Item
    return { id = id, data = item.userdata }
end

---@return any id
---@return loop.pages.ItemTreePage.ItemData|nil data
function ItemTreePage:_cur_item_data()
    local row = vim.fn.line('.') - 1
    ---@type loop.tools.Tree.FlatNode
    local node = self._flat[row + 1]
    if not node then return nil, nil end
    return node.id, node.data
end

---------------------------------------------------------
-- Refresh
---------------------------------------------------------
function ItemTreePage:refresh_content()
    self:_immediate_render()
end

function ItemTreePage:get_or_create_buf()
    local buf, refresh = Page.get_or_create_buf(self)
    if refresh then
        self:_render()
    end
    return buf, refresh
end

return ItemTreePage
