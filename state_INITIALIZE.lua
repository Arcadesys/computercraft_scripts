-- State: INITIALIZE
-- Handles validation, chest detection, and first-time setup before building.
local shared = require("factoryrefactor")

local function run(ctx)
  shared.states[shared.STATE_INITIALIZE](ctx)
  return ctx.currentState or shared.STATE_INITIALIZE
end

return {
  run = run,
}
