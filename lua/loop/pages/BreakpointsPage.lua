local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')

---@class loop.pages.BreakpointsPage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.BreakpointsPage): loop.pages.BreakpointsPage
local BreakpointsPage = class(ItemListPage)

function BreakpointsPage:init()
    ItemListPage.init(self, "Breakpoints")
    self._items = {}
    self._index = {}

    self:set_select_handler(function (item)
        self:_on_item_selected(item)
    end)
end

function BreakpointsPage:_on_item_selected(item)
    vim.notify("BreakpointsPage item selected: " .. vim.inspect(item or "nil"))
end


return BreakpointsPage
