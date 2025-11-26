--[[
State: BUILD
Executes the build plan step by step.
--]]

local movement = require("lib_movement")
local placement = require("lib_placement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local orientation = require("lib_orientation")
local diagnostics = require("lib_diagnostics")
local world = require("lib_world")
local startup = require("lib_startup")

local function localToWorld(localPos, facing)
    return world.localToWorld(localPos, facing)
end

local function addPos(p1, p2)
    return { x = p1.x + p2.x, y = p1.y + p2.y, z = p1.z + p2.z }
end

local function BUILD(ctx)
    local strategy, errMsg = diagnostics.requireStrategy(ctx)
    if not strategy then
        return "ERROR"
    end

    if ctx.pointer > #strategy then
        return "DONE"
    end

    local step = strategy[ctx.pointer]
    local material = step.block.material
    
    -- 1. Check Fuel
    if not startup.runFuelCheck(ctx, ctx.chests, 100, 1000) then
        return "BUILD"
    end

    -- 2. Check Inventory
    local count = inventory.countMaterial(ctx, material)
    if count == 0 then
        logger.log(ctx, "warn", "Out of material: " .. material)
        ctx.missingMaterial = material
        ctx.resumeState = "BUILD"
        return "RESTOCK"
    end

    -- 3. Move to position
    -- Convert local approach position to world position
    -- We assume ctx.origin is where we started.
    local origin = ctx.origin
    local worldOffset = localToWorld(step.approachLocal, origin.facing)
    local targetPos = addPos(origin, worldOffset)
    
    -- Use movement lib to go there
    -- We might want a "travel clearance" (fly high) strategy, but for now direct.
    local ok, err = movement.goTo(ctx, targetPos)
    if not ok then
        logger.log(ctx, "warn", "Movement blocked: " .. tostring(err))
        ctx.resumeState = "BUILD"
        return "BLOCKED"
    end

    -- 4. Place Block
    -- Ensure we are facing the right way if needed, or just place.
    -- placement.placeMaterial handles orientation if we pass 'side'.
    -- step.side is the side of the block to place ON.
    -- We are at 'approachLocal'.
    
    local placed, placeErr = placement.placeMaterial(ctx, material, {
        side = step.side,
        block = step.block,
        dig = true, -- Clear obstacles
        attack = true
    })

    if not placed then
        if placeErr == "already_present" then
            -- It's fine
        else
            local failureMsg = "Placement failed: " .. tostring(placeErr)
            logger.log(ctx, "warn", failureMsg)
            ctx.lastError = failureMsg
            -- Could be empty inventory (handled above?) or something else.
            -- If it's "out of items", we should restock.
            -- But placeMaterial might not return specific enough error.
            -- Let's assume if we had count > 0, it's an obstruction or failure.
            -- Retry?
            return "ERROR" -- For now, fail hard so we can debug.
        end
    end

    ctx.pointer = ctx.pointer + 1
    ctx.retries = 0
    return "BUILD"
end

return BUILD
