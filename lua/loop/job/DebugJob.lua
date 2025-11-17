local Job            = require('loop.job.Job')
local class          = require('loop.tools.class')
local uitools        = require('loop.tools.uitools')
local strtools       = require('loop.tools.strtools')
local Session        = require('loop.dap.Session')

---@alias loop.job.DebugJob.TrackingEvent "session_add"|"session_del"|"session_event"
---@alias loop.job.DebugJob.Tracker fun(event: loop.job.DebugJob.TrackingEvent, args : any)

---@class loop.job.DebugJob : loop.job.Job
---@field new fun(self: loop.job.DebugJob) : loop.job.DebugJob
---@field _tracker loop.job.DebugJob.Tracker
local DebugJob       = class(Job)

---@diagnostic disable-next-line: undefined-field
local main_thread_id = vim.loop.thread_self() -- capture at startup
local function assert_main_thread()
    ---@diagnostic disable-next-line: undefined-field
    assert(vim.loop.thread_self() == main_thread_id, "Not in main thread!")
end

---Initializes the DebugJob instance.
function DebugJob:init()
    ---@type table<number,loop.dap.Session>
    self._sessions = {}
    self._last_session_id = 0
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

    local session_id = self._last_session_id + 1
    self._last_session_id = session_id

    local function session_exit_handler(code)
        -- this runs in the fast event context, so use schedule hereby
        vim.schedule(function()
            self:_notify_tracker("session_del", { id = session_id })
            self._sessions[session_id] = nil
            if next(self._sessions) == nil then
                ---no more sessions
                args.on_exit_handler(code)
            end
        end)
    end

    ---@param session_event loop.session.TrackerEvent
    ---@param session_args any
    local tracker = function(session_event, session_args)
        self:_notify_tracker("session_event", { id = session_id, event = session_event, event_args = session_args })
    end

    ---@type loop.dap.session.Args
    local session_args = {
        name = args.name,
        dap = args.debugger,
        target = args.target,
        tracker = tracker,
        exit_handler = session_exit_handler
    }

    local session = Session:new(session_args)
    self._sessions[session_id] = session

    self:_notify_tracker("session_add", { id = session_id, name = session:name(), state = session:state() })

    return true
end

---@param tracker loop.job.DebugJob.Tracker
function DebugJob:track(tracker)
    assert(not self._tracker)
    self._tracker = tracker
    for id, session in pairs(self._sessions) do
        self._tracker("session_add", { id = id, name = session:name(), state = session:state() })
    end
end

---@param event loop.job.DebugJob.TrackingEvent
---@param args any
function DebugJob:_notify_tracker(event, args)
    if self._tracker then -- before schedule to sync with DebugJob:track()
        vim.schedule(function()
            self._tracker(event, args)
        end)
    end
end

return DebugJob
