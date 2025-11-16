
function ___Session:_send_launch(on_response, pre_initialize)
    if pre_initialize then
        if not self.is_apple_lldb then
            on_response(true)
            return
        end
    else
        if self.is_apple_lldb then
            on_response(true)
            return
        end
    end
    if self.launched then
        self.log:error("Unexpected launch request")
        on_response(false)
        return
    end
    self.launched                    = true
end

function ___Session:_send_terminate()
    self._base_session:request_terminate(function(response)
        if response.success then
            self._fsm:trigger("resp_terminate_ok")
        else
            self.log:log("DAP termination error: " .. response.message)
            self._fsm:trigger("resp_terminate_err")
        end
    end)
end

function ___Session:_send_disconnect()
    self._base_session:request_disconnect(function(response)
        if response.success then
            self._fsm:trigger("resp_disconnect_ok")
        else
            self.log:log("DAP termination error: " .. response.message)
            self._fsm:trigger("resp_disconnect_err")
        end
    end)
end

function ___Session:_kill()
    self._base_session.kill()
end

function ___Session:current_state()
    return self._fsm.current
end
