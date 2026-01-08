local M = {}

local filetools = require('loop.tools.file')
local uitools = require('loop.tools.uitools')

---@alias loop.ws.IsolationFlags {shada:boolean, undo:boolean}

local function ensure_dir(path)
    if vim.fn.isdirectory(path) == 0 then
        vim.fn.mkdir(path, "p")
    end
end

local function _refresh_buffers()
    -- === Refresh buffers ===
    -- This ensures buffers pick up the new undo/shada context
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if uitools.is_regular_buffer(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
            if not vim.bo[bufnr].modified then
                vim.api.nvim_buf_call(bufnr, function()
                    vim.cmd("silent! edit")
                end)
            end
        end
    end
end

---@param config_dir string
---@param flags loop.ws.IsolationFlags
function M.open(config_dir, flags)
    if not (flags.shada or flags.undo) then
        return
    end
    ensure_dir(config_dir)
    -- === ShaDa Support ===
    if flags.shada then
        -- Disable ShaDa temporarily to "disconnect" from Global
        vim.opt.shadafile = "NONE"
        -- Purge internal memory
        -- This ensures Global data doesn't leak into the next step
        vim.fn.histdel(':') -- Clear command history
        vim.fn.histdel('/') -- Clear search history
        vim.fn.histdel('@') -- Clear input history
        local regs = 'abcdefghijklmnopqrstuvwxyz0123456789"*-+'
        for i = 1, #regs do
            local r = regs:sub(i, i)
            vim.fn.setreg(r, {})
        end
        -- Clear uppercase Global Marks (A-Z)
        for i = 65, 90 do
            local mark = string.char(i)
            vim.cmd('delmarks ' .. mark)
        end
        -- Clear numbered marks (0-9) - these are usually 'last exit' positions
        for i = 0, 9 do
            vim.cmd('delmarks ' .. i)
        end
        -- load project shada
        local shada_path = vim.fs.joinpath(config_dir, "main.shada")
        vim.o.shadafile = shada_path
        if not filetools.file_exists(shada_path) then
            filetools.write_content(shada_path, "")
        end
        vim.cmd("rshada!")
    end

    -- === Undo Support ===
    if flags.undo then
        local undo_dir = vim.fs.joinpath(config_dir, "undo")
        ensure_dir(undo_dir)

        vim.opt.undodir = undo_dir
        vim.opt.undofile = true
    end

    if flags.shada or flags.undo then
        _refresh_buffers()
    end
end

return M
