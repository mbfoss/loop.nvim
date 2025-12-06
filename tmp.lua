--[[

---@param command loop.job.DebugJob.Command|nil
---@return boolean,string|nil
function DebugJob:debug_command(command)
    local active_session = 1 -- TODO: make this selectable from the UI
    local session = self._sessions[active_session]
    if not session then
        return false, "no active sessions"
    end
    if command == 'continue' then
        for _, s in pairs(self._sessions) do
            s:debug_continue()
        end
    elseif command == "step_in" then
        session:debug_stepIn()
    elseif command == "step_out" then
        session:debug_stepOut()
    elseif command == "step_over" then
        session:debug_stepOver()
    elseif command == "terminate" then
        session:debug_terminate()
    elseif command == "terminate_all" then
        for _, s in pairs(self._sessions) do
            s:debug_terminate()
        end
    else
        return false, "Invalid debug command: " .. tostring(command)
    end
    return true
end

]]