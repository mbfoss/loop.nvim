        self._base_session:request_threads(function(response)
            if not response.success then
                ---@type loop.dap.session.notify.LogData
                local logdata = { level = "error", lines = { "Failed to query threads", response.message } }
                self:_notify_tracker("log", logdata)
                return
            end
            ---@type loop.dap.proto.ThreadsResponse
            local data = response.body
            self:_notify_tracker("threads", data)
        end)      
    end


---@param context table
---@param sess_id number
---@param sess_name string
---@param msg loop.dap.proto.ThreadsResponse
function DebugJob:show_debug_threads(context, sess_id, sess_name, msg)
    context.threads_pages = context.threads_pages or {}

    ---@type loop.pages.ItemListPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = context.threads_pages[sess_id] or nil
    if not page then
        page = ItemListPage:new(sess_name)
        context.threads_pages[sess_id] = page
        _add_tab_page(_tabs.threads, page)
    end
    ---@type loop.pages.ItemListPage.Item[]
    items = {}
    for _, thread in ipairs(msg.threads) do
        ---@type loop.pages.ItemListPage.Item
        local item = {
            id = thread.id,
            text = tostring(thread.id) .. ': ' .. tostring(thread.name)
        }
        table.insert(items, item)
    end
    page:set_items(items)
end

--@param context table
---@param sess_id number
---@param sess_name string
---@param msg loop.dap.proto.StackTraceResponse
function DebugJob:show_debug_stacktrace(context, sess_id, sess_name, msg)
    context.stacktrace_pages = context.stacktrace_pages or {}

    ---@type loop.pages.ItemListPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = context.stacktrace_pages[sess_id] or nil
    if not page then
        page = ItemListPage:new(sess_name)
        context.stacktrace_pages[sess_id] = page
        _add_tab_page(_tabs.stacktrace, page)
    end
    ---@type loop.pages.ItemListPage.Item[]
    items = { { id = 0, text = string.format("Session %d (%s)", sess_id, sess_name) } }
    for idx, frame in ipairs(msg.stackFrames) do
        local text
        if frame.source then
            text = string.format("%d: %s - %s:%d:%d",
                frame.id, frame.name, frame.source.name, frame.line, frame.column)
        else
            text = string.format("%d: %s", frame.id, frame.name)
        end
        ---@type loop.pages.ItemListPage.Item
        local item = { id = idx, text = text }
        table.insert(items, item)
    end
    page:set_items(items)
end
