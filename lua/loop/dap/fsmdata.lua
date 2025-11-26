local M = {}

require('loop.tools.FSM')

M.trigger =
{
    initialize_resp_ok = "initialize_resp_ok",
    initialize_resp_err = "initialize_resp_err",
    initialized = "initialized",
    configure1_success = "configure1_success",
    configure1_error = "configure1_error",
    configure2_success = "configure2_success",
    configure2_error = "configure2_error",
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
---@field waiting_initialized loop.dap.fsmdata.StateHandler
---@field configuring1 loop.dap.fsmdata.StateHandler
---@field launching loop.dap.fsmdata.StateHandler
---@field configuring2 loop.dap.fsmdata.StateHandler
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
                    [M.trigger.initialize_resp_ok] = "waiting_initialized",
                    [M.trigger.initialize_resp_err] = "disconnecting",
                    [M.trigger.disconnect] = 'disconnecting',
                }
            },
            waiting_initialized = {
                state_handler = handlers.waiting_initialized,
                triggers = {
                    [M.trigger.initialized] = "configuring1",
                    [M.trigger.disconnect] = 'disconnecting',
                }
            },
            configuring1 = {
                state_handler = handlers.configuring1,
                triggers = {
                    [M.trigger.disconnect] = "disconnecting",
                    [M.trigger.configure1_success] = "launching",
                    [M.trigger.configure1_error] = "disconnecting",
                }
            },
            launching = {
                state_handler = handlers.launching,
                triggers = {
                    [M.trigger.disconnect] = "disconnecting",
                    [M.trigger.launch_resp_ok] = "configuring2",
                    [M.trigger.launch_resp_error] = "disconnecting",
                }
            },
            configuring2 = {
                state_handler = handlers.configuring2,
                triggers = {
                    [M.trigger.disconnect] = "disconnecting",
                    [M.trigger.configure2_success] = "running",
                    [M.trigger.configure2_error] = "disconnecting",
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
