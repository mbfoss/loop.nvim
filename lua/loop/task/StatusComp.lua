local class        = require('loop.tools.class')
local ItemTreeComp = require('loop.comp.ItemTree')
local config       = require("loop.config")

---@alias loop.task.TasksStatusComp.Item loop.comp.ItemTree.Item

-- Example state-to-highlight mapping
local _highlights     = {
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

---@class loop.task.TasksStatusComp : loop.comp.ItemTree
---@field new fun(self: loop.task.TasksStatusComp): loop.task.TasksStatusComp
local TasksStatusComp = class(ItemTreeComp)

---@param id any
---@param data any
---@param highlights loop.Highlight[]
---@return string
local function _node_formatter(id, data, highlights)
    return "formatter not implemented"
end

function TasksStatusComp:init()
    local symbols = config.current.window.symbols
    ---@type loop.comp.ItemTree.InitArgs
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
                text = text .. '\n' .. data.error_msg
            end
            return text
        end,
    }
    ItemTreeComp.init(self, comp_args)
end

return TasksStatusComp
