local process_task = require('loop.coretasks.process')

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
        start_one_task = function(task, page_manager, on_exit)
            -- composite task does nothing by itself
            on_exit(true)
            ---@type loop.TaskControl
            local controller = { terminate = function() end }
            return controller, nil
        end
    }
end

function M.get_process_task_provider()
    ---@type loop.TaskTypeProvider
    return {
        get_task_schema = function()
            local schema = require('loop.coretasks.processschema')
            return schema
        end,
        start_one_task = process_task.start_task
    }
end

return M
