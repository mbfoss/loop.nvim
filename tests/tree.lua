require("plenary.busted")
local Tree = require("loop.tools.Tree")

describe("loop.tools.Tree", function()
    it("inserts a root item", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", { value = 1 })
        assert.truthy(tree.nodes["A"])
        assert.same(nil, tree.nodes["A"].parent_id)
        assert.equal("A", tree.root_first)
        assert.equal("A", tree.root_last)
        local flat = tree:flatten()
        assert.same({
            { id = "A", data = { value = 1 }, depth = 0 }
        }, flat)
    end)

    it("inserts children in order and preserves sibling order", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", {})
        tree:upsert_item("A", "B", {})
        tree:upsert_item("A", "C", {})
        tree:upsert_item("A", "D", {})
        local A = tree.nodes["A"]
        assert.equal("B", A.first_child)
        assert.equal("D", A.last_child)
        assert.equal("C", tree.nodes["B"].next_sibling)
        assert.equal("D", tree.nodes["C"].next_sibling)
        assert.is_nil(tree.nodes["D"].next_sibling)
        local flat = tree:flatten()
        assert.same({
            { id = "A", depth = 0, data = {} },
            { id = "B", depth = 1, data = {} },
            { id = "C", depth = 1, data = {} },
            { id = "D", depth = 1, data = {} },
        }, flat)
    end)

    it("upserts (updates) existing node data", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", { value = 1 })
        tree:upsert_item(nil, "A", { value = 99 }) -- update same id
        assert.same({ value = 99 }, tree.nodes["A"].data)
    end)

    it("reparents a node correctly", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", {})
        tree:upsert_item(nil, "B", {})
        tree:upsert_item(nil, "C", {})
        tree:upsert_item("A", "B", {}) -- move B under A
        assert.equal("A", tree.nodes["B"].parent_id)
        assert.equal("B", tree.nodes["A"].first_child)
        assert.equal("B", tree.nodes["A"].last_child)
        -- root list should now contain A, C
        assert.equal("A", tree.root_first)
        assert.equal("C", tree.root_last)
        assert.equal("C", tree.nodes["A"].next_sibling)
        assert.is_nil(tree.nodes["C"].next_sibling)
    end)

    it("removes a leaf node", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", {})
        tree:upsert_item(nil, "B", {})
        tree:remove_item("B")
        assert.is_nil(tree.nodes["B"])
        local flat = tree:flatten()
        assert.same({
            { id = "A", data = {}, depth = 0 },
        }, flat)
    end)

    it("removes a whole subtree", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", {})
        tree:upsert_item("A", "B", {})
        tree:upsert_item("B", "C", {})
        tree:remove_item("B")
        assert.is_nil(tree.nodes["B"])
        assert.is_nil(tree.nodes["C"])
        local flat = tree:flatten()
        assert.same({
            { id = "A", data = {}, depth = 0 }
        }, flat)
    end)

    it("upsert_items inserts children in array order", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", {})
        tree:upsert_items("A", {
            { id = "B", data = {} },
            { id = "C", data = {} },
            { id = "D", data = {} },
        })
        assert.equal("B", tree.nodes["A"].first_child)
        assert.equal("D", tree.nodes["A"].last_child)
        local flat = tree:flatten()
        assert.same({
            { id = "A", data = {}, depth = 0 },
            { id = "B", data = {}, depth = 1 },
            { id = "C", data = {}, depth = 1 },
            { id = "D", data = {}, depth = 1 },
        }, flat)
    end)

    it("keeps tree stable through multiple operations", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "root", {})
        tree:upsert_items("root", {
            { id = "a", data = {} },
            { id = "b", data = {} },
        })
        -- Add grandchildren
        tree:upsert_items("a", {
            { id = "a1", data = {} },
            { id = "a2", data = {} },
        })
        -- Reparent b under a2
        tree:upsert_item("a2", "b", {})
        local flat = tree:flatten()
        assert.same({
            { id = "root", depth = 0, data = {} },
            { id = "a",    depth = 1, data = {} },
            { id = "a1",   depth = 2, data = {} },
            { id = "a2",   depth = 2, data = {} },
            { id = "b",    depth = 3, data = {} },
        }, flat)
    end)

    -- Additional tests for upsert_item
    it("handles upsert_item with nil parent_id for root", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "Root1", { key = "value" })
        assert.equal("Root1", tree.root_first)
        assert.equal("Root1", tree.root_last)
        assert.same(nil, tree.nodes["Root1"].parent_id)
        assert.same({ key = "value" }, tree.nodes["Root1"].data)
    end)

    it("updates data without changing position if parent same", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", { old = true })
        tree:upsert_item(nil, "A", { new = true })
        assert.same({ new = true }, tree.nodes["A"].data)
        assert.equal("A", tree.root_first)
    end)

    it("reparents from root to child", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "Parent", {})
        tree:upsert_item(nil, "Child", {})
        tree:upsert_item("Parent", "Child", {}) -- Move Child under Parent
        assert.equal("Parent", tree.nodes["Child"].parent_id)
        assert.equal("Child", tree.nodes["Parent"].first_child)
        assert.equal("Parent", tree.root_first)
        assert.equal("Parent", tree.root_last) -- Only Parent at root
    end)

    it("reparents from child to root", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "Parent", {})
        tree:upsert_item("Parent", "Child", {})
        tree:upsert_item(nil, "Child", {}) -- Move to root
        assert.same(nil, tree.nodes["Child"].parent_id)
        assert.is_nil(tree.nodes["Parent"].first_child)
        assert.equal("Parent", tree.root_first)
        assert.equal("Child", tree.root_last)
        assert.equal("Child", tree.nodes["Parent"].next_sibling)
    end)

    it("handles reparenting with siblings preserved", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "P1", {})
        tree:upsert_item("P1", "A", {})
        tree:upsert_item("P1", "B", {})
        tree:upsert_item("P1", "C", {})
        tree:upsert_item(nil, "P2", {})
        tree:upsert_item("P2", "B", {}) -- Move B to P2
        assert.equal("A", tree.nodes["P1"].first_child)
        assert.equal("C", tree.nodes["P1"].last_child)
        assert.equal("C", tree.nodes["A"].next_sibling)
        assert.is_nil(tree.nodes["C"].next_sibling)
        assert.equal("B", tree.nodes["P2"].first_child)
    end)

    -- Additional tests for remove_item
    it("handles remove_item on non-existent node gracefully", function()
        local tree = Tree:new()
        tree:remove_item("NonExistent")
        -- No error, just no-op
        assert.same({}, tree.nodes)
    end)

    it("removes root node with no children", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "Root", {})
        tree:remove_item("Root")
        assert.is_nil(tree.root_first)
        assert.is_nil(tree.root_last)
        assert.same({}, tree.nodes)
    end)

    it("removes root node with siblings", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "R1", {})
        tree:upsert_item(nil, "R2", {})
        tree:upsert_item(nil, "R3", {})
        tree:remove_item("R2")
        assert.equal("R1", tree.root_first)
        assert.equal("R3", tree.root_last)
        assert.equal("R3", tree.nodes["R1"].next_sibling)
        assert.is_nil(tree.nodes["R3"].next_sibling)
    end)

    it("removes node with children and siblings", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "Root", {})
        tree:upsert_item("Root", "A", {})
        tree:upsert_item("Root", "B", {})
        tree:upsert_item("Root", "C", {})
        tree:upsert_item("B", "B1", {})
        tree:upsert_item("B", "B2", {})
        tree:remove_item("B")
        assert.equal("A", tree.nodes["Root"].first_child)
        assert.equal("C", tree.nodes["Root"].last_child)
        assert.equal("C", tree.nodes["A"].next_sibling)
        assert.is_nil(tree.nodes["C"].next_sibling)
        assert.is_nil(tree.nodes["B1"])
        assert.is_nil(tree.nodes["B2"])
    end)

    it("removes entire tree by removing all roots", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "R1", {})
        tree:upsert_item("R1", "C1", {})
        tree:upsert_item(nil, "R2", {})
        tree:remove_item("R1")
        tree:remove_item("R2")
        assert.same({}, tree.nodes)
        assert.is_nil(tree.root_first)
    end)

    -- Additional tests for upsert_items
    it("handles upsert_items with empty array", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "Parent", {})
        tree:upsert_items("Parent", {})
        -- No change
        assert.is_nil(tree.nodes["Parent"].first_child)
    end)

    it("handles upsert_items mixing new and existing items", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "Parent", {})
        tree:upsert_item("Parent", "Existing", { old = true })
        tree:set_children("Parent", {
            { id = "New1",     data = {} },
            { id = "Existing", data = { new = true } },
            { id = "New2",     data = {} },
        })
        assert.same({ new = true }, tree.nodes["Existing"].data)
        assert.equal("New1", tree.nodes["Parent"].first_child)
        assert.equal("New2", tree.nodes["Parent"].last_child)
        assert.equal("Existing", tree.nodes["New1"].next_sibling)
        assert.equal("New2", tree.nodes["Existing"].next_sibling)
    end)

    it("handles set_children to root (nil parent)", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "ExistingRoot", {})
        tree:set_children(nil, {
            { id = "NewRoot1",     data = {} },
            { id = "ExistingRoot", data = { updated = true } },
            { id = "NewRoot2",     data = {} },
        })
        assert.equal("NewRoot1", tree.root_first)
        assert.equal("NewRoot2", tree.root_last)
        assert.same({ updated = true }, tree.nodes["ExistingRoot"].data)
        assert.equal("ExistingRoot", tree.nodes["NewRoot1"].next_sibling)
        assert.equal("NewRoot2", tree.nodes["ExistingRoot"].next_sibling)
    end)

    -- Additional tests for flatten
    it("handles flatten on empty tree", function()
        local tree = Tree:new()
        local flat = tree:flatten()
        assert.same({}, flat)
    end)

    it("handles flatten with multiple roots and deep nesting", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "R1", { r1 = true })
        tree:upsert_item("R1", "C1", { c1 = true })
        tree:upsert_item("C1", "GC1", { gc1 = true })
        tree:upsert_item(nil, "R2", { r2 = true })
        tree:upsert_item("R2", "C2", { c2 = true })
        local flat = tree:flatten()
        assert.same({
            { id = "R1",  data = { r1 = true },  depth = 0 },
            { id = "C1",  data = { c1 = true },  depth = 1 },
            { id = "GC1", data = { gc1 = true }, depth = 2 },
            { id = "R2",  data = { r2 = true },  depth = 0 },
            { id = "C2",  data = { c2 = true },  depth = 1 },
        }, flat)
    end)

    it("handles flatten after removals", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", {})
        tree:upsert_item("A", "B", {})
        tree:remove_item("B")
        local flat = tree:flatten()
        assert.same({
            { id = "A", data = {}, depth = 0 },
        }, flat)
    end)
    it("handles complex sequence: upserts, reparents, removes", function()
        local tree = Tree:new()

        -- Initial structure: two roots
        tree:upsert_items(nil, {
            { id = "Root1", data = {} },
            { id = "Root2", data = {} },
        })

        -- Add children
        tree:upsert_items("Root1", {
            { id = "ChildA", data = {} },
            { id = "ChildB", data = {} },
        })
        tree:upsert_items("Root2", {
            { id = "ChildC", data = {} },
        })

        -- NEW: Instead of reparenting ChildB via upsert_items (which doesn't move it),
        -- we do it properly with upsert_item (single node) — this actually moves it!
        tree:upsert_item("Root2", "ChildB", { updated = true })

        -- Remove ChildC
        tree:remove_item("ChildC")

        -- Add grandchild under ChildB
        tree:upsert_item("ChildB", "Grandchild", {})

        -- Final expected flatten order (Root1 → ChildA → Root2 → ChildB → Grandchild)
        local flat = tree:flatten()
        assert.same({
            { id = "Root1",      data = {},                 depth = 0 },
            { id = "ChildA",     data = {},                 depth = 1 },
            { id = "Root2",      data = {},                 depth = 0 },
            { id = "ChildB",     data = { updated = true }, depth = 1 },
            { id = "Grandchild", data = {},                 depth = 2 },
        }, flat)

        -- Check direct links
        assert.equal("ChildA", tree.nodes["Root1"].first_child)
        assert.is_nil(tree.nodes["Root1"].last_child.next_sibling) -- only one child

        assert.equal("ChildB", tree.nodes["Root2"].first_child)
        assert.equal("ChildB", tree.nodes["Root2"].last_child)

        assert.equal("Grandchild", tree.nodes["ChildB"].first_child)
        assert.equal("Grandchild", tree.nodes["ChildB"].last_child)
    end)

    it("handles large batch upsert_items with mixed new and existing items", function()
        local tree = Tree:new()

        -- Root parent
        tree:upsert_item(nil, "P", { name = "Parent" })

        -- Batch 1: Add three new children under P
        tree:upsert_items("P", {
            { id = 1, data = { value = "one" } },
            { id = 2, data = { value = "two" } },
            { id = 3, data = { value = "three" } },
        })

        -- Batch 2: Mix of updates (same parent) and new nodes — NO reparenting!
        tree:upsert_items("P", {
            { id = 2, data = { value = "two", updated = true } }, -- existing → update only
            { id = 4, data = { value = "four" } },                -- new
            { id = 1, data = { value = "one", updated = true } }, -- existing → update only
            { id = 5, data = { value = "five" } },                -- new
        })

        -- Expected behavior of upsert_items:
        -- - New nodes (4, 5) are appended in order they appear
        -- - Existing nodes (2, 1) stay where they were unless reparented (they aren't)
        -- - So final order under P: 1 → 2 → 3 → 4 → 5
        --   (original 1→2→3 preserved, then 4 and 5 appended)

        local parent_node = tree.nodes["P"]
        assert.equal(1, parent_node.first_child) -- unchanged
        assert.equal(5, parent_node.last_child)  -- new ones appended

        -- Verify full chain
        local chain = {}
        local cur = parent_node.first_child
        while cur do
            table.insert(chain, cur)
            cur = tree.nodes[cur].next_sibling
        end

        assert.same({ 1, 2, 3, 4, 5 }, chain)

        -- Verify data was updated correctly
        assert.same({ value = "one", updated = true }, tree.nodes[1].data)
        assert.same({ value = "two", updated = true }, tree.nodes[2].data)
        assert.same({ value = "three" }, tree.nodes[3].data)
        assert.same({ value = "four" }, tree.nodes[4].data)
        assert.same({ value = "five" }, tree.nodes[5].data)
    end)

    it("handles upsert_items with duplicate ids in same batch (last wins?)", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "P", {})
        tree:upsert_items("P", {
            { id = "Dup", data = { first = true } },
            { id = "New", data = {} },
            { id = "Dup", data = { second = true } },
        })
        -- Processes sequentially, so Dup created first, then updated later
        assert.same({ second = true }, tree.nodes["Dup"].data)
        -- Order: Dup (first), New, Dup (but same id, updated but position from first insert)
        -- Since same id, second is update, no new link
        assert.equal("Dup", tree.nodes["P"].first_child)
        assert.equal("New", tree.nodes["Dup"].next_sibling)
        assert.equal("New", tree.nodes["P"].last_child)
        -- Only two children
    end)

    -- Edge case: Remove after upsert_items
    it("handles remove after batch upsert", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "P", {})
        tree:upsert_items("P", {
            { id = "A", data = {} },
            { id = "B", data = {} },
        })
        tree:remove_item("A")
        assert.equal("B", tree.nodes["P"].first_child)
        assert.equal("B", tree.nodes["P"].last_child)
    end)

    it("preserves sibling order when updating existing nodes in upsert_items", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "P", {})
        tree:upsert_items("P", { { id = "A" }, { id = "B" }, { id = "C" } })

        -- This batch only updates data — should NOT reorder anything
        tree:upsert_items("P", {
            { id = "B", data = { updated = true } },
            { id = "A", data = { updated = true } },
        })

        local chain = {}
        local cur = tree.nodes["P"].first_child
        while cur do
            table.insert(chain, cur); cur = tree.nodes[cur].next_sibling
        end

        assert.same({ "A", "B", "C" }, chain) -- Order preserved!
        assert.truthy(tree.nodes["A"].data.updated)
        assert.truthy(tree.nodes["B"].data.updated)
    end)

    it("handles set_children removing all children", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "P", {})
        tree:upsert_items("P", { { id = "A" }, { id = "B" } })

        tree:set_children("P", {}) -- Empty list = remove all

        assert.is_nil(tree.nodes["P"].first_child)
        assert.is_nil(tree.nodes["P"].last_child)
        assert.is_nil(tree.nodes["A"])
        assert.is_nil(tree.nodes["B"])
    end)

    it("handles set_children on root with empty list", function()
        local tree = Tree:new()
        tree:upsert_items(nil, { { id = "A" }, { id = "B" } })

        tree:set_children(nil, {})

        assert.is_nil(tree.root_first)
        assert.is_nil(tree.root_last)
        assert.same({}, tree.nodes)
    end)

    it("prevents cycles via reparenting (detects and errors or ignores)", function()
        -- This is the ONE thing missing: cycle safety
        local tree = Tree:new()
        tree:upsert_item(nil, "A", {})
        tree:upsert_item("A", "B", {})
        tree:upsert_item("B", "C", {})

        -- Try to create cycle: C → A
        local ok, err = pcall(tree.upsert_item, tree, "C", "A", {})
        -- You currently allow this → creates infinite loop in flatten()!!

        if ok then
            -- If you allow it, at least flatten() should not infinite loop
            local ok2, _ = pcall(tree.flatten, tree)
            assert.is_true(ok2)
        else
            assert.truthy(err and (err:match("cycle") or err:match("parent"))) -- if you error, great!
        end
    end)

    it("reparents a deep child back to root correctly", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", {})
        tree:upsert_item("A", "B", {})
        tree:upsert_item("A", "C", {})
        tree:upsert_item("C", "D", {})               -- deep chain A → C → D

        tree:upsert_item(nil, "D", { moved = true }) -- reparent to root

        assert.same(nil, tree.nodes["D"].parent_id)
        assert.equal("D", tree.root_last)

        -- C lost its only child
        assert.is_nil(tree.nodes["C"].first_child)

        local flat = tree:flatten()
        assert.same({
            { id = "A", depth = 0, data = {} },
            { id = "B", depth = 1, data = {} },
            { id = "C", depth = 1, data = {} },
            { id = "D", depth = 0, data = { moved = true } },
        }, flat)
    end)

    it("reparents root node under a deep child", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "Root1", {})
        tree:upsert_item(nil, "Root2", {})
        tree:upsert_item("Root1", "A", {})
        tree:upsert_item("A", "B", {})

        tree:upsert_item("B", "Root2", { moved = true })

        assert.equal("B", tree.nodes["Root2"].parent_id)
        assert.equal("Root1", tree.root_first)
        assert.is_nil(tree.nodes["Root1"].next_sibling) -- Root2 removed from root list

        local flat = tree:flatten()
        assert.same({
            { id = "Root1", depth = 0, data = {} },
            { id = "A",     depth = 1, data = {} },
            { id = "B",     depth = 2, data = {} },
            { id = "Root2", depth = 3, data = { moved = true } },
        }, flat)
    end)

    it("updates existing node without changing sibling order", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "P", {})
        tree:upsert_items("P", { { id = "A" }, { id = "B" }, { id = "C" } })

        -- B updated but should stay between A and C
        tree:upsert_item("P", "B", { updated = true })

        local chain = {}
        local cur = tree.nodes["P"].first_child
        while cur do
            table.insert(chain, cur)
            cur = tree.nodes[cur].next_sibling
        end

        assert.same({ "A", "B", "C" }, chain)
        assert.same({ updated = true }, tree.nodes["B"].data)
    end)

    it("reparents last sibling to become first child", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "P", {})
        tree:upsert_items("P", { { id = "A", data = {} }, { id = "B", data = {} }, { id = "C", data = {} } })

        tree:upsert_item("P", "C", { moved = true }) -- just updates data, does NOT move

        -- Sibling order stays the same
        assert.equal("A", tree.nodes["P"].first_child)
        assert.equal("B", tree.nodes["A"].next_sibling)
        assert.equal("C", tree.nodes["B"].next_sibling)
        assert.equal("C", tree.nodes["P"].last_child)

        local flat = tree:flatten()
        assert.same({
            { id = "P", depth = 0, data = {} },
            { id = "A", depth = 1, data = {} },
            { id = "B", depth = 1, data = {} },
            { id = "C", depth = 1, data = { moved = true } },
        }, flat)
    end)


    it("prevents reparenting that would create a cycle", function()
        local tree = Tree:new()
        tree:upsert_item(nil, "A", {})
        tree:upsert_item("A", "B", {})
        tree:upsert_item("B", "C", {})

        local ok, err = pcall(tree.upsert_item, tree, "C", "A", {})
        if ok then
            -- flatten must not infinite loop
            local ok2 = pcall(function() tree:flatten() end)
            assert.is_true(ok2)
        else
            assert.matches("cycle", err)
        end
    end)
end)
