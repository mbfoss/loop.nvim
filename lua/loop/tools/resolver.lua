local M = {}
local config = require('loop.config')

---@alias SimpleValue string | number | boolean | table

-- Simple data validation (unchanged, excellent as-is)
local function _is_simple_data(value, _seen)
  _seen = _seen or {}
  local t = type(value)
  if t == "string" or t == "number" or t == "boolean" then
    return true
  end
  if t ~= "table" then
    return false, ("unsupported type: %s"):format(t)
  end
  if _seen[value] then return true end
  _seen[value] = true

  for k, v in pairs(value) do
    local kt = type(k)
    if kt ~= "string" and kt ~= "number" then
      return false, ("table key must be string or number, got %s"):format(kt)
    end
    local ok, err = _is_simple_data(v, _seen)
    if not ok then
      return false, ("invalid value at key %s: %s"):format(vim.inspect(k), err)
    end
  end
  return true
end

local ESCAPE_MARKER = "\001"

-- Async-capable string expansion
local function _expand_string_async(str, callback)
  if type(str) ~= "string" then
    return callback(false, nil, "Input must be a string")
  end
  if str:find(ESCAPE_MARKER, 1, true) then
    return callback(false, nil, "String contains internal escape sequence")
  end

  -- Escape literal $${macro}
  local escaped = str:gsub("%$%${(.-)}", ESCAPE_MARKER .. "{%1}")

  -- Check if it's exactly one macro: "${name}"
  local single_macro = str:match("^%${([^}]+)}$")
  if single_macro then
    local fn = config.current.macros[single_macro]
    if not fn then
      return callback(false, nil, ("Unknown macro: ${%s}"):format(single_macro))
    end

    -- Support both sync and async macros
    local ok, result_or_err = pcall(fn)
    if not ok then
      return callback(false, nil, ("Macro crashed: ${%s}"):format(single_macro))
    end

    -- Async macro: fn(callback)
    if type(result_or_err) == "function" then
      result_or_err(function(value, err)
        if err then
          callback(false, nil, err)
        elseif not _is_simple_data(value) then
          callback(false, nil, ("Macro ${%s} returned invalid data"):format(single_macro))
        else
          callback(true, value)
        end
      end)
    else
      -- Sync macro: fn() → value
      local value = result_or_err
      if not _is_simple_data(value) then
        return callback(false, nil, ("Macro ${%s} returned invalid data"):format(single_macro))
      end
      callback(true, value)
    end
    return
  end

  -- Multiple macros → sequential async expansion
  local pending = 0
  local result = escaped
  local success = true
  local last_err = nil

  result = result:gsub("%${([^}]+)}", function(name)
    pending = pending + 1
    local placeholder = "\002" .. pending .. "\002"  -- unique placeholder

    local fn = config.current.macros[name]
    if not fn then
      success = false
      last_err = ("Unknown macro: ${%s}"):format(name)
      pending = pending - 1
      return placeholder
    end

    local function done(value, err)
      if not success then
        pending = pending - 1
        if pending == 0 then callback(success, result, last_err) end
        return
      end

      if err or value == nil then
        success = false
        last_err = err or ("Macro failed: ${%s}"):format(name)
      elseif type(value) ~= "string" then
        success = false
        last_err = ("Macro ${%s} returned non-string"):format(name)
      else
        result = result:gsub(placeholder, value, 1)
      end

      pending = pending - 1
      if pending == 0 then
        -- Restore escaped $${macro}
        result = result:gsub(ESCAPE_MARKER .. "{(.-)}", "${%1}")
        callback(success, result, last_err)
      end
    end

    -- Call macro (sync or async)
    local ok, ret = pcall(fn)
    if not ok then
      success = false
      last_err = ("Macro crashed: ${%s}"):format(name)
      pending = pending - 1
      if pending == 0 then callback(success, result, last_err) end
      return placeholder
    end

    if type(ret) == "function" then
      ret(done)  -- async: fn(cb)
    else
      done(ret)  -- sync: fn() → value
    end

    return placeholder
  end)

  if pending == 0 then
    result = result:gsub(ESCAPE_MARKER .. "{(.-)}", "${%1}")
    callback(success, result, last_err)
  end
end

---@param final_callback fun(success:boolean, err:string|nil)
local function _expand_table_async(tbl, seen, final_callback)
  seen = seen or {}
  if seen[tbl] then return final_callback(true) end
  seen[tbl] = true

  local keys_to_process = {}
  for k, v in pairs(tbl) do
    if type(v) == "string" then
      table.insert(keys_to_process, { key = k, value = v })
    elseif type(v) == "table" then
      table.insert(keys_to_process, { key = k, value = v, is_table = true })
    end
  end

  if #keys_to_process == 0 then
    return final_callback(true)
  end

  local pending = #keys_to_process
  local success = true
  local last_err = nil

  for _, item in ipairs(keys_to_process) do
    if item.is_table then
      _expand_table_async(item.value, seen, function(ok, err)
        if not ok then success = false; last_err = err or "table expansion failed" end
        pending = pending - 1
        if pending == 0 then final_callback(success, last_err) end
      end)
    else
      _expand_string_async(item.value, function(ok, expanded, err)
        if ok then
          tbl[item.key] = expanded
        else
          success = false
          last_err = err
        end
        pending = pending - 1
        if pending == 0 then final_callback(success, last_err) end
      end)
    end
  end
end

-- Public API
---@param tbl table
---@param callback fun(success:boolean, result_table:table|nil, err:string|nil)
function M.resolve_macros(tbl, callback)
  if not tbl or type(tbl) ~= "table" then
    return vim.schedule(function() callback(false, nil, "Input must be a table") end)
  end

  local tbl_copy = vim.deepcopy(tbl)  -- never mutate original
  _expand_table_async(tbl_copy, {}, function(success, err)
    vim.schedule(function()
      callback(success, success and tbl_copy or nil, err)
    end)
  end)
end

return M