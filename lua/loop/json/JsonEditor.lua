local class        = require("loop.tools.class")
local ItemTreeComp = require("loop.comp.ItemTree")
local CompBuffer   = require('loop.buf.CompBuffer')
local floatwin     = require("loop.tools.floatwin")
local selector     = require("loop.tools.selector")
local validator    = require("loop.tools.jsonschema")

---@class loop.JsonEditor
---@field new fun(self: loop.JsonEditor): loop.JsonEditor
---@field _buf number
---@field _filepath string
---@field _data table
---@field _schema table|nil
---@field _layout_cache table<string, boolean>
local JsonEditor   = class()

-----------------------------------------------------------------------
-- Utilities
-----------------------------------------------------------------------

local function is_array(t)
    return type(t) == "table" and vim.islist(t)
end

local function value_type(v)
    if v == nil then return "null" end
    if type(v) == "table" then
        return is_array(v) and "array" or "object"
    end
    return type(v)
end

local function join_path(base, key)
    if base == "" then
        return "/" .. key
    end
    return base .. "/" .. key
end

local function split_path(path)
    local parts = {}
    for p in path:gmatch("/([^/]+)") do
        table.insert(parts, p)
    end
    return parts
end

-----------------------------------------------------------------------
-- Schema resolution
-----------------------------------------------------------------------

local function resolve_schema(schema, path)
    if not schema or path == "" then
        return schema
    end

    local cur = schema
    for _, key in ipairs(split_path(path)) do
        if cur.type == "object" and cur.properties then
            cur = cur.properties[key]
        elseif cur.type == "array" and cur.items then
            cur = cur.items
        else
            return nil
        end
        if not cur then return nil end
    end

    return cur
end

-----------------------------------------------------------------------
-- Type coercion
-----------------------------------------------------------------------

local function coerce_value(input, schema)
    if not schema or not schema.type then
        return input
    end

    local types = type(schema.type) == "table" and schema.type or { schema.type }

    for _, t in ipairs(types) do
        if t == "number" then
            local n = tonumber(input)
            if n ~= nil then return n end
        elseif t == "boolean" then
            if input == "true" then return true end
            if input == "false" then return false end
        elseif t == "null" then
            if input == "null" then return nil end
        elseif t == "string" then
            return input
        end
    end

    return input
end

-----------------------------------------------------------------------
-- Formatter
-----------------------------------------------------------------------

local function formatter(_, data, hls)
    if not data then return "" end

    local key = tostring(data.key)
    local vt  = data.value_type
    local val = data.value

    table.insert(hls, { group = "@property", start_col = 0, end_col = #key })

    if vt == "object" then
        return key .. ": { }"
    elseif vt == "array" then
        return key .. ": [ ]"
    elseif vt == "string" then
        table.insert(hls, { group = "@string", start_col = #key + 2 })
        return key .. ': "' .. val .. '"'
    elseif vt == "null" then
        table.insert(hls, { group = "@constant", start_col = #key + 2 })
        return key .. ": null"
    else
        table.insert(hls, { group = "@constant", start_col = #key + 2 })
        return key .. ": " .. tostring(val)
    end
end

-----------------------------------------------------------------------
-- Init / binding
-----------------------------------------------------------------------

function JsonEditor:init()
end

function JsonEditor:open(winid, filepath, schema)
    assert(not self._is_open)
    self._is_open = true

    self._itemtree =
        ItemTreeComp:new({
            formatter = formatter,
            render_delay_ms = 50,
        })

    self._filepath = filepath
    self._schema = schema
    self._layout_cache = {}

    self:_init_buffer()
    self:_reload_from_buffer()

    self._itemtree:add_tracker({
        on_toggle = function(_, data, expanded)
            self._layout_cache[data.path] = expanded
        end,
    })

    local comp_buf = CompBuffer:new("jsoneditor", "JSON Editor")
    local comp_buf_ctrl = comp_buf:make_controller()
    comp_buf:add_keymap("e", {
        desc = "Edit value",
        callback = function()
            local item = self._itemtree:get_cur_item(comp_buf_ctrl)
            if item then self:_edit_value(item) end
        end,
    })
    comp_buf:add_keymap("a", {
        desc = "Add property",
        callback = function()
            local item = self._itemtree:get_cur_item(comp_buf_ctrl)
            if item and item.data.value_type == "object" then
                self:_add_property(item)
            end
        end,
    })

    comp_buf:add_keymap("d", {
        desc = "Delete property",
        callback = function()
            local item = self._itemtree:get_cur_item(comp_buf_ctrl)
            if item then self:_delete(item) end
        end,
    })

    comp_buf:add_keymap("s", {
        desc = "Save JSON",
        callback = function() self:save() end,
    })

    self._itemtree:link_to_buffer(comp_buf_ctrl)

    vim.api.nvim_win_set_buf(winid, (comp_buf:get_or_create_buf()))
end

function JsonEditor:_init_buffer()
    self._buf = vim.api.nvim_create_buf(false, true)
    vim.bo[self._buf].buftype = ""
    vim.bo[self._buf].filetype = "json"
    vim.bo[self._buf].swapfile = false

    local lines = vim.fn.readfile(self._filepath)
    vim.api.nvim_buf_set_lines(self._buf, 0, -1, false, lines)
end

-----------------------------------------------------------------------
-- Buffer <-> data sync
-----------------------------------------------------------------------

function JsonEditor:_reload_from_buffer()
    local text = table.concat(
        vim.api.nvim_buf_get_lines(self._buf, 0, -1, false),
        "\n"
    )

    local ok, decoded = pcall(vim.json.decode, text)
    if not ok then return end

    self._data = decoded
    self:_reload_tree()
end

function JsonEditor:_write_buffer()
    local text = vim.json.encode(self._data, { indent = true })
    vim.api.nvim_buf_set_lines(
        self._buf,
        0,
        -1,
        false,
        vim.split(text, "\n")
    )
end

-----------------------------------------------------------------------
-- Tree loading
-----------------------------------------------------------------------

function JsonEditor:_reload_tree()
    self._itemtree:clear_items()
    self._itemtree:upsert_item({
        id = "root",
        expanded = true,
        data = {
            key = "root",
            path = "",
            value = self._data,
            value_type = value_type(self._data),
        },
        children_callback = function(cb)
            self:_load_children(self._data, "", "root", cb)
        end,
    })
end

function JsonEditor:_load_children(tbl, path, parent_id, cb)
    local items = {}

    for k, v in pairs(tbl) do
        local p = join_path(path, tostring(k))
        local id = parent_id .. "::" .. tostring(k)

        local item = {
            id = id,
            parent_id = parent_id,
            expanded = self._layout_cache[p],
            data = {
                key = k,
                path = p,
                value = v,
                value_type = value_type(v),
            },
        }

        if type(v) == "table" then
            item.children_callback = function(child_cb)
                self:_load_children(v, p, id, child_cb)
            end
        end

        table.insert(items, item)
    end

    cb(items)
end

-----------------------------------------------------------------------
-- Editing helpers
-----------------------------------------------------------------------

function JsonEditor:_resolve_parent(path)
    local parts = split_path(path)
    local cur = self._data
    for i = 1, #parts - 1 do
        cur = cur[parts[i]]
    end
    return cur, parts[#parts]
end

function JsonEditor:_apply_edit(path, value)
    local parent, key = self:_resolve_parent(path)
    parent[key] = value
    self:_write_buffer()

    local errs = self._schema and validator.validate(self._schema, self._data)
    if errs then
        vim.cmd("undo")
        floatwin.show_floatwin(table.concat(errs, "\n"), {
            title = "Schema validation failed",
        })
        return
    end

    self:_reload_from_buffer()
end

-----------------------------------------------------------------------
-- Edit value
-----------------------------------------------------------------------

function JsonEditor:_edit_value(item)
    local path = item.data.path
    local schema = resolve_schema(self._schema, path)

    if schema and schema.const ~= nil then
        return
    end

    if schema and schema.enum then
        local items = {}
        for _, v in ipairs(schema.enum) do
            table.insert(items, { label = tostring(v), data = v })
        end
        selector.select("Select value", items, nil, function(v)
            self:_apply_edit(path, v)
        end)
        return
    end

    if schema and schema.oneOf then
        local items = {}
        for i, s in ipairs(schema.oneOf) do
            table.insert(items, {
                label = s.title or ("Option " .. i),
                data = s,
            })
        end
        selector.select(
            "Select schema",
            items,
            function(s) return vim.inspect(s), "" end,
            function(subschema)
                self:_edit_value({
                    data = item.data,
                    _schema_override = subschema,
                })
            end
        )
        return
    end

    floatwin.input_at_cursor({
        default_text = tostring(item.data.value),
        on_confirm = function(txt)
            if txt == nil then return end
            local coerced = coerce_value(txt, schema)
            self:_apply_edit(path, coerced)
        end,
    })
end

-----------------------------------------------------------------------
-- Add / delete
-----------------------------------------------------------------------

function JsonEditor:_add_property(item)
    local schema = resolve_schema(self._schema, item.data.path)
    if schema and schema.additionalProperties == false then
        return
    end

    floatwin.input_at_cursor({
        title = "Property name",
        on_confirm = function(key)
            if not key or key == "" then return end
            self:_apply_edit(join_path(item.data.path, key), "")
        end,
    })
end

function JsonEditor:_delete(item)
    local parent, key = self:_resolve_parent(item.data.path)
    local schema = resolve_schema(self._schema, item.data.path:match("(.+)/[^/]+$") or "")

    if schema and schema.required then
        for _, r in ipairs(schema.required) do
            if r == key then return end
        end
    end

    parent[key] = nil
    self:_write_buffer()
    self:_reload_from_buffer()
end

-----------------------------------------------------------------------
-- Save
-----------------------------------------------------------------------

function JsonEditor:save()
    local errs = self._schema and validator.validate(self._schema, self._data)
    if errs then
        floatwin.show_floatwin(table.concat(errs, "\n"), {
            title = "Validation failed",
        })
        return
    end

    vim.fn.writefile(
        vim.api.nvim_buf_get_lines(self._buf, 0, -1, false),
        self._filepath
    )
end

return JsonEditor
