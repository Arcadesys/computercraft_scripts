---@diagnostic disable: undefined-global
--[[
State: BRANCHMINE
Dynamic branch mining logic.
Replaces the static strategy generator with a robust state machine.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local mining = require("lib_mining")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local startup = require("lib_startup")

local function ensureSpineAnchor(ctx, bm)
    if not bm then
        return
    end
    if not bm.spineInitialized then
        local pos = movement.getPosition(ctx)
        bm.spineY = bm.spineY or pos.y
        bm.spineFacing = bm.spineFacing or movement.getFacing(ctx)
        bm.spineInitialized = true
    end
end

local function verifyOutputChest(ctx, bm)
    if not bm or bm.chestVerified then
        return true
    end

    local dir = bm.chests and bm.chests.output
    if not dir then
        logger.log(ctx, "warn", "Output chest direction missing; skipping verification.")
        bm.chestVerified = true
        return true
    end

    local spineFacing = bm.spineFacing or movement.getFacing(ctx)
    local ok, err = movement.face(ctx, dir)
    if not ok then
        return false, "Unable to face output chest (" .. tostring(err) .. ")"
    end

    ---@diagnostic disable-next-line: undefined-global
    sleep(0.1)
    local hasBlock, data = turtle.inspect()
    local restoreFacing = spineFacing or movement.getFacing(ctx) or "north"
    local restored, restoreErr = movement.face(ctx, restoreFacing)
    if not restored then
        logger.log(ctx, "warn", "Failed to restore facing after chest verification: " .. tostring(restoreErr))
    end

    if not hasBlock then
        return false, "Missing output chest on " .. dir
    end

    local name = data and data.name or "unknown block"
    if not name:find("chest") and not name:find("barrel") then
        return false, string.format("Expected chest on %s but found %s", dir, name)
    end

    bm.chestVerified = true
    return true
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

local function placeTorch(ctx)
    local ok = selectTorch(ctx)
    if not ok then
        logger.log(ctx, "warn", "No torches to place.")
        return false
    end
    
    -- Try standard placement (works if there is space)
    if turtle.placeDown() then return true end
    if turtle.placeUp() then return true end
    
    -- Try placing behind (turn 180)
    movement.turnRight(ctx)
    movement.turnRight(ctx)
    
    -- Clear obstruction behind
    if turtle.detect() then
        turtle.dig()
    end

    local placed = false
    if turtle.place() then
        placed = true
    else
        -- Try placing on the right wall (relative to original facing)
        movement.turnLeft(ctx)
        if turtle.detect() then
            turtle.dig()
        end
        
        if turtle.place() then
            placed = true
            movement.turnRight(ctx) -- Restore to facing behind
        else
            movement.turnRight(ctx) -- Restore to facing behind
            
            -- Last resort: Dig down and place in hole
            if turtle.digDown() then
                if turtle.placeDown() then
                    placed = true
                end
            end
        end
    end
    
    -- Restore facing
    movement.turnRight(ctx)
    movement.turnRight(ctx)
    
    return placed
end

local function dumpTrash(ctx)
    inventory.scan(ctx)
    local state = ctx.inventory
    if not state or not state.slots then return end
    
    for slot, item in pairs(state.slots) do
        if mining.TRASH_BLOCKS[item.name] and not item.name:find("torch") and not item.name:find("chest") then
            turtle.select(slot)
            turtle.drop()
        end
    end
end

local function BRANCHMINE(ctx)
    local bm = ctx.branchmine
    if not bm then return "INITIALIZE" end

    ensureSpineAnchor(ctx, bm)

    -- 1. Fuel Check
    if not startup.runFuelCheck(ctx, bm.chests, 100, 1000) then
        return "BRANCHMINE"
    end

    -- 2. State Machine
    if bm.state == "SPINE" then
        if bm.currentDist >= bm.length then
            bm.state = "RETURN"
            return "BRANCHMINE"
        end

        if not bm.chestVerified then
            local ok, err = verifyOutputChest(ctx, bm)
            if not ok then
                local message = err or "Output chest verification failed"
                logger.log(ctx, "error", message)
                ctx.lastError = message
                return "ERROR"
            end
        end

        -- Move forward
        local isNewGround = turtle.detect()
        if not movement.forward(ctx, { dig = true }) then
            logger.log(ctx, "warn", "Blocked on spine.")
            return "BRANCHMINE" -- Retry
        end
        
        bm.currentDist = bm.currentDist + 1
        if isNewGround then
            mining.scanAndMineNeighbors(ctx)
        end

        -- Place Torch
        if bm.currentDist % bm.torchInterval == 0 then
            placeTorch(ctx)
        end

        -- Dump Trash
        if bm.currentDist % 5 == 0 then
            dumpTrash(ctx)
        end

        -- Branch?
        if bm.currentDist % bm.branchInterval == 0 then
            bm.state = "BRANCH_LEFT_INIT"
        end
        
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_LEFT_INIT" then
        movement.turnLeft(ctx)
        bm.branchDist = 0
        bm.state = "BRANCH_LEFT_OUT"
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_LEFT_OUT" then
        if bm.branchDist >= bm.branchLength then
            bm.state = "BRANCH_LEFT_UP"
            return "BRANCHMINE"
        end
        
        local isNewGround = turtle.detect()
        if not movement.forward(ctx, { dig = true }) then
             -- If blocked, maybe bedrock? Just return.
             logger.log(ctx, "warn", "Branch blocked. Returning.")
             bm.state = "BRANCH_LEFT_RETURN"
             return "BRANCHMINE"
        end
        
        bm.branchDist = bm.branchDist + 1
        if isNewGround then
            mining.scanAndMineNeighbors(ctx)
        end
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_LEFT_UP" then
        -- Go UP 1 to mine upper layer
        if movement.up(ctx) then
            -- Air above, skip mining unless we want to be thorough?
            -- User requested: "if the robot detects air it should assume that it does not have to dig."
            -- So we skip scanning here.
        else
            turtle.digUp()
            if movement.up(ctx) then
                mining.scanAndMineNeighbors(ctx)
            end
        end
        bm.state = "BRANCH_LEFT_RETURN"
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_LEFT_RETURN" then
        -- Initialize return if needed
        if not bm.returning then
            movement.turnAround(ctx)
            bm.returning = true
            bm.returnDist = 0
        end
        
        if bm.returnDist >= bm.branchDist then
            bm.returning = false
            -- Done returning horizontally
            -- Now go down
             while movement.getPosition(ctx).y > bm.spineY do
                if not movement.down(ctx) then
                    turtle.digDown()
                end
            end
            movement.turnLeft(ctx)
            bm.state = "BRANCH_RIGHT_INIT"
            return "BRANCHMINE"
        end
        
        -- Move one step
        if not movement.forward(ctx) then
            turtle.dig()
            movement.forward(ctx)
        end
        
        -- Mine if upper
        if movement.getPosition(ctx).y > bm.spineY then
            mining.scanAndMineNeighbors(ctx)
        end
        
        bm.returnDist = bm.returnDist + 1
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_RIGHT_INIT" then
        movement.turnRight(ctx)
        bm.branchDist = 0
        bm.state = "BRANCH_RIGHT_OUT"
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_RIGHT_OUT" then
        if bm.branchDist >= bm.branchLength then
            bm.state = "BRANCH_RIGHT_UP"
            return "BRANCHMINE"
        end
        
        local isNewGround = turtle.detect()
        if not movement.forward(ctx, { dig = true }) then
             logger.log(ctx, "warn", "Branch blocked. Returning.")
             bm.state = "BRANCH_RIGHT_RETURN"
             return "BRANCHMINE"
        end
        
        bm.branchDist = bm.branchDist + 1
        if isNewGround then
            mining.scanAndMineNeighbors(ctx)
        end
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_RIGHT_UP" then
        if movement.up(ctx) then
            -- Air above, skip mining
        else
            turtle.digUp()
            if movement.up(ctx) then
                mining.scanAndMineNeighbors(ctx)
            end
        end
        bm.state = "BRANCH_RIGHT_RETURN"
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_RIGHT_RETURN" then
        -- Initialize return if needed
        if not bm.returning then
            movement.turnAround(ctx)
            bm.returning = true
            bm.returnDist = 0
        end
        
        if bm.returnDist >= bm.branchDist then
            bm.returning = false
            -- Done returning horizontally
            -- Now go down
             while movement.getPosition(ctx).y > bm.spineY do
                if not movement.down(ctx) then
                    turtle.digDown()
                end
            end
            movement.turnRight(ctx)
            bm.state = "SPINE"
            return "BRANCHMINE"
        end
        
        -- Move one step
        if not movement.forward(ctx) then
            turtle.dig()
            movement.forward(ctx)
        end
        
        -- Mine if upper
        if movement.getPosition(ctx).y > bm.spineY then
            mining.scanAndMineNeighbors(ctx)
        end
        
        bm.returnDist = bm.returnDist + 1
        return "BRANCHMINE"

    elseif bm.state == "RETURN" then
        logger.log(ctx, "info", "Mining done. Returning home.")
        movement.goTo(ctx, {x=0, y=0, z=0})
        return "DONE"
    end

    return "BRANCHMINE"
end

return BRANCHMINE
