---@mod loop.selector
---@brief Simple floating selector with fuzzy filtering and optional preview.

---@class loop.SelectorItem
---@field label string        Display label
---@field file string?
---@field line number?
---@field data  any           Payload returned on select

---@alias loop.SelectorCallback fun(data:any|nil)

---@alias loop.PreviewFormatter fun(data:any):(string, string|nil)
--- Returns preview text and optional filetype

local M = {}

-- Namespace for prompt highlighting
local NS_PREVIEW = vim.api.nvim_create_namespace("LoopSelectorPreview")

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

---@param formatter loop.PreviewFormatter?   (optional custom preview generator)
---@param items loop.SelectorItem[]
---@param cur integer                        current selected index (1-based)
---@param buf integer                        preview buffer handle
local function update_preview(formatter, items, cur, buf)
    -- Guard: no valid item
    local item = items[cur]
    if not item then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "No selection" })
        vim.bo[buf].filetype = ""
        return
    end

    -- ──────────────────────────────────────────────────────────────
    --  File + line → load file contents into the preview buffer
    -- ──────────────────────────────────────────────────────────────
    if item.file and item.line then
        local filepath = vim.fs.normalize(item.file)
        local target_lnum = tonumber(item.line)

        if vim.fn.filereadable(filepath) ~= 1 then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                "File not readable:",
                filepath,
            })
            vim.bo[buf].filetype = "text"
            return
        end

        if not target_lnum or target_lnum < 1 then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                "Invalid line number:",
                filepath .. ":" .. tostring(item.line),
            })
            vim.bo[buf].filetype = "text"
            return
        end

        -- Clear previous content safely
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

        -- Load file contents into the buffer using :read (most "native" way)
        local ok, load_err = pcall(vim.api.nvim_buf_call, buf, function()
            -- :read adds content after current line → so we read into an empty buffer
            vim.cmd("silent! read " .. vim.fn.fnameescape(filepath))

            -- :read often inserts an empty first line when buffer was empty
            local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
            if first_line == "" then
                vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
            end
        end)

        if not ok then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                "Failed to load file into preview buffer:",
                vim.inspect(load_err),
            })
            vim.bo[buf].filetype = "text"
            return
        end

        -- Enable syntax highlighting
        vim.bo[buf].filetype = vim.filetype.match({ filename = filepath }) or "text"

        -- Try to position cursor / view at target line
        local preview_win = vim.fn.bufwinid(buf)
        local target_win = preview_win ~= -1 and preview_win or 0

        local set_ok = pcall(vim.api.nvim_win_set_cursor, target_win, { target_lnum, 0 })
        if set_ok then
            vim.api.nvim_win_call(target_win, function()
                vim.cmd("normal! zz") -- center the target line
            end)
        else
            -- Line might be out of range → fall back to first line
            pcall(vim.api.nvim_win_set_cursor, target_win, { 1, 0 })
        end

        -- Brief visual feedback: highlight target line
        pcall(vim.api.nvim_buf_clear_namespace, buf, NS_PREVIEW, 0, -1)
        -- Highlight the target line fully (works for single-line too)
        vim.api.nvim_buf_set_extmark(buf, NS_PREVIEW, target_lnum - 1, 0, {
            end_row = target_lnum, -- makes it "multiline" → enables hl_eol
            hl_group = "CursorLine",
            hl_eol = true,
            hl_mode = "blend",
        })
        return
    end

    -- ──────────────────────────────────────────────────────────────
    --  Custom formatter has highest priority
    -- ──────────────────────────────────────────────────────────────
    if formatter then
        local ok, text, ft = pcall(formatter, item.data, item)
        if not ok then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                "Formatter error:",
                vim.inspect(text), -- error message
            })
            vim.bo[buf].filetype = "lua"
            return
        end

        local lines = type(text) == "string" and vim.split(text, "\n") or { "<empty preview>" }
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].filetype = ft or ""
        return
    end


    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.bo[buf].filetype = ""
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

---@class loop.selector.opts
---@field prompt string
---@field items loop.SelectorItem[]
---@field file_preview boolean?
---@field formatter loop.PreviewFormatter|nil
---@field callback loop.SelectorCallback
---@field initial integer? -- 1-based index into items

---@param opts loop.selector.opts
function M.select(opts)
    local prompt, items, formatter, callback = opts.prompt, opts.items, opts.formatter, opts.callback

    if #items == 0 then
        callback(nil)
        return
    end

    local has_preview = opts.file_preview or type(opts.formatter) == "function"

    --------------------------------------------------------------------------
    -- Layout
    --------------------------------------------------------------------------

    local list_w = compute_width(opts.items, 4)
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
        title = (" %s "):format(prompt),
        title_pos = "center"
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

    local filtered = vim.deepcopy(items)
    local cur = math.max(1, math.min(opts.initial or 1, #items))
    local closed = false

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

    local function update_content()
        update_list(filtered, cur, lbuf, lwin)
        if vbuf then update_preview(formatter, filtered, cur, vbuf) end
    end

    local key_opts = { buffer = pbuf, nowait = true, silent = true }

    vim.keymap.set("i", "<CR>", function()
        close(filtered[cur] and filtered[cur].data)
    end, key_opts)

    vim.keymap.set("i", "<Esc>", function() close(nil) end, key_opts)
    vim.keymap.set("i", "<C-c>", function() close(nil) end, key_opts)

    vim.keymap.set("i", "<Down>", function()
        cur = move_wrap(#filtered, cur, 1)
        update_content()
    end, key_opts)

    vim.keymap.set("i", "<C-n>", function()
        cur = move_wrap(#filtered, cur, 1)
        update_content()
    end, key_opts)

    vim.keymap.set("i", "<Up>", function()
        cur = move_wrap(#filtered, cur, -1)
        update_content()
    end, key_opts)

    vim.keymap.set("i", "<C-p>", function()
        cur = move_wrap(#filtered, cur, -1)
        update_content()
    end, key_opts)

    local page = math.max(1, math.floor(height / 2))
    vim.keymap.set("i", "<C-d>", function()
        cur = move_clamp(#filtered, cur, page)
        update_content()
    end, key_opts)

    vim.keymap.set("i", "<C-u>", function()
        cur = move_clamp(#filtered, cur, -page)
        update_content()
    end, key_opts)

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = pbuf,
        callback = function()
            if vim.api.nvim_buf_line_count(pbuf) == 0 then
                vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, { "" })
            end

            local plines = vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)
            local query = plines[1] or ""
            -- now recompute filtered list
            filtered, cur = recompute(items, query, cur)
            update_content()
        end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = pbuf,
        once = true,
        callback = function() close(nil) end,
    })

    vim.api.nvim_set_current_win(pwin)
    vim.schedule(function()
        if vim.api.nvim_win_is_valid(pwin)
            and vim.api.nvim_get_current_win() == pwin
            and vim.fn.mode() ~= "i" then
            vim.cmd("startinsert!")
        end
    end)

    update_content()
end

return M
