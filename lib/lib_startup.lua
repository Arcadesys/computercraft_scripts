---@diagnostic disable: undefined-global
--[[
Startup logic for turtles.
Handles fuel checks and chest setup.
--]]

local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local movement = require("lib_movement")
local inventory = require("lib_inventory")

local startup = {}

-- Checks fuel level and attempts to refuel from inventory or fuel chest.
-- Returns true if fuel is sufficient, false if critical shortage (caller should wait/retry).
function startup.runFuelCheck(ctx, chests, threshold, target)
    threshold = threshold or 200
    target = target or 1000
    
    local current = turtle.getFuelLevel()
    if current == "unlimited" then return true end
    if type(current) ~= "number" then current = 0 end
    
    if current < threshold then
        logger.log(ctx, "warn", "Fuel low (" .. current .. "). Attempting refuel...")
        fuelLib.refuel(ctx, { target = target })
        
        current = turtle.getFuelLevel()
        if current == "unlimited" then current = math.huge end
        if type(current) ~= "number" then current = 0 end

        if current < threshold then
            if chests and chests.fuel then
                logger.log(ctx, "info", "Going to fuel chest...")
                movement.goTo(ctx, { x=0, y=0, z=0 })
                movement.face(ctx, chests.fuel)
                turtle.suck()
                fuelLib.refuel(ctx, { target = target })
            end
        end
        
        current = turtle.getFuelLevel()
        if current == "unlimited" then current = math.huge end
        if type(current) ~= "number" then current = 0 end

        if current < threshold then
             logger.log(ctx, "error", "Critical fuel shortage. Waiting.")
             sleep(10)
             return false
        end
    end
    
    return true
end

-- Runs the chest setup wizard.
-- Returns the configured chests table.
function startup.runChestSetup(ctx)
    local chests = {}
    
    logger.log(ctx, "info", "Scanning for nearby containers...")
    
    -- Scan all sides for a container
    local sides = {"front", "top", "bottom", "left", "right", "back"}
    local foundSide = nil
    
    for _, side in ipairs(sides) do
        local info = inventory.detectContainer(ctx, { side = side })
        if info then
            foundSide = side
            logger.log(ctx, "info", "Found container at " .. side)
            break
        end
    end
    
    if foundSide then
        -- Use the found container for everything
        chests.output = foundSide
        chests.trash = foundSide
        chests.fuel = foundSide
        logger.log(ctx, "info", "Using " .. foundSide .. " container for all operations.")
    else
        logger.log(ctx, "warn", "No containers found nearby. Operations requiring chests may fail.")
        -- Fallback to 'front' just in case the user places one later without restarting
        chests.output = "front"
        chests.trash = "front"
        chests.fuel = "front"
    end
    
    return chests
end

return startup
