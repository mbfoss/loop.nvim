---@class loop.SelectorItem
---@field label string
---@field data any

---@alias loop.SelectorCallback fun(data: any)

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

--- Native floating selector with live filtering and preview
---@param prompt string
---@param items loop.SelectorItem[]
---@param formatter? fun(data:any):string
---@param callback loop.SelectorCallback
function M.select(prompt, items, formatter, callback)
  if #items == 0 then
    callback(nil)
    return
  end

  formatter = formatter or function(data)
    if type(data) == "table" then
      return vim.inspect(data)
    end
    return tostring(data)
  end

  -- Layout
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local width = math.floor(editor_width * 0.7)
  local height = math.floor(editor_height * 0.7)
  local list_width = math.floor(width * 0.4)
  local preview_width = width - list_width - 1

  local row = math.floor((editor_height - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  -- State
  local query = ""
  local filtered = vim.deepcopy(items)
  local cursor = 1

  -- Windows & buffers
  local list_buf, list_win = create_win {
    row = row,
    col = col,
    width = list_width,
    height = height,
  }

  local prev_buf, prev_win = create_win {
    row = row,
    col = col + list_width + 1,
    width = preview_width,
    height = height,
  }

  vim.bo[list_buf].filetype = "loop-selector-list"
  vim.bo[prev_buf].filetype = "loop-selector-preview"
  vim.bo[prev_buf].buftype = "nofile"

  -- Syntax highlight preview if possible
  vim.api.nvim_win_set_option(prev_win, "winhl", "Normal:FloatBorder,FloatBorder:FloatBorder")

  local function update_list()
    local lines = { prompt .. (query ~= "" and (" > " .. query) or "") }
    for i, item in ipairs(filtered) do
      local prefix = i == cursor and "▶ " or "  "
      table.insert(lines, prefix .. item.label)
    end
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    vim.api.nvim_buf_add_highlight(list_buf, -1, "Title", 0, 0, -1)
  end

  local function update_preview()
    if not filtered[cursor] then
      vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, { "" })
      return
    end

    local ok, text = pcall(formatter, filtered[cursor].data)
    if not ok then text = "<error formatting data>" end

    local lines = vim.split(text, "\n", { trimempty = false })
    vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, lines)

    -- Try to set filetype for syntax highlighting in preview
    if type(filtered[cursor].data) == "table" and filtered[cursor].data.__filetype then
      vim.bo[prev_buf].filetype = filtered[cursor].data.__filetype
    else
      vim.bo[prev_buf].syntax = "lua" -- fallback
    end
  end

  local function rerender()
    filtered = apply_filter(items, query)
    if #filtered == 0 then
      cursor = 1
    else
      cursor = math.max(1, math.min(cursor, #filtered))
    end
    update_list()
    update_preview()
  end

  local function close(result)
    if vim.api.nvim_win_is_valid(list_win) then vim.api.nvim_win_close(list_win, true) end
    if vim.api.nvim_win_is_valid(prev_win) then vim.api.nvim_win_close(prev_win, true) end
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

  -- Keymaps (buffer-local)
  local opts = { buffer = list_buf, nowait = true, silent = true }

  vim.keymap.set("n", "<Esc>", function() close(nil) end, opts)
  vim.keymap.set("n", "q",     function() close(nil) end, opts)
  vim.keymap.set("n", "<C-c>", function() close(nil) end, opts)

  vim.keymap.set("n", "<CR>", function()
    close(filtered[cursor] and filtered[cursor].data or nil)
  end, opts)

  vim.keymap.set("n", "<C-n>", function() move(1) end, opts)
  vim.keymap.set("n", "<Down>", function() move(1) end, opts)
  vim.keymap.set("n", "j", function() move(1) end, opts)

  vim.keymap.set("n", "<C-p>", function() move(-1) end, opts)
  vim.keymap.set("n", "<Up>", function() move(-1) end, opts)
  vim.keymap.set("n", "k", function() move(-1) end, opts)

  -- Backspace
  vim.keymap.set("n", "<BS>", function()
    if #query > 0 then
      query = query:sub(1, -2)
      rerender()
    end
  end, opts)

  -- Printable characters → filter
  for code = 32, 126 do
    local char = string.char(code)
    if not vim.tbl_contains({ "q", "j", "k" }, char) then -- avoid conflicts
      vim.keymap.set("n", char, function()
        query = query .. char
        rerender()
      end, opts)
    end
  end

  -- Make list window active
  vim.api.nvim_set_current_win(list_win)
end

return M