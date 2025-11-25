--[[
State: ERROR
Handles fatal errors.
--]]

local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")

local function ERROR(ctx)
    local message = tostring(ctx.lastError or "Unknown fatal error")
    if ctx.logger then
        -- Avoid dumping the full context snapshot to console as it is too large
        ctx.logger:error("Fatal Error: " .. message)
    else
        logger.log(ctx, "error", "Fatal Error: " .. message)
    end
    print("Press Enter to exit...")
    ---@diagnostic disable-next-line: undefined-global
    read()
    return "EXIT"
end

return ERROR
