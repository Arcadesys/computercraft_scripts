-- State: ERROR
-- Handles blocking failures and prepares the context to retry.
local shared = require("factoryrefactor")

local function run(ctx)
  shared.states[shared.STATE_ERROR](ctx)
  return ctx.currentState or shared.STATE_ERROR
end

return {
  run = run,
}
