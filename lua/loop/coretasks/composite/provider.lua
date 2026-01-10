local jsontools = require('loop.tools.json')

local field_order = { "name", "type", "save_buffers", "depends_on", "depends_order" }
---@type loop.TaskProvider
local provider = {

    get_task_schema = function()
        return {}
    end,
    get_task_templates = function()
        ---@type loop.taskTemplate[]
        return {
            {
                name = "Sequence",
                task = {
                    __order = field_order,
                    name = "Sequence",
                    type = "composite",
                    depends_on = { "", "" },
                    depends_order = "sequence",
                    save_buffers = nil,
                },
            },
            {
                name = "Parallel",
                task = {
                    __order = field_order,
                    name = "Parallel",
                    type = "composite",
                    depends_on = { "", "" },
                    depends_order = "parallel",
                    save_buffers = nil,
                },
            },
        }
    end,
    get_task_preview = function(task)
        local cpy = vim.fn.copy(task)
        ---@diagnostic disable-next-line: inject-field
        cpy.__order = field_order
        return jsontools.to_string(cpy), "json"
    end,
    start_one_task = function(_, _, on_exit)
        on_exit(true)
        ---@type loop.TaskControl
        return {
            terminate = function()
            end
        }
    end
}

return provider
