local class = require('loop.tools.class')
local TaskPage = require('loop.pages.TaskPage')
local uitools = require('loop.tools.uitools')

---@class loop.pages.DebugTaskPage : loop.pages.TaskPage
---@field new fun(self: loop.pages.DebugTaskPage): loop.pages.DebugTaskPage
local DebugTaskPage = class(TaskPage)

-- ----------------------------------------------------------------------
-- Format a breakpoint entry for UI (e.g. Telescope, quickfix, etc.)
-- ----------------------------------------------------------------------
local function format_entry(entry)
    local parts = {}
    -- 2. File + line
    table.insert(parts, "session[")
    table.insert(parts, tostring(entry.id))
    table.insert(parts, "] - ")
    table.insert(parts, entry.session:name())
    return table.concat(parts, "")
end

function DebugTaskPage:init()
    TaskPage.init(self)
    self._items = {}
end

---@param sesions table<number,loop.dap.Session>
function DebugTaskPage:set_session_list(sesions)
    self._items = {}
    for i, s in pairs(sesions) do
        table.insert(self._items, { id = i, session = s })
    end
    self:_refresh_buffer(self:get_buf())
end

---@param added boolean
---@param id number
---@param session loop.dap.Session
function DebugTaskPage:add_session(id, session)
    table.insert(self._items, { id = id, session = session })
    self:_refresh_buffer(self:get_buf())
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
    local lines = {"Debug sessions:"}
    for _, entry in ipairs(self._items) do
        lines[#lines + 1] = format_entry(entry)
    end

    -- 2. Update buffer
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
end

return DebugTaskPage
