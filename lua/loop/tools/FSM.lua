local class = require('loop.tools.class')

local FSM = class()

function FSM:init(name, fsm_data)
    self.log = require('loop.tools.Logger').create_logger("fsm." .. name)
    self.states = fsm_data.states or {}
    self.current = fsm_data.initial
    self.log:info("FSM created. Current state: " .. (self.current or "nil"))
    self.started = false
end

function FSM:start()
    assert(self.current ~= nil)
    assert(self.started == false)

    self.started = true
    self:_call_state_handler()
end

function FSM:trigger(trigger)
    vim.schedule(function()
        self:_trigger(trigger)
    end)
end

function FSM:_trigger(trigger)
    if not self.current then
        self.log:warn("FSM has no current state")
        return
    end

    local state_data = self.states[self.current]
    local next_state = state_data.triggers and state_data.triggers[trigger]
    if next_state then
        self:_change_state(next_state, "trigger: " .. trigger)
    else
        self.log:warn("Trigger '" .. trigger .. "' not valid from state '" .. self.current .. "'")
    end
end

function FSM:_change_state(next_state, reason)
    assert(next_state ~= nil)
    self.log:info("State change '" .. self.current .. "' -> '" .. next_state .. "' (" .. reason .. ")")
    self.current = next_state
    self:_call_state_handler()
end

function FSM:_call_state_handler()
    local state = self.current
    local state_data = self.states[state]
    assert(state_data ~= nil)

    local handler = state_data.state_handler
    if not handler then
        self.log:error("No state_handler for state '" .. state .. "'")
        return
    end

    local cb_error = function(err)
        self.log:error("In FSM callback for " .. (state or "?") .. "\n" .. debug.traceback(
            "Error: " .. tostring(err) .. "\n", 2))
    end

    local ok, _ = xpcall(handler, cb_error)
    if not ok then
        self.log:error({ "Error in state handler for ", state })
    end
end

return FSM
