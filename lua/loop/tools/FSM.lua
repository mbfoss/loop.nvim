local class = require('loop.tools.class')

---@class loop.tools.FSMState
---@field state_handler fun()               # Called when state becomes active.
---@field triggers table<string,string>         # Valid triggers for this state.

---@class loop.tools.FSMData
---@field initial string                    # Name of the initial state.
---@field states table<string, loop.tools.FSMState>   # Map: state name → state definition.

---@class loop.tools.FSM
---@field log any
---@field states table<string, loop.tools.FSMState>
---@field current string|nil
---@field started boolean
---@field valid_triggers table<string,boolean>
---@field new fun(self: loop.tools.FSM, name : string, fsmdata : loop.tools.FSMData) : loop.tools.FSM
local FSM = class()

--- Initialize the FSM.
---@param name string: Name used for logging.
---@param fsmdata loop.tools.FSMData: Configuration object containing initial state and state table.
function FSM:init(name, fsmdata)
    self.log = require('loop.tools.Logger').create_logger("fsm." .. name)
    self.states = fsmdata.states or {}
    self.current = fsmdata.initial
    self.started = false

    self.valid_triggers = {}
    for n, s in pairs(fsmdata.states) do
        assert(s.triggers, "triggers missing in state: " .. tostring(n))
        for t, tgt in pairs(s.triggers) do
            self.valid_triggers[t] = true
            assert(self.states[tgt], "Invalid target state in trigger: " .. tostring(t) .. ', in state: ' .. tostring(n))
        end
    end

    self.log:info("FSM created. Current state: " .. (self.current or "nil"))
end

--- Start the FSM by calling the state_handler of the initial state.
-- Must not have been started already.
function FSM:start()
    assert(self.current ~= nil, "FSM has no initial state")
    assert(self.started == false, "FSM already started")

    self.started = true
    self:_call_state_handler()
end

--- Trigger a transition asynchronously via vim.schedule().
-- This avoids recursive trigger issues inside state handlers.
---@param trigger string
function FSM:trigger(trigger)
    assert(self.valid_triggers[trigger] == true, "Invalid trigger: " .. tostring(trigger))
    vim.schedule(function()
        self:_trigger(trigger)
    end)
end

---@return string
function FSM:curr_state()
    return self.current
end

--- Internal trigger handler (synchronous).
-- Looks up the next state and performs the transition.
---@param trigger string
function FSM:_trigger(trigger)
    if not self.current then
        self.log:warn("FSM has no current state")
        return
    end

    local state_data = self.states[self.current]
    if not state_data then
        self.log:error("No state data for state '" .. tostring(self.current) .. "'")
        return
    end

    local next_state = state_data.triggers and state_data.triggers[trigger]
    if next_state then
        self:_change_state(next_state, "trigger: " .. trigger)
    else
        self.log:warn("Trigger '" .. trigger .. "' not valid from state '" .. self.current .. "'")
    end
end

--- Internal function: change the current state and call the new state's handler.
---@param next_state string
---@param reason string
function FSM:_change_state(next_state, reason)
    assert(next_state ~= nil, "next_state cannot be nil")

    self.log:info("State change '" ..
        tostring(self.current) .. "' -> '" .. tostring(next_state) ..
        "' (" .. reason .. ")")

    self.current = next_state
    self:_call_state_handler()
end

--- Internal: call the state handler for the current state.
-- Uses xpcall to log errors with traceback.
function FSM:_call_state_handler()
    local state = self.current
    local state_data = self.states[state]
    assert(state_data ~= nil, "Missing state data for '" .. tostring(state) .. "'")

    local handler = state_data.state_handler
    if not handler then
        self.log:error("No state_handler for state '" .. tostring(state) .. "'")
        return
    end

    local cb_error = function(err)
        self.log:error("In FSM callback for " ..
            (state or "?") .. "\n" ..
            debug.traceback("Error: " .. tostring(err) .. "\n", 2))
    end

    local ok = xpcall(handler, cb_error)
    if not ok then
        self.log:error({ "Error in state handler for ", state })
    end
end

return FSM
