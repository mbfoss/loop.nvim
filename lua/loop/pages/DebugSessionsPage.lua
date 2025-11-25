local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')

---@class loop.pages.DebugSessionsPage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.DebugSessionsPage): loop.pages.DebugSessionsPage
local DebugSessionsPage = class(ItemListPage)

function DebugSessionsPage:init()
    ItemListPage.init(self, "Debug Sessions")
    self._items = {}
    self._index = {}
end


return DebugSessionsPage
