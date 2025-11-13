-- State: BUILD
-- Places the next block in the manifest-driven sequence.
local shared = require("factoryrefactor")

local function run(ctx)
  shared.states[shared.STATE_BUILD](ctx)
  return ctx.currentState or shared.STATE_BUILD
end

return {
  run = run,
}
