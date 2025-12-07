---@class loop.SelectorItem
---@field label string
---@field data any
---@alias loop.SelectorCallback fun(data: any|nil)
local M = {}

-- One single namespace for the whole module
local _ns_prompt = vim.api.nvim_create_namespace("LoopPluginItemSelectPrompt")

local function fuzzy_filter(items, query)
    if query == "" then return vim.deepcopy(items) end
    local q = query:lower()
    local res = {}
    for _, item in ipairs(items) do
        if item.label:lower():find(q, 1, true) then table.insert(res, item) end
    end
    return res
end

local function _update_prompt(prompt_prefix, query, pbuf, pwin)
    local full_text = prompt_prefix .. query
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, { full_text })

    -- Clear previous highlights/extmarks in this namespace
    pcall(vim.api.nvim_buf_clear_namespace, pbuf, _ns_prompt, 0, -1)

    -- Apply the new highlight via extmark (non-deprecated)
    vim.api.nvim_buf_set_extmark(pbuf, _ns_prompt, 0, 0, {
        end_col = #prompt_prefix,
        hl_group = "Title",
    })

    -- Force cursor position *after* the text is set
    vim.schedule(function()
        pcall(vim.api.nvim_win_set_cursor, pwin, { 1, #full_text })
    end)
end

local function _update_list(filtered, cur, lbuf, lwin)
    local lines = {}
    for i, item in ipairs(filtered) do
        lines[i] = (i == cur and "> " or "  ") .. tostring(item.label)
    end
    vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, lines)
    pcall(vim.api.nvim_win_set_cursor, lwin, { cur, 0 })
end

local function _update_preview(has_preview, formatter, filtered, cur, vbuf)
    if not has_preview then return end
    local item = filtered[cur]
    if not item then
        vim.api.nvim_buf_set_lines(vbuf, 0, -1, false, { "" })
        return
    end
    local ok, txt = pcall(formatter, item.data)
    vim.api.nvim_buf_set_lines(vbuf, 0, -1, false, vim.split(ok and txt or "<error>", "\n"))
end

local function _redraw(items, query, filtered, cur)
    filtered = fuzzy_filter(items, query)
    cur = #filtered > 0 and math.min(cur, #filtered) or 1
    return filtered, cur
end

local function _close(callback, callback_called, res, pwin, lwin, vwin)
    if not callback_called then
        callback_called = true
        vim.schedule(function()
            callback(res)
        end)
    end
    for _, w in ipairs({ pwin, lwin, vwin }) do
        if w and vim.api.nvim_win_is_valid(w) then
            pcall(vim.api.nvim_win_close, w, true)
        end
    end
    vim.cmd("stopinsert")
    return callback_called
end

local function _move(filtered, cur, d)
    if #filtered == 0 then return cur end
    cur = (cur - 1 + d) % #filtered + 1
    return cur
end

---@param prompt string The prompt/title to display
---@param items loop.SelectorItem[] List of items with label and data table
---@param formatter (fun(data:any):string)|nil Convert the data into text for display in the preview
---@param callback loop.SelectorCallback
function M.select(prompt, items, formatter, callback)
    if #items == 0 then return callback(nil) end
    local callback_called = false
    local has_preview = type(formatter) == "function"
    formatter = formatter or function(v) return type(v) == "table" and vim.inspect(v) or tostring(v) end
    local width = math.floor(vim.o.columns * (has_preview and 0.8 or 0.5))
    local height = math.floor(vim.o.lines * 0.8)
    local list_w = has_preview and math.floor(width * 0.5) or width
    local prev_w = has_preview and (width - list_w) or 0
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    local query = ""
    local filtered = vim.deepcopy(items)
    local cur = 1
    local pbuf = vim.api.nvim_create_buf(false, true)
    local lbuf = vim.api.nvim_create_buf(false, true)
    local vbuf = has_preview and vim.api.nvim_create_buf(false, true) or nil
    local pwin = vim.api.nvim_open_win(pbuf, true, {
        relative = "editor",
        style = "minimal",
        border = "rounded",
        width = width,
        height = 1,
        row = row - 2,
        col = col,
    })
    local lwin = vim.api.nvim_open_win(lbuf, false, {
        relative = "editor",
        style = "minimal",
        border = "rounded",
        width = list_w,
        height = height,
        row = row,
        col = col,
    })
    local vwin = vbuf and vim.api.nvim_open_win(vbuf, false, {
        relative = "editor",
        style = "minimal",
        border = "rounded",
        width = prev_w,
        height = height,
        row = row,
        col = col + list_w,
    }) or nil
    vim.bo[lbuf].filetype = ""
    if has_preview then vim.bo[vbuf].filetype = "json" end
    local prompt_prefix = prompt .. " > "

    local function redraw()
        filtered, cur = _redraw(items, query, filtered, cur)
        _update_prompt(prompt_prefix, query, pbuf, pwin)
        _update_list(filtered, cur, lbuf, lwin)
        _update_preview(has_preview, formatter, filtered, cur, vbuf)
    end

    local function close(res)
        callback_called = _close(callback, callback_called, res, pwin, lwin, vwin)
    end

    local function move(d)
        cur = _move(filtered, cur, d)
        redraw()
    end

    redraw()
    -- Auto-close on focus loss
    vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
        buffer = pbuf,
        once = true,
        callback = function()
            close(nil)
        end,
    })
    local opts = { buffer = pbuf, nowait = true, silent = true }
    vim.keymap.set("i", "<CR>", function() close(filtered[cur] and filtered[cur].data or nil) end, opts)
    vim.keymap.set("i", "<Esc>", function() close(nil) end, opts)
    vim.keymap.set("i", "<C-c>", function() close(nil) end, opts)
    vim.keymap.set("i", "<C-n>", function() move(1) end, opts)
    vim.keymap.set("i", "<C-p>", function() move(-1) end, opts)
    vim.keymap.set("i", "<Down>", function() move(1) end, opts)
    vim.keymap.set("i", "<Up>", function() move(-1) end, opts)
    vim.keymap.set("i", "<BS>", function()
        if #query > 0 then
            query = query:sub(1, -2); redraw()
        end
    end, opts)
    vim.keymap.set("i", "<C-w>", function()
        local promptcol = vim.api.nvim_win_get_cursor(0)[2]
        if promptcol > #prompt_prefix then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-w>", true, true, true), "n", false)
        end
    end, { buffer = pbuf, silent = true })
    for i = 32, 126 do
        local c = string.char(i)
        vim.keymap.set("i", c, function()
            query = query .. c; redraw()
        end, opts)
    end
    vim.cmd("startinsert")
end

return M
