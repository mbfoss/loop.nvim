local M = {}

require('loop.tools.FSM')

M.trigger =
{
    initialize_resp_ok_macos_lldb = "initialize_resp_ok_macos_lldb",
    initialize_resp_ok = "initialize_resp_ok",
    initialize_resp_err = "initialize_resp_err",
    configure_success = "configure_success",
    configure_success_macos_lldb = "configure_success_macos_lldb",
    configure_error = "configure_error",
    launch_resp_ok = "launch_resp_ok",
    launch_resp_ok_macos_lldb = "launch_resp_ok_macos_lldb",
    launch_resp_error = "launch_resp_error",
    terminated = "terminated",
    disconnect = "disconnect",
    dap_stopped = "dap_stopped",
    disconnect_resp_ok = "disconnect_resp_ok",
    disconnect_resp_err = "disconnect_resp_err",
    killed = "killed",
}

---@return loop.tools.FSMData
function M.create_fsm_data(session)
    ---@type loop.tools.FSMData
    return {
        initial = "initializing",
        states = {
            initializing = {
                desc = "Initializing",
                state_handler = function(...) session:_on_initializing_state(...) end,
                triggers = {
                    [M.trigger.initialize_resp_ok_macos_lldb] = "launching",
                    [M.trigger.initialize_resp_ok] = "configuring",
                    [M.trigger.initialize_resp_err] = "disconnecting",
                }
            },
            configuring = {
                state_handler = function(...) session:_on_configuring_state(...) end,
                triggers = {
                    [M.trigger.configure_success] = "launching",
                    [M.trigger.configure_success_macos_lldb] = "running",
                    [M.trigger.configure_error] = "disconnecting",
                    [M.trigger.terminated] = 'disconnecting',
                    [M.trigger.disconnect] = "disconnecting",
                }
            },
            launching = {
                state_handler = function(...) session:_on_launching_state(...) end,
                triggers = {
                    [M.trigger.launch_resp_ok] = "running",
                    [M.trigger.launch_resp_ok_macos_lldb] = "configuring",
                    [M.trigger.launch_resp_error] = "disconnecting",
                }
            },
            running = {
                state_handler = function(...) session:_on_running_state(...) end,
                triggers = {
                    [M.trigger.dap_stopped] = "stopped",
                }
            },
            stopped = {
                state_handler = function(...) session:_on_stopped_state(...) end,
                triggers = {
                }
            },
            disconnecting = {
                state_handler = function(...) session:_on_disconnecting_state(...) end,
                triggers = {
                    [M.trigger.disconnect_resp_ok] = "ended",
                    [M.trigger.disconnect_resp_err] = "kill"
                }
            },
            kill = {
                state_handler = function(...) session:_on_kill_state(...) end,
                triggers = {
                    [M.trigger.killed] = "ended",
                }
            },
            ended = {
                state_handler = function(...) session:_on_ended_state(...) end,
                triggers = {}
            },
        }
    }
end

return M
