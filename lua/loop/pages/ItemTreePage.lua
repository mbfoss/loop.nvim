local class = require('loop.tools.class')
local Page  = require('loop.pages.Page')

local ns_id = vim.api.nvim_create_namespace('LoopPluginTreePage')

---@class loop.pages.ItemTreeNode.highlight
---@field group string
---@field start_col number 0-based
---@field end_col number 0-based

---@class loop.pages.ItemTreeNode
---@field id any
---@field text string
---@field data any
---@field children loop.pages.ItemTreeNode[]|nil
---@field expanded boolean|nil
---@field highlights loop.pages.ItemTreeNode.highlight[]|nil

---@class loop.pages.ItemTreePage : loop.pages.Page
local ItemTreePage = class(Page)

function ItemTreePage:init(name)
    Page.init(self, "tree", name)

    self._roots = {}        -- top-level nodes
    self._flat  = {}        -- flattened list [(node, depth)]
    self._index = {}        -- id → flat index

    self:add_keymap("<CR>", {
        callback = function() self:_on_select() end,
        desc = "Select item",
    })

    self:add_keymap("<Tab>", {
        callback = function() self:toggle_expand() end,
        desc = "Expand/collapse node",
    })
end

-- PUBLIC API -----------------------------------------------------

function ItemTreePage:set_select_handler(handler)
    self._select_handler = handler
end

function ItemTreePage:set_items(roots)
    self._roots = roots or {}
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

function ItemTreePage:toggle_expand()
    local cur = self:get_cur_item()
    if not cur then return end

    cur.node.expanded = not cur.node.expanded
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

---@return { node: loop.pages.ItemTreeNode, depth: number }|nil
function ItemTreePage:get_cur_item()
    local buf = self:get_buf()
    if buf == -1 or buf ~= vim.api.nvim_get_current_buf() then
        return nil
    end

    local row = vim.api.nvim_win_get_cursor(0)[1]
    return self._flat[row]
end

function ItemTreePage:set_item(item)
    -- replace node by id
    for _, entry in ipairs(self._flat) do
        if entry.node.id == item.id then
            entry.node.text        = item.text
            entry.node.data        = item.data
            entry.node.highlights  = item.highlights
            -- children and expanded state remain
            break
        end
    end
    self:_refresh_buffer(self:get_buf())
end

function ItemTreePage:remove_item(id)
    local function rec_remove(list)
        for i, node in ipairs(list) do
            if node.id == id then
                table.remove(list, i)
                return true
            end
            if node.children and rec_remove(node.children) then
                return true
            end
        end
    end

    rec_remove(self._roots)
    self:_rebuild_flat()
    self:_refresh_buffer(self:get_buf())
end

-- INTERNAL -------------------------------------------------------

function ItemTreePage:_on_select()
    local cur = self:get_cur_item()
    if self._select_handler then
        self._select_handler(cur)
    end
end

function ItemTreePage:_rebuild_flat()
    self._flat = {}
    self._index = {}

    local function walk(list, depth)
        for _, node in ipairs(list) do
            local entry = { node = node, depth = depth }
            table.insert(self._flat, entry)
            self._index[node.id] = #self._flat

            if node.expanded and node.children then
                walk(node.children, depth + 1)
            end
        end
    end

    walk(self._roots, 0)
end

function ItemTreePage:_refresh_buffer(buf)
    if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

    vim.bo[buf].modifiable = true

    local lines = {}
    local folds = {}

    for i, entry in ipairs(self._flat) do
        local prefix
        if entry.node.children and #entry.node.children > 0 then
            prefix = entry.node.expanded and "▾ " or "▸ "
        else
            prefix = "  "
        end

        local indent = string.rep("  ", entry.depth)
        lines[i] = indent .. prefix .. entry.node.text:gsub("\n", " ")

        -- create folds: fold over children
        if entry.node.children and entry.node.expanded == false then
            -- collapse fold
            local start = i
            local stop = i
            -- fold entire subtree until depth <= parent depth
            for j = i + 1, #self._flat do
                if self._flat[j].depth <= entry.depth then break end
                stop = j
            end
            if stop > start then
                table.insert(folds, { start = start, stop = stop })
            end
        end
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- FOLDS ------------------------------------------------------
    vim.api.nvim_command("setlocal foldmethod=manual")
    vim.api.nvim_buf_set_folds(buf, folds)

    -- HIGHLIGHTS -------------------------------------------------
    for i, entry in ipairs(self._flat) do
        local node = entry.node
        if node.highlights then
            for _, hl in ipairs(node.highlights) do
                vim.api.nvim_buf_set_extmark(buf, ns_id, i - 1, hl.start_col, {
                    end_col = hl.end_col,
                    hl_group = hl.group,
                    priority = 200,
                })
            end
        end
    end
end

return ItemTreePage
