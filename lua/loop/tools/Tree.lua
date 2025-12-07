local class = require("loop.tools.class")

---@class loop.tools.Tree.Item
---@field id any
---@field data any

---@class loop.tools.Tree.Node
---@field parent_id any|nil
---@field data any
---@field first_child any|nil
---@field last_child any|nil
---@field next_sibling any|nil
---@field prev_sibling any|nil

---@generic T
---@class loop.tools.Tree
---@field new fun(self: loop.tools.Tree) : loop.tools.Tree
---@field _nodes table<any, loop.tools.Tree.Node>
---@field _root_first any|nil
---@field _root_last any|nil
local Tree = class()

---Initialize internal state
function Tree:init()
    ---@type table<any, loop.tools.Tree.Node>
    self._nodes = {}

    ---@type any|nil
    self._root_first = nil

    ---@type any|nil
    self._root_last = nil
end

--==============================================================
-- Internal Helpers
--==============================================================

---Link a node as the last child of a parent.
---@private
---@param parent_id any|nil
---@param id any
function Tree:_link_child(parent_id, id)
    local parent = parent_id and self._nodes[parent_id]
    if not parent then
        -- link under root list
        if not self._root_first then
            self._root_first = id
            self._root_last = id
        else
            local last = self._root_last
            self._nodes[last].next_sibling = id
            self._nodes[id].prev_sibling = last
            self._root_last = id
        end
        return
    end

    -- Normal case: parent exists
    if not parent.first_child then
        parent.first_child = id
        parent.last_child = id
    else
        local last = parent.last_child
        self._nodes[last].next_sibling = id
        self._nodes[id].prev_sibling = last
        parent.last_child = id
    end
end

---Unlink a node from its parent’s child list (root or not).
---@private
---@param id any
function Tree:_unlink(id)
    local node = self._nodes[id]
    local parent_id = node.parent_id

    local prev = node.prev_sibling
    local next = node.next_sibling

    if parent_id == nil then
        -- unlink from root
        if id == self._root_first then self._root_first = next end
        if id == self._root_last then self._root_last = prev end
    else
        local parent = self._nodes[parent_id]
        if id == parent.first_child then parent.first_child = next end
        if id == parent.last_child then parent.last_child = prev end
    end

    if prev then self._nodes[prev].next_sibling = next end
    if next then self._nodes[next].prev_sibling = prev end

    node.prev_sibling = nil
    node.next_sibling = nil
end

---Recursively remove a node and all of its descendants.
---@private
---@param id any
function Tree:_remove_subtree(id)
    local node = self._nodes[id]
    if not node then return end

    local child = node.first_child
    while child do
        local next_child = self._nodes[child].next_sibling
        self:_remove_subtree(child) -- recurse first
        child = next_child
    end

    self:_unlink(id)
    self._nodes[id] = nil
end

--==============================================================
-- Public API
--==============================================================

---Insert or update a node.
---
---If the node exists:
---  - update its data
---  - reparent if parent_id changed
---
---If new:
---  - create the node
---  - link it to parent
---

--- Replace the children of parent_id with exactly these items, in order.
---@generic T
---@param parent_id any|nil
---@param items loop.tools.Tree.Item[]
function Tree:set_children(parent_id, items)
    assert(type(items) == "table")

    local parent_node = parent_id and self._nodes[parent_id]
    assert(not parent_id or parent_node)

    local old_children = {}
    do
        local child
        if parent_node then
            child = parent_node.first_child
        else
            child = self._root_first
        end
        while child do
            old_children[child] = true
            child = self._nodes[child].next_sibling
        end
    end

    local first = nil
    local last = nil
    local prev_id = nil

    for _, item in ipairs(items) do
        local id = assert(item.id)
        local data = item.data

        local node = self._nodes[id]
        if node then
            assert(node.parent_id == parent_id, "Node exists under another parent")
            node.data = data
        else
            node = {
                parent_id = parent_id,
                data = data,
                first_child = nil,
                last_child = nil,
                next_sibling = nil,
                prev_sibling = nil,
            }
            self._nodes[id] = node
        end

        -- Remove from old children set
        old_children[id] = nil

        -- Relink in new position
        node.prev_sibling = prev_id
        node.next_sibling = nil
        if prev_id then
            self._nodes[prev_id].next_sibling = id
        end
        if not first then first = id end
        last = id
        prev_id = id
    end

    -- Update parent pointers
    if parent_node then
        parent_node.first_child = first
        parent_node.last_child = last
    else
        self._root_first = first
        self._root_last = last
    end

    -- Remove any children not in the new list
    for id in pairs(old_children) do
        self:remove_item(id)
    end
end

---@generic T
---@param parent_id any|nil
---@param id any
---@param data T
function Tree:upsert_item(parent_id, id, data)
    assert(id ~= nil, "id is required")
    assert(parent_id == nil or self._nodes[parent_id], "parent does not exist")

    local node = self._nodes[id]
    if node then
        -- Update data
        node.data = data

        -- Reparent if needed
        if node.parent_id ~= parent_id then
            -- 1. Unlink from old parent (does not delete children)
            self:_unlink(id)

            -- 2. Update parent reference
            node.parent_id = parent_id

            -- 3. Relink under new parent
            self:_link_child(parent_id, id)
        end
    else
        -- Create new node
        node = {
            parent_id    = parent_id,
            data         = data,
            first_child  = nil,
            last_child   = nil,
            next_sibling = nil,
            prev_sibling = nil,
        }
        self._nodes[id] = node

        -- Link under parent or root
        self:_link_child(parent_id, id)
    end
end

---@generic T
---@param parent_id any|nil
---@param items loop.tools.Tree.Item[]
function Tree:upsert_items(parent_id, items)
    assert(type(items) == "table", "items must be a table")
    assert(parent_id == nil or self._nodes[parent_id], "parent does not exist")

    for _, item in ipairs(items) do
        local id   = assert(item.id, "each item must have an 'id'")
        local data = item.data

        local node = self._nodes[id]
        if node then
            -- Update data
            node.data = data

            -- Reparent if needed
            if node.parent_id ~= parent_id then
                -- Remove from old parent (keeps subtree intact)
                self:_unlink(id)

                -- Update parent reference
                node.parent_id = parent_id

                -- Link under new parent
                self:_link_child(parent_id, id)
            end
        else
            -- Create new node
            node = {
                parent_id    = parent_id,
                data         = data,
                first_child  = nil,
                last_child   = nil,
                next_sibling = nil,
                prev_sibling = nil,
            }
            self._nodes[id] = node

            -- Link into child chain
            self:_link_child(parent_id, id)
        end
    end
end

---@param id any
---@return any -- node data
function Tree:get_item(id)
    assert(id, "id required")
    local node = self._nodes[id]
    return node.data
end

---@return loop.tools.Tree.Item[]
function Tree:get_items()
    local items = {}
    for id, node in pairs(self._nodes) do
        table.insert(items, { id = id, data = node.data })
    end
    return items
end

---@param id any
---@return boolean
function Tree:have_children(id)
    assert(id, "id required")
    local node = self._nodes[id]
    return node and node.first_child ~= nil
end

---Remove a node and all its descendants.
---@param id any
function Tree:remove_item(id)
    assert(id, "id required")
    self:_remove_subtree(id)
end

--==============================================================
-- Flattening (for UI)
--==============================================================

---A flattened node structure (for UI rendering).
---@class loop.tools.Tree.FlatNode
---@field id any
---@field data any
---@field depth integer

---Flatten the tree in depth-first order.
---
---Used for UIs (Neovim buffers, virtual lists, etc.)
---@param exclude_node (fun(data:any):boolean)|nil
---@param exclude_children (fun(data:any):boolean)|nil
---@return loop.tools.Tree.FlatNode[]
function Tree:flatten(exclude_node, exclude_children)
    ---@type loop.tools.Tree.FlatNode<any>[]
    local out = {}

    -- Set to track visited node IDs during this traversal
    local visited = {}
    local path = {} -- for better error reporting (shows the cycle path)

    local function walk(id, depth)
        local node = self._nodes[id]
        if not node then
            error(string.format("Tree:flatten() - Invalid node id %s (nil node)", tostring(id)))
        end

        if exclude_node and exclude_node(node.data) then
            goto continue
        end

        -- Cycle detection
        if visited[id] then
            -- Build a readable cycle path
            local cycle_start = id
            local path_str = {}
            for i = #path, 1, -1 do
                table.insert(path_str, 1, tostring(path[i]))
                if path[i] == cycle_start then break end
            end
            table.insert(path_str, tostring(id)) -- close the loop

            assert(false, string.format(
                "Cycle detected in tree structure during flatten(): %s → %s (loop closes)",
                table.concat(path_str, " → "), tostring(id)
            ))
        end

        -- Mark as being visited (in current path)
        visited[id] = true
        table.insert(path, id)

        out[#out + 1] = {
            id = id,
            data = node.data,
            depth = depth,
        }

        if not exclude_children or not exclude_children(node.data) then
            local child = node.first_child
            while child do
                walk(child, depth + 1)
                child = self._nodes[child].next_sibling
            end
        end

        -- Backtrack: remove from current path
        table.remove(path)
        -- Note: we don't remove from 'visited' here because we allow re-visiting from other roots
        -- But since this is a tree (forest), each node should appear only once anyway

        ::continue::
    end

    local id = self._root_first
    while id do
        -- Reset visited set for each root (in case of forest with shared _nodes - which shouldn't happen in a tree)
        -- But to be safe and allow detection across roots if somehow shared
        if visited[id] then
            assert(false, string.format("Node %s appears under multiple roots - not a valid forest", tostring(id)))
        end
        walk(id, 0)
        id = self._nodes[id].next_sibling
    end

    return out
end

return Tree
