local Job            = require('loop.job.Job')
local class          = require('loop.tools.class')
local uitools        = require('loop.tools.uitools')
local strtools       = require('loop.tools.strtools')
local Session        = require('loop.dap.Session')

---@alias loop.job.DebugJob.NewSessionHandler fun(id:number, session:loop.dap.Session)

---@class loop.job.DebugJob : loop.job.Job
---@field new fun(self: loop.job.DebugJob) : loop.job.DebugJob
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

    local function exit_handler(code)
        -- this runs in the fast event context, so use schedule hereby
        vim.schedule(function()
            args.on_exit_handler(code)
            if self.on_sessions_updated then
                self.on_sessions_updated(false, session_id, nil)
            end
        end)
    end

    local output_handler = function()
        assert_main_thread()
        self._sessions[session_id] = nil
        --TODO
    end

    ---@type loop.dap.session.Args
    local session_args = {
        name = args.name,
        dap = args.debugger,
        target = args.target,
        output_handler = output_handler,
        exit_handler = exit_handler
    }

    local session = Session:new(session_args)
    self._sessions[session_id] = session

    if self._new_session_handlers then
        for _,handler in ipairs(self._new_session_handlers) do
            handler(session_id, session)
        end
    end
    
    return true
end

---@param on_new_session loop.job.DebugJob.NewSessionHandler
---@return table<number,loop.dap.Session>
function DebugJob:track_sessions(on_new_session)
    --shallow clone
    local copy = {}
    for k, v in pairs(self._sessions) do
        copy[k] = v
    end
    if not self._new_session_handlers then
        self._new_session_handlers = {}
    end
    table.insert(self._new_session_handlers, on_new_session)
    return copy
end

return DebugJob
