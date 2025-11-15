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
    ---@type loop.dap.Session[]
    self.sessions = {}
end

---@return boolean
function DebugJob:is_running()
    return #self.sessions > 0
end

function DebugJob:kill()
    error("Not implemented")
end

---@class loop.DebugJob.StartArgs
---@field bufnr number
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

    assert(args.bufnr > 0)
    assert(args.on_exit_handler)

    local output_handler = function()
        assert_main_thread()
        --TODO
    end

    ---@type loop.dap.session.Args
    local session_args = {
        name = args.name,
        dap = args.debugger,
        target = args.target,
        output_handler = output_handler,
        exit_handler = args.on_exit_handler
    }
    local session = Session:new(session_args)
    table.insert(self.sessions, session)
    return true
end

return DebugJob
