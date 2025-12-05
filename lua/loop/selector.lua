---@class loop.SelectorItem
---@field label string
---@field data any
---@alias loop.SelectorCallback fun(data: any|nil)

local M = {}

local function fuzzy_filter(items, query)
  if query == "" then return vim.deepcopy(items) end
  local q = query:lower()
  local res = {}
  for _, item in ipairs(items) do
    if item.label:lower():find(q, 1, true) then table.insert(res, item) end
  end
  return res
end

--- Native selector – preview optional (pass formatter = nil to hide it)
function M.select(prompt, items, formatter, callback)
  if #items == 0 then return callback(nil) end

  local has_preview = type(formatter) == "function"
  formatter = formatter or function(v) return type(v)=="table" and vim.inspect(v) or tostring(v) end

  local width  = math.floor(vim.o.columns * (has_preview and 0.8 or 0.5))
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
    relative="editor", style="minimal", border="rounded",
    width=width, height=1, row=row-2, col=col,
  })

  local lwin = vim.api.nvim_open_win(lbuf, false, {
    relative="editor", style="minimal", border="rounded",
    width=list_w, height=height, row=row, col=col,
  })

  local vwin = has_preview and vim.api.nvim_open_win(vbuf, false, {
    relative="editor", style="minimal", border="rounded",
    width=prev_w, height=height, row=row, col=col + list_w,
  }) or nil

  vim.bo[lbuf].filetype = "loop-selector-list"
  if has_preview then vim.bo[vbuf].filetype = "json" end

  local function redraw()
    filtered = fuzzy_filter(items, query)
    cur = #filtered > 0 and math.min(cur, #filtered) or 1

    -- Prompt
    local ptext = prompt .. " > " .. query
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, { ptext })
    vim.api.nvim_buf_add_highlight(pbuf, -1, "Title", 0, 0, -1)
    pcall(vim.api.nvim_win_set_cursor, pwin, {1, #ptext})

    -- List
    local lines = {}
    for i, item in ipairs(filtered) do
      lines[i] = (i == cur and "> " or "  ") .. item.label
    end
    vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, lines)
    pcall(vim.api.nvim_win_set_cursor, lwin, {cur, 0})

    -- Preview (only if enabled)
    if has_preview and filtered[cur] then
      local ok, txt = pcall(formatter, filtered[cur].data)
      vim.api.nvim_buf_set_lines(vbuf, 0, -1, false,
        vim.split(ok and txt or "<error>", "\n"))
    end
  end

  local function close(res)
    for _, w in ipairs({pwin, lwin, vwin}) do
      if w and vim.api.nvim_win_is_valid(w) then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
    callback(res)
  end

  local function move(d)
    if #filtered == 0 then return end
    cur = (cur - 1 + d) % #filtered + 1
    redraw()
  end

  redraw()

  local opts = {buffer = pbuf, nowait = true, silent = true}

  vim.keymap.set("i", "<CR>",   function() close(filtered[cur] and filtered[cur].data or nil) end, opts)
  vim.keymap.set("i", "<Esc>",  function() close(nil) end, opts)
  vim.keymap.set("i", "<C-c>",  function() close(nil) end, opts)
  vim.keymap.set("i", "<C-n>",  function() move(1)  end, opts)
  vim.keymap.set("i", "<C-p>",  function() move(-1) end, opts)
  vim.keymap.set("i", "<Down>", function() move(1)  end, opts)
  vim.keymap.set("i", "<Up>",   function() move(-1) end, opts)

  vim.keymap.set("i", "<BS>", function()
    if #query > 0 then query = query:sub(1,-2); redraw() end
  end, opts)

  for i = 32, 126 do
    local c = string.char(i)
    vim.keymap.set("i", c, function() query = query .. c; redraw() end, opts)
  end

  vim.cmd("startinsert")
end

return M