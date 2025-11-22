local M = {}

require('loop.tools.FSM')

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
                    initialize_resp_ok_macos_lldb = "launching",
                    initialize_resp_ok = "configuring",
                    initialize_resp_err = "disconnecting",
                }
            },
            configuring = {
                state_handler = function(...) session:_on_configuring_state(...) end,
                triggers = {
                    configure_success = "launching",
                    configure_success_macos_lldb = "running",
                    configure_error = "terminating",
                    terminated = 'terminating',
                    disconnect = "disconnecting",
                }
            },
            launching = {
                state_handler = function(...) session:_on_launching_state(...) end,
                triggers = {
                    launch_resp_ok = "running",
                    launch_resp_ok_macos_lldb = "configuring",
                    launch_resp_error = "disconnecting",
                }
            },
            running = {
                state_handler = function(...) session:_on_running_state(...) end,
                triggers = {
                    dap_stopped = "stopped",
                }
            },
            stopped = {
                state_handler = function(...) session:_on_stopped_state(...) end,
                triggers = {
                }
            },
            terminating = {
                state_handler = function(...) session:_on_terminating_state(...) end,
                triggers = {
                    terminated = 'disconnecting',
                    terminate_resp_ok = "disconnecting",
                    terminate_resp_err = "kill"
                }
            },
            disconnecting = {
                state_handler = function(...) session:_on_disconnecting_state(...) end,
                triggers = {
                    resp_disconnect_ok = "ended",
                    resp_disconnect_err = "kill"
                }
            },
            kill = {
                state_handler = function(...) session:_on_kill_state(...) end,
                triggers = {
                    kill_ok = "ended",
                    kill_error = "ended"
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
