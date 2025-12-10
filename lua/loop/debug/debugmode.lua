local M = {}
local notifications = require('loop.notifications')

---@type fun(cmd: loop.job.DebugJob.Command)|nil
M.command_function = nil

local DEBUG_HL = 'LoopPluginDebugModeLine'

-- ===================================================================
-- Highlight setup
-- ===================================================================
local function setup_debug_highlight()
    local hl = vim.api.nvim_get_hl(0, { name = 'CursorLine', link = false })
    local bg = hl.bg or (vim.o.background == 'dark' and 0x444c5e or 0xe6d080)
    vim.api.nvim_set_hl(0, DEBUG_HL, { bg = bg, bold = true, underline = true })
end
setup_debug_highlight()

-- ===================================================================
-- Debug command wrapper
-- ===================================================================
local function debug_cmd(cmd)
    if not M.command_function then
        notifications.notify("No active debug session", vim.log.levels.WARN)
        return
    end
    M.command_function(cmd)
end

-- ===================================================================
-- Saved state
-- ===================================================================
local saved = {
    cursorline    = nil,
    cursorlineopt = nil,
    cursorline_hl = nil,
    original_maps = nil,  -- only h/j/k/l
}

-- ===================================================================
-- Keys that can EVER modify the buffer → completely blocked
-- ===================================================================
local BLOCKED_KEYS = {
    -- Editing / deletion / change
    'c', 'cc', 'C', 's', 'S', 'd', 'dd', 'D', 'x', 'X',
    'y', 'yy', 'Y', 'p', 'P', 'r', 'R',
    '>', '>>', '<', '<<', '=', '==',
    '~', 'g~', 'gu', 'gU', '!', 'gq', 'gw',

    -- Undo / redo (they change the buffer!)
    'u', '<C-r>',

    -- Mode changes
    'i', 'I', 'a', 'A', 'o', 'O',
    'v', 'V', '<C-v>', 'gv', 'gi',

    -- Dangerous commands
    ':', 'q', 'Q', 'ZZ', 'ZQ', '<Insert>',
}

local DEBUG_CONTROL_KEYS = { 'h', 'j', 'k', 'l' }

-- ===================================================================
-- ENABLE DEBUG MODE – iron-clad protection
-- ===================================================================
function M.enable_debug_mode()
    if vim.g.loop_debug_active then
        notifications.notify("Debug mode already active", vim.log.levels.WARN)
        return
    end

    -- Save visual state
    saved.cursorline    = vim.o.cursorline
    saved.cursorlineopt = vim.o.cursorlineopt
    saved.cursorline_hl = vim.api.nvim_get_hl(0, { name = 'CursorLine' })

    vim.o.cursorline    = true
    vim.o.cursorlineopt = 'both'
    vim.api.nvim_set_hl(0, 'CursorLine', { link = DEBUG_HL })
    vim.cmd.stopinsert()

    local opts = { noremap = true, silent = true, nowait = true }
    local noop = function() end

    -- Save original h/j/k/l mappings (so gj/gk etc. survive)
    saved.original_maps = {}
    for _, key in ipairs(DEBUG_CONTROL_KEYS) do
        local map = vim.fn.maparg(key, 'n', false, true)
        if map and (map.rhs ~= "" or map.callback) then
            saved.original_maps[key] = map
        end
    end

    -- Block EVERY key that could modify the buffer
    for _, key in ipairs(BLOCKED_KEYS) do
        vim.keymap.set('n', key, noop, opts)
    end

    -- Block entering insert/visual from ANY mode (including operator-pending)
    local mode_entry = { 'i', 'I', 'a', 'A', 'o', 'O', 'v', 'V', '<C-v>' }
    for _, key in ipairs(mode_entry) do
        vim.keymap.set({ 'n', 'v', 'x', 's', 'o' }, key, noop, opts)
    end

    -- NO insert-mode input blocking → if someone does `lua vim.cmd('startinsert')`, they can type
    -- (this is what you explicitly asked for)

    -- Debug navigation
    vim.keymap.set('n', 'h', function() debug_cmd('step_out') end, opts)
    vim.keymap.set('n', 'j', function() debug_cmd('step_over') end, opts)
    vim.keymap.set('n', 'k', function() debug_cmd('continue') end, opts)
    vim.keymap.set('n', 'l', function() debug_cmd('step_in') end, opts)

    -- Esc exits debug mode from anywhere
    vim.keymap.set({ 'n', 'i', 'v', 'x', 's', 'o' }, '<Esc>', function()
        M.disable_debug_mode()
    end, opts)

    vim.g.loop_debug_active = true
    notifications.notify("DEBUG MODE ON → h=out  j=over  k=continue  l=in  Esc=quit", vim.log.levels.WARN)
end

-- ===================================================================
-- DISABLE DEBUG MODE – perfect cleanup
-- ===================================================================
function M.disable_debug_mode()
    if not vim.g.loop_debug_active then return end

    local del_opts = { silent = true }

    -- Remove all blocked keys
    for _, key in ipairs(BLOCKED_KEYS) do
        pcall(vim.keymap.del, 'n', key, del_opts)
    end

    -- Remove mode-entry blocks
    local mode_entry = { 'i', 'I', 'a', 'A', 'o', 'O', 'v', 'V', '<C-v>' }
    for _, key in ipairs(mode_entry) do
        pcall(vim.keymap.del, { 'n', 'v', 'x', 's', 'o' }, key, del_opts)
    end

    -- Remove debug controls
    for _, key in ipairs(DEBUG_CONTROL_KEYS) do
        pcall(vim.keymap.del, 'n', key, del_opts)
    end
    pcall(vim.keymap.del, { 'n', 'i', 'v', 'x', 's', 'o' }, '<Esc>', del_opts)

    -- Restore original h/j/k/l mappings
    for key, map in pairs(saved.original_maps or {}) do
        local o = {
            noremap = map.noremap == 1,
            silent  = map.silent == 1,
            nowait  = map.nowait == 1,
            expr    = map.expr == 1,
        }
        if map.callback then
            vim.keymap.set('n', key, map.callback, o)
        elseif map.rhs and map.rhs ~= "" then
            vim.api.nvim_set_keymap('n', key, map.rhs, o)
        end
    end
    saved.original_maps = nil

    -- Restore visuals exactly
    vim.o.cursorline    = saved.cursorline or false
    vim.o.cursorlineopt = saved.cursorlineopt or 'both'
    if saved.cursorline_hl then
        ---@diagnostic disable-next-line: param-type-mismatch
        vim.api.nvim_set_hl(0, 'CursorLine', saved.cursorline_hl)
    end

    vim.g.loop_debug_active = nil
    notifications.notify("Debug mode OFF", vim.log.levels.INFO)
end

-- ===================================================================
-- Toggle
-- ===================================================================
function M.toggle_debug_mode()
    if vim.g.loop_debug_active then
        M.disable_debug_mode()
    else
        M.enable_debug_mode()
    end
end

return M
