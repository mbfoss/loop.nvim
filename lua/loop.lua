---@class MyModule
local M = {}

local project = require('loop.project')
local config = require('loop.config')

local function setup_user_command(calls)
    -- Command completion: suggest subcommands first
    local function loop_complete(arg_lead, cmd_line, _)
        local args = vim.split(cmd_line, "%s+")
        -- Complete subcommands when typing the first argument
        if #args == 2 then
            local matches = {}
            for _, cmd in ipairs(vim.tbl_keys(calls)) do
                if not vim.startswith(cmd, '_') and vim.startswith(cmd, arg_lead) then
                    table.insert(matches, cmd)
                end
            end
            return matches
        elseif #args == 3 then
            if args[2] == 'ext' or args[2] == 'configure_ext' then
                return require('loop.ext.extensions').ext_names()
            elseif args[2] == 'show' then
                return project.tab_names()
            elseif args[2] == 'breakpoints' then
                return { "toggle", "clear_file", "clear_all" }
            elseif args[2] == 'debug' then
                return { "start", "continue", "restart", "stop" }
            end
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

---@param args loop.Config?
M.setup = function(args)
    assert(not setup_done, "Loop.nvim: setup() already done")
    setup_done = true
    if vim.fn.has("nvim-0.10") ~= 1 then
        error("loop.nvim requires Neovim >= 0.10")
    end

    M.config = vim.tbl_deep_extend("force", config.defaut_config, args or {})
    project.setup(M.config)

    _G.LoopProject =
    {
        _winbar_click = project.winbar_click,
        create_project = project.create_project,
        open_project = project.open_project,
        close_project = project.close_project,
        add_task = project.add_task,
        task = project.run_task,
        redo = project.repeat_task,
        ext = project.extension_task,
        configure_ext = project.extension_config,
        toggle = project.toggle_window,
        show = project.show_window,
        hide = project.hide_window,
        breakpoints = project.update_breakpoints,
        debug = project.debug_command,
    }
    setup_user_command(_G.LoopProject)
end

return M
