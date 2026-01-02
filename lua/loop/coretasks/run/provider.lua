local run = require('loop.coretasks.run.run')
local jsontools = require('loop.tools.json')

---@type loop.TaskProvider
local provider = {
    get_task_schema = function()
        local schema = require('loop.coretasks.run.schema')
        return schema
    end,
    get_task_templates = function(config)
        local templates = require('loop.coretasks.run.templates')
        return templates
    end,
    get_task_preview = function(task)
        local cpy = vim.fn.copy(task)
        local templates = require('loop.coretasks.run.templates')
        ---@diagnostic disable-next-line: undefined-field, inject-field
        cpy.__order = templates[1].task.__order
        return jsontools.to_string(cpy), "json"
    end,
    start_one_task = run.start_app
}

return provider
