-- Auto-generated state registry mapping state names to module files.
-- Transitions use identity mapping so handlers can return the next state's name directly.
local function identityTransitions(...)
  local map = {}
  for _, state in ipairs({ ... }) do
    map[state] = state
  end
  return map
end

return {
  initial_state = "INITIALIZE",
  modules = {
    INITIALIZE = "state_INITIALIZE",
    BUILD = "state_BUILD",
    SERVICE = "state_SERVICE",
    ERROR = "state_ERROR",
    BLOCKED = "state_BLOCKED",
    DONE = "state_DONE",
  },
  transitions = {
    INITIALIZE = identityTransitions("INITIALIZE", "BUILD", "SERVICE", "ERROR", "BLOCKED", "DONE"),
    BUILD = identityTransitions("BUILD", "SERVICE", "ERROR", "BLOCKED", "DONE"),
    SERVICE = identityTransitions("SERVICE", "BUILD", "ERROR", "BLOCKED"),
    ERROR = identityTransitions("ERROR", "INITIALIZE", "BUILD", "SERVICE", "BLOCKED"),
    BLOCKED = identityTransitions("BLOCKED", "ERROR", "BUILD", "SERVICE"),
    DONE = identityTransitions("DONE"), -- Terminal state remains in DONE
  },
}
