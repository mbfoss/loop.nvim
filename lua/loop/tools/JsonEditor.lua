local class        = require("loop.tools.class")
local ItemTreeComp = require("loop.comp.ItemTree")
local CompBuffer   = require("loop.buf.CompBuffer")
local floatwin     = require("loop.tools.floatwin")
local selector     = require("loop.tools.selector")
local validator    = require("loop.tools.jsonschema")
local json_util    = require("loop.tools.json")
local file_util    = require("loop.tools.file")

---@alias JsonPrimitive string|number|boolean|nil
---@alias JsonValue JsonPrimitive|table

---@class loop.JsonEditorOpts
---@field name? string
---@field filepath string
---@field schema? table
---@field on_data_open? fun(data:table):any
---@field on_node_added? fun(path:string,callback:fun(to_add:any|nil))
---@field exclude_null_from_property_type? boolean

---@class loop.JsonEditor
---@field _opts loop.JsonEditorOpts
---@field _filepath string
---@field _data table
---@field _schema table|nil
---@field _fold_cache table<string, boolean>
---@field _undo_stack table[]
---@field _redo_stack table[]
---@field _validation_errors loop.json.ValidationError[]
---@field _is_dirty boolean
---@field _on_node_added fun(path:string,callback:fun(nodes:any))|nil
---@field _itemtree loop.comp.ItemTree
---@field _buf_ctrl any
---@field _is_open boolean
local JsonEditor   = class()

---@param t any
---@return boolean
local function is_array(t)
    return type(t) == "table" and vim.islist(t)
end

---@param v any
---@return string
local function value_type(v)
    local ty = type(v)
    if ty == "nil" then return "null" end
    if ty == "table" then return is_array(v) and "array" or "object" end
    if ty == "boolean" then return "boolean" end
    if ty == "number" then return "number" end
    if ty == "string" then return "string" end
    return "unknown"
end

---@param base string
---@param key string
---@return string
local function join_path(base, key)
    if base == "" then return "/" .. key end
    return base .. "/" .. key
end

---@param path string
---@return string[]
local function split_path(path)
    if path == "" or path == "/" then
        return {}
    end

    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    return parts
end


---@generic T
---@param t T
---@return T
local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deep_copy(v)
    end
    return copy
end


---@param value any
---@param schema table|nil
---@return table|nil
function _resolve_oneof_schema(value, schema)
    if schema and schema.oneOf then
        for _, subschema in ipairs(schema.oneOf) do
            local errs = validator.validate(subschema, value)
            if not errs then
                return subschema
            end
        end
        return nil
    end
    return schema
end

---@param schema table|nil
---@param value any
---@param path string
---@return table|nil
local function _resolve_schema(schema, value, path)
    if not schema then return nil end
    if path == "" or path == "/" then
        return _resolve_oneof_schema(value, schema)
    end

    local cur_schema = schema
    local cur_value  = value

    for _, key in ipairs(split_path(path)) do
        -- Resolve oneOf at current level using the ACTUAL value
        cur_schema = _resolve_oneof_schema(cur_value, cur_schema) or cur_schema

        if cur_schema.type == "object"
            and cur_schema.properties
            and cur_schema.properties[key]
        then
            cur_schema = cur_schema.properties[key]
            cur_value  = type(cur_value) == "table" and cur_value[key] or nil
        elseif cur_schema.type == "array"
            and cur_schema.items
        then
            cur_schema = cur_schema.items
            local idx = tonumber(key)
            cur_value = (idx and type(cur_value) == "table") and cur_value[idx] or nil
        elseif cur_schema.additionalProperties then
            cur_schema =
                cur_schema.additionalProperties == true
                and {}
                or cur_schema.additionalProperties
            cur_value = type(cur_value) == "table" and cur_value[key] or nil
        else
            return nil
        end
    end

    -- Final oneOf resolution
    return _resolve_oneof_schema(cur_value, cur_schema) or cur_schema
end


---@param keys string[]
---@param schema table|nil
local function _order_keys(keys, schema)
    local order = type(schema) == "table" and schema.__order or nil
    if not order then
        vim.fn.sort(keys)
        return
    end

    local ordered = {}
    for i = 1, #order do
        ordered[i] = order[i]
    end

    local priorities = {}
    for i, v in ipairs(ordered) do
        priorities[v] = i
    end

    local index = #ordered + 1
    for _, v in ipairs(keys) do
        if not priorities[v] then
            priorities[v] = index
            index = index + 1
        end
    end

    table.sort(keys, function(a, b)
        return priorities[a] < priorities[b]
    end)
end

---@param input string
---@param schema table|nil
---@return any
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
        if n then return n else return vim.NIL end
    end

    if vim.tbl_contains(want, "string") then
        return input
    end

    local ok, val = pcall(vim.json.decode, input)
    if ok then return val end

    return input
end

---@param _ any
---@param data table
---@return string,loop.Highlight[]?,loop.comp.ItemTree.VirtText[]?
local function _formatter(_, data)
    ---@type loop.Highlight[]
    local hls = {}

    if not data then return "" end

    local key     = tostring(data.key or "")
    local vt      = data.value_type
    local value   = data.value
    local err_msg = data.err_msg

    table.insert(hls, { group = "@property", start_col = 0, end_col = #key })
    local line = key

    if vt == "object" or vt == "array" then
        local count = type(value) == "table" and #value or 0
        local bracket = vt == "object" and "{…}" or ("[…] (" .. count .. ")")
        line = line .. ": " .. bracket
    elseif vt == "string" then
        table.insert(hls, { group = "@string", start_col = #line + 2 })
        line = line .. ": " .. value
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

    ---@type loop.comp.ItemTree.VirtText[]
    local virt_text = {}
    if err_msg then
        table.insert(virt_text, { text = "  " .. err_msg, highlight = "DiagnosticWarn" })
    else
        table.insert(virt_text, { text = vt, highlight = "Comment" })
    end
    return line, hls, virt_text
end

---@param opts loop.JsonEditorOpts
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
    self._is_open     = true

    local name        = self._opts.name or "JSON Editor"
    local header_line = " (For help: g?)"


    ---@type loop.comp.ItemTree
    ---@diagnostic disable-next-line: undefined-field
    self._itemtree = ItemTreeComp:new({
        formatter       = _formatter,
        render_delay_ms = 40,
    })

    self:_reload_data_and_tree()

    self._itemtree:add_tracker({
        on_toggle = function(_, data, expanded)
            self._fold_cache[data.path or ""] = expanded
        end,
    })

    local buf = CompBuffer:new("jsoneditor", name)
    local ctrl = buf:make_controller()

    local function with_current_item(fn)
        local item = self._itemtree:get_cur_item(ctrl)
        if item then fn(item) end
    end

    buf:add_keymap("c", {
        desc = "Change value",
        callback = function()
            with_current_item(function(i) self:_edit_value(i) end)
        end
    })

    buf:add_keymap("C", {
        desc = "Change value (multiline)",
        callback = function()
            with_current_item(function(i) self:_edit_value(i, true) end)
        end
    })

    buf:add_keymap("a", {
        desc = "Add property/item",
        callback = function()
            with_current_item(function(i) self:_add_new(i) end)
        end
    })

    buf:add_keymap("d", {
        desc = "Delete",
        callback = function()
            with_current_item(function(i) self:_delete(i) end)
        end
    })

    buf:add_keymap("s", { desc = "Save (s)", callback = function() self:save() end })

    buf:add_keymap("u", { desc = "Undo (u)", callback = function() self:undo() end })

    buf:add_keymap("<C-r>", { desc = "Redo (C-r)", callback = function() self:redo() end })

    buf:add_keymap("g?", { desc = "Help (?)", callback = function() self:_show_help() end })

    buf:add_keymap("ge", { desc = "Show errors (!)", callback = function() self:_show_errors() end })

    self._itemtree:link_to_buffer(ctrl)
    self._buf_ctrl = ctrl

    local bufid, _ = buf:get_or_create_buf()
    vim.api.nvim_win_set_buf(winid, bufid)
end

function JsonEditor:_reload_data_and_tree()
    local ok, data = json_util.load_from_file(self._filepath)

    if not ok then
        if file_util.file_exists(self._filepath) then
            vim.notify("Failed to load JSON: " .. tostring(data), vim.log.levels.WARN)
            return
        else
            data = {}
        end
    end

    if self._opts.on_data_open then
        local ret = self._opts.on_data_open(data)
        if ret ~= nil then data = ret end
    end

    self._data = data
    self:_reload_tree()
end

function JsonEditor:_reload_tree()
    self._validation_errors = {}
    ---@type table<string, string>
    local errors = {}
    if self._schema then
        local validation_errors = validator.validate2(self._schema, self._data)
        if validation_errors then
            self._validation_errors = validation_errors
            for _, e in ipairs(validation_errors) do
                errors['/' .. e.path] = e.err_msg:gsub("\n", " ")
            end
        end
    end
    self:_upsert_tree_items(self._data, "", nil, self._schema, errors)
end

---@param tbl table
---@param path string
---@param parent_id string?
---@param parent_schema table?
---@param errors {string:string}
function JsonEditor:_upsert_tree_items(tbl, path, parent_id, parent_schema, errors)
    assert(type(tbl) == "table")
    ---@type loop.comp.ItemTree.Item[]
    local items = {}

    parent_schema = _resolve_oneof_schema(tbl, parent_schema)

    if is_array(tbl) then
        for i, v in ipairs(tbl) do
            local str_i = tostring(i)
            local p = join_path(path, str_i)
            local id = parent_id and (parent_id .. "/" .. str_i) or str_i
            local item_schema = parent_schema and parent_schema.items or nil
            local e = errors[p]
            ---@type loop.comp.ItemTree.Item
            local item = {
                id = id,
                expanded = self._fold_cache[p] ~= false,
                data = {
                    key = "[" .. str_i .. "]",
                    path = p,
                    value = v,
                    err_msg = e,
                    value_type = value_type(v),
                    schema = item_schema,
                },
            }
            table.insert(items, item)
        end
    else
        local keys = vim.tbl_keys(tbl)
        _order_keys(keys, parent_schema)
        for _, k in ipairs(keys) do
            if k == "$schema" then goto continue end

            local v = tbl[k]
            local p = join_path(path, k)
            local id = parent_id and (parent_id .. "/" .. k) or k
            local prop_schema = nil
            local e = errors[p]
            if parent_schema then
                if parent_schema.properties and parent_schema.properties[k] then
                    prop_schema = parent_schema.properties[k]
                end
                if prop_schema then
                    if prop_schema.additionalProperties == nil then
                        prop_schema.additionalProperties = parent_schema.additionalProperties
                    end
                end
            end
            ---@type loop.comp.ItemTree.Item
            local item = {
                id = id,
                parent_id = parent_id,
                expanded = self._fold_cache[p] ~= false,
                data = {
                    key = k,
                    path = p,
                    value = v,
                    err_msg = e,
                    value_type = value_type(v),
                    schema = prop_schema,
                },
            }
            table.insert(items, item)
            ::continue::
        end
    end

    self._itemtree:update_children(parent_id, items)
    for _, item in ipairs(items) do
        if type(item.data.value) == "table" then
            local data = item.data
            self:_upsert_tree_items(data.value, data.path, item.id, data.schema, errors)
        end
    end
end

function JsonEditor:_edit_value(item, multiline)
    local path   = item.data.path
    local schema = item.data.schema or {}

    if not item.data.value or type(item.data.value) == "table" then return end

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

    local opts = {
        title = ("value of '%s'"):format(tostring(item.data.key or "")),
        default_text = default,
        on_confirm = function(txt)
            if txt == nil then return end
            local coerced = smart_coerce(txt, schema)
            self:_set_value(path, coerced)
        end,
    }
    if multiline then
        floatwin.input_multiline(opts)
    else
        floatwin.input_at_cursor(opts)
    end
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
    local schema = _resolve_schema(self._schema, self._data, path) or {}
    
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

    if vim.islist(parent) then
        table.remove(parent, tonumber(key))
    else
        parent[key] = nil
    end

    local ok, err = json_util.save_to_file(self._filepath, self._data)
    if not ok then
        vim.notify("Failed to save: " .. tostring(err), vim.log.levels.ERROR)
        table.remove(self._undo_stack)
        return
    end

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
            if item.data.value[key] ~= nil then
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
    end
end

function JsonEditor:_show_errors()
    if #self._validation_errors == 0 then
        vim.notify("No validation errors", vim.log.levels.INFO)
        return
    end

    local error_text = "=== Validation Errors ===\n\n"
    for i, err in ipairs(self._validation_errors) do
        error_text = error_text .. string.format("%d. at '%s': %s\n", i, err.path, err.err_msg)
    end

    floatwin.show_floatwin(error_text, { title = "Errors" })
end

function JsonEditor:_show_help()
    local help_text = {
        "Navigation:",
        "  <CR>     Toggle expand/collapse",
        "  j/k      Move up/down",
        "",
        "Editing:",
        "  a        Add property/item",
        "  c        Change value",
        "  d        Delete",
        "",
        "File:",
        "  s        Save",
        "  u        Undo",
        "  C-r      Redo",
        "",
        "Other:",
        "  !        Show validation errors",
        "  g?       Show this help",
    }
    floatwin.show_floatwin(table.concat(help_text, "\n"), { title = "Help" })
end

function JsonEditor:_get_parent_and_key(path)
    local parts = split_path(path)
    if #parts < 1 then return nil, nil end

    local cur = self._data
    for i = 1, #parts - 1 do
        local idx = tonumber(parts[i])
        cur = cur[idx and idx or parts[i]]
    end

    local last = parts[#parts]
    local numkey = tonumber(last)
    local key = numkey or last
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

    vim.schedule(function() self:_reload_data_and_tree() end)
end

return JsonEditor
