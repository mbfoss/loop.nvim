local class = require('loop.tools.class')
local ItemTreePage = require('loop.pages.ItemTreePage')
local strtools = require('loop.tools.strtools')

---@alias loop.pages.VarWatchPage.Item loop.pages.ItemTreePage.Item

---@class loop.pages.VarWatchPage : loop.pages.ItemTreePage
---@field new fun(self: loop.pages.VarWatchPage, name:string): loop.pages.VarWatchPage
local VarWatchPage = class(ItemTreePage)

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
    if data.greyout then
        table.insert(highlights, { group = "NonText" })
    else
        local valuehl = data.is_na_value and "NonText" or _get_vartype_hightlight(data.type)
        table.insert(highlights, { group = "@symbol", start_col = 0, end_col = #data.name })
        table.insert(highlights, { group = valuehl, start_col = #data.name + 2 })
    end
    return tostring(data.name) .. ": " .. tostring(data.value)
end

---@param name string
function VarWatchPage:init(name)
    ItemTreePage.init(self, name, {
        formatter = _variable_node_formatter,
    })
    self:add_keymap("i", {
        desc = 'Add a watcher',
        callback = function()
            vim.ui.input({
                prompt = "Expression: "
            }, function(expr)
                if expr and #expr > 0 and not vim.tbl_contains(self._watch_exressions, expr) then
                    table.insert(self._watch_exressions, expr)
                    self:_load_expr_value(expr)
                end
            end)
        end
    })
    self:add_keymap("d", {
        desc = 'Delete a watcher',
        callback = function()
            local item = self:get_cur_item()
            if item then
                self:remove_item(item.id)
                for idx, expr in ipairs(self._watch_exressions) do
                    if expr == item.data.name then
                        table.remove(self._watch_exressions, idx)
                        break
                    end
                end
            end
        end
    })
    ---@type string[]
    self._watch_exressions = {}
    ---@type loop.dap.session.notify.ThreadData|nil
    self._cur_thread_data = nil
    ---@type loop.dap.proto.StackFrame
    self._cur_frame = nil
    ---@type table<any,boolean> -- id --> expanded
    self._layout_cache = {}

    self:_load_expressions()
end

---@param thread_data loop.dap.session.notify.ThreadData
---@param ref number
---@param parent_id number|string
---@param callback fun(items:loop.pages.VariablesPage.Item[])
function VarWatchPage:_load_variables(thread_data, ref, parent_id, callback)
    thread_data.variables_provider({ variablesReference = ref },
        function(_, vars_data)
            local children = {}
            if vars_data then
                for _, var in ipairs(vars_data.variables) do
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
                                self:_load_variables(thread_data, var.variablesReference, item_id, cb)
                            end
                        end
                    end
                    table.insert(children, var_item)
                end
            end
            callback(children)
        end)
end

function VarWatchPage:_load_expressions()
    ---@type loop.pages.ItemTreePage.Item[]
    for _, expr in ipairs(self._watch_exressions) do
        self:_load_expr_value(expr)
    end
end

---@param expr string
function VarWatchPage:_load_expr_value(expr)
    ---@type loop.pages.VariablesPage.Item
    local var_item = {
        id = expr,
        parent = nil,
        expanded = self._layout_cache[expr],
        data = { name = expr }
    }
    if not self._cur_thread_data or not self._cur_frame then
        var_item.data.value = "not available"
        var_item.data.is_na_value = true
        self:upsert_item(var_item)
        return
    end
    self._cur_thread_data.evaluate_provider({
        expression = expr,
        frameId = self._cur_frame.id,
        context = 'watch',
    }, function(err, data)
        if err or not data then
            var_item.data.value = "not available"
            var_item.data.is_na_value = true
        else
            var_item.data.value = data.result
            if data.variablesReference and data.variablesReference > 0 then
                var_item.children_callback = function(cb)
                    if var_item.data.greyout then
                        cb({})
                    else
                        self:_load_variables(self._cur_thread_data, data.variablesReference, var_item.id, cb)
                    end
                end
            end
        end
        self:upsert_item(var_item)
    end)
end

---@param thread_data loop.dap.session.notify.ThreadData
---@param frame loop.dap.proto.StackFrame
function VarWatchPage:update_data(thread_data, frame)
    self._cur_thread_data = thread_data
    self._cur_frame = frame
    self:_load_expressions()
end

function VarWatchPage:greyout_content()
    local items = self:get_items()
    for _, item in ipairs(items) do
        item.data.greyout = true
        self._layout_cache[item.id] = item.expanded
    end
    self:refresh_content()
end

return VarWatchPage
