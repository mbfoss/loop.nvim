local class = require('loop.tools.class')
local ItemTreePage = require('loop.pages.ItemTreePage')
local strtools = require('loop.tools.strtools')

---@alias loop.pages.VariablesPage.Item loop.pages.ItemTreePage.Item

---@class loop.pages.VariablesPage : loop.pages.ItemTreePage
---@field new fun(self: loop.pages.VariablesPage, name:string): loop.pages.VariablesPage
local VariablesPage = class(ItemTreePage)

local _vartype_to_group = {
    -- primitives
    ["string"]     = "@string",
    ["number"]     = "@number",
    ["boolean"]    = "@boolean",
    ["null"]       = "@constant.builtin",
    ["undefined"]  = "@constant.builtin",
    -- functions
    ["function"]   = "@function",
    ["function()"] = "@function", -- seen in some DAP servers
    ["function "]  = "@function",
    ["func"]       = "@function",
    ["Function"]   = "@function",
    -- objects / tables / arrays
    ["array"]      = "@structure",
    ["list"]       = "@structure",
    ["table"]      = "@structure",
    ["object"]     = "@structure",
    ["Object"]     = "@structure",
    ["Array"]      = "@structure",
    ["Module"]     = "@module",
}

---@param vartype string
---@return string|nil
function _get_vartype_hightlight(vartype)
    if not vartype then return nil end
    vartype = tostring(vartype)
    vartype = vartype:gsub("%s+", "")
    vartype = vartype:lower()
    local hl = _vartype_to_group[vartype]
    return hl or "@variable"
end

---@param id any
---@param data any
---@param highlights loop.pages.ItemTreePage.Highlight
---@return string
local function _variable_node_formatter(id, data, highlights)
    if not data then return "" end
    if data.scopelabel then
        table.insert(highlights, { group = "Directory" })
        return data.scopelabel
    end
    if data.is_na then
        table.insert(highlights, { group = "NonText" })
        return "not available"
    end

    if data.greyout then
        table.insert(highlights, { group = "NonText" })
    else
        table.insert(highlights, { group = "@symbol", start_col = 0, end_col = #data.name })
        table.insert(highlights, { group = _get_vartype_hightlight(data.type), start_col = #data.name + 2 })
    end
    return tostring(data.name) .. ": " .. tostring(data.value)
end

---@param scopes loop.dap.proto.Scope[]
---@param thread_data loop.dap.session.notify.ThreadData
---@param variables_page loop.pages.VariablesPage
function VariablesPage:_load_scopes(scopes, thread_data, variables_page)
    ---@param ref number
    ---@param parent_id string
    ---@param callback fun(items:loop.pages.VariablesPage.Item[])
    local function load_variables(ref, parent_id, callback)
        thread_data.variables_provider({ variablesReference = ref },
            function(_, vars_data)
                local children = {}
                if vars_data then
                    for var_idx, var in ipairs(vars_data.variables) do
                        local item_id = parent_id .. strtools.escape_marker1() .. var.name
                        ---@type loop.pages.VariablesPage.Item
                        local var_item = {
                            id = item_id,
                            parent = parent_id,
                            expanded = self._layout_cache[item_id],
                            data = {
                                name = var.name,
                                type = var.type,
                                value = var.value
                            },
                        }
                        if var.variablesReference and var.variablesReference > 0 then
                            var_item.children_callback = function(cb)
                                if var_item.data.greyout then
                                    cb({})
                                else
                                    load_variables(var.variablesReference, item_id, cb)
                                end
                            end
                        end
                        table.insert(children, var_item)
                    end
                else
                    ---@type loop.pages.VariablesPage.Item
                    local var_item = {
                        id = {}, -- a unique id
                        parent =
                            parent_id,
                        data = { is_na = true },
                    }
                    table.insert(children, var_item)
                end
                callback(children)
            end)
    end

    ---@type loop.pages.ItemTreePage.Item[]
    local scope_items = {}
    for scope_idx, scope in ipairs(scopes) do
        local item_id = scope.name
        local prefix = scope.expensive and "⏱ " or ""
        local expanded = self._layout_cache[item_id]
        if expanded == nil then
            if scope.expensive
                or scope.presentationHint == "globals"
                or scope.name == "Globals"
                or scope.presentationHint == "registers"
            then
                expanded = false
            else
                expanded = true
            end
        end
        ---@type loop.pages.ItemTreePage.Item
        local scope_item = {
            id = item_id,
            expanded = expanded,
            data = { scopelabel = prefix .. scope.name }
        }
        scope_item.children_callback = function(cb)
            if scope_item.data.greyout then
                cb({})
            else
                load_variables(scope.variablesReference, item_id, cb)
            end
        end
        table.insert(scope_items, scope_item)
    end
    variables_page:upsert_items(scope_items)
end

---@param name string
function VariablesPage:init(name)
    ItemTreePage.init(self, name, {
        formatter = _variable_node_formatter
    })
    ---@type table<any,boolean> -- id --> expanded
    self._layout_cache = {}
end

---@param event_data loop.dap.session.notify.ThreadData
---@param frame loop.dap.proto.StackFrame
function VariablesPage:load_variables(event_data, frame)
    event_data.scopes_provider({ frameId = frame.id }, function(_, scopes_data)
        if scopes_data and scopes_data.scopes then
            self:_load_scopes(scopes_data.scopes, event_data, self)
        end
    end)
end

function VariablesPage:greyout_content()
    self._layout_cache = {}
    local items = self:get_items()
    for _, item in ipairs(items) do
        item.data.greyout = true
        self._layout_cache[item.id] = item.expanded
    end
    self:refresh_content()
end

return VariablesPage
