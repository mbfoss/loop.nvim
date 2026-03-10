local Spinner    = require("loop.tools.Spinner")
local class      = require("loop.tools.class")

---@mod loop.picker
---@brief Floating async picker with fuzzy filtering and optional preview.

local M          = {}

--------------------------------------------------------------------------------
-- Namespaces
--------------------------------------------------------------------------------

local NS_CURSOR  = vim.api.nvim_create_namespace("LoopSelectorCursor")
local NS_VIRT    = vim.api.nvim_create_namespace("LoopSelectorVirtText")
local NS_SPINNER = vim.api.nvim_create_namespace("LoopSelectorSpinner")

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

---@class loop.Picker.Item
---@field label string?
---@field label_chunks {[1]:string,[2]:string?}[]?
---@field virt_lines? {[1]:string,[2]:string?}[][]
---@field data any

---@alias loop.Picker.Callback fun(data:any|nil)

---@class loop.Picker.AsyncFetcherOpts
---@field list_width number
---@field list_height number

---@class loop.Picker.AsyncPreviewOpts
---@field preview_width number
---@field preview_height number

---@alias loop.Picker.AsyncFetcher fun(query:string,opts:loop.Picker.AsyncFetcherOpts,callback:fun(new_items:loop.Picker.Item[]?)):fun()?
---@alias loop.Picker.AsyncPreviewLoader fun(data:any,opts:loop.Picker.AsyncPreviewOpts,callback:fun(preview:string?)):fun()?

---@class loop.Picker.opts
---@field prompt string
---@field async_fetch loop.Picker.AsyncFetcher
---@field async_preview loop.Picker.AsyncPreviewLoader?
---@field height_ratio number?
---@field width_ratio number?
---@field preview_ratio number?
---@field list_wrap boolean?

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

---@class loop.Picker.Layout
---@field prompt_row number
---@field prompt_col number
---@field prompt_width number
---@field prompt_height number
---@field list_row number
---@field list_col number
---@field list_width number
---@field list_height number
---@field prev_row number
---@field prev_col number
---@field prev_width number
---@field prev_height number

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

---@param v number
---@param min number
---@param max number
---@return number
local function clamp(v, min, max)
    return math.max(min, math.min(max, v))
end

--------------------------------------------------------------------------------
-- Layout computation
--------------------------------------------------------------------------------

---@param opts {has_preview:boolean,height_ratio:number?,width_ratio:number?,preview_ratio:number?}
---@return loop.Picker.Layout
local function compute_layout(opts)
    local cols = vim.o.columns
    local lines = vim.o.lines

    local has_preview = opts.has_preview
    local spacing = has_preview and 2 or 0

    local width = math.floor(cols * clamp(opts.width_ratio or .8, 0, 1))

    local list_ratio = clamp(opts.preview_ratio or (has_preview and .5 or 1), 0, 1)
    local list_width = math.floor(width * list_ratio)

    local prev_width = has_preview and clamp(width - list_width - spacing, 1, width) or 0

    local height = math.floor(lines * clamp(opts.height_ratio or .7, 0, 1))

    local total_height = height + 3

    local row = math.floor((lines - total_height) / 2)
    local col = math.floor((cols - (list_width + prev_width + spacing)) / 2)

    return {
        prompt_row = row,
        prompt_col = col,
        prompt_width = list_width + prev_width + spacing,
        prompt_height = 1,

        list_row = row + 3,
        list_col = col,
        list_width = list_width,
        list_height = height,

        prev_row = row + 3,
        prev_col = col + list_width + spacing,
        prev_width = prev_width,
        prev_height = height
    }
end

--------------------------------------------------------------------------------
-- Picker Class
--------------------------------------------------------------------------------

---@class loop.tools.Picker
---@field new fun(self: loop.tools.Picker,opts:loop.Picker.opts,callback:loop.Picker.Callback) : loop.tools.Picker
---@field opts loop.Picker.opts
---@field callback loop.Picker.Callback
---@field has_preview boolean
---@field layout loop.Picker.Layout
---@field pbuf integer
---@field lbuf integer
---@field vbuf integer|nil
---@field pwin integer
---@field lwin integer
---@field vwin integer|nil
---@field spinner loop.tools.Spinner|nil
---@field closed boolean
---@field items_data any[]
---@field fetch_context integer
---@field async_fetch_cancel fun()|nil
---@field async_preview_cancel fun()|nil
local Picker = class()

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

---@param opts loop.Picker.opts
---@param callback loop.Picker.Callback
function Picker:init(opts, callback)
    self.opts = opts
    self.callback = callback

    self.has_preview = type(opts.async_preview) == "function"

    self.items_data = {}

    self.fetch_context = 0
    self.closed = false

    self.async_fetch_cancel = nil
    self.async_preview_cancel = nil

    self.spinner = nil

    self:setup_ui()
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

---@return nil
function Picker:setup_ui()
    local opts = self.opts

    self.layout = compute_layout {
        has_preview = self.has_preview,
        height_ratio = opts.height_ratio,
        width_ratio = opts.width_ratio,
        preview_ratio = opts.preview_ratio
    }

    local title = opts.prompt and (" " .. opts.prompt .. " ") or ""

    self.pbuf = vim.api.nvim_create_buf(false, true)
    self.lbuf = vim.api.nvim_create_buf(false, true)
    self.vbuf = self.has_preview and vim.api.nvim_create_buf(false, true) or nil

    for _, b in ipairs({ self.pbuf, self.lbuf, self.vbuf }) do
        if b then
            vim.bo[b].buftype = "nofile"
            vim.bo[b].bufhidden = "wipe"
            vim.bo[b].swapfile = false
            vim.bo[b].undolevels = -1
        end
    end

    local base_cfg = {
        relative = "editor",
        style = "minimal",
        border = "rounded"
    }

    self.pwin = vim.api.nvim_open_win(self.pbuf, true, vim.tbl_extend("force", base_cfg, {
        row = self.layout.prompt_row,
        col = self.layout.prompt_col,
        width = self.layout.prompt_width,
        height = 1,
        title = title,
        title_pos = "center"
    }))

    self.lwin = vim.api.nvim_open_win(self.lbuf, false, vim.tbl_extend("force", base_cfg, {
        row = self.layout.list_row,
        col = self.layout.list_col,
        width = self.layout.list_width,
        height = self.layout.list_height
    }))

    if self.vbuf then
        self.vwin = vim.api.nvim_open_win(self.vbuf, false, vim.tbl_extend("force", base_cfg, {
            row = self.layout.prev_row,
            col = self.layout.prev_col,
            width = self.layout.prev_width,
            height = self.layout.prev_height
        }))
        vim.wo[self.vwin].wrap = true
    end

    local winhl = "NormalFloat:Normal,FloatBorder:LoopTransparentBorder,CursorLine:Visual"
    for _, w in ipairs({ self.pwin, self.lwin, self.vwin }) do
        if w then
            vim.wo[w].winhighlight = winhl
        end
    end

    vim.wo[self.pwin].wrap = false
    vim.wo[self.lwin].wrap = self.opts.list_wrap ~= false
end

--------------------------------------------------------------------------------
-- UI Rendering
--------------------------------------------------------------------------------

---@return nil
function Picker:render_ui()
    if not vim.api.nvim_buf_is_valid(self.lbuf) then
        return
    end

    vim.api.nvim_buf_clear_namespace(self.lbuf, NS_CURSOR, 0, -1)
    vim.api.nvim_buf_clear_namespace(self.pbuf, NS_CURSOR, 0, -1)

    local total = #self.items_data
    if total == 0 then
        return
    end

    local cur = self:get_cursor()

    ------------------------------------------------
    -- Cursor marker
    ------------------------------------------------

    if total > 0 then
        vim.api.nvim_buf_set_extmark(self.lbuf, NS_CURSOR, cur - 1, 0, {
            virt_text = { { "> ", "Special" } },
            virt_text_pos = "overlay",
            priority = 200,
        })
    end

    ------------------------------------------------
    -- Position hint
    ------------------------------------------------

    if total > 0 and vim.api.nvim_buf_is_valid(self.pbuf) then
        local text = string.format("%d/%d", cur, total)

        vim.api.nvim_buf_set_extmark(self.pbuf, NS_CURSOR, 0, 0, {
            virt_text = { { text, "Comment" } },
            virt_text_pos = "right_align",
            hl_mode = "blend",
            priority = 1,
        })
    end
end

--------------------------------------------------------------------------------
-- Cursor
--------------------------------------------------------------------------------

---@return integer
function Picker:get_cursor()
    return vim.api.nvim_win_get_cursor(self.lwin)[1]
end

---@param row integer
---@param force boolean?
function Picker:move_cursor(row, force)
    if not force then
        if row == self:get_cursor() then return end
    end

    local total = #self.items_data
    if total == 0 then return end

    if row > total then row = 1 end
    if row < 1 then row = total end

    vim.api.nvim_win_set_cursor(self.lwin, { row, 0 })

    self:render_ui()
    self:update_preview()
end

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------

---@return nil
function Picker:update_preview()
    if not self.vbuf then return end

    if self.async_preview_cancel then
        self.async_preview_cancel()
        self.async_preview_cancel = nil
    end

    local data = self.items_data[self:get_cursor()]

    if not data then
        vim.api.nvim_buf_set_lines(self.vbuf, 0, -1, false, {})
        return
    end

    self.async_preview_cancel = self.opts.async_preview(
        data,
        {
            preview_width = self.layout.prev_width,
            preview_height = self.layout.prev_height
        },
        function(preview)
            local lines = preview and vim.split(preview, "\n") or {}

            if vim.api.nvim_buf_is_valid(self.vbuf) then
                vim.api.nvim_buf_set_lines(self.vbuf, 0, -1, false, lines)
            end
        end
    )
end

--------------------------------------------------------------------------------
-- Spinner
--------------------------------------------------------------------------------

function Picker:start_spinner()
    if self.spinner then return end

    self.spinner = Spinner:new {
        interval = 80,
        on_update = function(frame)
            if not vim.api.nvim_buf_is_valid(self.pbuf) then return end

            vim.api.nvim_buf_clear_namespace(self.pbuf, NS_SPINNER, 0, -1)

            vim.api.nvim_buf_set_extmark(self.pbuf, NS_SPINNER, 0, 0, {
                virt_text = { { frame .. " ", "Comment" } },
                virt_text_pos = "right_align"
            })
        end
    }

    self.spinner:start()
end

function Picker:stop_spinner()
    if self.spinner then
        self.spinner:stop()
        self.spinner = nil
    end

    if vim.api.nvim_buf_is_valid(self.pbuf) then
        vim.api.nvim_buf_clear_namespace(self.pbuf, NS_SPINNER, 0, -1)
    end
end

--------------------------------------------------------------------------------
-- List manipulation
--------------------------------------------------------------------------------

function Picker:clear_list()
    self.items_data = {}

    vim.api.nvim_buf_set_lines(self.lbuf, 0, -1, false, {})
    vim.api.nvim_buf_clear_namespace(self.lbuf, NS_VIRT, 0, -1)

    if self.vbuf and vim.api.nvim_buf_is_valid(self.vbuf) then
        vim.api.nvim_buf_set_lines(self.vbuf, 0, -1, false, {})
    end

    self:render_ui()
end

function Picker:add_new_lines(items)
    local prefix = "  "
    local lines = {}
    local extmarks = {}
    local virt_extmarks = {}

    -- 1. Check if the buffer is currently "fresh" (one empty line)
    local current_buf_count = vim.api.nvim_buf_line_count(self.lbuf)
    local is_empty = current_buf_count == 1 and vim.api.nvim_buf_get_lines(self.lbuf, 0, 1, false)[1] == ""

    -- 2. Determine where we start counting rows for highlights
    local start_row = is_empty and 0 or current_buf_count

    for _, item in ipairs(items) do
        local label = item.label
        if not label and item.label_chunks then
            local parts = {}
            for _, chunk in ipairs(item.label_chunks) do
                if chunk[1] then parts[#parts + 1] = chunk[1] end
            end
            label = table.concat(parts)
        end

        label = (label or ""):gsub("\n", "")
        table.insert(lines, prefix .. label)
        table.insert(self.items_data, item.data)

        local row = start_row + #lines - 1
        local col = #prefix

        if item.label_chunks then
            for _, chunk in ipairs(item.label_chunks) do
                local text, hl = chunk[1], chunk[2]
                if text and #text > 0 then
                    if hl then
                        table.insert(extmarks, { row = row, col_start = col, col_end = col + #text, hl_group = hl })
                    end
                    col = col + #text
                end
            end
        end

        if item.virt_lines and #item.virt_lines > 0 then
            local vlines = {}
            for _, line in ipairs(item.virt_lines) do
                local vl = { { prefix } }
                vim.list_extend(vl, line)
                table.insert(vlines, vl)
            end
            table.insert(virt_extmarks, { row = row, col = 0, opts = { virt_lines = vlines, hl_mode = "blend" } })
        end
    end

    if #lines == 0 then return end

    -- 3. Apply the changes to the buffer
    if is_empty then
        -- Replace the initial blank line entirely
        vim.api.nvim_buf_set_lines(self.lbuf, 0, -1, false, lines)
    else
        -- Append to existing items
        vim.api.nvim_buf_set_lines(self.lbuf, start_row, start_row, false, lines)
    end

    -- 4. Apply highlights and virtual lines
    for _, mark in ipairs(extmarks) do
        vim.api.nvim_buf_set_extmark(self.lbuf, NS_VIRT, mark.row, mark.col_start, {
            end_col = mark.col_end,
            hl_group = mark.hl_group,
        })
    end

    for _, mark in ipairs(virt_extmarks) do
        vim.api.nvim_buf_set_extmark(self.lbuf, NS_VIRT, mark.row, mark.col, mark.opts)
    end

    -- 5. Final validation
    local final_count = vim.api.nvim_buf_line_count(self.lbuf)
    assert(#self.items_data == final_count, string.format("Data (%d) != Buf (%d)", #self.items_data, final_count))
end

--------------------------------------------------------------------------------
-- Fetch
--------------------------------------------------------------------------------

---@param query string
function Picker:run_fetch(query)
    if self.async_fetch_cancel then
        self.async_fetch_cancel()
        self.async_fetch_cancel = nil
    end

    self:stop_spinner()

    if query == "" then
        self:clear_list()
        return
    end

    self.fetch_context = self.fetch_context + 1
    local context = self.fetch_context

    local waiting_first = true

    self:start_spinner()

    self.async_fetch_cancel = self.opts.async_fetch(
        query,
        {
            list_width = self.layout.list_width,
            list_height = self.layout.list_height
        },
        function(new_items)
            if self.closed or context ~= self.fetch_context then return end

            if waiting_first then
                waiting_first = false
                self.items_data = {}
                vim.api.nvim_buf_set_lines(self.lbuf, 0, -1, false, {})
            end

            if new_items == nil then
                self:stop_spinner()
                return
            end

            self:add_new_lines(new_items)
            self:render_ui()

            if #self.items_data == #new_items and #self.items_data > 0 then
                self:move_cursor(1, true)
            end
        end
    )
end

--------------------------------------------------------------------------------
-- Close
--------------------------------------------------------------------------------

---@param result any|nil
function Picker:close(result)
    if self.closed then return end
    self.closed = true

    self:stop_spinner()

    if self.async_fetch_cancel then self.async_fetch_cancel() end
    if self.async_preview_cancel then self.async_preview_cancel() end

    for _, w in ipairs({ self.pwin, self.lwin, self.vwin }) do
        if w and vim.api.nvim_win_is_valid(w) then
            vim.api.nvim_win_close(w, true)
        end
    end

    if result ~= nil then
        vim.schedule(function()
            self.callback(result)
        end)
    end
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

function Picker:setup_input()
    local key_opts = { buffer = self.pbuf, nowait = true, silent = true }

    vim.keymap.set("i", "<CR>", function()
        self:close(self.items_data[self:get_cursor()])
    end, key_opts)

    vim.keymap.set("i", "<Esc>", function() self:close(nil) end, key_opts)
    vim.keymap.set("i", "<C-c>", function() self:close(nil) end, key_opts)

    vim.keymap.set("i", "<Down>", function()
        self:move_cursor(self:get_cursor() + 1)
    end, key_opts)

    vim.keymap.set("i", "<C-n>", function()
        self:move_cursor(self:get_cursor() + 1)
    end, key_opts)

    vim.keymap.set("i", "<Up>", function()
        self:move_cursor(self:get_cursor() - 1)
    end, key_opts)

    vim.keymap.set("i", "<C-p>", function()
        self:move_cursor(self:get_cursor() - 1)
    end, key_opts)

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = self.pbuf,
        callback = function()
            local query = vim.api.nvim_buf_get_lines(self.pbuf, 0, 1, false)[1] or ""
            if query == "" then
                self:clear_list()
                return
            end
            self:run_fetch(query)
        end
    })
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

function Picker:start()
    self:setup_input()
    self:render_ui()

    vim.api.nvim_set_current_win(self.pwin)

    vim.schedule(function()
        vim.cmd("startinsert!")
    end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---@param opts loop.Picker.opts
---@param callback loop.Picker.Callback
function M.select(opts, callback)
    assert(type(opts.async_fetch) == "function")

    local picker = Picker:new(opts, callback)

    picker:start()
end

return M
