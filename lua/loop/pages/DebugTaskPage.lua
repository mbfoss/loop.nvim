local class = require('loop.tools.class')
local TaskPage = require('loop.pages.TaskPage')
local uitools = require('loop.tools.uitools')

---@class loop.pages.DebugTaskPage : loop.pages.TaskPage
---@field new fun(self: loop.pages.DebugTaskPage, name:string): loop.pages.DebugTaskPage
local DebugTaskPage = class(TaskPage)

-- ----------------------------------------------------------------------
-- Format a breakpoint entry for UI (e.g. Telescope, quickfix, etc.)
-- ----------------------------------------------------------------------
local function format_entry(entry)
    local parts = {}
    -- 2. File + line
    table.insert(parts, "[")
    table.insert(parts, tostring(entry.id))
    table.insert(parts, ': ')
    table.insert(parts, entry.name)
    table.insert(parts, "] ")
    if entry.state then
        table.insert(parts, entry.state)
    end
    return table.concat(parts, "")
end

---@param name string
function DebugTaskPage:init(name)
    TaskPage.init(self, name)
    self._items = {}
end

---@param id number
---@param name string
---@param state string
function DebugTaskPage:add_session(id, name, state)
    table.insert(self._items, { id = id, name=name, state = state })
    self:_refresh_buffer(self:get_buf())
end

---@param id number
function DebugTaskPage:remove_session(id)
    vim.defer_fn(function ()
        for idx,item in ipairs(self._items) do
            if item.id == id then
                self._items[idx] = nil
                self:_refresh_buffer(self:get_buf())
                break
            end
        end        
    end, 15000)
end

---@param id number
---@param state string
function DebugTaskPage:set_session_state(id, state)
    for idx,item in ipairs(self._items) do
        if item.id == id then
            item.state = state
            self:_refresh_buffer(self:get_buf())
            break
        end
    end
end

function DebugTaskPage:get_or_create_buf()
    local buf, created = TaskPage.get_or_create_buf(self)
    if not created then
        return buf, false
    end
    self:_refresh_buffer(buf)
    return buf, true
end

---@param buf number
function DebugTaskPage:_refresh_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    -- 1. Build lines
    local lines = {"Debug task: " .. self:get_name()}
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

return DebugTaskPage
