local class = require("loop.tools.class")
local ItemTreeComp = require("loop.comp.ItemTree")
local CompBuffer = require("loop.buf.CompBuffer")
local floatwin = require("loop.tools.floatwin")
local selector = require("loop.tools.selector")
local validator = require("loop.tools.jsonschema")
local json_util = require("loop.tools.json")
local file_util = require("loop.tools.file")
local strtools = require("loop.tools.strtools")

---@alias JsonPrimitive string|number|boolean|nil
---@alias JsonValue JsonPrimitive|table<string,JsonValue>|JsonValue[]

---@class loop.JsonEditorOpts
---@field name string?
---@field filepath string?
---@field schema table?
---@field on_data_open fun(data:table):table?
---@field on_node_added fun(path:string, callback:fun(to_add:any|nil))?
---@field null_support boolean?

---@class loop.JsonEditor
---@field new fun(self:loop.JsonEditor,opts:loop.JsonEditorOpts)
---@field _opts loop.JsonEditorOpts
---@field _filepath string
---@field _data table
---@field _schema table|nil
---@field _fold_cache table<string, boolean>
---@field _undo_stack table[]
---@field _redo_stack table[]
---@field _validation_errors loop.json.ValidationError[]
---@field _is_dirty boolean
---@field _on_node_added fun(path:string, callback:fun(nodes:any))|nil
---@field _itemtree loop.comp.ItemTree
---@field _buf_ctrl any
---@field _is_open boolean
local JsonEditor = class()

---Determine displayed type name for tree rendering
---@param v any
---@return string
local function _value_type(v)
    local ty = type(v)
    if ty == "table" then
        return vim.islist(v) and "array" or "object"
    end
    if ty == "boolean" then return "boolean" end
    if ty == "number" then return "number" end
    if ty == "string" then return "string" end
    if v == vim.NIL then return "null" end
    return "unknown"
end

---@param value any
---@param schema table|nil
---@return table|nil
local function _resolve_oneof_schema(value, schema)
    if not (schema and schema.oneOf) then
        return schema
    end

    for _, subschema in ipairs(schema.oneOf) do
        local errs = validator.validate(subschema, value)
        if not errs then
            return subschema
        end
    end
    return nil
end

---@param dest table|nil
---@param src table|nil
local function _merge_additional_properties(dest, src)
    if not dest then return end
    if dest.additionalProperties == nil
        and type(src) == "table"
        and type(src.additionalProperties) == "boolean" then
        dest.additionalProperties = src.additionalProperties
    end
end

---@param keys string[]
---@param schema table|nil
local function _order_keys(keys, schema)
    vim.fn.sort(keys) -- initial alphabetic sort
    local order = type(schema) == "table" and schema.__order or nil
    if order then
        strtools.order_strings(keys, order)
    end
end

---@param input string
---@param wanted_type string
---@return any
local function _smart_coerce(input, wanted_type)
    assert(type(input) == "string")
    assert(type(wanted_type) == "string")

    if wanted_type == "null" and (input == "" or input:lower() == "null") then
        return vim.NIL
    end

    if wanted_type == "boolean" then
        local l = input:lower()
        if l == "true" or l == "yes" or l == "1" then return true end
        if l == "false" or l == "no" or l == "0" then return false end
        return nil
    end

    if wanted_type == "integer" then
        local n = tonumber(input)
        if n and n == math.floor(n) then return n end
        return nil
    end

    if wanted_type == "number" then
        return tonumber(input)
    end

    -- fallback: string
    return input
end

---@param _ any
---@param data table
---@return string
---@return loop.Highlight[]?
---@return loop.comp.ItemTree.VirtText[]?
local function _formatter(_, data)
    ---@type loop.Highlight[]
    local hls = {}
    ---@type loop.comp.ItemTree.VirtText[]
    local virt_text = {}

    if not data then return "", hls, virt_text end

    local key = tostring(data.key or "")
    local vt = data.value_type
    local value = data.value
    local err_msg = data.err_msg

    table.insert(hls, { group = "Label", start_col = 0, end_col = #key })

    local line = key

    if vt == "object" or vt == "array" then
        local count = type(value) == "table" and #value or 0
        local bracket = vt == "object" and "{…}" or ("[…] (" .. count .. ")")
        table.insert(virt_text, { text = bracket, highlight = "Comment" })
    else
        table.insert(hls, { group = "Comment", start_col = #line, end_col = #line + 2 })
        line = line .. ": "

        if vt == "string" then
            table.insert(hls, { group = "@string", start_col = #line })
            line = line .. value
        elseif vt == "null" then
            table.insert(hls, { group = "@constant", start_col = #line })
            line = line .. "null"
        elseif vt == "boolean" then
            table.insert(hls, { group = "@boolean", start_col = #line })
            line = line .. tostring(value)
        else
            table.insert(hls, { group = "@number", start_col = #line })
            line = line .. tostring(value)
        end
    end

    if err_msg then
        table.insert(virt_text, { text = "● " .. err_msg, highlight = "DiagnosticError" })
    end

    return line, hls, virt_text
end

---@param opts loop.JsonEditorOpts
function JsonEditor:init(opts)
    self._opts = opts or {} ---@type loop.JsonEditorOpts
    self._undo_stack = {} ---@type table[]
    self._redo_stack = {} ---@type table[]
    self._is_dirty = false
    self._validation_errors = {} ---@type loop.json.ValidationError[]
    self._filepath = opts.filepath
    self._schema = opts.schema
    self._on_node_added = opts.on_node_added
    self._fold_cache = {} ---@type table<string, boolean>
    self._is_open = false
end

---@param winid integer
function JsonEditor:open(winid)
    assert(not self._is_open, "Editor already open")
    self._is_open = true

    local name = self._opts.name or "JSON Editor"
    local header_line = " (For help: g?)"

    ---@diagnostic disable-next-line: undefined-field
    self._itemtree = ItemTreeComp:new({
        formatter = _formatter,
        render_delay_ms = 40,
    })

    self:_reload_data()

    self._itemtree:add_tracker({
        on_toggle = function(_, data, expanded)
            self._fold_cache[data.path or ""] = expanded
        end,
    })

    local buf = CompBuffer:new("jsoneditor", name)
    local ctrl = buf:make_controller() ---@type any

    local function with_current_item(fn)
        local item = self._itemtree:get_cur_item(ctrl)
        if item then fn(item) end
    end

    buf:add_keymap("c", {
        desc = "Change value",
        callback = function() with_current_item(function(i) self:_edit_value(i) end) end,
    })

    buf:add_keymap("C", {
        desc = "Change value (multiline)",
        callback = function() with_current_item(function(i) self:_edit_value(i, true) end) end,
    })

    buf:add_keymap("a", {
        desc = "Add property/item",
        callback = function() with_current_item(function(i) self:_add_new(i) end) end,
    })

    buf:add_keymap("i", {
        desc = "insert item (Add the parent node)",
        callback = function() with_current_item(function(i) self:_add_new(i, true) end) end,
    })

    buf:add_keymap("d", {
        desc = "Delete",
        callback = function() with_current_item(function(i) self:_delete(i) end) end,
    })

    buf:add_keymap("K", {
        desc = "Show schema/help for current node (K)",
        callback = function() with_current_item(function(i) self:_show_node_help(i) end) end,
    })

    buf:add_keymap("s", { desc = "Save (s)", callback = function() self:save() end })
    buf:add_keymap("u", { desc = "Undo (u)", callback = function() self:undo() end })
    buf:add_keymap("<C-r>", { desc = "Redo (C-r)", callback = function() self:redo() end })
    buf:add_keymap("g?", { desc = "Help (?)", callback = function() self:_show_help() end })
    buf:add_keymap("ge", { desc = "Show errors (!)", callback = function() self:_show_errors() end })

    self._itemtree:link_to_buffer(ctrl)
    self._buf_ctrl = ctrl

    local bufid = buf:get_or_create_buf()
    vim.api.nvim_win_set_buf(winid, bufid)
end

function JsonEditor:_show_help()
    local help_text = {
        "Navigation:",
        "  <CR>     Toggle expand/collapse",
        "  j/k      Move up/down",
        "",
        "Editing:",
        "  a        Add element to object or array",
        "  i        Insert node",
        "  c        Change value",
        "  C        Change value (multiline)",
        "  d        Delete",

        "",
        "File:",
        "  s        Save",
        "  u        Undo",
        "  C-r      Redo",
        "",
        "Other:",
        "  K        Show node help (hover window)",
        "  !        Show validation errors",
        "  g?       Show this help",
    }

    floatwin.show_floatwin(table.concat(help_text, "\n"), { title = "Help" })
end

---@param item loop.comp.ItemTree.Item?
function JsonEditor:_show_node_help(item)
    if not item or not item.data then
        vim.notify("No node selected", vim.log.levels.WARN)
        return
    end
    local data = item.data
    local schema = data.unresolved_schema
    local lines = {}
    if schema then
        local function add_field(label, value)
            if value == nil then return end
            if type(value) == "table" then
                value = vim.inspect(value):gsub("\n", " ")
            end
            table.insert(lines, ("  %-14s %s"):format(label .. ":", tostring(value)))
        end

        if type(schema.description) then
            table.insert(lines, schema.description)
        end

        if schema.enum then
            local enum_str = table.concat(vim.tbl_map(vim.inspect, schema.enum), ", ")
            add_field("enum", enum_str)
        end

        if schema.items and not vim.islist(schema.items) then
            local item_types = self:_get_allowed_types(schema.items)
            add_field("items type", table.concat(item_types, " | "))
        end

        local req = schema.required or {}
        if #req > 0 then
            add_field("required properties", table.concat(req, ", "))
        end

        if schema.default ~= nil then
            add_field("default", vim.inspect(schema.default))
        end

        if schema.format then
            add_field("format", schema.format)
        end

        if schema.pattern then
            add_field("pattern", schema.pattern)
        end

        if schema.minimum or schema.maximum then
            add_field("range", (schema.minimum or "-∞") .. " ≤ x ≤ " .. (schema.maximum or "∞"))
        end
    end
    if #lines == 0 then
        table.insert(lines, "(no information available)")
    end

    floatwin.show_tooltip(table.concat(lines, "\n"))
end

function JsonEditor:_reload_data()
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
        if validation_errors and #validation_errors > 0 then
            self._validation_errors = validation_errors
            for _, e in ipairs(validation_errors) do
                errors[e.path] = e.err_msg:gsub("\n", " ")
            end
        end
    end
    self:_upsert_tree_items(self._data, "", nil, self._schema, errors)
end

---@param tbl table
---@param path string
---@param parent_id string?
---@param parent_schema table?
---@param errors table<string,string>
function JsonEditor:_upsert_tree_items(tbl, path, parent_id, parent_schema, errors)
    assert(type(tbl) == "table")

    ---@type loop.comp.ItemTree.Item[]
    local items = {}

    if vim.islist(tbl) then
        for i, v in ipairs(tbl) do
            local str_i = tostring(i)
            local p = validator.join_path(path, str_i)
            local item_schema = parent_schema and parent_schema.items or nil
            _merge_additional_properties(item_schema, parent_schema)

            local unresolved_schema = item_schema
            local resolved_schema = _resolve_oneof_schema(v, item_schema) or item_schema

            local e = errors[p]

            ---@type loop.comp.ItemTree.Item
            local item = {
                id = p,
                expanded = self._fold_cache[p] ~= false,
                data = {
                    key               = "[" .. str_i .. "]",
                    path              = p,
                    value             = v,
                    err_msg           = e,
                    value_type        = _value_type(v),
                    unresolved_schema = unresolved_schema,
                    schema            = resolved_schema,
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
            local p = validator.join_path(path, k)

            local prop_schema, unresolved_schema, resolved_schema
            if parent_schema and parent_schema.properties and parent_schema.properties[k] then
                prop_schema = parent_schema.properties[k]
                _merge_additional_properties(prop_schema, parent_schema)
                unresolved_schema = prop_schema
                resolved_schema = _resolve_oneof_schema(v, prop_schema) or prop_schema
            end

            local e = errors[p]

            ---@type loop.comp.ItemTree.Item
            local item = {
                id = p,
                parent_id = parent_id,
                expanded = self._fold_cache[p] ~= false,
                data = {
                    key               = k,
                    path              = p,
                    value             = v,
                    err_msg           = e,
                    value_type        = _value_type(v),
                    unresolved_schema = unresolved_schema,
                    schema            = resolved_schema,
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

---@param item loop.comp.ItemTree.Item
---@param multiline? boolean
function JsonEditor:_edit_value(item, multiline)
    local path = item.data.path ---@type string
    local schema = item.data.schema or {} ---@type table
    local current_value = item.data.value ---@type any

    if current_value == nil or type(current_value) == "table" then
        return
    end

    -- Enum case → show selector
    if schema.enum then
        ---@type {label: string, data: any}[]
        local choices = {}
        for _, v in ipairs(schema.enum) do
            table.insert(choices, { label = vim.inspect(v), data = v })
        end

        selector.select("Select value", choices, nil, function(data)
            if data then
                self:_set_value(path, data)
            end
        end)
        return
    end

    -- Normal scalar editing
    local default_text ---@type string
    if item.data.value_type == "string" then
        default_text = current_value
    else
        default_text = vim.json.encode(current_value)
    end

    ---@type table
    local input_opts = {
        title = ("%s (%s)"):format(item.data.key or "", item.data.value_type),
        default_text = default_text,
        on_confirm = function(txt)
            if txt == nil then return end
            local coerced = _smart_coerce(txt, item.data.value_type)
            if coerced ~= nil then
                self:_set_value(path, coerced)
            end
        end,
    }

    if multiline then
        floatwin.input_multiline(input_opts)
    else
        floatwin.input_at_cursor(input_opts)
    end
end

---@param item loop.comp.ItemTree.Item
---@param sibling boolean?
function JsonEditor:_add_new(item, sibling)
    if sibling then
        local parts = validator.split_path(item.data.path)
        if #parts < 2 then return end
        table.remove(parts, #parts)
        local parent_path = validator.join_path_parts(parts)
        local par_item = self._itemtree:get_item(parent_path)
        if not par_item then return end
        item = par_item
    end
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

---@param item loop.comp.ItemTree.Item
function JsonEditor:_add_new_default(item)
    local vt = item.data.value_type ---@type string
    local schema = item.data.schema ---@type table|nil

    if vt == "array" then
        self:_add_array_item(item, schema)
    elseif vt == "object" then
        self:_add_object_property(item, schema)
    else
        vim.notify("Can only add to object or array", vim.log.levels.INFO)
    end
end

---@param item loop.comp.ItemTree.Item
---@param to_add any
function JsonEditor:_add_new_from_object(item, to_add)
    local vt = item.data.value_type ---@type string
    local path = item.data.path ---@type string

    if vt == "array" then
        self:_push_undo()
        table.insert(item.data.value, to_add)
        self:_set_value(path, item.data.value)
        return
    end

    if vt == "object" then
        self:_push_undo()
        local obj = item.data.value ---@type table
        for k, v in pairs(to_add) do
            if obj[k] == nil then
                obj[k] = v
            end
        end
        self:_set_value(path, obj)
        return
    end

    vim.notify("Can only add JSON object to object or array", vim.log.levels.INFO)
end

---@param item loop.comp.ItemTree.Item
function JsonEditor:_delete(item)
    if not item or not item.data or item.data.path == "" then
        vim.notify("Cannot delete root node", vim.log.levels.WARN)
        return
    end

    self:_push_undo()

    local parts = validator.split_path(item.data.path) ---@type string[]
    if #parts == 0 then
        self:_pop_undo()
        return
    end

    -- Build path stack: root → … → parent → target
    local stack = { self._data } ---@type table[]
    local current = self._data

    for _, key in ipairs(parts) do
        local next_val = current[tonumber(key) or key]
        if next_val == nil then
            vim.notify("Path no longer exists – data may be inconsistent", vim.log.levels.ERROR)
            self:_pop_undo()
            return
        end
        current = next_val
        table.insert(stack, current)
    end

    local parent = stack[#stack - 1] ---@type table
    local key = parts[#parts] ---@type string
    local numkey = tonumber(key)

    -- Perform deletion
    if vim.islist(parent) then
        if numkey and numkey >= 1 and numkey <= #parent then
            table.remove(parent, numkey)
        else
            vim.notify("Invalid array index: " .. tostring(key), vim.log.levels.ERROR)
            self:_pop_undo()
            return
        end
    else
        parent[key] = nil
        -- Clean up empty objects (optional behavior)
        if next(parent) == nil and #stack > 2 then
            local parentkey = parts[#parts - 1]
            local gparent = stack[#stack - 2]
            gparent[parentkey] = vim.empty_dict()
        elseif next(parent) == nil then
            self._data = vim.empty_dict()
        end
    end

    self:save()
    vim.schedule(function()
        self:_reload_data()
    end)
end

---@param item loop.comp.ItemTree.Item
---@param schema table|nil
function JsonEditor:_add_array_item(item, schema)
    local item_schema = schema and schema.items or {} ---@type table

    local allowed = self:_get_allowed_types(item_schema) ---@type string[]
    if #allowed == 0 then
        allowed = { "string", "number", "boolean", "object", "array" }
        if self._opts.null_support == true then
            table.insert(allowed, "null")
        end
    else
        if self._opts.null_support ~= true then
            allowed = vim.tbl_filter(function(v) return v ~= "null" end, allowed)
        end
    end

    if #allowed == 1 then
        self:_create_and_add_array_item(item, allowed[1])
    else
        ---@type {label: string, data: string}[]
        local choices = {}
        for _, t in ipairs(allowed) do
            table.insert(choices, { label = t, data = t })
        end

        selector.select("Select item type", choices, nil, function(data)
            if data then
                self:_create_and_add_array_item(item, data)
            end
        end)
    end
end

---@param item loop.comp.ItemTree.Item
---@param type_choice string
function JsonEditor:_create_and_add_array_item(item, type_choice)
    local default_val = self:_create_default_value(type_choice)

    if type_choice == "string" or type_choice == "number" or type_choice == "boolean" then
        floatwin.input_at_cursor({
            title = "New " .. type_choice .. " value",
            on_confirm = function(txt)
                if txt == nil then return end
                self:_push_undo()
                local arr = item.data.value ---@type any[]
                local newval = _smart_coerce(txt, type_choice)
                if newval ~= nil then
                    table.insert(arr, newval)
                    self:_set_value(item.data.path, arr)
                end
            end,
        })
    else
        -- object / array / null → insert directly
        self:_push_undo()
        local arr = item.data.value ---@type any[]
        table.insert(arr, default_val)
        self:_set_value(item.data.path, arr)
    end
end

---@param item loop.comp.ItemTree.Item
---@param schema table|nil
function JsonEditor:_add_object_property(item, schema)
    schema = schema or {} ---@type table
    local obj = item.data.value ---@type table

    -- Collect candidate keys from schema.properties / oneOf
    ---@type table<string, {schema: table, parent: table}[]>
    local key_candidates = {}
    ---@type string[]
    local suggested_keys = {}

    local function add_candidate(key, prop_schema, parent_schema)
        if obj[key] ~= nil then return end
        if not key_candidates[key] then
            key_candidates[key] = {}
            table.insert(suggested_keys, key)
        end
        table.insert(key_candidates[key], {
            schema = prop_schema or {},
            parent = parent_schema,
        })
    end

    if schema.oneOf then
        for _, subschema in ipairs(schema.oneOf) do
            local errs = validator.validate(subschema, obj)
            if not errs or #errs == 0 then
                if subschema.properties then
                    for k, ps in pairs(subschema.properties) do
                        add_candidate(k, ps, subschema)
                    end
                end
            end
        end
    elseif schema.properties then
        for k, ps in pairs(schema.properties) do
            add_candidate(k, ps, schema)
        end
    end

    table.sort(suggested_keys)

    floatwin.input_at_cursor({
        title = "New property name",
        completions = suggested_keys,
        on_confirm = function(key)
            if not key or key == "" then return end
            if obj[key] ~= nil then
                vim.notify("Key already exists", vim.log.levels.WARN)
                return
            end

            local schemas = key_candidates[key]
            local function with_schema(prop_schema)
                self:_choose_type_and_add_property(item, key, prop_schema)
            end

            if schemas and #schemas > 1 then
                ---@type {label: string, data: table}[]
                local choices = {}
                for _, info in ipairs(schemas) do
                    table.insert(choices, {
                        label = info.parent.__name or "<schema>",
                        data = info.schema,
                    })
                end
                selector.select(
                    "Select schema for '" .. key .. "'",
                    choices,
                    nil,
                    function(data)
                        if data then with_schema(data) end
                    end
                )
                return
            end

            if schemas and schemas[1] then
                with_schema(schemas[1].schema)
                return
            end

            -- fallback: additionalProperties
            local ap = schema.additionalProperties
            with_schema(type(ap) == "table" and ap or {})
        end,
    })
end

---@param item loop.comp.ItemTree.Item
---@param key string
---@param prop_schema table
function JsonEditor:_choose_type_and_add_property(item, key, prop_schema)
    local allowed = self:_get_allowed_types(prop_schema) ---@type string[]

    if #allowed == 0 then
        allowed = { "string", "number", "boolean", "object", "array" }
        if self._opts.null_support == true then
            table.insert(allowed, "null")
        end
    else
        if self._opts.null_support ~= true then
            allowed = vim.tbl_filter(function(v) return v ~= "null" end, allowed)
        end
    end

    if #allowed == 1 then
        self:_create_and_add_object_property(item, key, allowed[1], prop_schema)
        return
    end

    ---@type {label: string, data: string}[]
    local choices = {}
    for _, t in ipairs(allowed) do
        table.insert(choices, { label = t, data = t })
    end

    selector.select("Select property type", choices, nil, function(data)
        if data then
            self:_create_and_add_object_property(item, key, data, prop_schema)
        end
    end)
end

---@param item loop.comp.ItemTree.Item
---@param key string
---@param type_choice string
---@param schema table
function JsonEditor:_create_and_add_object_property(item, key, type_choice, schema)
    local default_val = self:_create_default_value(type_choice)

    if type_choice == "string" or type_choice == "number" or type_choice == "boolean" then
        floatwin.input_at_cursor({
            title = "Value for " .. key .. " (" .. type_choice .. ")",
            on_confirm = function(txt)
                if txt == nil then return end
                self:_push_undo()
                local obj = item.data.value ---@type table
                local newval = _smart_coerce(txt, type_choice)
                if newval ~= nil then
                    obj[key] = newval
                    self:_set_value(item.data.path, obj)
                end
            end,
        })
    else
        self:_push_undo()
        local obj = item.data.value ---@type table
        obj[key] = default_val
        self:_set_value(item.data.path, obj)
    end
end

---@param schema table|nil
---@return string[]
function JsonEditor:_get_allowed_types(schema)
    if not schema then return {} end

    if schema.const ~= nil then
        return { _value_type(schema.const) }
    end

    if schema.enum then
        ---@type table<string, boolean>
        local types_set = {}
        for _, v in ipairs(schema.enum) do
            types_set[_value_type(v)] = true
        end
        local types = {}
        for t in pairs(types_set) do
            table.insert(types, t)
        end
        return types
    end

    if schema.oneOf then
        ---@type table<string, boolean>
        local types_set = {}
        for _, subschema in ipairs(schema.oneOf) do
            if subschema.type then
                local t = subschema.type
                if type(t) == "table" then
                    for _, typ in ipairs(t) do types_set[typ] = true end
                else
                    types_set[t] = true
                end
            elseif subschema.const ~= nil then
                types_set[_value_type(subschema.const)] = true
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

---@param type_choice string
---@return any
function JsonEditor:_create_default_value(type_choice)
    if type_choice == "null" then return vim.NIL end
    if type_choice == "boolean" then return false end
    if type_choice == "number" then return 0 end
    if type_choice == "string" then return "" end
    if type_choice == "array" then return {} end
    if type_choice == "object" then return vim.empty_dict() end
    return vim.NIL
end

function JsonEditor:_push_undo()
    table.insert(self._undo_stack, vim.fn.deepcopy(self._data))
    self._redo_stack = {}
    self._is_dirty = true
end

---@return table|nil
function JsonEditor:_pop_undo()
    return table.remove(self._undo_stack)
end

function JsonEditor:undo()
    if #self._undo_stack == 0 then
        vim.notify("Nothing to undo", vim.log.levels.INFO)
        return
    end

    table.insert(self._redo_stack, vim.fn.deepcopy(self._data))
    self._data = self:_pop_undo() or self._data

    self:save()
    vim.schedule(function()
        self:_reload_data()
    end)
end

function JsonEditor:redo()
    if #self._redo_stack == 0 then
        vim.notify("Nothing to redo", vim.log.levels.INFO)
        return
    end
    table.insert(self._undo_stack, vim.fn.deepcopy(self._data))
    self._data = table.remove(self._redo_stack)
    
    self:save()
    vim.schedule(function()
        self:_reload_data()
    end)
end

function JsonEditor:save()
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

    local lines = { "=== Validation Errors ===\n" }
    for i, err in ipairs(self._validation_errors) do
        table.insert(lines, string.format("%d. at '%s': %s\n", i, err.path, err.err_msg))
    end

    floatwin.show_floatwin(table.concat(lines), { title = "Errors" })
end


---@param path string
---@param new_value any
function JsonEditor:_set_value(path, new_value)
    local parts = validator.split_path(path) ---@type string[]
    if #parts < 1 then return end

    local parent_id = self._itemtree:get_parent_id(path)
    if not parent_id then return end
    ---@type loop.comp.ItemTree.Item?
    local par_item = self._itemtree:get_item(parent_id)
    if not par_item then return end

    local last = parts[#parts]
    local numkey = tonumber(last)
    local key = numkey or last

    self:_push_undo()
    par_item.data.value[key] = new_value

    self:save()
    vim.schedule(function()
        self:_reload_data()
    end)
end

return JsonEditor
