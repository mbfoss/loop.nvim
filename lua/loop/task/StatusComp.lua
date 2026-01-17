local class        = require('loop.tools.class')
local ItemListComp = require('loop.comp.ItemList')
local config       = require("loop.config")

---@alias loop.task.TasksStatusComp.Item loop.comp.ItemList.Item

-- Example state-to-highlight mapping
local _highlights  = {
    pending = "LoopPluginTaskPending",
    running = "LoopPluginTaskRunning",
    success = "LoopPluginTaskSuccess",
    warning = "LoopPluginTaskWarning",
    failure = "LoopPluginTaskFailure",
}

vim.api.nvim_set_hl(0, _highlights.pending, { link = "Comment" })
vim.api.nvim_set_hl(0, _highlights.running, { link = "DiffChange" })
vim.api.nvim_set_hl(0, _highlights.success, { link = "DiffAdd" })
vim.api.nvim_set_hl(0, _highlights.warning, { link = "WarningMsg" })
vim.api.nvim_set_hl(0, _highlights.failure, { link = "ErrorMsg" })

local _line_id = 0

---@class loop.task.TasksStatusComp : loop.comp.ItemList
---@field new fun(self: loop.task.TasksStatusComp): loop.task.TasksStatusComp
local TasksStatusComp = class(ItemListComp)

function TasksStatusComp:init()
    local symbols = config.current.window.symbols
    ---@type loop.comp.ItemList.InitArgs
    local comp_args = {
        formatter = function(id, data, out_highlights)
            if data.log_message then
                if data.log_level == vim.log.levels.ERROR then
                    table.insert(out_highlights, { group = _highlights.failure })
                end
                return data.log_message
            end
            local hl = _highlights.pending
            local icon = symbols.waiting
            if data.event == "start" then
                icon = symbols.running
                hl = _highlights.running
            elseif data.event == "stop" then
                if data.success then
                    icon = symbols.success
                    hl = _highlights.success
                else
                    icon = symbols.failure
                    hl = _highlights.failure
                end
            end
            local prefix = "[" .. icon .. "]"
            table.insert(out_highlights, { group = hl, end_col = #prefix })
            local text = prefix .. data.name
            if data.error_msg then
                text = text .. ' - ' .. data.error_msg
            end
            return text
        end,
    }
    ItemListComp.init(self, comp_args)
end

---@param name string
---@return number
function TasksStatusComp:add_task(name)
    _line_id = _line_id + 1
    local id = _line_id
    ---@type loop.comp.ItemList.Item
    local item = {
        id = name,
        data = {
            name = name
        }
    }
    self:upsert_item(item)
    return id
end

---@param name string
---@param event "start"|"stop"
---@param success boolean
---@param reason string?
function TasksStatusComp:set_task_status(name, event, success, reason)
    local item = self:get_item(name)
    if item then
        item.data.event = event
        item.data.success = success
        item.data.error_msg = (not success) and reason or nil
        self:refresh_content()
    end
end

return TasksStatusComp
