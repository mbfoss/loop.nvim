local M = {}
local notifications = require('loop.notifications')

---@type fun(cmd: loop.job.DebugJob.Command)|nil
M.command_function = nil

local loop_debug_active

local saved = {
    cursorline    = nil,
    cursorlineopt = nil,
    cursorline_hl = nil,
    original_maps = nil, -- only h/j/k/l
}

local DEBUG_KEYS = { "h", "j", "k", "l", "c", 'C', 't', 'T' }

local function debug_cmd(cmd)
    if not M.command_function then
        notifications.notify("No active debug session", vim.log.levels.WARN)
        return
    end
    M.command_function(cmd)
end

-- -------------------------------------------------------------------
-- ENABLE
-- -------------------------------------------------------------------
function M.enable_debug_mode()
    if loop_debug_active then
        notifications.notify("Debug mode already active", vim.log.levels.WARN)
        return
    end

    vim.cmd.stopinsert()

    -- Save existing mappings
    saved.original_maps = {}
    for _, key in ipairs(DEBUG_KEYS) do
        local map = vim.fn.maparg(key, "n", false, true)
        if map and (map.rhs ~= "" or map.callback) then
            saved.original_maps[key] = map
        end
    end

    local opts = { noremap = true, silent = true }

    -- Override hjkl
    vim.keymap.set("n", "h", function() debug_cmd("step_out") end, opts)
    vim.keymap.set("n", "j", function() debug_cmd("step_over") end, opts)
    vim.keymap.set("n", "k", function() debug_cmd("step_back") end, opts)
    vim.keymap.set("n", "l", function() debug_cmd("step_in") end, opts)
    vim.keymap.set("n", "c", function() debug_cmd("continue") end, opts)
    vim.keymap.set("n", "C", function() debug_cmd("continue_all") end, opts)
    vim.keymap.set("n", "t", function() debug_cmd("terminate") end, opts)
    vim.keymap.set("n", "T", function() debug_cmd("terminate_all") end, opts)

    -- <Esc> to exit (in all modes)
    vim.keymap.set({ "n", "i", "v", "x", "s", "o" }, "<Esc>", function()
        M.disable_debug_mode()
    end, opts)

    loop_debug_active = true

    notifications.notify(
        "DEBUG MODE ON → h=out  j=over  k=continue  l=in  Esc=quit",
        vim.log.levels.WARN
    )
end

-- -------------------------------------------------------------------
-- DISABLE
-- -------------------------------------------------------------------
function M.disable_debug_mode()
    if not loop_debug_active then return end

    -- Remove our mappings
    for _, key in ipairs(DEBUG_KEYS) do
        pcall(vim.keymap.del, "n", key)
    end
    pcall(vim.keymap.del, { "n", "i", "v", "x", "s", "o" }, "<Esc>")

    -- Restore previous hjkl mappings
    for key, map in pairs(saved.original_maps or {}) do
        local o = {
            noremap = map.noremap == 1,
            silent  = map.silent == 1,
            nowait  = map.nowait == 1,
            expr    = map.expr == 1,
        }
        if map.callback then
            vim.keymap.set("n", key, map.callback, o)
        elseif map.rhs and map.rhs ~= "" then
            vim.api.nvim_set_keymap("n", key, map.rhs, o)
        end
    end
    saved.original_maps = nil
    loop_debug_active = nil
    notifications.notify("Debug mode OFF", vim.log.levels.INFO)
end

-- -------------------------------------------------------------------
-- Toggle
-- -------------------------------------------------------------------
function M.toggle_debug_mode()
    if loop_debug_active then
        M.disable_debug_mode()
    else
        M.enable_debug_mode()
    end
end

return M
