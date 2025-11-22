local Job      = require('loop.job.Job')
local class    = require('loop.tools.class')
local uitools  = require('loop.tools.uitools')
local strtools = require('loop.tools.strtools')
local Session  = require('loop.dap.Session')
local TermProc = require('loop.tools.TermProc')
local window   = require('loop.window')

---@class loop.job.DebugJob : loop.job.Job
---@field new fun(self: loop.job.DebugJob) : loop.job.DebugJob
---@field _sessions table<number,loop.dap.Session>
---@field _last_session_id number
---@field _task_page loop.pages.OutputPage
---@field _output_pages table<number,loop.pages.OutputPage>
---@field _stacktrace_pages table<number,loop.pages.ItemListPage>
local DebugJob = class(Job)

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
    self._sessions = {}
end

---@class loop.DebugJob.StartArgs
---@field name string
---@field debugger loop.dap.session.Args.DAP
---@field target loop.dap.session.Args.Target
---@field on_exit_handler fun(code : number)

---Starts a new terminal job.
---@param args loop.DebugJob.StartArgs
---@return boolean, string|nil
function DebugJob:start(args)
    if #self._sessions > 0 then
        return false, "A debug job is already running"
    end

    assert(args.on_exit_handler)

    local cmd_parts = strtools.cmd_to_string_array(args.target.cmd)
    local name = vim.fn.fnamemodify(cmd_parts[1] or "", ":t")

    if vim.fn.executable(cmd_parts[1]) == 0 then
        return false, "Debug target is not an executable: " .. tostring(cmd_parts[1])
    end

    local session_id = self._last_session_id + 1
    self._last_session_id = session_id

    local function session_exit_handler(code)
        -- this runs in the fast event context, so use schedule hereby
        vim.schedule(function()
            self._sessions[session_id] = nil
            if next(self._sessions) == nil then
                ---no more sessions
                args.on_exit_handler(code)
            end
            if self._task_page then
                self._task_page:add_lines({ "Session ended: " .. tostring(session_id) .. ' - ' .. tostring(args.name) })
            end
        end)
    end

    ---@param session loop.dap.Session
    ---@param event loop.session.TrackerEvent
    ---@param event_data any
    local tracker = function(session, event, event_data)
        self:_on_session_event(session_id, session, event, event_data)
    end

    ---@type loop.dap.session.Args
    local session_args = {
        name = name,
        dap = args.debugger,
        target = args.target,
        tracker = tracker,
        exit_handler = session_exit_handler
    }

    local session = Session:new()
    local started, start_err = session:start(session_args)
    if not started then
        return false, "Failed to start debug session, " .. start_err
    end

    self._sessions[session_id] = session

    self._task_page = window.add_debug_task_page(args.name)

    self._task_page:add_lines({ "New debug session started: " .. tostring(session_id) .. ' - ' .. tostring(args.name) })

    return true
end

function DebugJob:debug_continue()
    for _, s in pairs(self._sessions) do
        s:debug_continue()
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
        self._task_page:add_lines({ "Session " .. sess_id .. " state: " .. state.state })
        return
    end
    if event == "output" then
        ---@type loop.dap.proto.OutputEvent
        local output = event_data
        if output.category == "stdout" or output.category == "stderr" then
            self:add_debug_output(sess_id, session:name(), output.category, output.output)
        end
        if output.category == "console" then
            self._task_page:add_lines({ "Session " .. sess_id .. ": " .. output.output })
        else
            self._task_page:add_lines({ "Session " .. sess_id .. ": (" .. output.category ") " .. output.output })
        end
        return
    end
    if event == "runInTerminal_request" then
        ---@type loop.dap.session.notify.RunInTerminalReq
        local request = event_data
        self:add_debug_term(session:name(), request.args, request.on_success, request.on_failure)
        return
    end
    if event == "stopped" then
        ---@type loop.dap.proto.StoppedEvent
        local event = event_data
        self:_on_session_stop_event(sess_id, session, event)
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

---@param sess_id number
---@param session loop.dap.Session
---@param stopped_event loop.dap.proto.StoppedEvent
function DebugJob:_on_session_stop_event(sess_id, session, stopped_event)
    ---@type loop.pages.ItemListPage|nil
    ---@diagnostic disable-next-line: assign-type-mismatch
    local page = self._stacktrace_pages[sess_id]
    if not page then
        page = window.add_stacktrace_page(session:name())
        self._stacktrace_pages[sess_id] = page
    end
    page:set_items({ { id = 0, text = "Loading stack trace..." } })
    session:request_stackTrace({
            threadId = stopped_event.threadId,
            levels = 100, --TODO: make configurable
        },
        function(response)
            if not response.success then
                page:set_items({
                    { id = 0, text = "Failed to load stack trace" },
                    { id = 1, text = tostring(response.message) }
                })
                return
            end
            local data = response.body
            ---@cast data loop.dap.proto.StackTraceResponse
            local items = { { id = 0, text = string.format("Session %d (%s)", sess_id, session:name()) } }
            for idx, frame in ipairs(data.stackFrames) do
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
        end)
end

return DebugJob
