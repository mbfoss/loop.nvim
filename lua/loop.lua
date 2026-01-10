-- lua/loop/init.lua
local strtools = require('loop.tools.strtools')
local extensions = require('loop.extensions')

local M = {}

-- Dependencies
local workspace = require("loop.workspace")
local config = require("loop.config")

-----------------------------------------------------------
-- Defaults
-----------------------------------------------------------

---@type loop.Config
local DEFAULT_CONFIG = {
    selector = "builtin",
    window = {
        symbols = {
            change  = "●",
            success = "✓",
            failure = "✗",
            waiting = "⧗",
            running = "▶",
        },
    },
    macros = {},
    quickfix_matchers = {},
    debug = false,
    autosave_interval = 5, -- 5 minutes
    logs_count = 50,       -- Number of recent logs to show
}

-----------------------------------------------------------
-- State
-----------------------------------------------------------

local setup_done = false
local initialized = false

-----------------------------------------------------------
-- Setup (user config only)
-----------------------------------------------------------

---@param opts loop.Config?
function M.setup(opts)
    if vim.fn.has("nvim-0.10") ~= 1 then
        error("loop.nvim requires Neovim >= 0.10")
    end

    config.current = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
    setup_done = true

    M.init()
end

-----------------------------------------------------------
-- Command completion
-----------------------------------------------------------

function M.complete(arg_lead, cmd_line)
    M.init()

    local function filter(strs)
        local out = {}
        for _, s in ipairs(strs or {}) do
            if not vim.startswith(s, '_') and vim.startswith(s, arg_lead) then
                table.insert(out, s)
            end
        end
        return out
    end

    local args = strtools.split_shell_args(cmd_line)
    if cmd_line:match("%s+$") then
        table.insert(args, ' ')
    end

    if #args == 2 then
        local func_names = filter(vim.tbl_keys(_G.LoopWorkspace or {}))
        -- sort because tbl_keys order may change every time
        local cmds = vim.fn.sort(func_names)
        cmds = vim.list_extend(cmds, extensions.cmd_leads())
        return filter(cmds)
    elseif #args >= 3 then
        local cmd = args[2]
        local rest = { unpack(args, 3) }
        rest[#rest] = nil

        if cmd == "task" then
            return filter(workspace.task_subcommands(rest))
        elseif cmd == "workspace" then
            return filter(workspace.workspace_subcommands(rest))
        elseif cmd == "ui" then
            return filter(workspace.ui_subcommands(rest))
        elseif cmd == "page" then
            return filter(workspace.page_subcommands(rest))
        elseif cmd == "var" then
            return filter(workspace.var_subcommands(rest))
        else
            local cmd_provider = extensions.get_cmd_provider(cmd)
            if cmd_provider then
                return filter(cmd_provider.get_subcommands(rest))
            end
        end
    end

    return {}
end

function M.select_command()
    local task_types = require('loop.task.providers').names()

    ---@type loop.tools.Cmd[]
    local all_cmds = {
        { vimcmd = "Loop workspace info",      help = "Show information about the current workspace" },
        { vimcmd = "Loop workspace create",    help = "Create a new workspace in the current working directory" },
        { vimcmd = "Loop workspace open",      help = "Open a workspace or reload the current one" },
        { vimcmd = "Loop workspace save",      help = "Save workspace buffers (as defined in the workspace configuration)" },
        { vimcmd = "Loop workspace configure", help = "Create/Open the workspace configuration file" },
        { vimcmd = "Loop ui",                  help = "Toggle Loop window" },
        { vimcmd = "Loop ui show",             help = "Show Loop window" },
        { vimcmd = "Loop ui hide",             help = "Hide Loop window" },
        { vimcmd = "Loop page",                help = "Select the page shown in the Loop window" },
        { vimcmd = "Loop page open",           help = "Select and open a page in the current window" },
        { vimcmd = "Loop logs",                help = "Show recent logs" },
    }

    ------------------------------------------------------------------
    -- Task add subcommands
    ------------------------------------------------------------------
    for _, type in ipairs(task_types) do
        table.insert(all_cmds, {
            vimcmd = "Loop task add " .. type,
            help = "Create a new task of type " .. type,
        })
    end

    ------------------------------------------------------------------
    -- Other task subcommands (ordered)
    ------------------------------------------------------------------
    local other_task_cmds = {
        { "run",       "Run task" },
        { "repeat",    "Repeat last task" },
        { "terminate", "Terminate running tasks" },
    }

    for _, cmd in ipairs(other_task_cmds) do
        table.insert(all_cmds, {
            vimcmd = "Loop task " .. cmd[1],
            help = cmd[2],
        })
    end

    table.insert(all_cmds,
        { vimcmd = "Loop task configure", help = "Configure tasks or check the current configuration" })

    ------------------------------------------------------------------
    -- Var subcommands
    ------------------------------------------------------------------
    table.insert(all_cmds,
        { vimcmd = "Loop var add", help = "Create a new variable" })
    table.insert(all_cmds,
        { vimcmd = "Loop var configure", help = "Configure variables or check the current configuration" })

    require("loop.tools.cmdmenu").select_and_run_command(all_cmds)
end

-----------------------------------------------------------
-- Dispatcher
-----------------------------------------------------------

---@param opts vim.api.keyset.create_user_command.command_args
function M.dispatch(opts)
    M.init()

    local args = strtools.split_shell_args(opts.args)
    local subcmd = args[1]

    if not subcmd or subcmd == "" then
        M.select_command()
        return
    end

    local fn = _G.LoopWorkspace[subcmd]
    if not fn then
        local cmd_provider = extensions.get_cmd_provider(subcmd)
        if cmd_provider then
            local rest = { unpack(args, 2) }
            cmd_provider.dispatch(rest, opts)
            return            
        end
        vim.notify(
            "Invalid command: " .. subcmd,
            vim.log.levels.ERROR
        )
        return
    end

    local rest = { unpack(args, 2) }
    local ok, err = pcall(fn, unpack(rest))
    if not ok then
        vim.notify(
            "Loop " .. subcmd .. " failed: " .. tostring(err),
            vim.log.levels.ERROR
        )
    end
end

-----------------------------------------------------------
-- Initialization (runs once)
-----------------------------------------------------------

function M.init()
    if initialized then
        return
    end
    initialized = true

    -- Apply defaults if setup() was never called
    if not setup_done then
        config.current = DEFAULT_CONFIG
    end

    workspace.init()

    _G.LoopWorkspace = {
        _winbar_click = workspace.winbar_click,
        ui = workspace.ui_command,
        page = workspace.page_command,
        workspace = workspace.workspace_cmmand,
        task = workspace.task_command,
        var = workspace.var_command,
        logs = workspace.logs_command,
    }
end

function M.load_workspace(dir)
    M.init()
    workspace.open_workspace(dir, true)
end

return M
