local M = {}

local filetools = require("loop.tools.file")

---@return number window number
local function find_regular_window()
    -- Get current tabpage and all its windows
    local tabpage = vim.api.nvim_get_current_tabpage()
    local windows = vim.api.nvim_tabpage_list_wins(tabpage)
    -- Helper: check if a buffer is "regular" (listed, not special, etc.)
    local function is_regular_buffer(bufnr)
        if not vim.api.nvim_buf_is_valid(bufnr) then
            return false
        end
        local buftype = vim.bo[bufnr].buftype
        local buflisted = vim.bo[bufnr].buflisted

        -- Exclude special buffer types
        if buftype ~= '' or not buflisted then
            return false
        end
        return true
    end

    -- Search through all windows in current tab
    for _, winid in ipairs(windows) do
        if vim.api.nvim_win_is_valid(winid) then
            local bufnr = vim.api.nvim_win_get_buf(winid)
            if is_regular_buffer(bufnr) then
                return winid
            end
        end
    end
    -- If no regular window found, create a horizontal split
    vim.cmd('split')
    local new_win = vim.api.nvim_get_current_win()
    local new_buf = vim.api.nvim_win_get_buf(new_win)

    -- Ensure the new buffer is regular (it should be by default)
    -- But just in case, create an empty buffer if needed
    if not is_regular_buffer(new_buf) then
        local buf = vim.api.nvim_create_buf(true, false) -- listed, not scratch
        vim.api.nvim_win_set_buf(new_win, buf)
    end

    return new_win
end

---@param filepath string
---@return number winid
---@return number bufnr
---@param line? integer 1‑based line number (nil = just open)
function M.smart_open_file(filepath, line)
    local function set_line(winid, bufnr)
        if line and type(line) == 'number' and line > 0 then
            -- Clamp to valid range
            local maxline = vim.api.nvim_buf_line_count(bufnr)
            line = math.min(line, maxline)
            vim.api.nvim_win_set_cursor(winid, { line, 0 })
        end
    end
    -- Normalize filepath to handle relative paths
    local full_path = vim.fn.fnamemodify(filepath, ':p')
    -- Check all windows for the file
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local bufnr = vim.api.nvim_win_get_buf(winid)
        local buf_path = vim.api.nvim_buf_get_name(bufnr)
        if buf_path == full_path and vim.api.nvim_win_is_valid(winid) then
            -- Activate the window with the file
            vim.api.nvim_set_current_win(winid)
            set_line(winid, bufnr)
            return winid, bufnr
        end
    end

    local winid = find_regular_window()

    vim.api.nvim_set_current_win(winid)
    local bufnr = vim.fn.bufadd(full_path)
    if vim.fn.bufloaded(bufnr) == 0 then
        vim.fn.bufload(bufnr)
    end
    vim.bo[bufnr].buflisted = true
    vim.api.nvim_win_set_buf(winid, bufnr)

    return winid, bufnr
end

---@param filepath  string
---@return boolean success
---@return string content or error
function M.smart_read_file(filepath)
    local full_path = vim.fn.fnamemodify(filepath, ":p")
    local bufnr = vim.fn.bufnr(full_path, false) -- false = don't create

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
    local winid = find_regular_window()
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

---@param msg string
---@param default_yes boolean
---@param callback fun(yes: boolean|nil)
function M.confirm_action(msg, default_yes, callback)
    local choices = "&Yes\n&No"
    local default = default_yes and 1 or 2

    vim.schedule(function()
        local choice = vim.fn.confirm(msg, choices, default)
        if choice == 1 then
            callback(true)
        elseif choice == 2 then
            callback(false)
        else
            callback(nil)
        end
    end)
end

return M
