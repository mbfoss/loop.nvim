local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')
local config = require('loop.config')
local selector = require('loop.selector')
local Trackers = require("loop.tools.Trackers")

---@class loop.pages.StackTracePage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.StackTracePage, name:string): loop.pages.StackTracePage
local StackTracePage = class(ItemListPage)

---@param item loop.pages.ItemListPage.Item
---@param highlights loop.pages.ItemListPage.Highlight[]
local function _item_formatter(item, highlights)
    if not item.data or item.data.greyout then
        table.insert(highlights, {
            group = "NonText"
        })
    end

    if item.data.text then return item.data.text end
    local frame = item.data.frame
    if not frame then return "no frame data" end
    local parts = { tostring(frame.id) }
    table.insert(parts, ": ")
    table.insert(parts, tostring(frame.name))
    if frame.source and frame.source.name then
        table.insert(parts, " - ")
        table.insert(parts, tostring(frame.source.name))
        if frame.line then
            table.insert(parts, ":")
            table.insert(parts, tostring(frame.line))
            if frame.column then
                table.insert(parts, ":")
                table.insert(parts, tostring(frame.column))
            end
        end
    end
    return table.concat(parts, '')
end

---@param name string
function StackTracePage:init(name)
    ItemListPage.init(self, name, {
        formatter = _item_formatter,
    })

    self._frametrackers = Trackers:new()
    self:add_tracker({
        on_selection = function(item)
            if item and item.data then
                if item.id == 0 then
                    -- title line
                    self:_select_n_load_stacktrace(item.data.thread_data)
                else
                    ---@type loop.dap.proto.StackFrame
                    local frame = item.data.frame
                    vim.schedule(function ()
                        self._frametrackers:invoke("frame_selected", frame)
                    end)
                end
            end
        end
    })
end

---@param callback fun(frame:loop.dap.proto.StackFrame)
function StackTracePage:add_frame_tracker(callback)
    self._frametrackers:add_tracker({
        frame_selected = callback
    })
end

---@param data loop.dap.session.notify.ThreadData
function StackTracePage:_select_n_load_stacktrace(data)
    if not data.threads or not data.stack_provider then return end
    local choices = {}
    for _, thread in ipairs(data.threads) do
        ---@type loop.SelectorItem
        local item = {
            label = tostring(thread.id) .. ' - ' .. thread.name,
            data = thread.id,
        }
        table.insert(choices, item)
    end
    selector.select("Select a thread", choices, nil, function(thread_id)
        if thread_id and type(thread_id) == "number" then
            local newdata = vim.fn.copy(data)
            newdata.thread_id = thread_id
            self:set_content(newdata)
        end
    end)
end

---@param data loop.dap.session.notify.ThreadData
function StackTracePage:set_content(data)
    if not data.thread_id then
        return
    end
    data.stack_provider({
            threadId = data.thread_id,
            levels = config.current.debug.stack_levels_limit or 100,
        },
        function(err, resp)
            local text = "Thread " .. tostring(data.thread_id)
            if data.threads and #data.threads > 1 then
                text = text .. string.format(" (%s paused threads)", #data.threads)
            end
            local items = { {
                id = 0,
                data = { text = text, thread_data = data }
            } }
            if resp then
                for idx, frame in ipairs(resp.stackFrames) do
                    ---@type loop.pages.ItemListPage.Item
                    local item = { id = idx, data = { frame = frame } }
                    table.insert(items, item)
                end
            end
            self:set_items(items)
        end)
end

function StackTracePage:clear_content()
    self:set_items({})
end

function StackTracePage:greyout_content()
    local items = self:get_items()
    for _, item in ipairs(items) do
        item.data.greyout = true
    end
    self:refresh_content()
end

return StackTracePage
