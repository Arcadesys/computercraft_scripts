-- State: DONE
-- Finalizes the build once all work is complete.
local shared = require("factoryrefactor")

local function run(ctx)
  shared.states[shared.STATE_DONE](ctx)
  return ctx.currentState or shared.STATE_DONE
end

return {
  run = run,
}
