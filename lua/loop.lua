---@class MyModule
local M = {}

---@class Config
local config = {
    debuggers = {
        lldb = {
            command = "/Library/Developer/CommandLineTools/usr/bin/lldb-dap",
            args = "",
        },
        pthon = {
            command = "python",
            args = "-m debugpy.adapter",
        },        
    }
}

---@type Config
M.config = config

local function setup_user_command(calls)
    -- Command completion: suggest subcommands first
    local function loop_complete(arg_lead, cmd_line, _)
        local args = vim.split(cmd_line, "%s+")
        local subcmd = args[2] -- First argument after command name

        -- Complete subcommands when typing the first argument
        if #args == 2 then
            local matches = {}
            for _, cmd in ipairs(vim.tbl_keys(calls)) do
                if not vim.startswith(cmd, '_') and vim.startswith(cmd, arg_lead) then
                    table.insert(matches, cmd)
                end
            end
            return matches
        end
        return {}
    end

    -- Command handler
    local function loop_command(opts)
        local args = vim.split(opts.args, "%s+")
        local subcmd = args[1]
        if not subcmd or subcmd == "" then
            vim.notify("Usage: :Loop <subcommand> [args...]", vim.log.levels.WARN)
            return
        end
        local fn = calls[subcmd]
        if not fn then
            vim.notify("Unknown subcommand: " .. subcmd, vim.log.levels.ERROR)
            return
        end
        -- Pass any remaining arguments to the function
        local rest = { unpack(args, 2) }
        local ok, err = pcall(fn, unpack(rest))
        if not ok then
            vim.notify("Loop " .. subcmd .. " failed: " .. tostring(err), vim.log.levels.ERROR)
        end
    end

    vim.api.nvim_create_user_command("Loop", loop_command, {
        nargs = "*",
        complete = loop_complete,
        desc = "Loop.nvim management commands",
    })
end

local setup_done = false

---@param args Config?
M.setup = function(args)
    assert(not setup_done, "Loop.nvim: setup() already done")
    setup_done = true
    if vim.fn.has("nvim-0.10") ~= 1 then
        error("loop.nvim requires Neovim >= 0.10")
    end

    M.config = vim.tbl_deep_extend("force", M.config, args or {})
    local project = require('loop.project')
    project.setup(M.config)

    LoopProject =
    {
        create_project = project.create_project,
        open_project = project.open_project,
        close_project = project.close_project,
        create_cmake_config = project.create_cmake_config,
        add_task = project.add_task,
        task = project.run_task,
        repeat_task = project.repeat_task,
        cmake_configure = project.run_cmake_configure,
        cmake_task = project.run_cmake_task,
        cmake_repeat_task = project.repeat_cmake_task,
        events = project.show_events,
        toggle = project.toggle_window,
        show = project.show_window,
        hide = project.hide_window,
        breakpoint = project.toggle_breakpoint,
        _winbar_click = project.winbar_click
    }
    setup_user_command(LoopProject)
end

return M
