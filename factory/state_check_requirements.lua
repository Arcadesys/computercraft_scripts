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

local MATERIAL_ALIASES = {
    ["minecraft:potatoes"] = { "minecraft:potato" }, -- Blocks vs. item name
    ["minecraft:water_bucket"] = { "minecraft:water_bucket_bucket" }, -- Allow buckets to satisfy water needs
}

local function countWithAliases(invCounts, material)
    local total = invCounts[material] or 0
    local aliases = MATERIAL_ALIASES[material]
    if aliases then
        for _, alias in ipairs(aliases) do
            total = total + (invCounts[alias] or 0)
        end
    end
    return total
end

local function buildPullList(missing)
    local pull = {}
    for mat, count in pairs(missing) do
        local aliases = MATERIAL_ALIASES[mat]
        if aliases then
            for _, alias in ipairs(aliases) do
                pull[alias] = math.max(pull[alias] or 0, count)
            end
        else
            pull[mat] = count
        end
    end
    return pull
end

local function calculateRequirements(ctx, strategy)
    -- Potatofarm: assume soil is prepped at y=0; only require fuel and potatoes for replanting.
    if ctx.potatofarm then
        local width = tonumber(ctx.potatofarm.width) or tonumber(ctx.config.width) or 9
        local height = tonumber(ctx.potatofarm.height) or tonumber(ctx.config.height) or 9
        -- Rough fuel budget: sweep the inner grid twice plus margin.
        local inner = math.max(1, (width - 2)) * math.max(1, (height - 2))
        local fuelNeeded = math.ceil(inner * 2.0) + 100
        local potatoesNeeded = inner -- enough to replant every spot once
        return {
            fuel = fuelNeeded,
            materials = { ["minecraft:potato"] = potatoesNeeded }
        }
    end

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
    -- Assume dirt is already placed in the world; do not require the turtle to carry dirt.
    if reqs and reqs.materials then
        reqs.materials["minecraft:dirt"] = nil
        -- Do not require water buckets for farm strategies; assume water is pre-placed in the world.
        reqs.materials["minecraft:water_bucket"] = nil
    end

    local invCounts = inventory.getCounts(ctx)
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
        -- Assume water is pre-placed; treat requirement as satisfied.
        if mat == "minecraft:water_bucket" then
            invCounts[mat] = count
        end
        -- Assume dirt is already available in the world (don't require the turtle to carry it).
        if mat == "minecraft:dirt" then
            invCounts[mat] = count
        end

        local have = countWithAliases(invCounts, mat)
        
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
        local pullList = buildPullList(missing.materials)
        if inventory.retrieveFromNearby(ctx, pullList) then
             -- Re-check inventory
             invCounts = inventory.getCounts(ctx)
             -- Re-apply assumptions (water/dirt) after re-check
             for mat, count in pairs(reqs.materials) do
                if mat == "minecraft:water_bucket" or mat == "minecraft:dirt" then
                    invCounts[mat] = count
                end
             end
             hasMissing = false
             missing.materials = {}
             for mat, count in pairs(reqs.materials) do
                local have = countWithAliases(invCounts, mat)
                if have < count then
                    missing.materials[mat] = count - have
                    hasMissing = true
                end
             end
        end
    end

    -- If we're still missing items, check whether nearby chests have enough
    -- even if we can't hold them all at once (e.g., lots of water buckets).
    local nearby = nil
    if hasMissing then
        nearby = inventory.checkNearby(ctx, buildPullList(missing.materials))
        for mat, deficit in pairs(missing.materials) do
            local total = countWithAliases(invCounts, mat)
            total = total + (nearby[mat] or 0)
            local aliases = MATERIAL_ALIASES[mat]
            if aliases then
                for _, alias in ipairs(aliases) do
                    total = total + (nearby[alias] or 0)
                end
            end

            -- If the material is dirt, assume it's available in-world and treat as satisfied.
            if mat == "minecraft:dirt" then
                total = reqs.materials[mat] or total
            end

            if total >= (reqs.materials[mat] or 0) then
                missing.materials[mat] = nil
            end
        end

        -- Recompute hasMissing after relaxing for nearby stock
        hasMissing = missing.fuel > 0
        for _ in pairs(missing.materials) do
            hasMissing = true
            break
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
    nearby = nearby or inventory.checkNearby(ctx, missing.materials)
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
