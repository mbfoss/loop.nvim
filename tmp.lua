function DebugJob:_refresh_debug_sessions_page()
    local page, created = window:get_debugsessions_page()
    ---@type loop.pages.ItemListPage.Item[]
    if created then
        page:add_tracker({
            on_selection = function(item)
                if item then
                    self:_set_current_session(self._sessions[item.id])
                end
            end
        })
    end
    local items = {}
    for id, session in pairs(self._sessions) do
        local current = session == self._current_session
        local prefix = current and "> " or "  "
        ---@type loop.pages.ItemListPage.Item
        local item = {
            id = id,
            text = prefix .. session:name(),
            highlights = current and {
                {
                    group = "Todo",
                    start_col = 0,
                    end_col = 2,
                }
            } or nil
        }
        table.insert(items, item)
    end
    table.sort(items, function(a, b) return a.id < b.id end)
    page:set_items(items)
end




---@param page loop.pages.ItemListPage
---@param session loop.dap.Session
---@param thread_id number|nil
---@param show_buffer boolean
function DebugJob:load_stack_trace(page, session, thread_id, show_buffer)
    local threads = session:stopped_threads()
    if not thread_id then
        page:set_items({ { id = 0, text = string.format("%s paused threads", #threads) } })
        return
    end

    page:set_items({ { id = 0, text = "Loading stack trace..." } })
    session:request_stackTrace({
            threadId = thread_id,
            levels = config.current.debug.stack_levels_limit or 100,
        },
        function(err, resp)
            if not session:thread_is_stopped(thread_id) then
                --probaby continued while we were laoding the stack trace
                return
            end
            if err or not resp then
                page:set_items({
                    { id = 0, text = "Failed to load stack trace" },
                    { id = 1, text = tostring(err) }
                })
                return
            end
            local text = "Thread " .. tostring(thread_id)
            if threads and #threads > 1 then
                text = text .. string.format(" (%s paused threads)", #threads)
            end
            local items = { { id = 0, text = text } }
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
            if resp.stackFrames and #resp.stackFrames > 0 then
                local frame = resp.stackFrames[1]
                if frame.source and frame.source.path and frame.line then
                    signs.remove_signs("currentframe")
                    signs.place_file_sign(frame.source.path, frame.line, "currentframe", "currentframe")
                    if show_buffer then
                        uitools.smart_open_file(frame.source.path, frame.line, frame.column)
                    end
                end
            end
            page:set_items(items)
        end)
end



---@param page loop.pages.ItemListPage
---@param session loop.dap.Session
function DebugJob:select_n_load_stacktrace(page, session)
    local threads = session:stopped_threads()
    if not threads then return end
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
            self:load_stack_trace(session, thread_id, true)
        end
    end)
end


    ---@type loop.pages.ItemListPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = self._stacktrace_pages[sess_id]
    if not page then
        page = window.add_stacktrace_page(session:name())
        self._stacktrace_pages[sess_id] = page
        page:add_tracker({
            on_selection = function(item)
                ---@type loop.pages.ItemListPage.Item
                if item then
                    if item.id == 0 then
                        self:select_n_load_stacktrace(page, session)
                    elseif item.data then
                        local data = item.data
                        ---@cast data loop.dap.proto.StackFrame
                        if data.source and data.source.path then
                            uitools.smart_open_file(data.source.path, data.line, data.column)
                        end
                    end
                end
            end
        })
    end


    ---@param session loop.dap.Session|nil
function DebugJob:_set_current_session(session)
    if session == self._current_session then
        return
    end

    signs.remove_signs("currentframe")

    self._current_session = session
    self:_refresh_debug_sessions_page()

    local ids = breakpoints.get_ids()
    for _, id in ipairs(ids) do
        self:update_breakpoint_status(id)
    end
end

function DebugJob:update_breakpoint_status(id)
    local verified = next(self._sessions) == nil
    for _, session in pairs(self._sessions) do
        local state = session:get_breakpoint_state(id)
        verified = verified or (state or false)
    end
    breakpoints.update_verified_status(id, verified)
end


---@param sess_id number
---@param session loop.dap.Session
---@param event "pause"|"continue"
---@param thread_id number|nil
function DebugJob:_on_session_threads_event(sess_id, session, event, thread_id)
    if event == "pause" then
        self._trackers:invoke("on_thread_paused", sess_id, thread_id)
    elseif event == "continue" then
        signs.remove_signs("currentframe")
    else
        self._trackers:invoke("on_trace","Unhandled event " .. event, "error")
    end
end