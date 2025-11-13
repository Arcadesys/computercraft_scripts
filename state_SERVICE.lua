-- State: SERVICE
-- Performs refuel or material restock trips before resuming work.
local shared = require("factoryrefactor")

local function run(ctx)
  shared.states[shared.STATE_SERVICE](ctx)
  return ctx.currentState or shared.STATE_SERVICE
end

return {
  run = run,
}
