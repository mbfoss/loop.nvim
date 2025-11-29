local class       = require('loop.tools.class')
local config      = require('loop.config')
local Job         = require('loop.job.Job')
local Session     = require('loop.dap.Session')
local TermProc    = require('loop.tools.TermProc')
local window      = require('loop.window')
local selector    = require("loop.selector")
local uitools     = require('loop.tools.uitools')
local signs       = require('loop.signs')
local breakpoints = require('loop.dap.breakpoints')

---@alias loop.job.DebugJob.Command "continue"|"step_in"|"step_out"|"step_over"|"terminate"

---@class loop.job.DebugJob : loop.job.Job
---@field new fun(self: loop.job.DebugJob) : loop.job.DebugJob
---@field _sessions table<number,loop.dap.Session>
---@field _last_session_id number
---@field _task_page loop.pages.OutputPage
---@field _output_pages table<number,loop.pages.OutputPage>
---@field _stacktrace_pages table<number,loop.pages.ItemListPage>
---@field _current_session loop.dap.Session|nil
local DebugJob    = class(Job)

---Initializes the DebugJob instance.
function DebugJob:init()
    ---@type table<number,loop.dap.Session>
    self._sessions = {}
    self._last_session_id = 0
    self._output_pages = {}
    self._stacktrace_pages = {}
end

---@return boolean
function DebugJob:is_running()
    return next(self._sessions) ~= nil
end

function DebugJob:kill()
    for _, s in pairs(self._sessions) do
        s:kill()
    end
end

---@class loop.DebugJob.StartArgs
---@field name string
---@field debug_args loop.dap.session.DebugArgs
---@field on_exit_handler fun(code : number)


---Starts a new terminal job.
---@param args loop.DebugJob.StartArgs
---@return boolean, string|nil
function DebugJob:start(args)
    if #self._sessions > 0 then
        return false, "A debug job is already running"
    end

    assert(args.on_exit_handler)
    self._on_exit_handler = args.on_exit_handler

    self._task_page = window.add_debug_task_page(args.name)

    return self:add_new_session(args.name, args.debug_args)
end

---@param name string
---@param debug_args loop.dap.session.DebugArgs
---@param parent_sess_id number|nil
---@return boolean,string|nil
function DebugJob:add_new_session(name, debug_args, parent_sess_id)
    local session_id      = self._last_session_id + 1
    self._last_session_id = session_id

    ---@param session loop.dap.Session
    ---@param event loop.session.TrackerEvent
    ---@param event_data any
    local tracker         = function(session, event, event_data)
        self:_on_session_event(session_id, session, event, event_data)
    end

    local exit_handler    = function(code)
        self:_session_exit_handler(session_id, code)
    end


    ---@type loop.dap.session.Args
    local session_args = {
        name = name,
        debug_args = debug_args,
        tracker = tracker,
        exit_handler = exit_handler,
    }

    -- start new session
    local session = Session:new()

    local started, start_err = session:start(session_args)
    if not started then
        return false, "Failed to start debug session, " .. start_err
    end

    self._sessions[session_id] = session

    if not self._current_session then
        self._current_session = session
    end

    self._task_page:add_lines({ "New debug session started: " ..
    tostring(session_id) .. ' (' .. tostring(name) .. ')' })

    self:_refresh_debug_sessions_page()

    return true, nil
end

function DebugJob:_session_exit_handler(session_id, code)
    vim.schedule(function()
        if self._current_session == self._sessions[session_id] then
            self._sessions[session_id] = nil
            local _, next = next(self._sessions)
            self:_set_current_session(next)
        else
            self._sessions[session_id] = nil
        end

        local page = self._stacktrace_pages[session_id]
        if page then
            page:set_items({})
        end

        if self._task_page then
            self._task_page:add_lines({ "Session " ..
            tostring(session_id) .. " debugger exited (code " .. tostring(code) .. ")" })
        end

        if next(self._sessions) == nil then
            ---no more sessions
            self._on_exit_handler(code)
            breakpoints.reset_verified_status()
        end
    end)
end

function DebugJob:_refresh_debug_sessions_page()
    local page, created = window:get_debugsessions_page()
    ---@type loop.pages.ItemListPage.Item[]
    if created then
        page:set_select_handler(function(item)
            if item then
                self:_set_current_session(self._sessions[item.id])
            end
        end)
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

---@param command loop.job.DebugJob.Command|nil
function DebugJob:debug_command(command)
    if not self._current_session then
        return
    end
    if command == 'continue' then
        for _, s in pairs(self._sessions) do
            s:debug_continue()
        end
    elseif command == "step_in" then
        self._current_session:debug_stepIn()
    elseif command == "step_out" then
        self._current_session:debug_stepOut()
    elseif command == "step_over" then
        self._current_session:debug_stepOver()
    elseif command == "terminate" then
        self._current_session:debug_terminate()
    else
        self._task_page:add_lines({ 'loop.nvim: Invalid debug command: ' .. tostring(command) }, "error")
    end
end

---@param sess_id number
---@param session loop.dap.Session
---@param event loop.session.TrackerEvent
---@param event_data any
function DebugJob:_on_session_event(sess_id, session, event, event_data)
    if event == "log" then
        ---@type loop.dap.session.notify.LogData
        local log = event_data
        self._task_page:add_lines(vim.list_extend({ "Session " .. sess_id .. " " .. log.level }, log.lines))
        return
    end
    if event == "state" then
        ---@type loop.dap.session.notify.StateData
        local state = event_data
        self._task_page:add_lines({ "Session " .. sess_id .. " " .. state.state })
        return
    end
    if event == "output" then
        ---@type loop.dap.proto.OutputEvent
        local output = event_data
        if output.category == "stdout" or output.category == "stderr" then
            self:add_debug_output(sess_id, session:name(), output.category, output.output)
        elseif output.category == "console" then
            self._task_page:add_lines({ "Session " .. tostring(sess_id) .. ": " .. tostring(output.output) })
        else
            self._task_page:add_lines({ "Session " ..
            tostring(sess_id) .. ": (" .. tostring(output.category) .. ") " .. tostring(output.output) })
        end
        return
    end
    if event == "runInTerminal_request" then
        ---@type loop.dap.session.notify.RunInTerminalReq
        local request = event_data
        self:add_debug_term(session:name(), request.args, request.on_success, request.on_failure)
        return
    end
    if event == "threads_paused" then
        self:_on_session_threads_event(sess_id, session, "pause", event_data.thread_id)
        return
    end
    if event == "threads_continued" then
        self:_on_session_threads_event(sess_id, session, "continue")
        return
    end
    if event == "breakpoints" then
        ---@type loop.dap.session.notify.BreakpointsEvent
        local data = event_data
        self:_on_session_breakpoints_event(sess_id, session, data)
        return
    end
    if event == "debuggee_exit" then
        self:_on_session_debuggee_exit(sess_id, session)
        return
    end
    if event == "subsession_request" then
        ---@type loop.dap.session.notify.SubsessionRequest
        local request = event_data
        self:_on_subsession_request(sess_id, session, request)
        return
    end
    error("unhandled dap session event: " .. event)
end

---@param sess_id number
---@param sess_name string
---@param category string
---@param output string
function DebugJob:add_debug_output(sess_id, sess_name, category, output)
    ---@type loop.pages.OutputPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = self._output_pages[sess_id]
    if not page then
        page = window.add_debug_output_page(sess_name)
        self._output_pages[sess_id] = page
    end
    local level = category == "stderr" and "error" or nil
    page:add_lines({ output }, level)
end

---@param name string
---@param args loop.dap.proto.RunInTerminalRequestArguments
---@param on_success fun(pid:number)
---@param on_failure fun(reason:string)
function DebugJob:add_debug_term(name, args, on_success, on_failure)
    --vim.notify(vim.inspect{name, args, on_success, on_failure})

    assert(type(name) == "string")
    assert(type(args) == "table")
    assert(type(on_success) == "function")
    assert(type(on_failure) == "function")

    local proc = TermProc:new()
    local bufnr, proc_err = proc:start({
        name = name,
        command = args.args,
        env = args.env,
        cwd = args.cwd,
        on_exit_handler = function(code)
        end
    })
    if bufnr <= 0 then
        on_failure(proc_err or "target startup error")
        return
    end

    local pid = proc:get_pid()
    window.add_debug_term_page(name, bufnr)
    on_success(pid)
end

---@param page loop.pages.ItemListPage
---@param session loop.dap.Session
---@param thread_id number|nil
function DebugJob:load_stack_trace(page, session, thread_id)
    local threads = session:stopped_threads()
    if not thread_id then
        page:set_items({ { id = 0, text = string.format("%s paused threads", #threads) } })
        return
    end

    page:set_items({ { id = 0, text = "Loading stack trace..." } })
    window.show_stacktrace()
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
                end
            end
            page:set_items(items)
            window.show_stacktrace()
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
            self:load_stack_trace(page, session, thread_id)
        end
    end)
end

---@param sess_id number
---@param session loop.dap.Session
---@param event "pause"|"continue"
---@param thread_id number|nil
function DebugJob:_on_session_threads_event(sess_id, session, event, thread_id)
    ---@type loop.pages.ItemListPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = self._stacktrace_pages[sess_id]
    if not page then
        page = window.add_stacktrace_page(session:name())
        self._stacktrace_pages[sess_id] = page
        page:set_select_handler(function(item)
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
        end)
    end
    if event == "pause" then
        self:_set_current_session(session)
        self:load_stack_trace(page, session, thread_id)
    elseif event == "continue" then
        signs.remove_signs("currentframe")
        page:set_items({ { id = 0, text = "No paused threads" } })
    else
        self._task_page:add_lines({ "Unhandled event " .. event }, "error")
    end
end

---@param sess_id number
---@param session loop.dap.Session
---@param event loop.dap.session.notify.BreakpointsEvent
function DebugJob:_on_session_breakpoints_event(sess_id, session, event)
    if session == self._current_session then
        for _, state in ipairs(event) do
            self:update_breakpoint_status(state.id)
        end
    end
end

---@param sess_id number
---@param session loop.dap.Session
function DebugJob:_on_session_debuggee_exit(sess_id, session)
end

---@param sess_id number
---@param session loop.dap.Session
---@param request loop.dap.session.notify.SubsessionRequest
function DebugJob:_on_subsession_request(sess_id, session, request)
    local dapreq_type = request.dap_request.request -- "launch" or "attach"
    local dapreq_args = request.dap_request.configuration or {}

    if dapreq_type ~= "launch" and dapreq_type ~= "attach" then
        return request.on_failure("Unsupported request type: " .. tostring(dapreq_type))
    end

    self._task_page:add_lines({ "Starting subsession via startDebugging: " .. dapreq_type })

    ---@type loop.dap.session.DebugArgs
    local child_debug_args = {
        dap         = request.dap_config,
        request     = dapreq_type,
        launch_args = dapreq_type == "launch" and dapreq_args or nil,
        attach_args = dapreq_type == "attach" and dapreq_args or nil,
    }

    local ok, err = self:add_new_session(request.name, child_debug_args)
    if not ok then
        return request.on_failure("failed to startup child session, " .. tostring(err))
    end
    request.on_success({})
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

return DebugJob
