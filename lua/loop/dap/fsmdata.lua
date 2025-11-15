local M = {}
function M.create_fsm_data(session)
	return {
		initial = "initializing",
		states = {
			initializing = {
				desc = "Initializing",
				state_handler = function(on_response) session:_send_initialize(on_response) end,
				on_success = "launching1",
				--on_error = "disconnecting",
				triggers = {
					initialized = "configuring",
				}
			},
			launching1 = {
				desc = "Launching",
				state_handler = function(on_response) session:_send_launch(on_response, true) end,
				on_success = "configuring",
				-- on_error = "terminating",
				triggers = {
					-- terminated = 'terminated',
					-- disconnect = "disconnect",
				}
			},
			configuring = {
				state_handler = function(on_response) session:_send_configuration(on_response) end,
				reponse_handler = nil,
				on_success = "launching2",
				--on_error = "disconnect",
			},
			launching2 = {
				state_handler = function(on_response) session:_send_launch(on_response) end,
				on_success = "running",
				on_error = nil,
				triggers = {
				}
			},
			running = {
				state_handler = function(on_response) on_response(true) end,
				on_success = nil,
				on_error = nil,
				triggers = {
					stopped = "stopped",
				}
			},
			stopped = {
				state_handler = function(on_response) on_response(true) end,
				on_success = nil,
				on_error = nil,
				triggers = {
					stopped = "stopped",
				}
			},
			--[[
            running = {
                on_enter = function() session.log:info("DAP: Running") end,
                triggers = {
                    terminated = 'disconnect',
                    pause = "paused",
                    terminate = "terminated",
                    disconnect = "disconnect"
                }
            },
            paused = {
                on_enter = function() session.log:info("DAP: Paused") end,
                triggers = {
                    continue = "running",
                    step_over = "paused",
                    step_in = "paused",
                    step_out = "paused",
                    terminate = "disconnect",
                    disconnect = "disconnecting"
                }
            },
            terminating = {
                on_enter = function() session:_send_terminate() end,
                triggers = {
                    terminated = 'disconnect',
                    resp_terminate_ok = "terminated",
                    resp_terminate_err = "killed"
                }
            },
            disconnect = {
                on_enter = function() session:_send_disconnect() end,
                triggers = {
                    resp_disconnect_ok = "ended",
                    resp_disconnect_err = "kill"
                }
            },
            disconnected = {
            },
            kill = {
                on_enter = function() session:_kill("kill_ok", "kill_error") end,
                triggers = {
                    kill_ok = "ended",
                    kill_error = "ended"
                }
            },
            ended = {
                on_enter = function() session.log:info("DAP: session ended") end,
            },
            ]] --
		}
	}
end

return M