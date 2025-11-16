local Page = require('loop.pages.Page')
local class = require('loop.tools.class')

---@class loop.pages.TaskPage: loop.pages.Page
---@field new fun(self: loop.pages.TaskPage, filetype : string) : loop.pages.TaskPage
local TaskPage = class(Page)

---@param filetype string
function TaskPage:init(filetype)
    Page.init(self, filetype)
end

return TaskPage
