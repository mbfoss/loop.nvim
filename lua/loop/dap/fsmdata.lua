local M = {}

require('loop.tools.FSM')

M.trigger =
{
    initialize_resp_ok = "initialize_resp_ok",
    initialize_resp_err = "initialize_resp_err",
    initialized = "initialized",
    launch_resp_ok = "launch_resp_ok",
    launch_resp_error = "launch_resp_error",
    disconnect = "disconnect",
    disconnect_resp_ok = "disconnect_resp_ok",
    disconnect_resp_err = "disconnect_resp_err",
    killed = "killed",
}

---@alias loop.dap.fsmdata.StateHandler fun(trigger:string, triggerdata:any)

---@class loop.dap.fsmdata.StateHandlers
---@field initializing loop.dap.fsmdata.StateHandler
---@field starting loop.dap.fsmdata.StateHandler
---@field running loop.dap.fsmdata.StateHandler
---@field disconnecting loop.dap.fsmdata.StateHandler
---@field kill loop.dap.fsmdata.StateHandler
---@field ended loop.dap.fsmdata.StateHandler

---@param handlers loop.dap.fsmdata.StateHandlers
---@return loop.tools.FSMData
function M.create_fsm_data(handlers)
    ---@type loop.tools.FSMData
    return {
        initial = "initializing",
        states = {
            initializing = {
                state_handler = handlers.initializing,
                triggers = {
                    [M.trigger.initialize_resp_ok] = "starting",
                    [M.trigger.initialize_resp_err] = "disconnecting",
                    [M.trigger.disconnect] = 'disconnecting',
                }
            },
            starting = {
                state_handler = handlers.starting,
                triggers = {
                    [M.trigger.disconnect] = "disconnecting",
                    [M.trigger.launch_resp_ok] = "running",
                    [M.trigger.launch_resp_error] = "disconnecting",
                }
            },
            running = {
                state_handler = handlers.running,
                triggers = {
                    [M.trigger.disconnect] = "disconnecting",
                }
            },
            disconnecting = {
                state_handler = handlers.disconnecting,
                triggers = {
                    [M.trigger.disconnect] = 'disconnecting', --required in some cases
                    [M.trigger.disconnect_resp_ok] = "ended",
                    [M.trigger.disconnect_resp_err] = "kill"
                }
            },
            kill = {
                state_handler = handlers.kill,
                triggers = {
                    [M.trigger.killed] = "ended",
                }
            },
            ended = {
                state_handler = handlers.ended,
                triggers = {}
            },
        }
    }
end

return M
