local run = require('loop.coretasks.run')
local jsontools = require('loop.tools.json')

local M = {}

function M.get_composite_templates_provider()
    ---@type loop.TaskTemplateProvider
    return {
        get_task_templates = function()
            return require('loop.coretasks.templates.composite')
        end
    }
end

function M.get_build_templates_provider()
    ---@type loop.TaskTemplateProvider
    return {
        get_task_templates = function()
            return require('loop.coretasks.templates.build')
        end
    }
end

function M.get_run_templates_provider()
    ---@type loop.TaskTemplateProvider
    return {
        get_task_templates = function()
            return require('loop.coretasks.templates.run')
        end
    }
end

function M.get_composite_task_provider()
    ---@type loop.TaskTypeProvider
    return {
        get_task_schema = function()
            return {}
        end,
        get_task_preview = function(task)
            local cpy = vim.fn.copy(task)
            local templates = require('loop.coretasks.templates.composite')
            ---@diagnostic disable-next-line: undefined-field, inject-field
            cpy.__order = templates[1].task.__order
            return jsontools.to_string(cpy), "json"
        end,
        start_one_task = function (task, page_manager, on_exit)       
            -- composite task does nothing by itself
            on_exit(true) 
            ---@type loop.TaskControl
            local controller = { terminate = function() end }
            return controller, nil
        end
    }
end

function M.get_run_task_provider()
    ---@type loop.TaskTypeProvider
    return {
        get_task_schema = function()
            local schema = require('loop.coretasks.schema.run')
            return schema
        end,
        get_task_preview = function(task)
            local cpy = vim.fn.copy(task)
            local templates = require('loop.coretasks.templates.build')
            ---@diagnostic disable-next-line: undefined-field, inject-field
            cpy.__order = templates[1].task.__order
            return jsontools.to_string(cpy), "json"
        end,
        start_one_task = run.start_task
    }
end

return M
