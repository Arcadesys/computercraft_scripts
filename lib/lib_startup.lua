---@diagnostic disable: undefined-global
--[[
Startup logic for turtles.
Handles fuel checks and chest setup.
--]]

local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local movement = require("lib_movement")
local wizard = require("lib_wizard")

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
    local requirements = {
        south = { type = "chest", name = "Output Chest" },
        east = { type = "chest", name = "Trash Chest" },
        west = { type = "chest", name = "Fuel Chest" }
    }
    
    wizard.runChestSetup(ctx, requirements)
    
    -- Map directions to chest types for internal use
    local chests = {
        output = "south",
        trash = "east",
        fuel = "west"
    }
    
    return chests
end

return startup
