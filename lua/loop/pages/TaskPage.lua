local Page = require('loop.pages.Page')
local class = require('loop.tools.class')

---@class loop.pages.TaskPage: loop.pages.Page
---@field new fun(self: loop.pages.TaskPage) : loop.pages.TaskPage
local TaskPage = class(Page)

function TaskPage:init()
    Page.init(self, "loop-tasks")
end

return TaskPage
