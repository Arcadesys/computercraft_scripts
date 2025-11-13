-- State: BLOCKED
-- Responds to movement obstructions by retreating and retrying.
local shared = require("factoryrefactor")

local function run(ctx)
  shared.states[shared.STATE_BLOCKED](ctx)
  return ctx.currentState or shared.STATE_BLOCKED
end

return {
  run = run,
}
