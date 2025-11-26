---@diagnostic disable: undefined-global
--[[
Farming library for CC:Tweaked turtles.
Abstracts common farming logic like grid scanning and depositing items.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")

local farming = {}

-- Go home and deposit items
-- config: {
--   safeHeight = 6,
--   chests = { output="south", fuel="west", trash="east" },
--   keepItems = { ["minecraft:potato"] = 64 },
--   trashItems = { "minecraft:poisonous_potato" }, -- explicit trash
--   refuel = true
-- }
function farming.deposit(ctx, config)
    local chests = config.chests or ctx.chests
    if not chests then
        logger.log(ctx, "error", "No chests defined for deposit.")
        return false
    end

    logger.log(ctx, "info", "Heading home to deposit items...")

    -- 1. Go Home
    local safeHeight = config.safeHeight or 6
    if not movement.goTo(ctx, { x=0, y=safeHeight, z=0 }) then
        return false, "Failed to go home"
    end

    -- 2. Descend
    local descendRetries = 0
    while movement.getPosition(ctx).y > 0 do
        local hasDown, dataDown = turtle.inspectDown()
        if hasDown and not dataDown.name:find("air") and not dataDown.name:find("chest") then
            turtle.digDown()
        end
        if not movement.down(ctx) then
            turtle.digDown()
        end
        descendRetries = descendRetries + 1
        if descendRetries > 50 then
             logger.log(ctx, "error", "Failed to descend to home level.")
             return false, "Failed to descend"
        end
    end

    -- 3. Output (South)
    if chests.output then
        movement.face(ctx, chests.output)
        logger.log(ctx, "info", "Dropping items...")
        
        for i=1, 16 do
            local item = turtle.getItemDetail(i)
            if item then
                local keepCount = 0
                if config.keepItems then
                    for k, v in pairs(config.keepItems) do
                        if item.name == k or item.name:find(k) then
                            keepCount = v
                            break
                        end
                    end
                end
                
                -- If it's an explicit trash item, we'll handle it at the trash chest (or here if we want)
                -- But usually we dump "product" here.
                
                -- Logic: If it's in keepItems, keep up to N.
                -- If it's not in keepItems, is it a product?
                -- For simplicity: Dump everything not in keepItems, unless it's fuel/trash?
                -- Actually, usually Output is for EVERYTHING except what we keep.
                -- Trash is for specific junk.
                
                if keepCount > 0 then
                    if item.count > keepCount then
                        turtle.select(i)
                        turtle.drop(item.count - keepCount)
                    end
                    -- Update keep count for next slots (if split) - simplified here assuming consolidated
                else
                    -- Dump it?
                    -- Check if it's fuel we want to keep?
                    local isFuel = turtle.refuel(0)
                    local isTrash = false
                    if config.trashItems then
                        for _, t in ipairs(config.trashItems) do
                            if item.name == t then isTrash = true break end
                        end
                    end
                    
                    if not isFuel and not isTrash then
                        turtle.select(i)
                        turtle.drop()
                    end
                end
            end
        end
    end

    -- 4. Fuel (West)
    if config.refuel and chests.fuel then
        movement.face(ctx, chests.fuel)
        logger.log(ctx, "info", "Refueling...")
        turtle.suck()
        fuelLib.refuel(ctx, { target = 1000 })
        -- Dump excess fuel?
        local item = turtle.getItemDetail()
        if item and turtle.refuel(0) then
             turtle.drop()
        end
    end

    -- 5. Trash (East)
    if chests.trash then
        movement.face(ctx, chests.trash)
        logger.log(ctx, "info", "Trashing junk...")
        for i=1, 16 do
            local item = turtle.getItemDetail(i)
            if item then
                local isTrash = false
                if config.trashItems then
                    for _, t in ipairs(config.trashItems) do
                        if item.name == t then isTrash = true break end
                    end
                end
                
                -- Also trash if not in keep list and not fuel?
                local keepCount = 0
                if config.keepItems then
                    for k, v in pairs(config.keepItems) do
                        if item.name == k or item.name:find(k) then
                            keepCount = v
                            break
                        end
                    end
                end
                local isFuel = turtle.refuel(0)
                
                if isTrash or (keepCount == 0 and not isFuel) then
                    turtle.select(i)
                    turtle.drop()
                end
            end
        end
    end
    
    return true
end

return farming
