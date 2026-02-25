local M = {}

local selector = require("loop.tools.selector")
local taskmgr = require("loop.task.taskmgr")
local jsontools = require("loop.json.jsontools")

---@params task loop.Task
function M.select_taskobj(callback)
    taskmgr.select_task_template(callback)
end

function M.select_taskname(callback, data, path)
    local cur_task_name
    if type(path) == "string" then
        local cur_task_path = path:match("^(/tasks/%d+)/.*$")
        if cur_task_path then
            local task = jsontools.get_at_path(data, cur_task_path)
            if type(task) == "table" then
                cur_task_name = task.name
            end
        end
    end
    local tasks = data and data.tasks
    if tasks then
        local choices = {}
        for _, task in ipairs(tasks) do
            if task.name ~= cur_task_name then
                ---@type loop.SelectorItem
                local item = { label = task.name, data = task.name }
                if item.label then
                    table.insert(choices, item)
                end
            end
        end
        if #choices == 0 then
            vim.notify("No other tasks to select")
            callback(nil)
        else
            selector.select({
                prompt = "Select dependency",
                items = choices,
                callback = function(name)
                    if name then callback(name) end
                end
            })
        end
    else
        callback(nil)
    end
end

return M
