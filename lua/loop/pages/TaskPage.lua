local Page = require('loop.pages.Page')
local class = require('loop.tools.class')

---@class loop.pages.TaskPage: loop.pages.Page
---@field new fun(self: loop.pages.TaskPage, filetype : string, on_buf_enter : fun(buf : number)) : loop.pages.TaskPage
local TaskPage = class(Page)

---@param filetype string
---@param on_buf_enter fun(buf: number)
function TaskPage:init(filetype, on_buf_enter)
    Page.init(self, filetype, on_buf_enter)
end

return TaskPage
