-- tests/nodetree.lua
require("plenary.busted")
local ItemTreePage

describe("ItemTreePage (comprehensive tests)", function()
  local page

  before_each(function()
    ItemTreePage = require("loop.pages.ItemTreePage")
    page = ItemTreePage:new("test", {
      formatter = function(item) return item.data.name end,
      expand_char = "▶",
      collapse_char = "▼",
      indent_string = "  ",
      loading_text = "Loading children...",
    })
  end)

  after_each(function()
    if page and page.get_or_create_buf then
      local buf = page:get_or_create_buf()
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end)

  local function lines()
    return vim.api.nvim_buf_get_lines(page:get_or_create_buf(), 0, -1, false)
  end

  local function line(n)
    local l = lines()
    return l[n] or ""
  end

  local function wait_for_schedule()
    vim.wait(1000, function() return true end, 10) -- forces pending vim.schedule
  end

  it("starts empty (1 line)", function()
    assert.are.equal(1, #lines())
    assert.are.equal("", lines()[1])
  end)

  it("renders flat roots correctly", function()
    page:set_items({
      { id = 1, data = { name = "Alpha" } },
      { id = 2, data = { name = "Beta" } },
    })

    assert.are.equal(3, #lines())
    assert.is_truthy(line(1):match("^ Alpha$"))
    assert.is_truthy(line(2):match("^ Beta$"))
  end)

  it("renders nested tree with proper indentation and expand/collapse chars", function()
    page:set_items({
      { id = 1, data = { name = "Parent" }, expanded = true, children = {
        { id = 2, data = { name = "Child 1" } },
        { id = 3, data = { name = "Child 2" }, expanded = true, children = {
          { id = 4, data = { name = "Grandchild" } },
        }},
      }},
    })

    local expected = {
      "▼ Parent",
      "  ▶ Child 1",
      "  ▼ Child 2",
      "    Grandchild",
    }

    local actual = lines()
    assert.are.equal(#expected + 1, #actual) -- +1 for final empty line
    for i, exp in ipairs(expected) do
      assert.is_truthy(actual[i]:match("^" .. exp:gsub("[▼▶]", ".") .. "$"),
        ("Line %d: expected '%s', got '%s'"):format(i, exp, actual[i]))
      -- Check collapse/expand char
      if exp:find("▼") then
        assert.is_truthy(actual[i]:find("▼", 1, true))
      elseif exp:find("▶") then
        assert.is_truthy(actual[i]:find("▶", 1, true))
      end
    end
  end)

  it("collapses and expands correctly", function()
    page:set_items({
      { id = 1, data = { name = "Folder" }, expanded = true, children = {
        { id = 2, data = { name = "File A" } },
        { id = 3, data = { name = "File B" } },
      }}
    })

    assert.are.equal(4, #lines()) -- Folder + 2 children + empty
    assert.is_truthy(line(1):find("▼ Folder"))

    page:collapse(1)
    local l1 = lines()
    assert.are.equal(2, #l1)
    assert.is_truthy(l1[1]:find("▶ Folder"))

    page:expand(1)
    local l2 = lines()
    assert.are.equal(4, #l2)
    assert.is_truthy(l2[1]:find("▼ Folder"))
    assert.is_truthy(l2[2]:match("^  File A$"))
  end)

  it("shows loading placeholder and resolves async children", function()
    local loader_called = false
    local done_callback

    page:set_items({
      { id = 1, data = { name = "Lazy Node" }, children = function(done)
        loader_called = true
        done_callback = done
      end }
    })

    -- Initially collapsed
    assert.are.equal(2, #lines())
    assert.is_truthy(line(1):find("▶ Lazy Node"))

    -- Expand → should show loading
    page:toggle_expand(1)
    assert.is_truthy(line(1):find("▼ Lazy Node"))
    assert.is_truthy(line(2):match("^  Loading children...$"))
    assert.are.equal(3, #lines())
    assert.is_true(loader_called)

    -- Resolve with children
    done_callback({
      { id = 10, data = { name = "Dynamic 1" } },
      { id = 11, data = { name = "Dynamic 2" } },
    })
    wait_for_schedule()

    local final = lines()
    assert.are.equal(4, #final)
    assert.is_truthy(final[1]:find("▼ Lazy Node"))
    assert.is_truthy(final[2]:match("^  Dynamic 1$"))
    assert.is_truthy(final[3]:match("^  Dynamic 2$"))
  end)

  it("handles loader errors gracefully", function()
    page:set_items({
      { id = 1, data = { name = "Error Node" }, children = function(done)
        error("boom")
      end }
    })

    page:expand(1)
    wait_for_schedule()

    local l = lines()
    assert.are.equal(3, #l)
    assert.is_truthy(l[1]:find("▼ Error Node"))
    assert.is_truthy(l[2]:match("^  Error loading children$"))
  end)

  it("preserves expanded state on upsert_item", function()
    page:set_items({
      { id = 1, data = { name = "Node" }, expanded = true, children = {
        { id = 2, data = { name = "Child" } }
      }}
    })

    assert.are.equal(3, #lines())

    page:upsert_item({ id = 1, data = { name = "Renamed Node" } })
    local l = lines()

    assert.are.equal(3, #l) -- still expanded
    assert.is_truthy(l[1]:match("▼ Renamed Node"))
    assert.is_truthy(l[2]:match("Child"))
  end)

  it("preserves static children when upsert_item omits them", function()
    page:set_items({
      { id = 1, data = { name = "Parent" }, children = {
        { id = 2, data = { name = "Preserved" } }
      }, expanded = true }
    })

    page:upsert_item({ id = 1, data = { name = "Updated" } }) -- no children field!
    local l = lines()

    assert.are.equal(3, #l)
    assert.is_truthy(l[1]:match("Updated"))
    assert.is_truthy(l[2]:match("Preserved"))
  end)

  it("applies highlighter correctly", function()
    page = ItemTreePage:new("test_hl", {
      formatter = function(item) return item.data.name end,
      highlighter = function(item)
        if item.id == 1 then
          return {
            { group = "String", start_col = 0, end_col = 5 },
            { group = "Keyword", start_col = 6 },
          }
        end
      end,
    })

    page:set_items({ { id = 1, data = { name = "Hello World" } } })
  end)

  it("get_cur_item returns correct item under cursor", function()
    page:set_items({
      { id = 10, data = { name = "First" } },
      { id = 20, data = { name = "Second" } },
    })

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, page:get_or_create_buf())
    vim.api.nvim_win_set_cursor(win, { 2, 0 }) -- line 2 (0-based → Second)

    local item = page:get_cur_item()
    assert.are.equal(20, item.id)
  end)

  it("refresh_content does full re-render", function()
    page:set_items({
      { id = 1, data = { name = "Old" }, expanded = true, children = {
        { id = 2, data = { name = "Child" } }
      }}
    })

    page:upsert_item({ id = 1, data = { name = "New" } })
    page:refresh_content()

    assert.is_truthy(line(1):match("New"))
    assert.are.equal(3, #lines()) -- still expanded
  end)

  it("handles deep async nesting correctly", function()
    local loaders = {}
    local make_node = function(id, name, depth)
      if depth >= 2 then
        return { id = id, data = { name = name } }
      end
      return {
        id = id,
        data = { name = name },
        children = function(done)
          loaders[id] = done
        end
      }
    end

    page:set_items({ make_node(1, "Root", 0) })
    page:expand(1)
    assert.is_truthy(line(2):match("Loading children..."))

    loaders[1]({ make_node(10, "Level 1", 1) })
    wait_for_schedule()

    -- Now expand Level 1
    page:expand(10)
    wait_for_schedule()
    assert.is_truthy(lines()[3]:match("Loading children..."))

    loaders[10]({ make_node(100, "Level 2", 2) })
    wait_for_schedule()

    local final = lines()
    assert.is_truthy(final[1]:match("▼ Root"))
    assert.is_truthy(final[2]:match("▼ Level 1"))
    assert.is_truthy(final[3]:match("Level 2"))
  end)
end)