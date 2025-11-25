local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')

---@class loop.pages.StackTracePage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.StackTracePage): loop.pages.StackTracePage
local StackTracePage = class(ItemListPage)

function StackTracePage:init()
    ItemListPage.init(self, "Stack")
    self._items = {}
    self._index = {}
end

return StackTracePage
