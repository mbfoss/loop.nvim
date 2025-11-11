--[[
function M.run_debug_task()
    if not _project_dir then
        vim.notify("Loop.nvim: No active project")
        return
    end
    local ok, err = tasksmgr.select_run_task(_project_dir, "Debug",
        function(task)
            log:log(task)
            if not task.debugger then
                vim.notify("Debugger not configured for task " .. task.name, vim.log.levels.ERROR)
                return
            end
            if type(task.debugger) ~= 'table' then
                vim.notify("Invalid debugger configuration for task " .. task.name, vim.log.levels.ERROR)
                return
            end
            log:log(_module_config)
            local debugger = _module_config.debuggers[task.debugger]
            if not debugger then
                vim.notify("Invalid task '" .. task.name .. "'\nDebugger '" .. task.debugger .. "' not configured",
                    vim.log.levels.ERROR)
                return
            end
            local target = {
                name = task.name,
                cmd = task.command,
                env = task.env,
                cwd = task.cwd
            }
            local ok, err = window:debug_command(debugger, target)
            if not ok then
                vim.notify("Loop.nvim: " .. (err or 'debug error'))
            end
        end)
    if not ok then
        vim.notify("Loop.nvim: " .. (err or 'debug error'))
    end
end
    ]] --

