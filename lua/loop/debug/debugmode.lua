local M             = {}

local notifications = require('loop.notifications')

---@type fun(cmd:loop.job.DebugJob.Command)|nil
M.command_function  = nil

---@param command loop.job.DebugJob.Command
local function _debug_command(command)
    if not M.command_function then
        notifications.notify("No active debug task", vim.log.levels.WARN)
        return
    end
    if not command then
        notifications.notify("Debug command missing", vim.log.levels.WARN)
        return
    end
    M.command_function(command)
end

local DEBUG_HL = 'DebugCurrentLine'

-- Define the debug highlight once (strong and visible)
vim.api.nvim_set_hl(0, DEBUG_HL, {
    bg = '#2e2e2e',
    fg = '#ffffff',
    bold = true,
    underline = true, -- optional extra pop
})

-- Saved original state (filled on enable, used on disable)
local original = nil

function M.enable_debug_mode()
    if vim.g.debug_mode_active then
        vim.notify("Debug mode already active", vim.log.levels.WARN)
        return
    end

    -- === 1. Save everything the user had ===
    original = {
        cursorline    = vim.opt_global.cursorline,
        cursorlineopt = vim.opt_global.cursorlineopt,
        cursorline_hl = vim.api.nvim_get_hl(0, { name = 'CursorLine' }),
    }

    -- === 2. Force cursorline ON and hijack the highlight ===
    vim.opt_global.cursorline = true
    vim.opt_global.cursorlineopt = 'both' -- or 'line' if you don't use cursorlinenr
    vim.api.nvim_set_hl(0, 'CursorLine', { link = DEBUG_HL })

    -- === 3. Save + override global keymaps ===
    local prev_maps = {}
    local keys = { 'h', 'j', 'l', '<Esc>' }

    for _, key in ipairs(keys) do
        for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
            if map.lhs == key and not map.buffer then
                prev_maps[key] = map
                break
            end
        end
    end

    vim.g.debug_mode_active = true
    vim.g.debug_mode_prev_maps = prev_maps

    -- === 4. Set global debug keys ===
    local opts = { nowait = true, noremap = true, silent = true }
    vim.keymap.set('n', 'h', function() _debug_command('step_out') end, opts)
    vim.keymap.set('n', 'j', function() _debug_command('step_over') end, opts)
    vim.keymap.set('n', 'l', function() _debug_command('step_in') end, opts)
    vim.keymap.set('n', '<Esc>', M.disable_debug_mode, opts)

    vim.notify("Debug mode ON → h=out  j=over  l=in  Esc=quit", vim.log.levels.INFO)
end

function M.disable_debug_mode()
    if not vim.g.debug_mode_active then return end

    -- === Restore cursorline appearance ===
    if original then
        vim.opt_global.cursorline = original.cursorline
        vim.opt_global.cursorlineopt = original.cursorlineopt

        -- Restore exact original CursorLine highlight (even if it was empty)
        vim.api.nvim_set_hl(0, 'CursorLine', original.cursorline_hl or {})
    end

    -- === Remove our debug keymaps ===
    for _, key in ipairs({ 'h', 'j', 'k', 'l', '<Esc>' }) do
        pcall(vim.api.nvim_del_keymap, 'n', key)
    end

    -- === Restore previous global mappings ===
    if vim.g.debug_mode_prev_maps then
        for lhs, old in pairs(vim.g.debug_mode_prev_maps) do
            local rhs = old.callback or old.rhs or ''
            local opts = {
                noremap = old.noremap == 1,
                silent  = old.silent == 1,
                nowait  = old.nowait == 1,
            }
            if type(rhs) == 'function' then
                vim.keymap.set('n', lhs, rhs, opts)
            elseif rhs ~= '' then
                vim.api.nvim_set_keymap('n', lhs, rhs, opts)
            end
        end
    end

    -- === Cleanup ===
    vim.g.debug_mode_active = nil
    vim.g.debug_mode_prev_maps = nil
    original = nil

    vim.notify("Debug mode OFF – all settings restored", vim.log.levels.INFO)
end

function M.toggle_debug_mode()
    if vim.g.debug_mode_active then
        M.disable_debug_mode()
    else
        M.enable_debug_mode()
    end
end

return M
