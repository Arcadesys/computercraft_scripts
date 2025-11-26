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
local startup = require("lib_startup")

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

    if not startup.runFuelCheck(ctx, ctx.chests, 100, 1000) then
        return "MINE"
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
            if err == "blocked" then
                return "BLOCKED"
            end
            ctx.lastError = "Mining movement failed: " .. tostring(err)
            return "ERROR"
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
            logger.log(ctx, "warn", "No torches to place. Skipping.")
            -- ctx.resumeState = "MINE"
            -- return "RESTOCK"
        else
            -- Try standard placement (works if there is space)
            if turtle.placeDown() then
                -- Success
            elseif turtle.placeUp() then
                -- Success
            else
                -- Try placing behind (turn 180)
                movement.turnRight(ctx)
                movement.turnRight(ctx)
                
                -- Clear obstruction behind
                if turtle.detect() then
                    turtle.dig()
                end

                if turtle.place() then
                    -- Success
                else
                    -- Try placing on the right wall (relative to original facing)
                    movement.turnLeft(ctx)
                    if turtle.detect() then
                        turtle.dig()
                    end
                    
                    if turtle.place() then
                        -- Success
                        movement.turnRight(ctx) -- Restore to facing behind
                    else
                        movement.turnRight(ctx) -- Restore to facing behind
                        
                        -- Last resort: Dig down and place in hole
                        if turtle.digDown() then
                            turtle.placeDown()
                        else
                            logger.log(ctx, "warn", "Failed to place torch")
                        end
                    end
                end
                -- Restore facing
                movement.turnRight(ctx)
                movement.turnRight(ctx)
            end
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
        
        -- Fallback: Try to find any chest/barrel if the specific one isn't found
        if not ok then
            inventory.scan(ctx)
            local state = inventory.ensureState(ctx)
            for slot, item in pairs(state.slots) do
                if item.name:find("chest") or item.name:find("barrel") or item.name:find("shulker") then
                    turtle.select(slot)
                    ok = true
                    break
                end
            end
        end

        if not ok then
            local msg = "Pre-flight check failed: Missing chest"
            logger.log(ctx, "error", msg)
            ctx.lastError = msg
            return "ERROR"
        end
        
        if not turtle.placeDown() then
            if turtle.detectDown() then
                turtle.digDown()
                if not turtle.placeDown() then
                    local msg = "Pre-flight check failed: Could not place chest"
                    logger.log(ctx, "error", msg)
                    ctx.lastError = msg
                    return "ERROR"
                end
            else
                local msg = "Pre-flight check failed: Could not place chest"
                logger.log(ctx, "error", msg)
                ctx.lastError = msg
                return "ERROR"
            end
        end
    end
    
    ctx.pointer = stepIndex + 1
    ctx.retries = 0
    return "MINE"
end

return MINE
