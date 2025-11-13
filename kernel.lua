-- kernel.lua
-- Main driver that loads the modular state handlers for the factory builder.
local manifest = require("states_manifest")
local shared = require("factoryrefactor")

local ctx = shared.context
local state = manifest.initial_state

print("Factory Builder kernel - Starting")
if ctx.manifestPath then
  print("Manifest: " .. ctx.manifestPath)
end
if ctx.width and ctx.height and ctx.depth then
  print(string.format("Build size: %dx%dx%d", ctx.width, ctx.height, ctx.depth))
end

while state do
  ctx.currentState = state

  local moduleName = manifest.modules[state]
  assert(moduleName, "No module registered for state " .. tostring(state))
  local mod = require("states." .. moduleName)

  local result = mod.run(ctx) or state

  if state == shared.STATE_DONE then
    break
  end

  local transitions = manifest.transitions[state]
  assert(transitions, "No transitions defined for state " .. tostring(state))

  local nextState = transitions[result]
  assert(nextState, string.format("No transition for state %s via result %s", tostring(state), tostring(result)))

  state = nextState
end

if shared.goToOriginDirectly then
  print("Returning to origin...")
  shared.goToOriginDirectly()
  print("Factory build finished successfully.")
end
