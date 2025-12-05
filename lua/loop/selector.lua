---@class loop.SelectorItem
---@field label string
---@field data any
---@alias loop.SelectorCallback fun(data: any|nil)

local M = {}

local function fuzzy_filter(items, query)
  if query == "" then return vim.deepcopy(items) end
  local lowered = query:lower()
  local result = {}
  for _, item in ipairs(items) do
    if item.label:lower():find(lowered, 1, true) then
      table.insert(result, item)
    end
  end
  return result
end

--- Native selector with live filtering + preview (Telescope-style)
---@param prompt string
---@param items loop.SelectorItem[]
---@param formatter? fun(data:any):string
---@param callback loop.SelectorCallback
function M.select(prompt, items, formatter, callback)
  if #items == 0 then return callback(nil) end

  formatter = formatter or function(v)
    return type(v) == "table" and vim.inspect(v) or tostring(v)
  end

  -- Layout
  local width  = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local list_w = math.floor(width * 0.5)
  local prev_w = width - list_w - 2
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  -- State
  local query = ""
  local filtered = vim.deepcopy(items)
  local cursor_idx = 1

  -- Create buffers
  local prompt_buf = vim.api.nvim_create_buf(false, true)
  local list_buf   = vim.api.nvim_create_buf(false, true)
  local prev_buf   = vim.api.nvim_create_buf(false, true)

  -- Create windows
  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor", style = "minimal", border = "single",
    width = width, height = 1, row = row - 2, col = col,
  })

  local list_win = vim.api.nvim_open_win(list_buf, false, {
    relative = "editor", style = "minimal", border = "single",
    width = list_w, height = height, row = row, col = col,
  })

  local prev_win = vim.api.nvim_open_win(prev_buf, false, {
    relative = "editor", style = "minimal", border = "single",
    width = prev_w, height = height, row = row, col = col + list_w + 2,
  })

  vim.bo[list_buf].filetype = "loop-selector-list"
  vim.bo[prev_buf].filetype = "json"

  local function update_prompt()
    local text = query == "" and prompt or (prompt .. " > " .. query)
    vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { text })
    vim.api.nvim_buf_add_highlight(prompt_buf, -1, "Title", 0, 0, -1)
    pcall(vim.api.nvim_win_set_cursor, prompt_win, { 1, #text })
  end

  local function update_list()
    local lines = {}
    for i, item in ipairs(filtered) do
      lines[i] = (i == cursor_idx and "> " or "  ") .. item.label
    end
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    pcall(vim.api.nvim_win_set_cursor, list_win, { cursor_idx, 0 })
  end

  local function update_preview()
    local item = filtered[cursor_idx]
    if not item then
      vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, { "" })
      return
    end
    local ok, text = pcall(formatter, item.data)
    local lines = vim.split(ok and text or "<formatter error>", "\n")
    vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, lines)
  end

  local function rerender()
    filtered = fuzzy_filter(items, query)
    cursor_idx = #filtered > 0 and math.min(cursor_idx, #filtered) or 1
    update_prompt()
    update_list()
    update_preview()
  end

  local function close(result)
    for _, w in ipairs({ prompt_win, list_win, prev_win }) do
      if vim.api.nvim_win_is_valid(w) then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
    callback(result)
  end

  local function move(delta)
    if #filtered == 0 then return end
    cursor_idx = (cursor_idx - 1 + delta) % #filtered + 1
    rerender()
  end

  -- Initial render
  rerender()

  -- Keymaps (only in prompt buffer, insert mode)
  local opts = { buffer = prompt_buf, nowait = true, silent = true }

  vim.keymap.set("i", "<CR>",   function() close(filtered[cursor_idx] and filtered[cursor_idx].data or nil) end, opts)
  vim.keymap.set("i", "<Esc>",  function() close(nil) end, opts)
  vim.keymap.set("i", "<C-c>",  function() close(nil) end, opts)

  vim.keymap.set("i", "<C-n>",  function() move(1)  end, opts)
  vim.keymap.set("i", "<C-p>",  function() move(-1) end, opts)
  vim.keymap.set("i", "<Down>", function() move(1)  end, opts)
  vim.keymap.set("i", "<Up>",   function() move(-1) end, opts)

  vim.keymap.set("i", "<BS>", function()
    if #query > 0 then
      query = query:sub(1, -2)
      rerender()
    end
  end, opts)

  -- All printable characters
  for i = 32, 126 do
    local char = string.char(i)
    vim.keymap.set("i", char, function()
      query = query .. char
      rerender()
    end, opts)
  end

  -- Start in insert mode with blinking cursor
  vim.cmd("startinsert")
end

return M