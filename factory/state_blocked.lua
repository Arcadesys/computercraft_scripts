--[[
State: BLOCKED
Handles navigation failures.
--]]

local logger = require("lib_logger")

local function BLOCKED(ctx)
    local resume = ctx.resumeState or "BUILD"
    logger.log(ctx, "warn", string.format("Movement blocked while executing %s. Retrying in 5 seconds...", resume))
    ---@diagnostic disable-next-line: undefined-global
    sleep(5)
    ctx.retries = (ctx.retries or 0) + 1
    if ctx.retries > 5 then
        local message = string.format("Too many retries while resuming %s", resume)
        logger.log(ctx, "error", message)
        ctx.lastError = message
        ctx.resumeState = nil
        return "ERROR"
    end
    ctx.resumeState = nil
    -- ctx.retries is NOT reset here, so it accumulates if the next attempt fails immediately
    return resume
end

return BLOCKED
