local class = require('loop.tools.class')
local Tree = require("loop.tools.Tree")
local Trackers = require("loop.tools.Trackers")

---@class loop.comp.ItemTree.Item
---@field id any
---@field data any
---@field children_callback nil|fun(cb:fun(items:loop.comp.ItemTree.Item[]))
---@field expanded boolean|nil

---@class loop.comp.ItemTree.ItemData
---@field userdata any
---@field children_callback nil|fun(cb:fun(items:loop.comp.ItemTree.Item[]))
---@field expanded boolean|nil
---@field reload_children boolean|nil
---@field children_loading boolean|nil
---@field load_sequence number
---@field is_loading boolean|nil

---@class loop.comp.ItemTree.Tracker
---@field on_selection? fun(id:any,data:any)
---@field on_open? fun(id:any,data:any)
---@field on_toggle? fun(id:any,data:any,expanded:boolean)

---@class loop.comp.ItemTree.VirtText
---@field text string
---@field highlight string

---@alias loop.comp.ItemTree.FormatterFn fun(
---id:any,
---data:any)
---:string,out_highlights:loop.Highlight[]?,loop.comp.ItemTree.VirtText?

---@class loop.comp.ItemTree.InitArgs
---@field formatter loop.comp.ItemTree.FormatterFn
---@field expand_char string?
---@field collapse_char string?
---@field enable_loading_indictaor boolean?
---@field loading_char string?
---@field indent_string string?
---@field render_delay_ms number|nil

---@class loop.comp.ItemTree
local ItemTree = class()

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemTreeComp')

---@param item loop.comp.ItemTree.Item
---@return loop.comp.ItemTree.ItemData
local function _item_to_itemdata(item)
    return {
        userdata = item.data,
        children_callback = item.children_callback,
        expanded = item.expanded,
        reload_children = true,
        load_sequence = 1,
    }
end

---@param old loop.comp.ItemTree.ItemData
---@param new loop.comp.ItemTree.ItemData
local function _merge_itemdata(old, new)
    local data = old or {}
    data.userdata = new.userdata
    data.children_callback = new.children_callback
    data.reload_children = new.children_callback ~= nil
    -- Keep expanded/loading flags intact
    return data
end

local function _refresh_tree(tree, async_update)
    local flat = {}
    local have_loading_nodes = false
    local nodes = tree:flatten(function(id, data)
        if not data.expanded then
            return "exclude_children"
        end
        return nil
    end)

    for _, flat_node in ipairs(nodes) do
        table.insert(flat, flat_node)
        local item = flat_node.data
        if item.expanded then
            local item_id = flat_node.id
            if item.children_callback and item.reload_children ~= false then
                item.reload_children = false
                item.children_loading = true
                have_loading_nodes = true

                local sequence = item.load_sequence
                vim.schedule(function()
                    if sequence ~= item.load_sequence then return end
                    item.children_callback(function(loaded_children)
                        if sequence ~= item.load_sequence then return end
                        if tree:get_item(item_id) then
                            local treeitems = {}
                            for _, child in ipairs(loaded_children or {}) do
                                local basetreeitem = { id = child.id, data = _item_to_itemdata(child) }
                                table.insert(treeitems, basetreeitem)
                            end
                            tree:update_children(item_id, treeitems, _merge_itemdata)
                            item.children_loading = false
                            async_update()
                        end
                    end)
                end)
            end
        end
    end
    return flat, have_loading_nodes
end

function ItemTree:init(args)
    assert(args.formatter, "formatter is required")

    ---@type loop.comp.ItemTree.FormatterFn
    self._formatter = args.formatter
    self._trackers = Trackers:new()

    self._expand_char = args.expand_char or "▶"
    self._collapse_char = args.collapse_char or "▼"
    self._loading_char = args.enable_loading_indictaor and (args.loading_char or "⧗") or nil
    self._indent_string = args.indent_string or "  "
    self._render_delay_ms = args.render_delay_ms or 150

    self._tree = Tree:new()
    self._flat = {}
end

function ItemTree:add_tracker(cb) return self._trackers:add_tracker(cb) end

function ItemTree:link_to_buffer(buf_ctrl)
    local cur_item_data = function()
        local cursor = buf_ctrl:get_cursor()
        if not cursor then return nil end
        local row = cursor[1]
        local node = self._flat[row]
        if not node then return nil, nil end
        return node.id, node.data
    end

    local function on_open()
        local id, itemdata = cur_item_data()
        if not id or not itemdata then return end
        self._trackers:invoke("on_open", id, itemdata.userdata)
    end

    local function on_toggle()
        local id, itemdata = cur_item_data()
        if not id or not itemdata then return end
        local have_children = self._tree:have_children(id)
        if have_children or itemdata.children_callback then
            self:toggle_expand(id)
        end
    end

    self._linked_buf = buf_ctrl
    self._linked_buf.set_renderer({
        render = function(bufnr) return self:_on_render_request(bufnr) end,
        dispose = function() return self:dispose() end
    })

    self._linked_buf.add_keymap('<CR>', { callback = on_toggle, desc = "Expand/collapse" })
    self._linked_buf.add_keymap('go', { callback = on_open, desc = "Open details" })
    self._linked_buf.add_keymap('<2-LeftMouse>', { callback = on_toggle, desc = "Expand/collapse" })
    self._linked_buf.add_keymap('zo', { callback = on_toggle, desc = "Expand" })
    self._linked_buf.add_keymap('zc', { callback = on_toggle, desc = "Collapse" })
    self._linked_buf.add_keymap('za', { callback = on_toggle, desc = "Toggle" })

    buf_ctrl:request_refresh()
end

function ItemTree:dispose() end

function ItemTree:get_cur_item(comp)
    local cursor = comp:get_cursor()
    if not cursor then return nil end
    local row = cursor[1]

    local node = self._flat[row]
    if not node then return nil end

    local id, nodedata = node.id, node.data
    return { id = id, data = nodedata.userdata }
end

---@return loop.comp.ItemTree.Item?
function ItemTree:get_item(id)
    local itemdata = self:_get_item(id)
    if not itemdata then return nil end
    return { id = id, data = itemdata.userdata }
end

function ItemTree:clear_items()
    self._tree = Tree:new()
    self:_request_render()
end

---@param parent_id any
---@param items loop.comp.ItemTree.Item[]
function ItemTree:upsert_items(parent_id, items)
    for _, item in ipairs(items) do
        self._tree:upsert_item(parent_id, item.id, _item_to_itemdata(item))
    end
    self:_request_render()
end

---@param parent_id any
---@param children loop.comp.ItemTree.Item[]
function ItemTree:update_children(parent_id, children)
    ---@type loop.tools.Tree.Item[]
    local baseitems = {}
    for _, child_item in ipairs(children) do
        ---@type loop.tools.Tree.Item
        local item = {
            id = child_item.id,
            data = _item_to_itemdata(child_item)
        }
        table.insert(baseitems, item)
    end
    self._tree:update_children(parent_id, baseitems, _merge_itemdata)
    self:_request_render()
end

---@param parent_id any
---@param item loop.comp.ItemTree.Item
function ItemTree:upsert_item(parent_id, item)
    local new_data = _item_to_itemdata(item)

    local existing = self._tree:get_item(item.id)
    if existing then
        existing.userdata = new_data.userdata
        existing.children_callback = new_data.children_callback
        existing.reload_children = true
        existing.load_sequence = existing.load_sequence + 1
    else
        self._tree:upsert_item(parent_id, item.id, new_data)
    end

    self:_request_render()
end

function ItemTree:get_children(parent_id)
    local items = {}
    local tree_items = self._tree:get_children(parent_id)

    for _, treeitem in ipairs(tree_items) do
        local data = treeitem.data
        table.insert(items, {
            id = treeitem.id,
            parent_id = parent_id,
            data = data.userdata,
            expanded = data.expanded,
            children_callback = data.children_callback
        })
    end
    return items
end

function ItemTree:remove_items(ids)
    for _, id in ipairs(ids) do
        self._tree:remove_item(id)
    end
    self:_request_render()
    return true
end

function ItemTree:remove_item(id)
    self._tree:remove_item(id)
    self:_request_render()
    return true
end

function ItemTree:remove_children(id)
    self._tree:remove_children(id)
    self:_request_render()
    return true
end

function ItemTree:_request_render()
    if self._linked_buf then
        self._linked_buf.request_refresh()
    end
end

function ItemTree:_on_render_request(buf)
    local flat, have_loading_nodes = _refresh_tree(self._tree, function()
        vim.schedule(function() self:_request_render() end)
    end)

    if have_loading_nodes and not self._no_delay_next_render then
        vim.defer_fn(function()
            self._no_delay_next_render = true
            self:_request_render()
        end, self._render_delay_ms or 150)
        return false
    end
    self._no_delay_next_render = false

    local buffer_lines = {}
    local extmarks_data = {}
    local new_flat_nodes = {}

    for _, flatnode in ipairs(flat) do
        local item_id = flatnode.id
        local item = flatnode.data

        local icon = ""
        if item_id and (self._tree:have_children(item_id) or item.children_callback) then
            if self._loading_char and item.children_loading then
                icon = self._loading_char
            elseif item.expanded then
                icon = self._collapse_char
            else
                icon = self._expand_char
            end
        end

        local prefix = string.rep(self._indent_string, flatnode.depth or 0)
        if icon ~= "" then
            prefix = prefix .. icon .. " "
        else
            prefix = prefix .. string.rep(" ", vim.fn.strdisplaywidth(self._expand_char)) .. " "
        end

        local raw_text, raw_hls, virt_text
        if item_id then
            raw_text, raw_hls, virt_text = self._formatter(item_id, item.userdata)
        else
            raw_text = ""
        end

        assert(type(raw_text) == "string")
        raw_hls = raw_hls or {}

        local node_lines, mappings, all_node_hls = self:_process_node_lines(
            flatnode, prefix, raw_text, raw_hls
        )

        for i, line in ipairs(node_lines) do
            table.insert(buffer_lines, line)
            table.insert(new_flat_nodes, mappings[i])

            local current_row = #buffer_lines - 1
            local hls_for_this_line = all_node_hls[i]

            for _, hl in ipairs(hls_for_this_line) do
                table.insert(extmarks_data, {
                    row = current_row,
                    start_col = hl.start_col,
                    mark = {
                        end_col = hl.end_col,
                        hl_group = hl.group,
                    }
                })
            end
            if virt_text then
                local mark_vt = {}
                for _, t in ipairs(virt_text) do
                    table.insert(mark_vt, { t.text, t.highlight })
                end
                table.insert(extmarks_data, {
                    row = current_row,
                    start_col = 0,
                    mark = { virt_text = mark_vt },
                })
            end
        end
    end

    self._flat = new_flat_nodes

    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_lines)
    vim.bo[buf].modifiable = false

    for _, data in ipairs(extmarks_data) do
        vim.api.nvim_buf_set_extmark(buf, _ns_id, data.row, data.start_col, data.mark)
    end

    return true
end

function ItemTree:_process_node_lines(node_data, prefix, text, highlights)
    local lines = {}
    local mappings = {}
    local line_highlights = {}

    local node_lines = vim.split(text, "\n", { trimempty = false })
    local prefix_width = vim.fn.strdisplaywidth(prefix)
    local empty_prefix = string.rep(" ", prefix_width)

    local current_offset = 0
    for i, line_content in ipairs(node_lines) do
        local current_prefix = (i == 1) and prefix or empty_prefix
        table.insert(lines, current_prefix .. line_content)
        table.insert(mappings, node_data)

        local current_line_hls = {}
        local line_start = current_offset
        local line_end = current_offset + #line_content

        for _, hl in ipairs(highlights) do
            local hl_start = hl.start_col or 0
            local hl_end = hl.end_col or #text

            local intersect_start = math.max(line_start, hl_start)
            local intersect_end = math.min(line_end, hl_end)

            if intersect_start < intersect_end then
                table.insert(current_line_hls, {
                    group = hl.group,
                    start_col = #current_prefix + (intersect_start - line_start),
                    end_col = #current_prefix + (intersect_end - line_start),
                })
            end
        end

        table.insert(line_highlights, current_line_hls)
        current_offset = line_end + 1
    end

    return lines, mappings, line_highlights
end

function ItemTree:toggle_expand(id)
    local item = self:_get_item(id)
    if item then
        item.expanded = not item.expanded
        self:_request_render()
        self._trackers:invoke("on_toggle", id, item.userdata, item.expanded)
    end
end

function ItemTree:expand(id)
    local item = self._tree:get_item(id)
    if item then
        item.expanded = true
        self:_request_render()
        self._trackers:invoke("on_toggle", id, item.userdata, true)
    end
end

function ItemTree:collapse(id)
    local item = self._tree:get_item(id)
    if item then
        item.expanded = false
        self:_request_render()
        self._trackers:invoke("on_toggle", id, item.userdata, false)
    end
end

function ItemTree:_get_item(id)
    return self._tree:get_item(id)
end

function ItemTree:get_items()
    local items = {}
    for _, treeitem in ipairs(self._tree:get_items()) do
        local data = treeitem.data
        local item = {
            id = treeitem.id,
            data = data.userdata,
            expanded = data.expanded,
        }
        table.insert(items, item)
    end
    return items
end

function ItemTree:refresh_content()
    self:_request_render()
end

return ItemTree
