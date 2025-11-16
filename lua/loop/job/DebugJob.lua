local Job            = require('loop.job.Job')
local class          = require('loop.tools.class')
local uitools        = require('loop.tools.uitools')
local strtools       = require('loop.tools.strtools')
local Session        = require('loop.dap.Session')

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
    self.sessions = {}
    self.last_session_id = 0
end

---@return boolean
function DebugJob:is_running()
    return next(self.sessions) ~= nil
end

function DebugJob:kill()
    for _, s in pairs(self.sessions) do
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
    if #self.sessions > 0 then
        return false, "A debug job is already running"
    end

    assert(args.on_exit_handler)

    local function exit_handler(code)
        -- this runs in the fast event context, so use schedule hereby
        vim.schedule(function()
            args.on_exit_handler(code)
        end)
    end

    local session_id = self.last_session_id + 1
    self.last_session_id = session_id

    local output_handler = function()
        assert_main_thread()
        self.sessions[session_id] = nil
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
    self.sessions[session_id] = session
    return true
end

return DebugJob
