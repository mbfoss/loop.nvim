local Page = require('loop.pages.Page')
local class = require('loop.tools.class')

---@class loop.pages.TaskPage: loop.pages.Page
---@field new fun(self: loop.pages.TaskPage, name:string) : loop.pages.TaskPage
local TaskPage = class(Page)

---@param name string
function TaskPage:init(name)
    Page.init(self, "loop-tasks", name)
end

return TaskPage
