local class = require('loop.tools.class')
local ItemTreePage = require('loop.pages.ItemTreePage')
local uitools = require('loop.tools.uitools')

---@alias loop.pages.CallersTreePage.Item loop.pages.ItemTreePage.Item

---@class loop.pages.CallersTreePage : loop.pages.ItemTreePage
---@field new fun(self: loop.pages.CallersTreePage, name:string): loop.pages.CallersTreePage
local CallersTreePage = class(ItemTreePage)

---@param id any
---@param data any
---@param highlights loop.pages.ItemTreePage.Highlight
---@return string
local function _caller_node_formatter(id, data, highlights)
    if not data then return "" end
    table.insert(highlights, { group = "@function", start_col = 0, end_col = #data.name })
    table.insert(highlights, { group = "@comment", start_col = #data.name + 1 })
    return string.format("%s (%s:%d)", data.name, data.filename, data.lnum or 0)
end

---@param name string
function CallersTreePage:init(name)
    ItemTreePage.init(self, name, {
        formatter = _caller_node_formatter,
    })
    self:_add_keymaps()
end

function CallersTreePage:_add_keymaps()
    self:add_tracker({
        on_selection = function(id, data)
            if not data or not data.filename then return end
            uitools.smart_open_file(data.filename, data.lnum, data.col)
        end
    })
end

---@param win_id any
---@param item any
---@param callback fun(items:loop.pages.ItemTreePage.Item[],retry:boolean|nil)
---@param visited any
function CallersTreePage:_load_callers(win_id, item, callback, visited)
    visited = visited or {}

    -- prevent cycles using the opaque data token
    local key = item.data
    if visited[key] then
        local child_node = {
            id = {},
            expanded = true,
            data = { name = "<cycle>", filename = "", lnum = 0, col = 0 },
        }
        callback({ child_node })
        return
    end

    -- convert LSP range to position for prepareCallHierarchy
    local bufnr               = vim.uri_to_bufnr(item.uri)
    local line                = item.selectionRange.start.line
    local col                 = item.selectionRange.start.character
    local params              = vim.lsp.util.make_position_params(win_id, "utf-8")
    params.position.line      = line
    params.position.character = col

    -- call prepareCallHierarchy fresh for this symbol
    vim.lsp.buf_request(bufnr, "textDocument/prepareCallHierarchy", params, function(err, items)
        if err or not items or #items == 0 then
            callback({})
            return
        end

        local root_item = items[1] -- fresh LSP CallHierarchyItem

        -- now fetch incoming calls
        vim.lsp.buf_request(bufnr, "callHierarchy/incomingCalls", { item = root_item }, function(err2, calls)
            if err2 or not calls then
                callback({})
                return
            end

            local children = {}

            for _, call in ipairs(calls) do
                local from = call.from -- original LSP item

                if call.fromRanges and call.fromRanges[1] then
                    from.originSelectionRange = call.fromRanges[1]
                end

                local filename = vim.uri_to_fname(from.uri)
                local lnum     = from.range.start.line + 1
                local col      = from.range.start.character

                local node     = {
                    id = tostring({}),
                    expanded = false,
                    data = {
                        name = from.name or "<anonymous>",
                        filename = filename,
                        lnum = lnum,
                        col = col,
                    },
                    children_callback = function(cb)
                        -- recurse by preparing hierarchy again
                        self:_load_callers(win_id, from, cb, visited)
                    end,
                }

                table.insert(children, node)
            end

            local retry = #children == 0
            if not retry then
                visited[key] = true
            end
            callback(children, retry)
        end)
    end)
end

function CallersTreePage:load()
    self:clear_items()

    local bufnr           = vim.api.nvim_get_current_buf()
    local win_id          = vim.api.nvim_get_current_win()
    local line, col       = unpack(vim.api.nvim_win_get_cursor(win_id))
    local symbol_position = vim.lsp.util.make_position_params(win_id, "utf-8")

    vim.lsp.buf_request(bufnr, "textDocument/prepareCallHierarchy", symbol_position, function(err, items)
        if err or not items or #items == 0 then
            self:upsert_item({
                id = "<root>",
                expanded = true,
                data = { name = "No call hierarchy", filename = "", lnum = 0, col = 0 },
            })
            return
        end

        local target = items[1] -- Root CallHierarchyItem
        local root = {
            id = {},
            expanded = true,
            data = {
                name = target.name or "<symbol>",
                filename = vim.api.nvim_buf_get_name(bufnr),
                lnum = line,
                col = col,
            },
        }

        root.children_callback = function(cb)
            self:_load_callers(win_id, target, cb)
        end

        self:upsert_item(root)
    end)
end

return CallersTreePage
