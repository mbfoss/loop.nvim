local M = {}

-- Dependencies
local workspace = require("loop.workspace")
local strtools = require('loop.tools.strtools')

function M.complete(arg_lead, cmd_line)
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
        return filter(workspace.get_commands())
    elseif #args >= 3 then
        local cmd = args[2]
        local rest = { unpack(args, 3) }
        rest[#rest] = nil
            return filter(workspace.get_subcommands(cmd, rest))
    end
    return {}
end
---@param prefix string[]   -- e.g. { "task" }
---@param out loop.tools.Cmd[]
local function _collect_commands(prefix, out)
    local cmds = workspace.get_subcommands(prefix[1], { unpack(prefix, 2) })

    for _, cmd in ipairs(cmds or {}) do
        local parts = vim.list_extend(vim.deepcopy(prefix), { cmd })
        local vimcmd = "Loop " .. table.concat(parts, " ")

        table.insert(out, {
            vimcmd = vimcmd,
        })

        -- recurse to catch deeper subcommands
        _collect_commands(parts, out)
    end
end

function M.select_command()
    ---@type loop.tools.Cmd[]
    local all_cmds = {}

    -- Top-level commands
    for _, cmd in ipairs(workspace.get_commands()) do
        local vimcmd = "Loop " .. cmd

        table.insert(all_cmds, {
            vimcmd = vimcmd,
        })

        -- Subcommands (recursive)
        _collect_commands({ cmd }, all_cmds)
    end

    require("loop.tools.cmdmenu").select_and_run_command(all_cmds)
end

-----------------------------------------------------------
-- Dispatcher
-----------------------------------------------------------

---@param opts vim.api.keyset.create_user_command.command_args
function M.dispatch(opts)

    local args = strtools.split_shell_args(opts.args)
    local subcmd = args[1]

    if not subcmd or subcmd == "" then
        M.select_command()
        return
    end
    local rest = { unpack(args, 2) }
    local ok, err = pcall(workspace.run_command, subcmd, rest, opts)
    if not ok then
        vim.notify(
            "Loop " .. subcmd .. " failed: " .. tostring(err),
            vim.log.levels.ERROR
        )
    end
end

return M
