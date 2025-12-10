local M             = {}

local notifications = require('loop.notifications')

local original_cursorline
local original_hl

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

local DEBUG_HL = 'LoopPluginDebugModeLine'

local function setup_debug_highlight()
  -- Get the current highlight of CursorLine
  local cursorline = vim.api.nvim_get_hl(0, { name = 'CursorLine' })
  local bg = cursorline.bg or (vim.o.background == 'dark' and 0x444c5e or 0xe6d080)

  -- Set the debug highlight
  vim.api.nvim_set_hl(0, DEBUG_HL, {
    bg = bg,         -- background for debug line
    fg = nil,        -- nil to inherit from Normal
    bold = true,     -- optional emphasis
    underline = true -- underline to make it stand out
  })
end

setup_debug_highlight()

function M.enable_debug_mode()
    if vim.g.debug_mode_active then
        notifications.notify("Debug mode already active", vim.log.levels.WARN)
        return
    end

    -- Save original cursorline + highlight
    original_cursorline = vim.o.cursorline
    original_hl         = vim.api.nvim_get_hl(0, { name = 'CursorLine' })

    -- === 2. Force cursorline ON and hijack the highlight ===
    vim.o.cursorline    = true
    vim.o.cursorlineopt = 'both' -- or 'line' if you don't use cursorlinenr
    vim.api.nvim_set_hl(0, 'CursorLine', { link = DEBUG_HL })

    -- Save original global mappings
    local prev = {}
    local movement_keys = {
        'h', 'j', 'k', 'l',                    -- basic
        '0', '^', '$', 'gg', 'G',              -- line start/end
        '<C-u>', '<C-d>', '<C-f>', '<C-b>',    -- page
        '{', '}', '(', ')',                    -- paragraph/section
        '-', '+', '_',                         -- line up/down
        'gk', 'gj',                            -- screen lines
        '<Up>', '<Down>', '<Left>', '<Right>', -- arrows
        '<PageUp>', '<PageDown>',
        '<Home>', '<End>',
    }

    for _, key in ipairs(movement_keys) do
        for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
            if map.lhs == key and not map.buffer then
                prev[key] = map
                break
            end
        end
    end

    vim.g.debug_mode_active = true
    vim.g.debug_mode_maps = prev

    -- GLOBAL DUMMY + DEBUG KEYMAPS (override EVERYTHING)
    local opts = { nowait = true, noremap = true, silent = true }

    -- Your real debug commands
    vim.keymap.set('n', 'h', function() _debug_command('step_out') end, opts)
    vim.keymap.set('n', 'j', function() _debug_command('step_over') end, opts)
    vim.keymap.set('n', 'l', function() _debug_command('step_in') end, opts)
    vim.keymap.set('n', '<Esc>', M.disable_debug_mode, opts)

    -- BLOCK ALL OTHER MOVEMENT (dummy no-op)
    local no_op = function() end
    for _, key in ipairs(movement_keys) do
        if not vim.tbl_contains({ 'h', 'j', 'l', '<Esc>' }, key) then
            vim.keymap.set('n', key, no_op, opts) -- ← does nothing
        end
    end

    -- Optional: also block in visual/select mode if you want
    -- for _, key in ipairs(movement_keys) do
    --   vim.keymap.set('v', key, '<Nop>', opts)
    --   vim.keymap.set('s', key, '<Nop>', opts)
    -- end

    notifications.notify(
        "Debug mode on → cursor frozen | h=out  j=over  l=in  Esc=quit",
        vim.log.levels.INFO
    )
end

function M.disable_debug_mode()
    if not vim.g.debug_mode_active then return end

    -- Restore cursorline
    vim.o.cursorline = original_cursorline
    vim.api.nvim_set_hl(0, 'CursorLine', original_hl or {})

    -- Remove ALL our dummy + debug mappings
    local all_keys = { 'h', 'j', 'k', 'l', '<Esc>', '0', '^', '$', 'gg', 'G', '<C-u>', '<C-d>', '<C-f>', '<C-b>', '{',
        '}', '(', ')', '-', '+', '_', 'gk', 'gj', '<Up>', '<Down>', '<Left>', '<Right>', '<PageUp>', '<PageDown>',
        '<Home>', '<End>' }
    for _, k in ipairs(all_keys) do
        pcall(vim.api.nvim_del_keymap, 'n', k)
    end

    -- Restore original user mappings
    if vim.g.debug_mode_maps then
        for lhs, old in pairs(vim.g.debug_mode_maps) do
            local rhs = old.callback or old.rhs or ''
            local opt = { noremap = old.noremap == 1, silent = old.silent == 1, nowait = old.nowait == 1 }
            if type(rhs) == 'function' then
                vim.keymap.set('n', lhs, rhs, opt)
            elseif rhs ~= '' then
                vim.api.nvim_set_keymap('n', lhs, rhs, opt)
            end
        end
    end

    -- Cleanup
    vim.g.debug_mode_active = nil
    vim.g.debug_mode_maps = nil
    original_cursorline = nil
    original_hl = nil

    notifications.notify("Debug mode OFF", vim.log.levels.INFO)
end

function M.toggle_debug_mode()
    if vim.g.debug_mode_active then
        M.disable_debug_mode()
    else
        M.enable_debug_mode()
    end
end

return M
