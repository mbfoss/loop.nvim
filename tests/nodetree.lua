-- tests/nodetree.lua
require("plenary.busted")

describe("ItemTreePage (real, no anchor line, perfect rendering)", function()
  local ItemTreePage
  local page

  before_each(function()
    ItemTreePage = require("loop.pages.ItemTreePage")
    page = ItemTreePage:new("test", {
      formatter = function(item) return item.data.name end,
      loading_text = "Loading...",
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

  it("starts with 0 lines", function()
    assert.are.equal(0, #lines())
  end)

  it("renders 2 items → exactly 2 lines", function()
    page:set_items({
      { id = 1, data = { name = "Root 1" } },
      { id = 2, data = { name = "Root 2" } },
    })
    local l = lines()
    assert.are.equal(2, #l)
    assert.is_truthy(l[1]:match("Root 1$"))
    assert.is_truthy(l[2]:match("Root 2$"))
  end)

  it("renders expanded tree correctly", function()
    page:set_items({
      {
        id = 1,
        data = { name = "Parent" },
        expanded = true,
        children = { { id = 2, data = { name = "Child" } } },
      },
    })
    local l = lines()
    assert.are.equal(2, #l)
    assert.is_truthy(l[1]:match("^▾ Parent$"))
    assert.is_truthy(l[2]:match("^  Child$"))
  end)

  it("collapse/expand works perfectly", function()
    page:set_items({
      {
        id = 1,
        data = { name = "Folder" },
        expanded = true,
        children = { { id = 2, data = { name = "File.txt" } } },
      },
    })
    assert.are.equal(2, #lines())

    page:collapse(1)
    local l = lines()
    assert.are.equal(1, #l)
    assert.is_truthy(l[1]:match("^▸ Folder$"))

    page:expand(1)
    assert.are.equal(2, #lines())
  end)

  it("async loading works perfectly", function()
    local done
    page:set_items({
      {
        id = 1,
        data = { name = "Lazy Node" },
        children = function(cb) done = cb end,
      },
    })

    page:toggle_expand(1)
    vim.wait(1000, function()
      local l = lines()
      return #l == 2 and l[2]:match("Loading...")
    end)

    done({ { id = 10, data = { name = "One" } }, { id = 11, data = { name = "Two" } } })

    vim.wait(1000, function()
      local l = lines()
      return #l == 3 and l[2]:match("One") and l[3]:match("Two")
    end)

    local l = lines()
    assert.are.equal(3, #l)
    assert.is_truthy(l[1]:match("^▾ Lazy Node$"))
    assert.is_truthy(l[2]:match("One$"))
    assert.is_truthy(l[3]:match("Two$"))
  end)
end)