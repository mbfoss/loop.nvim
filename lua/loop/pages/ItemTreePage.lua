local class = require('loop.tools.class')
local Page  = require('loop.pages.Page')

local ns_id = vim.api.nvim_create_namespace('LoopPluginTreePage')

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

---@class loop.pages.ItemTreeNode.highlight
---@field group string                 -- highlight group name
---@field start_col number             -- 0-based start column
---@field end_col number               -- 0-based end column

---@class loop.pages.ItemTreeNode
---@field id any                       -- unique identifier
---@field text string                  -- text to display
---@field data any                     -- arbitrary payload
---@field children loop.pages.ItemTreeNode[]|nil
---@field expanded boolean|nil         -- whether the node is expanded
---@field highlights loop.pages.ItemTreeNode.highlight[]|nil

---@class loop.pages.ItemTreePage.FlatEntry
---@field node loop.pages.ItemTreeNode
---@field depth number                 -- depth in the tree

---@class loop.pages.ItemTreePage : loop.pages.Page
---@field _roots loop.pages.ItemTreeNode[]      -- top-level roots
---@field _flat  loop.pages.ItemTreePage.FlatEntry[]   -- linearized tree
---@field _index table<any, number>             -- id → flat index
---@field _select_handler fun(cur: loop.pages.ItemTreePage.FlatEntry|nil)|nil
local ItemTreePage = class(Page)

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

---Initialize the tree page.
---@param name string
function ItemTreePage:init(name)
    Page.init(self, "tree", name)

    self._roots = {}
    self._flat  = {}
    self._index = {}

    --TODO: add tracker 
    self:add_keymap("<CR>", {
        callback = function() self:_on_select() end,
        desc = "Select node",
    })

    self:add_keymap("<Tab>", {
        callback = function() self:toggle_expand() end,
        desc = "Expand/collapse node",
    })
end

---Set the tree’s list of root nodes.
---@param roots loop.pages.ItemTreeNode[]
function ItemTreePage:set_items(roots)
    self._roots = roots or {}
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

---Toggle expand/collapse on the node under cursor.
function ItemTreePage:toggle_expand()
    local cur = self:get_cur_item()
    if not cur then return end
    local node = cur.node

    node.expanded = not node.expanded

    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

---Get the tree node under the cursor.
---@return loop.pages.ItemTreePage.FlatEntry|nil
function ItemTreePage:get_cur_item()
    local buf = self:get_buf()
    if buf == -1 or buf ~= vim.api.nvim_get_current_buf() then
        return nil
    end

    local row = vim.api.nvim_win_get_cursor(0)[1]
    return self._flat[row]
end

---Replace/update an existing node by id.
---@param item loop.pages.ItemTreeNode
function ItemTreePage:set_item(item)
    if not item or item.id == nil then return end

    for _, entry in ipairs(self._flat) do
        if entry.node.id == item.id then
            entry.node.text       = item.text
            entry.node.data       = item.data
            entry.node.highlights = item.highlights
            break
        end
    end

    self:_refresh_buffer(self:get_buf())
end

---Remove a node by id (searches recursively).
---@param id any
function ItemTreePage:remove_item(id)

    local function rec_remove(nodes)
        for i, n in ipairs(nodes) do
            if n.id == id then
                table.remove(nodes, i)
                return true
            end
            if n.children and rec_remove(n.children) then
                return true
            end
        end
        return false
    end

    rec_remove(self._roots)
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

---Call select handler (if any).
function ItemTreePage:_on_select()
    if self._select_handler then
        local cur = self:get_cur_item()
        self._select_handler(cur)
    end
end

---Rebuild flattened list from hierarchical tree.
function ItemTreePage:_rebuild_flat()
    self._flat  = {}
    self._index = {}

    local function walk(list, depth)
        for _, node in ipairs(list) do
            local e = { node = node, depth = depth }
            table.insert(self._flat, e)
            self._index[node.id] = #self._flat

            if node.expanded and node.children then
                walk(node.children, depth + 1)
            end
        end
    end

    walk(self._roots, 0)
end

--------------------------------------------------------------------------------
-- Buffer Management + Rendering
--------------------------------------------------------------------------------

---Redraw the tree into the buffer.
---@param buf number
function ItemTreePage:_refresh_buffer(buf)
    if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

    vim.bo[buf].modifiable = true

    local lines = {}
    local folds = {}

    for i, entry in ipairs(self._flat) do
        local node  = entry.node
        local depth = entry.depth

        local indent = string.rep("  ", depth)
        local icon

        if node.children and #node.children > 0 then
            icon = node.expanded and "▾ " or "▸ "
        else
            icon = "  "
        end

        lines[i] = indent .. icon .. node.text:gsub("\n", " ")

        -- collapsed node → compute closed fold range
        if node.children and node.expanded == false then
            local start = i
            local stop  = i

            for j = i + 1, #self._flat do
                if self._flat[j].depth <= depth then break end
                stop = j
            end

            if stop > start then
                table.insert(folds, { start = start, stop = stop })
            end
        end
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    --------------------------------------------------------------------------
    -- Classic manual-fold implementation:
    --------------------------------------------------------------------------

    vim.api.nvim_set_option_value("foldmethod", "manual", { scope = "local", buf = buf })
    vim.api.nvim_buf_call(buf, function()
        vim.cmd("normal! zE")
    end)

    for _, f in ipairs(folds) do
        vim.api.nvim_buf_call(buf, function()
            vim.cmd(f.start .. "," .. f.stop .. "fold")
        end)
    end

    --------------------------------------------------------------------------
    -- Highlights
    --------------------------------------------------------------------------
    for i, entry in ipairs(self._flat) do
        local node = entry.node
        if node.highlights then
            for _, hl in ipairs(node.highlights) do
                vim.api.nvim_buf_set_extmark(buf, ns_id, i - 1, hl.start_col, {
                    end_col  = hl.end_col,
                    hl_group = hl.group,
                    priority = 200,
                })
            end
        end
    end
end

return ItemTreePage
