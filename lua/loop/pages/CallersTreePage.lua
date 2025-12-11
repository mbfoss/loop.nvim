local class = require('loop.tools.class')
local ItemTreePage = require('loop.pages.ItemTreePage')
local strtools = require('loop.tools.strtools')

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
    return string.format("%s (%s:%d)", data.name, data.filename, data.lnum)
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

        end
    })
end

---@param symbol_position table { uri=..., line=..., character=... }
---@param callback fun(items:loop.pages.ItemTreePage.Item[])
function CallersTreePage:_load_callers(symbol_position, callback)
    vim.lsp.buf_request(0, "textDocument/incomingCalls", symbol_position, function(err, result)
        if err or not result then
            callback({
                {
                    id = "<error>",
                    expanded = false,
                    data = {
                        name = "Failed to load callers .. " .. tostring(err),
                        filename = "",
                        lnum = 0,
                        col = 0,
                    }
                }
            })
            return
        end

        ---@type loop.pages.ItemTreePage.Item[]
        local children = {}

        for i, call in ipairs(result) do
            local loc = call.caller
            local child_position = {
                uri = loc.uri,
                position = {
                    line = loc.selectionRange.start.line,
                    character = loc.selectionRange.start.character,
                }
            }
            local child_item_id =
                string.format("%s:%d:%d",
                    child_position.uri, child_position.position.line,
                    child_position.position.character)

            local filename = vim.uri_to_fname(loc.uri)
            ---@type loop.pages.ItemTreePage.Item
            local child_item = {
                id = child_item_id,
                expanded = false,
                data = {
                    name = loc.name or "<anonymous>",
                    filename = filename,
                    lnum = loc.selectionRange.start.line + 1,
                    col = loc.selectionRange.start.character,
                },
            }
            -- load children on expansion
            child_item.children_callback = function(cb)
                self:_load_callers(child_position, cb)
            end
            table.insert(children, child_item)
        end

        callback(children)
    end)
end

---@param cursor_pos table|nil default: current cursor
function CallersTreePage:load(cursor_pos)
    self:clear_items()
    local win = cursor_pos and cursor_pos.window or 0
    local symbol_position = vim.lsp.util.make_position_params(win, 'utf-8')

    -- Try to get current line content as a fallback name
    local buf = vim.api.nvim_get_current_buf()
    local row = (cursor_pos and cursor_pos.line) or (vim.api.nvim_win_get_cursor(win)[1] - 1)
    local line_text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or "<current>"

    local root_item = {
        id = "<root>",
        expanded = true,
        data = {
            symbol_position = symbol_position,
            name = line_text:gsub("^%s*(.-)%s*$", "%1"), -- trim whitespace
            filename = vim.api.nvim_buf_get_name(buf),
            lnum = row + 1,
            col = (cursor_pos and cursor_pos.character) or vim.api.nvim_win_get_cursor(win)[2],
        },
    }

    root_item.children_callback = function(cb)
        self:_load_callers(symbol_position, cb)
    end

    self:upsert_item(root_item)
end

return CallersTreePage
