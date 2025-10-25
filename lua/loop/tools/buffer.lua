local M = {}

local filetools = require("loop.tools.file")

---@return number window number
function M.find_or_make_empty_window()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local bufnr = vim.api.nvim_win_get_buf(winid)
        if vim.api.nvim_buf_is_loaded(bufnr)
            and vim.bo[bufnr].buflisted
            and vim.bo[bufnr].buftype == '' -- skip special buffers
            and vim.api.nvim_buf_line_count(bufnr) == 1
            and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == ''
            and not vim.bo[bufnr].modified
        then
            return winid
        end
    end
    vim.cmd("split")
    return vim.api.nvim_get_current_win()
end

---@param filepath string
---@return number winid
---@return number bufnr
function M.smart_open_file(filepath)
    -- Normalize filepath to handle relative paths
    local full_path = vim.fn.fnamemodify(filepath, ':p')
    -- Check all windows for the file
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local bufnr = vim.api.nvim_win_get_buf(winid)
        local buf_path = vim.api.nvim_buf_get_name(bufnr)
        if buf_path == full_path and vim.api.nvim_win_is_valid(winid) then
            -- Activate the window with the file
            vim.api.nvim_set_current_win(winid)
            return winid, bufnr
        end
    end
    -- File not found in any window, use find_or_make_empty_window
    local winid = M.find_or_make_empty_window()
    vim.api.nvim_set_current_win(winid)
    local bufnr = vim.fn.bufnr(full_path, true) -- get or create buffer
    vim.api.nvim_win_set_buf(winid, bufnr)
    return winid, bufnr
end

---@param filepath  string
---@return boolean success
---@return string content or error
function M.smart_read_file(filepath)
    local full_path = vim.fn.fnamemodify(filepath, ":p")
    local bufnr = vim.fn.bufnr(full_path, false)  -- false = don't create

    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        return true, vim.fn.join(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    end
    return filetools.read_content(full_path)
end

---@param bufnr number
---@return number winid
function M.smart_open_buffer(bufnr) 
    -- Check if the buffer is already displayed in any visible window
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
            -- Buffer is already visible, just return this window
            vim.api.nvim_set_current_win(winid)
            return winid
        end
    end
    -- Buffer not visible in any window, find or create an empty window
    local winid = M.find_or_make_empty_window()
    vim.api.nvim_set_current_win(winid)
    vim.api.nvim_win_set_buf(winid, bufnr)
    return winid
end


---@text string
function M.move_to_first_occurence(text)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local word = '"name": "'
    local line = vim.fn.search(text)
    if line > 0 then
        -- Move cursor to the **end of the word** (0-indexed)
        local line_text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
        local s, e = line_text:find(word, 1, true) -- get start and end column
        if s and e then
            vim.api.nvim_win_set_cursor(0, { line, e })
        end
    end
end

---@text string
function M.move_to_last_occurence(text)
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
    local word = '"name": "'
    local line = vim.fn.search(word, 'bW') -- 'b' = backwards, 'W' = whole word
    if line > 0 then
        -- Move cursor to the **end of the word** (0-indexed)
        local line_text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
        local s, e = line_text:find(word, 1, true) -- get start and end column
        if s and e then
            vim.api.nvim_win_set_cursor(0, { line, e })
        end
    end
end

function M.disable_insert_mappings(buf)
    -- === 1. Disable direct insert-mode entry keys ===
    local insert_keys = {
        'i', 'a', 'o', 'I', 'A', 'O',
        'c', 'cc', 'C', 's', 'S', 'R', 'gi', 'gI', '.'
    }

    for _, key in ipairs(insert_keys) do
        vim.api.nvim_buf_set_keymap(buf, 'n', key, '<Nop>', { noremap = true, silent = true })
    end

    -- Visual mode: disable change/delete that enter insert
    local visual_keys = { 'c', 's', 'C', 'S', 'R' }
    for _, key in ipairs(visual_keys) do
        vim.api.nvim_buf_set_keymap(buf, 'v', key, '<Nop>', { noremap = true, silent = true })
    end
end

return M
