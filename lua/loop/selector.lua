---@class loop.SelectorItem
---@field label string
---@field data any

---@alias loop.SelectorCallback fun(data: any?)

local M = {}

local function create_win(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "single",
    width = opts.width,
    height = opts.height,
    row = opts.row,
    col = opts.col,
  })
  vim.wo[win].wrap = false
  vim.wo[win].scrolloff = 0
  return buf, win
end

local function apply_filter(items, query)
  if query == "" then return vim.deepcopy(items) end
  local q = query:lower()
  local result = {}
  for _, item in ipairs(items) do
    if item.label:lower():find(q, 1, true) then
      table.insert(result, item)
    end
  end
  return result
end

--- Native floating selector with live filtering + preview
---@param prompt string
---@param items loop.SelectorItem[]
---@param formatter? fun(data:any):string   -- defaults to vim.inspect / tostring
---@param callback loop.SelectorCallback
function M.select(prompt, items, formatter, callback)
  if #items == 0 then return callback(nil) end

  formatter = formatter or function(data)
    return type(data) == "table" and vim.inspect(data) or tostring(data)
  end

  -- Layout
  local width  = math.floor(vim.o.columns * 0.7)
  local height = math.floor(vim.o.lines    * 0.7)
  local list_w = math.floor(width * 0.4)
  local prev_w = width - list_w - 1

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- State
  local query    = ""
  local filtered = vim.deepcopy(items)
  local cursor   = 1

  -- Windows
  local list_buf, list_win = create_win { row = row, col = col,           width = list_w, height = height }
  local prev_buf, prev_win = create_win { row = row, col = col + list_w + 1, width = prev_w, height = height }

  vim.bo[list_buf].filetype = "loop-selector-list"
  vim.bo[prev_buf].filetype = "loop-selector-preview"
  vim.bo[prev_buf].buftype  = "nofile"

  local function update_list()
    local header = prompt .. (query ~= "" and (" > " .. query) or "")
    local lines = { header }
    for i, item in ipairs(filtered) do
      table.insert(lines, (i == cursor and "▶ " or "  ") .. item.label)
    end
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    vim.api.nvim_buf_add_highlight(list_buf, -1, "Title", 0, 0, -1) -- highlight prompt
  end

  local function update_preview()
    local item = filtered[cursor]
    if not item then
      vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, {""})
      return
    end

    local ok, text = pcall(formatter, item.data)
    if not ok then text = "<formatter error>" end

    local lines = vim.split(text, "\n")
    vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, lines)

    -- Optional: guess filetype for syntax highlighting
    if type(item.data) == "table" and item.data.__filetype then
      vim.bo[prev_buf].filetype = item.data.__filetype
    end
  end

  local function rerender()
    filtered = apply_filter(items, query)
    cursor = #filtered > 0 and math.min(cursor, #filtered) or 1
    update_list()
    update_preview()
  end

  local function close(result)
    pcall(vim.api.nvim_win_close, list_win, true)
    pcall(vim.api.nvim_win_close, prev_win, true)
    callback(result)
  end

  local function move(delta)
    if #filtered == 0 then return end
    cursor = ((cursor - 1 + delta) % #filtered) + 1
    update_list()
    update_preview()
  end

  -- Initial render
  rerender()

  -- Keymaps (only in the list buffer)
  local opts = { buffer = list_buf, nowait = true, silent = true }

  -- Cancel
  vim.keymap.set("n", "<Esc>", function() close(nil) end, opts)
  vim.keymap.set("n", "q",     function() close(nil) end, opts)
  vim.keymap.set("n", "<C-c>", function() close(nil) end, opts)

  -- Confirm
  vim.keymap.set("n", "<CR>", function()
    close(filtered[cursor] and filtered[cursor].data or nil)
  end, opts)

  -- Navigation – ONLY Ctrl-n / Ctrl-p (and arrows as bonus)
  vim.keymap.set("n", "<C-n>",     function() move(1)  end, opts)
  vim.keymap.set("n", "<C-p>",     function() move(-1) end, opts)
  vim.keymap.set("n", "<Down>",    function() move(1)  end, opts)
  vim.keymap.set("n", "<Up>",      function() move(-1) end, opts)

  -- Backspace
  vim.keymap.set("n", "<BS>", function()
    if #query > 0 then
      query = query:sub(1, -2)
      rerender()
    end
  end, opts)

  -- All printable characters → add to query (including j, k, etc.)
  for code = 32, 126 do
    local char = string.char(code)
    vim.keymap.set("n", char, function()
      query = query .. char
      rerender()
    end, opts)
  end

  -- Start in the list window
  vim.api.nvim_set_current_win(list_win)
end

return M