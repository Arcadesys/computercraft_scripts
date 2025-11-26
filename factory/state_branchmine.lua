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

local OPPOSITE = {
    north = "south",
    south = "north",
    east = "west",
    west = "east"
}

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
        logger.log(ctx, "error", "Failed to restore facing after chest verification: " .. tostring(restoreErr))
        return false, "Failed to restore facing: " .. tostring(restoreErr)
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
    local ok, item = selectTorch(ctx)
    if not ok then
        logger.log(ctx, "warn", "No torches to place (missing " .. tostring(item) .. ")")
        return false
    end
    
    -- Strategy 1: Place Down (if air below, e.g. flying)
    if turtle.placeDown() then return true end
    
    -- Strategy 2: Place Up (if air above)
    if turtle.placeUp() then return true end
    
    -- Strategy 3: Dig Down and Place Down (Floor Torch)
    -- This is usually safe and reliable in a 1x2 tunnel
    if turtle.digDown() then
        if turtle.placeDown() then
            return true
        end
    end
    
    -- Strategy 4: Wall Torch (Dig Right Wall)
    movement.turnRight(ctx)
    if turtle.detect() then
        turtle.dig()
    end
    if turtle.place() then
        movement.turnLeft(ctx)
        return true
    end
    movement.turnLeft(ctx) -- Restore facing
    
    -- Strategy 5: Wall Torch (Dig Left Wall)
    movement.turnLeft(ctx)
    if turtle.detect() then
        turtle.dig()
    end
    if turtle.place() then
        movement.turnRight(ctx)
        return true
    end
    movement.turnRight(ctx) -- Restore facing

    -- Strategy 6: Turn around and place (Backwards)
    movement.turnRight(ctx)
    movement.turnRight(ctx)
    if turtle.place() then
        movement.turnRight(ctx)
        movement.turnRight(ctx)
        return true
    end
    movement.turnRight(ctx)
    movement.turnRight(ctx)

    logger.log(ctx, "warn", "Failed to place torch (all strategies failed).")
    return false
end

local function dumpTrash(ctx)
    inventory.condense(ctx)
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

local function orientByChests(ctx, chests)
    if not chests then return false end
    
    logger.log(ctx, "info", "Auto-orienting based on chests...")
    
    -- 1. Scan surroundings (0=Front, 1=Right, 2=Back, 3=Left)
    local surroundings = {}
    for i = 0, 3 do
        local hasBlock, data = turtle.inspect()
        if hasBlock and (data.name:find("chest") or data.name:find("barrel")) then
            surroundings[i] = true
        else
            surroundings[i] = false
        end
        turtle.turnRight()
    end
    -- Turtle is now back to original physical facing
    
    -- 2. Score candidates
    local CARDINALS = {"north", "east", "south", "west"}
    local bestScore = -1
    local bestFacing = nil
    
    for i, candidate in ipairs(CARDINALS) do
        -- candidate is what we assume "Front" (0) is.
        -- Then Right (1) is CARDINALS[i+1] (wrapped)
        -- etc.
        
        local score = 0
        
        -- Check each defined chest
        for name, dir in pairs(chests) do
            -- dir is e.g. "south"
            -- Find which relative slot corresponds to 'dir' under this candidate assumption
            
            -- Find index of 'dir' in CARDINALS
            local dirIdx = -1
            for k, v in ipairs(CARDINALS) do if v == dir then dirIdx = k break end end
            
            -- Find index of 'candidate' in CARDINALS
            local candIdx = i
            
            -- Relative offset: (dirIdx - candIdx) % 4
            -- e.g. If candidate=North (1), dir=South (3). Offset = (3-1)%4 = 2 (Back). Correct.
            
            if dirIdx ~= -1 then
                local offset = (dirIdx - candIdx) % 4
                if surroundings[offset] then
                    score = score + 1
                end
            end
        end
        
        if score > bestScore then
            bestScore = score
            bestFacing = candidate
        end
    end
    
    if bestFacing and bestScore > 0 then
        logger.log(ctx, "info", "Oriented to " .. bestFacing .. " (Score: " .. bestScore .. ")")
        
        -- Update movement state
        ctx.movement = ctx.movement or {}
        ctx.movement.facing = bestFacing
        
        -- Also update origin if we are at start
        ctx.origin = ctx.origin or {}
        ctx.origin.facing = bestFacing
        
        return true
    else
        logger.log(ctx, "warn", "Could not determine orientation from chests.")
        return false
    end
end

local function BRANCHMINE(ctx)
    local bm = ctx.branchmine
    if not bm then return "INITIALIZE" end

    if bm.state == "SPINE" and bm.currentDist == 0 then
        if not bm.oriented then
            orientByChests(ctx, bm.chests)
            bm.oriented = true
            bm.spineInitialized = false
        end
        
        -- Align to mine direction (Away from output chest)
        if bm.chests and bm.chests.output then
            local outDir = bm.chests.output
            local mineDir = OPPOSITE[outDir]
            if mineDir then
                local current = movement.getFacing(ctx)
                if current ~= mineDir then
                    logger.log(ctx, "info", "Aligning to mine shaft: " .. mineDir)
                    movement.faceDirection(ctx, mineDir)
                    -- Reset spine anchor so it captures the new facing
                    bm.spineInitialized = false
                end
            end
        end
    end

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
        
        -- Ensure 2-high spine (and handle falling blocks like gravel)
        while turtle.detectUp() do
            if turtle.digUp() then
                turtle.suckUp()
            else
                break
            end
            sleep(0.5)
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
        -- Always scan, even if we moved into air (might be a cave with ores on walls/ceiling)
        mining.scanAndMineNeighbors(ctx)
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_LEFT_UP" then
        -- Go UP 1 to mine upper layer
        local moved = movement.up(ctx)
        if not moved then
            turtle.digUp()
            moved = movement.up(ctx)
        end

        if moved then
            mining.scanAndMineNeighbors(ctx)
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
            local downRetries = 0
             while movement.getPosition(ctx).y > bm.spineY do
                if not movement.down(ctx) then
                    turtle.digDown()
                end
                downRetries = downRetries + 1
                if downRetries > 20 then
                    logger.log(ctx, "warn", "Failed to descend to spine level. Aborting return.")
                    break
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
        -- Always scan
        mining.scanAndMineNeighbors(ctx)
        return "BRANCHMINE"

    elseif bm.state == "BRANCH_RIGHT_UP" then
        local moved = movement.up(ctx)
        if not moved then
            turtle.digUp()
            moved = movement.up(ctx)
        end

        if moved then
            mining.scanAndMineNeighbors(ctx)
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
            local downRetries = 0
             while movement.getPosition(ctx).y > bm.spineY do
                if not movement.down(ctx) then
                    turtle.digDown()
                end
                downRetries = downRetries + 1
                if downRetries > 20 then
                    logger.log(ctx, "warn", "Failed to descend to spine level. Aborting return.")
                    break
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
