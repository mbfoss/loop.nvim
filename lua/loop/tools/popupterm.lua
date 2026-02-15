local M = {}

---@param args loop.tools.TermProc.StartArgs
function M.run(args, opts)
    local TermProc = require('loop.tools.TermProc')

    opts = opts or {}

    local width = opts.width or math.floor(vim.o.columns * 0.8)
    local height = opts.height or math.floor(vim.o.lines * 0.8)

    local row = math.floor((vim.o.lines - height) / 2 - 1)
    local col = math.floor((vim.o.columns - width) / 2)

    -- create scratch buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'delete'

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        style = "minimal",
        border = opts.border or "rounded",
        width = width,
        height = height,
        row = row,
        col = col,
    })

    local proc, proc_ok, proc_err
    vim.api.nvim_buf_call(buf, function()
        proc = TermProc:new()
        proc_ok, proc_err = proc:start(args)
    end)

    vim.keymap.set('t', '<Esc>', function() vim.cmd('stopinsert') end, { buffer = buf })

    -- allow closing with 'q'
    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true })

    if not proc_ok then
        return nil, proc_err
    end

    return proc, nil
end

return M
