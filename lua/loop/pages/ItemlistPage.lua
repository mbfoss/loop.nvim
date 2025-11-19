local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local uitools = require('loop.tools.uitools')

---@class loop.pages.ItemListPage : loop.pages.Page
---@field new fun(self: loop.pages.ItemListPage, name:string): loop.pages.Page
local ItemListPage = class(Page)

local function format_entry(entry)
    local parts = {}
    -- 2. File + line
    table.insert(parts, "[")
    table.insert(parts, tostring(entry.id))
    table.insert(parts, ': ')
    table.insert(parts, entry.name)
    table.insert(parts, "] ")
    return table.concat(parts, "")
end

---@param name string
function ItemListPage:init(name)
    Page.init(self, "task", name)
    self._items = {}
end

---@param id number
---@param name string
function ItemListPage:add_item(id, name)
    table.insert(self._items, { id = id, name = name })
    self:_refresh_buffer(self:get_buf())
end

---@param id number
function ItemListPage:remove_item(id)
    for idx, item in ipairs(self._items) do
        if item.id == id then
            self._items[idx] = nil
            self:_refresh_buffer(self:get_buf())
            break
        end
    end
end

function ItemListPage:get_or_create_buf()
    local buf, created = Page.get_or_create_buf(self)
    if not created then
        return buf, false
    end
    self:_refresh_buffer(buf)
    return buf, true
end

---@param buf number
function ItemListPage:_refresh_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    -- 1. Build lines
    local lines = { "Debug task: " .. self:get_name() }
    if #self._items == 0 then
        lines[#lines] = "No active sessions"
    else
        for _, entry in ipairs(self._items) do
            lines[#lines + 1] = format_entry(entry)
        end
    end
    -- 2. Update buffer
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
end

return ItemListPage
