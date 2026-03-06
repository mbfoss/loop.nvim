-- IMPORTANT: keep this module light for lazy loading

if vim.fn.has("nvim-0.10") ~= 1 then
    error("loop.nvim requires Neovim >= 0.10")
end

vim.api.nvim_create_user_command("Loop", function(opts)
        require("loop.commands").dispatch(opts)
    end,
    {
        nargs = "*",
        complete = function(arg_lead, cmd_line, _)
            return require("loop.commands").complete(arg_lead, cmd_line)
        end,
        desc = "Loop.nvim management commands",
    })

local function _is_workspace_dir(dir)
    local loopconfig = require('loop').config
    local data_dir = loopconfig.workspace_data_dir
    if type(data_dir) ~= "string" then return false end
    local config_dir = vim.fs.joinpath(dir, data_dir)
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.loop.fs_stat(config_dir)
    return stat and stat.type == "directory"
end

local group = vim.api.nvim_create_augroup("LoopPluginOnVimEnter", { clear = true })
vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
        local args = vim.fn.argv()
        if #args == 0 then
            local dir = vim.fn.getcwd()
            -- don't load modules if the current dir is not a workspace directory
            if _is_workspace_dir(dir) then
                require("loop.workspace").open_workspace(dir, true)
            end
        end
    end
})
