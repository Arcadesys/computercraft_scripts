--[[
State: MINE
Executes the mining strategy step by step.
]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local mining = require("lib_mining")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")
local world = require("lib_world")

local function localToWorld(ctx, localPos)
    local rotated = world.localToWorld(localPos, ctx.origin.facing)
    return {
        x = ctx.origin.x + rotated.x,
        y = ctx.origin.y + rotated.y,
        z = ctx.origin.z + rotated.z
    }
end

local function selectTorch(ctx)
    local torchItem = ctx.config.torchItem or "minecraft:torch"
    local ok = inventory.selectMaterial(ctx, torchItem)
    if ok then
        return true, torchItem
    end
    ctx.missingMaterial = torchItem
    return false, torchItem
end

local function MINE(ctx)
    logger.log(ctx, "info", "State: MINE")

    if turtle.getFuelLevel and turtle.getFuelLevel() < 100 then
        -- Attempt refuel from inventory
        fuelLib.refuel(ctx, { target = 1000, excludeItems = { "minecraft:torch" } })
        
        if turtle.getFuelLevel() < 100 then
            logger.log(ctx, "warn", "Fuel low; switching to REFUEL")
            ctx.resumeState = "MINE"
            return "REFUEL"
        end
    end

    -- Get current step
    local stepIndex = ctx.pointer or 1
    local strategy, errMsg = diagnostics.requireStrategy(ctx)
    if not strategy then
        return "ERROR"
    end
    
    if stepIndex > #strategy then
        return "DONE"
    end
    
    local step = strategy[stepIndex]
    
    -- Execute step based on type
    if step.type == "move" then
        local dest = localToWorld(ctx, step)
        local ok, err = movement.goTo(ctx, dest, { dig = true, attack = true })
        if not ok then
            logger.log(ctx, "warn", "Mining movement blocked: " .. tostring(err))
            ctx.resumeState = "MINE"
            return err == "blocked" and "BLOCKED" or "ERROR"
        end
        
    elseif step.type == "turn" then
        if step.data == "left" then
            movement.turnLeft(ctx)
        elseif step.data == "right" then
            movement.turnRight(ctx)
        end
        
    elseif step.type == "mine_neighbors" then
        mining.scanAndMineNeighbors(ctx)
        
    elseif step.type == "place_torch" then
        local ok = selectTorch(ctx)
        if not ok then
            ctx.resumeState = "MINE"
            return "RESTOCK"
        end
        
        -- Try standard placement (works if there is space)
        if turtle.placeDown() then
            -- Success
        elseif turtle.placeUp() then
            -- Success
        else
            -- Try placing behind (turn 180)
            movement.turnRight(ctx)
            movement.turnRight(ctx)
            if turtle.place() then
                -- Success
            else
                -- Last resort: Dig down and place in hole
                if turtle.digDown() then
                    turtle.placeDown()
                end
            end
            -- Restore facing
            movement.turnRight(ctx)
            movement.turnRight(ctx)
        end
        
    elseif step.type == "dump_trash" then
        local dumped = inventory.dumpTrash(ctx)
        if not dumped then
            logger.log(ctx, "debug", "dumpTrash failed (probably empty inventory)")
        end
        
    elseif step.type == "done" then
        return "DONE"
    elseif step.type == "place_chest" then
        local chestItem = ctx.config.chestItem or "minecraft:chest"
        local ok = inventory.selectMaterial(ctx, chestItem)
        if not ok then
            logger.log(ctx, "error", "Pre-flight check failed: Missing chest")
            return "ERROR"
        end
        
        if not turtle.placeDown() then
            if turtle.detectDown() then
                turtle.digDown()
                if not turtle.placeDown() then
                    logger.log(ctx, "error", "Pre-flight check failed: Could not place chest")
                    return "ERROR"
                end
            else
                logger.log(ctx, "error", "Pre-flight check failed: Could not place chest")
                return "ERROR"
            end
        end
    end
    
    ctx.pointer = stepIndex + 1
    ctx.retries = 0
    return "MINE"
end

return MINE
