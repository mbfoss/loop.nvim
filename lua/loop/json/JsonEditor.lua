-- ──────────────────────────────────────────────────────────────────────────────
--  Improvements summary (2025–2026 style)
-- ──────────────────────────────────────────────────────────────────────────────
-- • Better value input & smart coercion / parsing
-- • Support adding to arrays
-- • Rename key support
-- • Better schema awareness (const, enum, additionalProperties, required)
-- • Preserve fold state better
-- • More undo-friendly operations
-- • Basic array item insert / append
-- • Visual feedback when buffer is invalid JSON

local class        = require("loop.tools.class")
local ItemTreeComp = require("loop.comp.ItemTree")
local CompBuffer   = require('loop.buf.CompBuffer')
local floatwin     = require("loop.tools.floatwin")
local selector     = require("loop.tools.selector")
local validator    = require("loop.tools.jsonschema")
local json_util    = require("loop.tools.json")

---@class loop.JsonEditor
---@field new fun(self: loop.JsonEditor, opts:table): loop.JsonEditor
---@field inint fun(self: loop.JsonEditor)
---@field _filepath string
---@field _data table
---@field _schema table|nil
---@field _fold_cache table<string, boolean>
---@field _undo_stack table
---@field _redo_stack table
---@field _is_dirty boolean
---@field _on_node_added fun(path:string,callback:fun(nodes:any))|nil
local JsonEditor   = class()

local function is_array(t) return type(t) == "table" and vim.islist(t) end

local function value_type(v)
    local ty = type(v)
    if ty == "nil" then return "null" end
    if ty == "table" then return is_array(v) and "array" or "object" end
    if ty == "boolean" then return "boolean" end
    if ty == "number" then return "number" end
    if ty == "string" then return "string" end
    return "unknown"
end

local function join_path(base, key)
    if base == "" then return "/" .. key end
    return base .. "/" .. key
end

local function split_path(path)
    if path == "" or path == "/" then return {} end
    local parts = {}
    for p in path:gmatch("/([^/]+)") do
        table.insert(parts, vim.fn.fnamemodify(p, ":e") == "" and p or vim.fn.fnamemodify(p, ":r"))
    end
    return parts
end

local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deep_copy(v)
    end
    return copy
end

local function resolve_schema(schema, path)
    if not schema then return nil end
    if path == "" or path == "/" then return schema end

    local cur = schema
    for _, key in ipairs(split_path(path)) do
        if cur.type == "object" and cur.properties and cur.properties[key] then
            cur = cur.properties[key]
        elseif cur.type == "array" and cur.items then
            cur = cur.items
        elseif cur.additionalProperties then
            cur = cur.additionalProperties == true and {} or cur.additionalProperties
        else
            return nil
        end
    end
    return cur
end

local function smart_coerce(input, schema)
    if not schema or not schema.type then return input end

    local want = type(schema.type) == "table" and schema.type or { schema.type }
    input = vim.trim(input)

    if vim.tbl_contains(want, "null") and (input == "" or input:lower() == "null") then
        return vim.NIL
    end

    if vim.tbl_contains(want, "boolean") then
        local l = input:lower()
        if l == "true" or l == "yes" or l == "1" then return true end
        if l == "false" or l == "no" or l == "0" then return false end
    end

    if vim.tbl_contains(want, "integer") then
        local n = tonumber(input)
        if n and n == math.floor(n) then return n end
    end

    if vim.tbl_contains(want, "number") then
        local n = tonumber(input)
        if n then return n end
    end

    if vim.tbl_contains(want, "string") then
        return input
    end

    local ok, val = pcall(vim.json.decode, input)
    if ok then return val end

    return input
end

local function format_value(value, max_len)
    max_len = max_len or 50
    local s
    if type(value) == "string" then
        s = '"' .. vim.fn.escape(value, '"') .. '"'
    else
        s = vim.json.encode(value)
    end
    if #s > max_len then
        return s:sub(1, max_len - 3) .. "…"
    end
    return s
end

local function formatter(_, data, hls)
    if not data then return "" end

    local key   = tostring(data.key or "")
    local vt    = data.value_type
    local value = data.value
    local icon  = " "

    table.insert(hls, { group = "@property", start_col = #icon, end_col = #icon + #key })

    local line = icon .. key

    if vt == "object" or vt == "array" then
        local count = type(value) == "table" and #value or 0
        local bracket = vt == "object" and "{…}" or ("[…] (" .. count .. ")")
        line = line .. ": " .. bracket
    elseif vt == "string" then
        table.insert(hls, { group = "@string", start_col = #line + 2 })
        line = line .. ": " .. format_value(value, 40)
    elseif vt == "null" then
        table.insert(hls, { group = "@constant", start_col = #line + 2 })
        line = line .. ": null"
    elseif vt == "boolean" then
        table.insert(hls, { group = "@boolean", start_col = #line + 2 })
        line = line .. ": " .. tostring(value)
    else
        table.insert(hls, { group = "@number", start_col = #line + 2 })
        line = line .. ": " .. tostring(value)
    end

    if data.has_error then
        table.insert(hls, { group = "ErrorMsg", start_col = 0, end_col = #line })
    end

    return line
end

function JsonEditor:init(opts)
    self._opts              = opts or {}
    self._undo_stack        = {}
    self._redo_stack        = {}
    self._is_dirty          = false
    self._validation_errors = {}
    self._filepath          = opts.filepath
    self._schema            = opts.schema
    self._on_node_added     = opts.on_node_added
    self._fold_cache        = {}
end

function JsonEditor:open(winid)
    assert(not self._is_open)
    self._is_open  = true

    ---@type loop.comp.ItemTree
    ---@diagnostic disable-next-line: undefined-field
    self._itemtree = ItemTreeComp:new({
        formatter       = formatter,
        render_delay_ms = 40,
    })

    self:_reload_data_and_tree()

    self._itemtree:add_tracker({
        on_toggle = function(_, data, expanded)
            self._fold_cache[data.path or ""] = expanded
        end,
    })

    local buf = CompBuffer:new("jsoneditor", "JSON Editor")
    local ctrl = buf:make_controller()

    local function with_current_item(fn)
        local item = self._itemtree:get_cur_item(ctrl)
        if item then fn(item) end
    end

    buf:add_keymap("e", {
        desc = "Edit value (e)",
        callback = function()
            with_current_item(function(i) self:_edit_value(i) end)
        end
    })

    buf:add_keymap("E", {
        desc = "Rename key (E)",
        callback = function()
            with_current_item(function(i) self:_rename_key(i) end)
        end
    })

    buf:add_keymap("a", {
        desc = "Add property/item (a)",
        callback = function()
            with_current_item(function(i) self:_add_new(i) end)
        end
    })

    buf:add_keymap("d", {
        desc = "Delete (d)",
        callback = function()
            with_current_item(function(i) self:_delete(i) end)
        end
    })

    buf:add_keymap("s", { desc = "Save (s)", callback = function() self:save() end })

    buf:add_keymap("u", { desc = "Undo (u)", callback = function() self:undo() end })

    buf:add_keymap("<C-r>", { desc = "Redo (C-r)", callback = function() self:redo() end })

    buf:add_keymap("?", { desc = "Help (?)", callback = function() self:_show_help() end })

    buf:add_keymap("!", { desc = "Show errors (!)", callback = function() self:_show_errors() end })

    self._itemtree:link_to_buffer(ctrl)
    self._buf_ctrl = ctrl

    local bufid, _ = buf:get_or_create_buf()
    vim.api.nvim_win_set_buf(winid, bufid)
    vim.notify("JSON Editor opened. Press ? for help.", vim.log.levels.INFO)
end

function JsonEditor:_reload_data_and_tree()
    local ok, data = json_util.load_from_file(self._filepath)

    if not ok then
        vim.notify("Failed to load JSON: " .. tostring(data), vim.log.levels.WARN)
        return
    end

    self._data = data
    self:_validate_data()
    self:_reload_tree()
end

function JsonEditor:_validate_data()
    self._validation_errors = {}
    if self._schema then
        local errs = validator.validate(self._schema, self._data)
        if errs and #errs > 0 then
            self._validation_errors = errs
        end
    end
end

function JsonEditor:_reload_tree()
    self:_upsert_tree_items(self._data, "", nil, self._schema)
end

function JsonEditor:_upsert_tree_items(tbl, path, parent_id, parent_schema)
    if is_array(tbl) then
        for i, v in ipairs(tbl) do
            local str_i = tostring(i)
            local p = join_path(path, str_i)
            local id = parent_id and (parent_id .. "::" .. str_i) or str_i
            local item_schema = parent_schema and parent_schema.items or nil

            local item = {
                id = id,
                parent_id = parent_id,
                expanded = self._fold_cache[p] ~= false,
                data = {
                    key = "[" .. str_i .. "]",
                    path = p,
                    value = v,
                    value_type = value_type(v),
                    schema = item_schema,
                },
            }
            self._itemtree:upsert_item(item)
            if type(v) == "table" then
                self:_upsert_tree_items(v, p, id, item_schema)
            end
        end
    else
        local keys = vim.tbl_keys(tbl)
        table.sort(keys)

        for _, k in ipairs(keys) do
            if k == "$schema" then goto continue end

            local v = tbl[k]
            local p = join_path(path, k)
            local id = parent_id and (parent_id .. "::" .. k) or k

            local prop_schema = nil
            if parent_schema then
                if parent_schema.properties and parent_schema.properties[k] then
                    prop_schema = parent_schema.properties[k]
                elseif parent_schema.oneOf then
                    prop_schema = self:_resolve_oneof_schema(parent_schema.oneOf, v, k)
                elseif parent_schema.additionalProperties then
                    prop_schema = parent_schema.additionalProperties == true and {} or parent_schema
                        .additionalProperties
                end
            end

            local item = {
                id = id,
                parent_id = parent_id,
                expanded = self._fold_cache[p] ~= false,
                data = {
                    key = k,
                    path = p,
                    value = v,
                    value_type = value_type(v),
                    schema = prop_schema,
                },
            }
            self._itemtree:upsert_item(item)
            if type(v) == "table" then
                self:_upsert_tree_items(v, p, id, prop_schema)
            end
            ::continue::
        end
    end
end

function JsonEditor:_resolve_oneof_schema(one_of_schemas, value, key)
    for _, subschema in ipairs(one_of_schemas) do
        if subschema.properties and subschema.properties[key] then
            return subschema.properties[key]
        end
    end
    return nil
end

function JsonEditor:_edit_value(item)
    local path   = item.data.path
    local schema = item.data.schema or {}

    if schema.const ~= nil then
        vim.notify("Value is const = " .. vim.inspect(schema.const), vim.log.levels.WARN)
        return
    end

    if schema.enum then
        local choices = {}
        for _, v in ipairs(schema.enum) do
            table.insert(choices, { label = vim.inspect(v), data = v })
        end
        selector.select("Select value", choices, nil, function(choice)
            if choice then self:_set_value(path, choice) end
        end)
        return
    end

    local default = item.data.value_type == "string" and item.data.value
        or vim.json.encode(item.data.value)

    floatwin.input_at_cursor({
        title = "Edit value",
        default_text = default,
        on_confirm = function(txt)
            if txt == nil then return end
            local coerced = smart_coerce(txt, schema)
            self:_set_value(path, coerced)
        end,
    })
end

function JsonEditor:_rename_key(item)
    if item.data.path == "" then
        vim.notify("Cannot rename root", vim.log.levels.WARN)
        return
    end

    local parent_path = item.data.path:match("^(.*)/[^/]+$") or ""
    local schema = resolve_schema(self._schema, parent_path)
    if schema and schema.additionalProperties == false then
        vim.notify("Object does not allow additional properties", vim.log.levels.WARN)
        return
    end

    local old_key = item.data.key:match("^%[(%d+)%]$") or item.data.key

    floatwin.input_at_cursor({
        title = "New key name",
        default_text = old_key,
        on_confirm = function(newkey)
            if not newkey or newkey == "" or newkey == old_key then return end

            self:_push_undo()

            local parent, oldkey = self:_get_parent_and_key(item.data.path)
            if not parent then
                table.remove(self._undo_stack)
                return
            end
            if oldkey then
                local value = parent[oldkey]
                parent[oldkey] = nil
                parent[newkey] = value
            end
            self:_set_value("", self._data)
        end,
    })
end

function JsonEditor:_add_new(item)
    if self._on_node_added then
        self._on_node_added(item.data.path, function(to_add)
            if to_add ~= nil then
                self:_add_new_from_object(item, to_add)
            else
                self:_add_new_default(item)
            end
        end)
    else
        self:_add_new_default(item)
    end
end

function JsonEditor:_add_new_default(item)
    local path   = item.data.path
    local vt     = item.data.value_type
    local schema = resolve_schema(self._schema, path) or {}

    if vt == "array" then
        self:_add_array_item(item, schema)
    elseif vt == "object" then
        self:_add_object_property(item, schema)
    else
        vim.notify("Can only add to object or array", vim.log.levels.INFO)
    end
end

function JsonEditor:_add_new_from_object(item, to_add)
    local vt = item.data.value_type
    local path = item.data.path

    -- Add to array → append
    if vt == "array" then
        self:_push_undo()
        table.insert(item.data.value, to_add)
        self:_set_value(path, item.data.value)
        return
    end

    -- Add to object → merge keys
    if vt == "object" then
        self:_push_undo()
        local obj = item.data.value

        for k, v in pairs(to_add) do
            -- Do not overwrite existing keys
            if obj[k] == nil then
                obj[k] = v
            end
        end

        self:_set_value(path, obj)
        return
    end

    vim.notify("Can only add JSON object to object or array", vim.log.levels.INFO)
end

function JsonEditor:_delete(item)
    if item.data.path == "" then
        vim.notify("Cannot delete root", vim.log.levels.WARN)
        return
    end

    self:_push_undo()

    local parent, key = self:_get_parent_and_key(item.data.path)
    if not parent or key == nil then
        table.remove(self._undo_stack)
        return
    end

    parent[key] = nil
    self._itemtree:remove_item(item.id)

    local ok, err = json_util.save_to_file(self._filepath, self._data)
    if not ok then
        vim.notify("Failed to save: " .. tostring(err), vim.log.levels.ERROR)
        table.remove(self._undo_stack)
        return
    end

    self:_validate_data()
    vim.schedule(function() self:_reload_data_and_tree() end)
end

function JsonEditor:_add_array_item(item, schema)
    local item_schema = schema.items or {}
    local allowed_types = self:_get_allowed_types(item_schema)

    if #allowed_types == 0 then
        allowed_types = { "string", "number", "boolean", "null", "object", "array" }
    end

    if #allowed_types == 1 then
        self:_create_and_add_array_item(item, allowed_types[1], item_schema)
    else
        local choices = {}
        for _, t in ipairs(allowed_types) do
            table.insert(choices, { label = t, data = t })
        end
        selector.select("Select item type", choices, nil, function(choice)
            if choice then
                self:_create_and_add_array_item(item, choice, item_schema)
            end
        end)
    end
end

function JsonEditor:_create_and_add_array_item(item, type_choice, schema)
    local default_val = self:_create_default_value(type_choice, schema)

    if type_choice == "string" or type_choice == "number" or type_choice == "boolean" then
        floatwin.input_at_cursor({
            title = "New " .. type_choice .. " value",
            on_confirm = function(txt)
                if txt == nil then return end
                self:_push_undo()
                local arr = item.data.value
                local newval = smart_coerce(txt, schema)
                table.insert(arr, newval)
                self:_set_value(item.data.path, arr)
            end,
        })
    else
        self:_push_undo()
        local arr = item.data.value
        table.insert(arr, default_val)
        self:_set_value(item.data.path, arr)
    end
end

function JsonEditor:_add_object_property(item, schema)
    if schema.additionalProperties == false then
        vim.notify("Object does not allow additional properties", vim.log.levels.WARN)
        return
    end

    local suggested_keys = {}
    local key_schemas = {}
    local obj = item.data.value

    if schema.oneOf then
        -- Find which oneOf subschemas validate the current data
        local valid_schemas = {}
        for i, subschema in ipairs(schema.oneOf) do
            local errs = validator.validate(subschema, item.data.value)
            if not errs or #errs == 0 then
                table.insert(valid_schemas, { schema = subschema, index = i })
            end
        end

        -- Only collect properties from validating schemas
        for _, schema_info in ipairs(valid_schemas) do
            local subschema = schema_info.schema
            if subschema.properties then
                for k in pairs(subschema.properties) do
                    if obj[k] == nil and not key_schemas[k] then
                        key_schemas[k] = {}
                        table.insert(suggested_keys, k)
                    end
                    if obj[k] == nil then
                        table.insert(key_schemas[k],
                            { schema = subschema.properties[k], parent = subschema, index = schema_info.index })
                    end
                end
            end
        end
    elseif schema.properties then
        for k in pairs(schema.properties) do
            if obj[k] == nil then
                table.insert(suggested_keys, k)
                key_schemas[k] = { { schema = schema.properties[k], parent = schema, index = 1 } }
            end
        end
    end

    table.sort(suggested_keys)

    floatwin.input_at_cursor({
        title = "New property name",
        completions = suggested_keys,
        on_confirm = function(key)
            if not key or key == "" then return end
            local obj = item.data.value
            if obj[key] ~= nil then
                vim.notify("Key already exists", vim.log.levels.WARN)
                return
            end

            local matched_schemas = key_schemas[key]

            if matched_schemas and #matched_schemas > 1 then
                local choices = {}
                for _, schema_info in ipairs(matched_schemas) do
                    local name = schema_info.parent.__name or "<no name>"
                    table.insert(choices, {
                        label = name,
                        data = schema_info.schema
                    })
                end
                selector.select("Select schema for '" .. key .. "'", choices, nil, function(choice)
                    if choice then
                        self:_create_and_add_object_property(item, key, nil, choice)
                    end
                end)
                return
            end

            local prop_schema = (matched_schemas and matched_schemas[1] and matched_schemas[1].schema) or {}
            local allowed_types = self:_get_allowed_types(prop_schema)

            if #allowed_types == 0 then
                allowed_types = { "string", "number", "boolean", "null", "object", "array" }
            end

            -- Filter out null if option is enabled (default: true)
            local exclude_null = self._opts.exclude_null_from_property_type ~= false
            if exclude_null then
                local filtered = {}
                for _, t in ipairs(allowed_types) do
                    if t ~= "null" then
                        table.insert(filtered, t)
                    end
                end
                if #filtered > 0 then
                    allowed_types = filtered
                end
            end

            if #allowed_types == 1 then
                self:_create_and_add_object_property(item, key, allowed_types[1], prop_schema)
            else
                local choices = {}
                for _, t in ipairs(allowed_types) do
                    table.insert(choices, { label = t, data = t })
                end
                selector.select("Select property type", choices, nil, function(choice)
                    if choice then
                        self:_create_and_add_object_property(item, key, choice, prop_schema)
                    end
                end)
            end
        end,
    })
end

function JsonEditor:_create_and_add_object_property(item, key, type_choice, schema)
    local default_val = self:_create_default_value(type_choice, schema)

    if type_choice == "string" or type_choice == "number" or type_choice == "boolean" then
        floatwin.input_at_cursor({
            title = "Value for " .. key .. " (" .. type_choice .. ")",
            on_confirm = function(txt)
                if txt == nil then return end
                self:_push_undo()
                local obj = item.data.value
                local newval = smart_coerce(txt, schema)
                obj[key] = newval
                self:_set_value(item.data.path, obj)
            end,
        })
    else
        self:_push_undo()
        local obj = item.data.value
        obj[key] = default_val
        self:_set_value(item.data.path, obj)
    end
end

function JsonEditor:_get_allowed_types(schema)
    if not schema then return {} end

    if schema.const ~= nil then
        return { value_type(schema.const) }
    end

    if schema.enum then
        local types_set = {}
        for _, v in ipairs(schema.enum) do
            types_set[value_type(v)] = true
        end
        local types = {}
        for t in pairs(types_set) do
            table.insert(types, t)
        end
        return types
    end

    if schema.oneOf then
        local types_set = {}
        for _, subschema in ipairs(schema.oneOf) do
            if subschema.type then
                local t = subschema.type
                if type(t) == "table" then
                    for _, typ in ipairs(t) do
                        types_set[typ] = true
                    end
                else
                    types_set[t] = true
                end
            elseif subschema.const ~= nil then
                types_set[value_type(subschema.const)] = true
            end
        end
        local types = {}
        for t in pairs(types_set) do
            table.insert(types, t)
        end
        return types
    end

    if schema.type then
        if type(schema.type) == "table" then
            return schema.type
        else
            return { schema.type }
        end
    end

    return {}
end

function JsonEditor:_create_default_value(type_choice, schema)
    if type_choice == "null" then
        return vim.NIL
    elseif type_choice == "boolean" then
        return false
    elseif type_choice == "number" then
        return 0
    elseif type_choice == "string" then
        return ""
    elseif type_choice == "array" then
        return {}
    elseif type_choice == "object" then
        return vim.empty_dict()
    end
    return vim.NIL
end

function JsonEditor:_push_undo()
    table.insert(self._undo_stack, deep_copy(self._data))
    self._redo_stack = {}
    self._is_dirty = true
end

function JsonEditor:undo()
    if #self._undo_stack == 0 then
        vim.notify("Nothing to undo", vim.log.levels.INFO)
        return
    end

    table.insert(self._redo_stack, deep_copy(self._data))
    self._data = table.remove(self._undo_stack)

    local ok, err = json_util.save_to_file(self._filepath, self._data)
    if not ok then
        vim.notify("Failed to save: " .. tostring(err), vim.log.levels.ERROR)
        return
    end

    self:_validate_data()
    vim.schedule(function() self:_reload_data_and_tree() end)
end

function JsonEditor:redo()
    if #self._redo_stack == 0 then
        vim.notify("Nothing to redo", vim.log.levels.INFO)
        return
    end

    table.insert(self._undo_stack, deep_copy(self._data))
    self._data = table.remove(self._redo_stack)

    local ok, err = json_util.save_to_file(self._filepath, self._data)
    if not ok then
        vim.notify("Failed to save: " .. tostring(err), vim.log.levels.ERROR)
        return
    end

    self:_validate_data()
    vim.schedule(function() self:_reload_data_and_tree() end)
end

function JsonEditor:save()
    if self._schema then
        local errs = validator.validate(self._schema, self._data)
        if errs and #errs > 0 then
            vim.notify("Validation failed. Fix errors before saving.", vim.log.levels.WARN)
            return
        end
    end

    local ok, err = json_util.save_to_file(self._filepath, self._data)
    if not ok then
        vim.notify("Save failed: " .. tostring(err), vim.log.levels.ERROR)
    else
        self._is_dirty = false
        self._undo_stack = {}
        self._redo_stack = {}
        vim.notify("Saved: " .. self._filepath, vim.log.levels.INFO)
    end
end

function JsonEditor:_show_errors()
    if #self._validation_errors == 0 then
        vim.notify("No validation errors", vim.log.levels.INFO)
        return
    end

    local error_text = "=== Validation Errors ===\n\n"
    for i, err in ipairs(self._validation_errors) do
        error_text = error_text .. string.format("%d. %s\n", i, err)
    end

    floatwin.show_floatwin(error_text, { title = "Errors" })
end

function JsonEditor:_show_help()
    local help_text = {
        "=== JSON Editor Help ===",
        "",
        "Navigation:",
        "  <CR>     Toggle expand/collapse",
        "  j/k      Move up/down",
        "",
        "Editing:",
        "  e        Edit value",
        "  E        Rename key",
        "  a        Add property/item",
        "  d        Delete",
        "",
        "File:",
        "  s        Save",
        "  u        Undo",
        "  C-r      Redo",
        "",
        "Other:",
        "  !        Show validation errors",
        "  ?        Show this help",
    }
    floatwin.show_floatwin(table.concat(help_text, "\n"), { title = "Help" })
end

function JsonEditor:_get_parent_and_key(path)
    local parts = split_path(path)
    if #parts <= 1 then return nil, nil end

    local cur = self._data
    for i = 1, #parts - 1 do
        local idx = tonumber(parts[i])
        cur = cur[idx and idx or parts[i]]
    end

    local last = parts[#parts]
    local key = tonumber(last) and tonumber(last) or last
    return cur, key
end

function JsonEditor:_set_value(path, new_value)
    local parent, key = self:_get_parent_and_key(path)
    if not parent or key == nil then
        return
    end

    self:_push_undo()

    parent[key] = new_value

    local ok, err = json_util.save_to_file(self._filepath, self._data)
    if not ok then
        vim.notify("Failed to save: " .. tostring(err), vim.log.levels.ERROR)
        table.remove(self._undo_stack)
        return
    end

    self:_validate_data()
    vim.schedule(function() self:_reload_data_and_tree() end)
end

return JsonEditor
