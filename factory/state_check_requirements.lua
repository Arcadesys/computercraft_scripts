---@diagnostic disable: undefined-global
--[[
State: CHECK_REQUIREMENTS
Verifies that the turtle has enough fuel and materials to complete the task.
Prompts the user if items are missing.
--]]

local inventory = require("lib_inventory")
local logger = require("lib_logger")
local fuel = require("lib_fuel")
local diagnostics = require("lib_diagnostics")
local movement = require("lib_movement")

local function calculateRequirements(ctx, strategy)
    local reqs = {
        fuel = 0,
        materials = {}
    }

    -- Estimate fuel
    -- A simple heuristic: 1 fuel per step.
    if strategy then
        reqs.fuel = #strategy
    end
    
    -- Add a safety margin for fuel (e.g. 10% + 100)
    reqs.fuel = math.ceil(reqs.fuel * 1.1) + 100

    -- Calculate materials
    if ctx.config.mode == "mine" then
        -- Mining mode
        -- Check for torches if strategy has place_torch
        for _, step in ipairs(strategy) do
            if step.type == "place_torch" then
                reqs.materials["minecraft:torch"] = (reqs.materials["minecraft:torch"] or 0) + 1
            elseif step.type == "place_chest" then
                reqs.materials["minecraft:chest"] = (reqs.materials["minecraft:chest"] or 0) + 1
            end
        end
    else
        -- Build mode
        for _, step in ipairs(strategy) do
            if step.block and step.block.material then
                local mat = step.block.material
                reqs.materials[mat] = (reqs.materials[mat] or 0) + 1
            end
        end
    end

    return reqs
end

local function calculateBranchmineRequirements(ctx)
    local bm = ctx.branchmine or {}
    local length = tonumber(bm.length or ctx.config.length) or 60
    local branchInterval = tonumber(bm.branchInterval or ctx.config.branchInterval) or 3
    local branchLength = tonumber(bm.branchLength or ctx.config.branchLength) or 16
    local torchInterval = tonumber(bm.torchInterval or ctx.config.torchInterval) or 6

    branchInterval = math.max(branchInterval, 1)
    torchInterval = math.max(torchInterval, 1)
    branchLength = math.max(branchLength, 1)

    local branchPairs = math.floor(length / branchInterval)
    local branchTravel = branchPairs * (4 * branchLength + 4)
    local totalTravel = length + branchTravel

    local reqs = {
        fuel = math.ceil(totalTravel * 1.1) + 100,
        materials = {}
    }

    local torchItem = ctx.config.torchItem or "minecraft:torch"
    local torchCount = math.max(1, math.floor(length / torchInterval))
    reqs.materials[torchItem] = torchCount

    return reqs
end

local function getInventoryCounts(ctx)
    local counts = {}
    -- Scan all slots
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then
            counts[item.name] = (counts[item.name] or 0) + item.count
        end
    end
    return counts
end

local function retrieveFromNearby(ctx, missing)
    local sides = {"front", "top", "bottom", "left", "right", "back"}
    local pulledAny = false
    
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) then
            local types = { peripheral.getType(side) }
            local isInventory = false
            for _, t in ipairs(types) do
                if t == "inventory" then isInventory = true break end
            end
            
            if isInventory then
                local p = peripheral.wrap(side)
                if p and p.list then
                    local list = p.list()
                    local neededFromChest = {}
                    for slot, item in pairs(list) do
                        if item and missing[item.name] and missing[item.name] > 0 then
                            neededFromChest[item.name] = true
                        end
                    end
                    
                    -- Check if we need anything from this chest
                    local hasNeeds = false
                    for k,v in pairs(neededFromChest) do hasNeeds = true break end
                    
                    if hasNeeds then
                        local pullSide = "forward"
                        local turned = false
                        
                        -- Turn to face the chest if needed
                        if side == "top" then pullSide = "up"
                        elseif side == "bottom" then pullSide = "down"
                        elseif side == "front" then pullSide = "forward"
                        elseif side == "left" then
                            movement.turnLeft(ctx)
                            turned = true
                            pullSide = "forward"
                        elseif side == "right" then
                            movement.turnRight(ctx)
                            turned = true
                            pullSide = "forward"
                        elseif side == "back" then
                            movement.turnRight(ctx)
                            movement.turnRight(ctx)
                            turned = true
                            pullSide = "forward"
                        end
                        
                        -- Pull all needed items
                        for mat, _ in pairs(neededFromChest) do
                            local amount = missing[mat]
                            if amount > 0 then
                                print(string.format("Attempting to pull %s from %s...", mat, side))
                                local success, err = inventory.pullMaterial(ctx, mat, amount, { side = pullSide })
                                if success then
                                    pulledAny = true
                                    missing[mat] = math.max(0, missing[mat] - amount)
                                else
                                     logger.log(ctx, "warn", "Failed to pull " .. mat .. ": " .. tostring(err))
                                end
                            end
                        end
                        
                        -- Restore facing
                        if turned then
                            if side == "left" then movement.turnRight(ctx)
                            elseif side == "right" then movement.turnLeft(ctx)
                            elseif side == "back" then 
                                movement.turnRight(ctx)
                                movement.turnRight(ctx)
                            end
                        end
                    end
                end
            end
        end
    end
    return pulledAny
end

local function checkNearbyChests(ctx, missing)
    local found = {}
    local sides = {"front", "top", "bottom", "left", "right", "back"}
    
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) then
            local types = { peripheral.getType(side) }
            local isInventory = false
            for _, t in ipairs(types) do
                if t == "inventory" then isInventory = true break end
            end
            
            if isInventory then
                local p = peripheral.wrap(side)
                if p and p.list then
                    local list = p.list()
                    for slot, item in pairs(list) do
                        if item and missing[item.name] then
                            found[item.name] = (found[item.name] or 0) + item.count
                        end
                    end
                end
            end
        end
    end
    return found
end

local function CHECK_REQUIREMENTS(ctx)
    logger.log(ctx, "info", "Checking requirements...")

    local reqs
    if ctx.branchmine then
        reqs = calculateBranchmineRequirements(ctx)
    else
        if ctx.config.mode == "mine" then
            logger.log(ctx, "warn", "Branchmine context missing, re-initializing...")
            ctx.branchmine = {
                length = tonumber(ctx.config.length) or 60,
                branchInterval = tonumber(ctx.config.branchInterval) or 3,
                branchLength = tonumber(ctx.config.branchLength) or 16,
                torchInterval = tonumber(ctx.config.torchInterval) or 6,
                currentDist = 0,
                state = "SPINE",
                spineY = 0,
                chests = ctx.chests
            }
            ctx.nextState = "BRANCHMINE"
            reqs = calculateBranchmineRequirements(ctx)
        else
            local strategy, errMsg = diagnostics.requireStrategy(ctx)
            if not strategy then
                ctx.lastError = errMsg or "Strategy missing"
                return "ERROR"
            end
            reqs = calculateRequirements(ctx, strategy)
        end
    end
    local invCounts = getInventoryCounts(ctx)
    local currentFuel = turtle.getFuelLevel()
    if currentFuel == "unlimited" then currentFuel = 999999 end
    if type(currentFuel) ~= "number" then currentFuel = 0 end

    local missing = {
        fuel = 0,
        materials = {}
    }
    local hasMissing = false

    -- Check fuel
    if currentFuel < reqs.fuel then
        -- Attempt to refuel from inventory or nearby sources
        print("Attempting to refuel to meet requirements...")
        logger.log(ctx, "info", "Attempting to refuel to meet requirements...")
        fuel.refuel(ctx, { target = reqs.fuel, excludeItems = { "minecraft:torch" } })
        
        currentFuel = turtle.getFuelLevel()
        if currentFuel == "unlimited" then currentFuel = 999999 end
        if type(currentFuel) ~= "number" then currentFuel = 0 end
    end

    if currentFuel < reqs.fuel then
        missing.fuel = reqs.fuel - currentFuel
        hasMissing = true
    end

    -- Check materials
    for mat, count in pairs(reqs.materials) do
        local have = invCounts[mat] or 0
        
        -- Special handling for chests: allow any chest/barrel if "minecraft:chest" is requested
        if mat == "minecraft:chest" and have < count then
            local totalChests = 0
            for invMat, invCount in pairs(invCounts) do
                if invMat:find("chest") or invMat:find("barrel") or invMat:find("shulker") then
                    totalChests = totalChests + invCount
                end
            end
            if totalChests >= count then
                have = count -- Satisfied
            end
        end

        if have < count then
            missing.materials[mat] = count - have
            hasMissing = true
        end
    end

    if hasMissing then
        print("Checking nearby chests for missing items...")
        if retrieveFromNearby(ctx, missing.materials) then
             -- Re-check inventory
             invCounts = getInventoryCounts(ctx)
             hasMissing = false
             missing.materials = {}
             for mat, count in pairs(reqs.materials) do
                local have = invCounts[mat] or 0
                if have < count then
                    missing.materials[mat] = count - have
                    hasMissing = true
                end
            end
        end
    end

    if not hasMissing then
        logger.log(ctx, "info", "All requirements met.")
        return ctx.nextState or "DONE"
    end

    -- Report missing
    print("\n=== MISSING REQUIREMENTS ===")
    if missing.fuel > 0 then
        print(string.format("- Fuel: %d (Have %d, Need %d)", missing.fuel, currentFuel, reqs.fuel))
    end
    for mat, count in pairs(missing.materials) do
        print(string.format("- %s: %d", mat, count))
    end

    -- Check nearby
    local nearby = checkNearbyChests(ctx, missing.materials)
    local foundNearby = false
    for mat, count in pairs(nearby) do
        if not foundNearby then
            print("\n=== FOUND IN NEARBY CHESTS ===")
            foundNearby = true
        end
        print(string.format("- %s: %d", mat, count))
    end

    print("\nPress Enter to re-check, or type 'q' then Enter to quit.")
    local input = read()
    if input == "q" or input == "Q" then
        return "DONE"
    end
    
    return "CHECK_REQUIREMENTS"
end

return CHECK_REQUIREMENTS
