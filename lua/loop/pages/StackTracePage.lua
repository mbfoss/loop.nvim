local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')
local config = require('loop.config')
local selector = require('loop.selector')
local uitools = require('loop.tools.uitools')

---@class loop.pages.StackTracePage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.StackTracePage, name:string): loop.pages.StackTracePage
local StackTracePage = class(ItemListPage)

---@param name string
function StackTracePage:init(name)
    ItemListPage.init(self, name)

    self:add_tracker({
        on_selection = function(item)
            if item and item.data then
                if item.id == 0 then
                    self:_select_n_load_stacktrace(item.data.threads, item.data.stackprovider)
                else
                    ---@type loop.dap.proto.StackFrame
                    local frame = item.data
                    if frame and frame.source and frame.source.path then
                        uitools.smart_open_file(frame.source.path, frame.line, frame.column)
                    end
                end
            end
        end
    })
end

---@param threads loop.dap.proto.Thread[]|nil,
---@param stackprovider loop.job.StackTracePovider
function StackTracePage:_select_n_load_stacktrace(threads, stackprovider)
    if not threads or not stackprovider then return end
    local choices = {}
    for _, thread in ipairs(threads) do
        ---@type loop.SelectorItem
        local item = {
            label = tostring(thread.id) .. ' - ' .. thread.name,
            data = thread.id,
        }
        table.insert(choices, item)
    end
    selector.select("Select a thread", choices, nil, function(thread_id)
        if thread_id and type(thread_id) == "number" then
            self:set_content(threads, thread_id, stackprovider)
        end
    end)
end

---@param threads loop.dap.proto.Thread[]|nil,
---@param thread_id number|nil,
---@param stackprovider loop.job.StackTracePovider
function StackTracePage:set_content(threads, thread_id, stackprovider)
    if not thread_id then
        return
    end
    self:set_items({ { id = 0, text = "Loading stack trace..." } })
    stackprovider(
        thread_id,
        config.current.debug.stack_levels_limit or 100,
        function(err, resp)
            local text = "Thread " .. tostring(thread_id)
            if threads and #threads > 1 then
                text = text .. string.format(" (%s paused threads)", #threads)
            end
            local items = { {
                id = 0,
                text = text,
                data = {
                    threads = threads,
                    stackprovider = stackprovider
                }
            } }
            if resp then
                for idx, frame in ipairs(resp.stackFrames) do
                    if frame.source then
                        text = string.format("%d: %s - %s:%d:%d",
                            frame.id, frame.name, frame.source.name, frame.line, frame.column)
                    else
                        text = string.format("%d: %s", frame.id, frame.name)
                    end
                    ---@type loop.pages.ItemListPage.Item
                    local item = { id = idx, text = text, data = frame }
                    table.insert(items, item)
                end
            end
            self:set_items(items)
        end)
end

function StackTracePage:clear_content()
    self:set_items({})
end

return StackTracePage
