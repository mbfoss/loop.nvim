local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')

---@class loop.pages.DebugSessionsPage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.DebugSessionsPage): loop.pages.DebugSessionsPage
local DebugSessionsPage = class(ItemListPage)

function DebugSessionsPage:init()
    ItemListPage.init(self, "Debug Sessions")
    self._items = {}
    self._index = {}

    self:set_select_handler(function (item)
        self:_on_item_selected(item)
    end)
end

function DebugSessionsPage:_on_item_selected(item)
    vim.notify("DebugSessionsPage item selected: " .. vim.inspect(item or "nil"))
end


return DebugSessionsPage
