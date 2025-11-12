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

---@param page loop.pages.Page
---@param set_active_tab fun(tab: loop.TabInfo)
local function set_keymaps(page, set_active_tab)
    local modes = { "n", "t" }
    local idx = 0
    for _, tab in ipairs(tabs_data) do
        if tab.page then
            local buf = page:get_buf()
            idx = idx + 1
            local key = tostring(idx)
            for _, mode in ipairs(modes) do
                local ok, err = pcall(vim.api.nvim_buf_del_keymap, buf, mode, key)
                log:log({ 'remove keymap ', ok, err })
            end
            vim.keymap.set(modes, key, function()
                log:log({ "setting active tab: ", tab.filetype })
                set_active_tab(tab)
            end, { buffer = buf })
        end
    end
end
    ]] --

