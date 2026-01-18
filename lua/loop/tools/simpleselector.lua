---@mod loop.selector
---@brief Simple floating selector with fuzzy filtering and optional preview.

---@class loop.SelectorItem
---@field label string        Display label
---@field data  any           Payload returned on select

---@alias loop.SelectorCallback fun(data:any|nil)

---@alias loop.PreviewFormatter fun(data:any):(string, string|nil)
--- Returns preview text and optional filetype

local M = {}

-- Namespace for prompt highlighting
local NS_PROMPT = vim.api.nvim_create_namespace("LoopSelectorPrompt")

--------------------------------------------------------------------------------
-- Utility functions
--------------------------------------------------------------------------------

---@param items loop.SelectorItem[]
---@param query string
---@return loop.SelectorItem[]
local function fuzzy_filter(items, query)
    if query == "" then
        return vim.deepcopy(items)
    end

    local q = query:lower()
    local res = {}

    for _, item in ipairs(items) do
        if item.label:lower():find(q, 1, true) then
            res[#res + 1] = item
        end
    end

    return res
end

---@param prompt_prefix string
---@param query string
---@param buf integer
---@param win integer
local function update_prompt(prompt_prefix, query, buf, win)
    local text = prompt_prefix .. query
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })

    vim.api.nvim_buf_clear_namespace(buf, NS_PROMPT, 0, -1)

    vim.api.nvim_buf_set_extmark(buf, NS_PROMPT, 0, 0, {
        end_col = #prompt_prefix,
        hl_group = "Title",
    })

    vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_cursor(win, { 1, #text })
        end
    end)
end

---@param items loop.SelectorItem[]
---@param cur integer
---@param buf integer
---@param win integer
local function update_list(items, cur, buf, win)
    local lines = {}

    for i, item in ipairs(items) do
        local prefix = (i == cur) and "> " or "  "
        lines[i] = prefix .. item.label
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_cursor(win, { math.max(cur, 1), 0 })
    end
end

---@param formatter loop.PreviewFormatter?
---@param items loop.SelectorItem[]
---@param cur integer
---@param buf integer
local function update_preview(formatter, items, cur, buf)
    local item = items[cur]
    if not item then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
        return
    end

    local ok, text, ft
    if formatter then
        ok, text, ft = pcall(formatter, item.data)
    else
        ok, text, ft = true, "", ""
    end

    vim.bo[buf].filetype = ft or ""
    if not ok then
        text = "<preview error>"
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
end

---@param items loop.SelectorItem[]
---@param query string
---@param cur integer
---@return loop.SelectorItem[], integer
local function recompute(items, query, cur)
    local filtered = fuzzy_filter(items, query)
    if #filtered == 0 then
        return filtered, 1
    end
    return filtered, math.min(cur, #filtered)
end

---@param max integer
---@param cur integer
---@param delta integer
---@return integer
local function move_wrap(max, cur, delta)
    if max == 0 then
        return cur
    end
    return ((cur - 1 + delta) % max) + 1
end

---@param max integer
---@param cur integer
---@param delta integer
---@return integer
local function move_clamp(max, cur, delta)
    if max == 0 then
        return cur
    end
    return math.min(max, math.max(1, cur + delta))
end

---@param items loop.SelectorItem[]
---@param padding integer?
---@return integer
local function compute_width(items, padding)
    local cols = vim.o.columns
    local maxw = 0

    for _, item in ipairs(items) do
        maxw = math.max(maxw, vim.fn.strdisplaywidth(item.label))
    end

    local desired = maxw + (padding or 4)
    return math.max(
        math.floor(cols * 0.2),
        math.min(math.floor(cols * 0.8), desired)
    )
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---@param prompt string
---@param items loop.SelectorItem[]
---@param formatter loop.PreviewFormatter|nil
---@param callback loop.SelectorCallback
function M.select(prompt, items, formatter, callback)
    if #items == 0 then
        callback(nil)
        return
    end

    local has_preview = type(formatter) == "function"

    --------------------------------------------------------------------------
    -- Layout
    --------------------------------------------------------------------------

    local list_w = compute_width(items, 4)
    local cols = vim.o.columns
    local lines = vim.o.lines

    local spacing = has_preview and 2 or 0
    local preview_w = has_preview and math.min(math.floor(cols * 0.3), cols - list_w - spacing) or 0
    local width = list_w + spacing + preview_w

    local height = math.max(
        math.floor(lines * 0.5),
        math.min(math.floor(lines * 0.8), #items + 2)
    )

    local row = math.floor((lines - height) / 2)
    local col = math.floor((cols - width) / 2)

    --------------------------------------------------------------------------
    -- Buffers & windows
    --------------------------------------------------------------------------

    local pbuf = vim.api.nvim_create_buf(false, true)
    local lbuf = vim.api.nvim_create_buf(false, true)
    local vbuf = has_preview and vim.api.nvim_create_buf(false, true) or nil


    for _, b in ipairs({ pbuf, lbuf, vbuf }) do
        if b then
            vim.bo[b].buftype = "nofile"
            vim.bo[b].bufhidden = "delete"
        end
    end

    vim.cmd("highlight default LoopTransparentBorder guibg=NONE")

    local base_cfg = {
        relative = "editor",
        style = "minimal",
        border = "rounded",
    }

    local pwin = vim.api.nvim_open_win(pbuf, true, vim.tbl_extend("force", base_cfg, {
        row = row - 3,
        col = col,
        width = width,
        height = 1,
    }))

    local lwin = vim.api.nvim_open_win(lbuf, false, vim.tbl_extend("force", base_cfg, {
        row = row,
        col = col,
        width = list_w,
        height = height,
    }))

    local vwin
    if vbuf then
        vwin = vim.api.nvim_open_win(vbuf, false, vim.tbl_extend("force", base_cfg, {
            row = row,
            col = col + list_w + spacing,
            width = preview_w,
            height = height,
        }))
        vim.wo[vwin].wrap = true
    end

    local winhl = "NormalFloat:Normal,FloatBorder:LoopTransparentBorder,CursorLine:Visual"
    for _, w in ipairs({ pwin, lwin, vwin }) do
        if w then
            vim.wo[w].winhighlight = winhl
        end
    end

    --------------------------------------------------------------------------
    -- State
    --------------------------------------------------------------------------

    local query = ""
    local filtered = vim.deepcopy(items)
    local cur = 1
    local closed = false
    local prompt_prefix = prompt .. " > "

    --------------------------------------------------------------------------
    -- Redraw
    --------------------------------------------------------------------------

    local function redraw()
        filtered, cur = recompute(items, query, cur)
        update_prompt(prompt_prefix, query, pbuf, pwin)
        update_list(filtered, cur, lbuf, lwin)
        if vbuf then
            update_preview(formatter, filtered, cur, vbuf)
        end
    end

    local function close(result)
        if closed then return end
        closed = true
        if vim.api.nvim_get_current_win() == pwin then
            vim.cmd("stopinsert")
        end
        vim.schedule(function()
            for _, w in ipairs({ pwin, lwin, vwin }) do
                if w and vim.api.nvim_win_is_valid(w) then
                    vim.api.nvim_win_close(w, true)
                end
            end
            if result ~= nil then
                vim.schedule(function()
                    callback(result)
                end)
            end
        end)
    end

    --------------------------------------------------------------------------
    -- Keymaps
    --------------------------------------------------------------------------

    local opts = { buffer = pbuf, nowait = true, silent = true }

    vim.keymap.set("i", "<CR>", function()
        close(filtered[cur] and filtered[cur].data or nil)
    end, opts)

    vim.keymap.set("i", "<Esc>", function() close(nil) end, opts)
    vim.keymap.set("i", "<C-c>", function() close(nil) end, opts)

    vim.keymap.set("i", "<Down>", function()
        cur = move_wrap(#filtered, cur, 1)
        redraw()
    end, opts)

    vim.keymap.set("i", "<C-n>", function()
        cur = move_wrap(#filtered, cur, 1)
        redraw()
    end, opts)

    vim.keymap.set("i", "<Up>", function()
        cur = move_wrap(#filtered, cur, -1)
        redraw()
    end, opts)

    vim.keymap.set("i", "<C-p>", function()
        cur = move_wrap(#filtered, cur, -1)
        redraw()
    end, opts)

    local page = math.max(1, math.floor(height / 2))
    vim.keymap.set("i", "<C-d>", function()
        cur = move_clamp(#filtered, cur, page)
        redraw()
    end, opts)

    vim.keymap.set("i", "<C-u>", function()
        cur = move_clamp(#filtered, cur, -page)
        redraw()
    end, opts)

    vim.keymap.set("i", "<BS>", function()
        if #query > 0 then
            query = query:sub(1, -2)
            redraw()
        end
    end, opts)

    for i = 32, 126 do
        local c = string.char(i)
        vim.keymap.set("i", c, function()
            query = query .. c
            redraw()
        end, opts)
    end

    --------------------------------------------------------------------------
    -- Start
    --------------------------------------------------------------------------

    redraw()

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = pbuf,
        once = true,
        callback = function() close(nil) end,
    })

    vim.api.nvim_set_current_win(pwin)
    vim.schedule(function()
        -- schedule AGAIN to ensure all WinEnter/BufEnter events are done
        vim.schedule(function()
            if vim.api.nvim_win_is_valid(pwin)
                and vim.api.nvim_get_current_win() == pwin
                and vim.fn.mode() ~= "i" then
                vim.cmd("startinsert!")
            end
        end)
    end)
end

return M
