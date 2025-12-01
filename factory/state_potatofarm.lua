---@diagnostic disable: undefined-global
--[[
State: POTATOFARM
Grid-based potato farming logic.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local wizard = require("lib_wizard")
local startup = require("lib_startup")
local farming = require("lib_farming")
local world = require("lib_world")

-- Till dirt/grass into farmland using any hoe found in inventory.
local function ensureFarmland(ctx, blockBelow)
    if not turtle or not turtle.placeDown then
        return true -- Assume farmland is already prepared in non-turtle environments.
    end
    if not blockBelow or blockBelow.name == "minecraft:farmland" then
        return true
    end

    local tillable = {
        ["minecraft:dirt"] = true,
        ["minecraft:coarse_dirt"] = true,
        ["minecraft:rooted_dirt"] = true,
        ["minecraft:grass_block"] = true,
    }
    if not tillable[blockBelow.name] then
        return false
    end

    inventory.scan(ctx)
    local hoeSlot
    for slot, info in pairs(ctx.inventoryState.slots or {}) do
        if info and info.name and info.count > 0 and info.name:find("hoe") then
            hoeSlot = slot
            break
        end
    end
    if not hoeSlot then
        logger.log(ctx, "warn", "No hoe in inventory; cannot till soil.")
        return false
    end

    turtle.select(hoeSlot)
    local placed = turtle.placeDown()
    if not placed then
        logger.log(ctx, "warn", "Failed to till soil with hoe in slot " .. tostring(hoeSlot))
        return false
    end

    local ok, data = turtle.inspectDown()
    return ok and data and data.name == "minecraft:farmland"
end

local function POTATOFARM(ctx)
    local pf = ctx.potatofarm
    if not pf then return "INITIALIZE" end

    -- 1. Fuel Check
    if not startup.runFuelCheck(ctx, pf.chests) then
        return "POTATOFARM"
    end

    -- 2. State Machine
    if pf.state == "SCAN" then
        -- Validate dimensions
        local width = tonumber(pf.width) or 9
        local height = tonumber(pf.height) or 9
        
        if width < 3 then width = 3 end
        if height < 3 then height = 3 end

        logger.log(ctx, "info", "PotatoFarm SCAN: " .. width .. "x" .. height)

        -- Scan only the crop area (exclude borders)
        local w, h = width - 2, height - 2
        
        -- Ensure pointers are numbers
        pf.nextX = tonumber(pf.nextX) or 0
        pf.nextZ = tonumber(pf.nextZ) or 0
        
        if pf.nextZ >= h then
            pf.state = "DEPOSIT"
            return "POTATOFARM"
        end
        
        local x = pf.nextX
        local z = pf.nextZ
        
        -- Fly over (height 1 is directly above crops)
        local hoverHeight = 1
        -- Apply 1x1 offset for safety (start at 1,1 relative to home)
        local localTarget = { x = x + 1, y = hoverHeight, z = -(z + 1) }
        local facing = (ctx.origin and ctx.origin.facing) or ((movement and movement.getFacing) and movement.getFacing(ctx)) or "north"
        local origin = ctx.origin or { x = 0, y = 0, z = 0, facing = facing }
        local target = world.localToWorldRelative(origin, localTarget)
        
        -- Move Y first to avoid hitting chests at origin perimeter
        if not movement.goTo(ctx, target, { axisOrder = { "y", "x", "z" } }) then
            logger.log(ctx, "warn", "Path blocked to " .. target.x .. "," .. target.z)
            -- Try to move up and over?
            if not movement.up(ctx) then
                 return "POTATOFARM" -- Stuck
            end
        else
            -- Check crop below
            local hasDown, dataDown = turtle.inspectDown()
            if hasDown and dataDown.name == "minecraft:potatoes" then
                local age = dataDown.state and dataDown.state.age or 0
                if age >= 7 then
                    -- Check inventory space
                    inventory.scan(ctx)
                    if not inventory.findEmptySlot(ctx) then
                        logger.log(ctx, "warn", "Inventory full. Depositing...")
                        pf.state = "DEPOSIT"
                        return "POTATOFARM"
                    end

                    logger.log(ctx, "info", "Harvesting potato at " .. x .. "," .. z)
                    
                    -- Attempt gentle harvest (interact) first to avoid AOE tool damage
                    local harvested = false
                    
                    -- Try to interact using a potato (often required for right-click harvest mods)
                    if inventory.selectMaterial(ctx, "minecraft:potato") then
                        turtle.placeDown()
                    else
                        -- Or try with empty hand
                        local emptySlot = inventory.findEmptySlot(ctx)
                        if emptySlot then
                            turtle.select(emptySlot)
                            turtle.placeDown()
                        end
                    end

                    -- Check if harvest happened (age reset)
                    local hCheck, dCheck = turtle.inspectDown()
                    if hCheck and dCheck.name == "minecraft:potatoes" then
                        local newAge = dCheck.state and dCheck.state.age or 0
                        if newAge < 7 then
                            harvested = true
                        end
                    end

                    if not harvested then
                        turtle.digDown()
                    end

                    sleep(0.2) -- Wait for drops
                    local pulled = false
                    while turtle.suckDown() do
                        pulled = true
                        sleep(0.1)
                    end

                    if pulled then
                        inventory.invalidate(ctx)
                    end
                    
                    -- Replant if needed
                    local hPost, dPost = turtle.inspectDown()
                    if not hPost or dPost.name == "minecraft:air" then
                        inventory.invalidate(ctx)
                        if inventory.selectMaterial(ctx, "minecraft:potato") then
                            if turtle.placeDown() then
                                inventory.invalidate(ctx)
                            end
                        end
                    end
                end
            elseif not hasDown or dataDown.name == "minecraft:air" then
                 -- Empty spot, plant
                 inventory.invalidate(ctx)
                 if inventory.selectMaterial(ctx, "minecraft:potato") then
                    if turtle.placeDown() then
                        inventory.invalidate(ctx)
                    end
                end
            else
                -- Ground block exists but isn't farmland; try to till then plant.
                if ensureFarmland(ctx, dataDown) then
                    inventory.invalidate(ctx)
                    if inventory.selectMaterial(ctx, "minecraft:potato") then
                        if turtle.placeDown() then
                            inventory.invalidate(ctx)
                        end
                    end
                end
            end
        end
        
        -- Next
        pf.nextX = pf.nextX + 1
        if pf.nextX >= w then
            pf.nextX = 0
            pf.nextZ = pf.nextZ + 1
        end
        
        return "POTATOFARM"

    elseif pf.state == "DEPOSIT" then
        if not pf.chests or not pf.chests.output then
             logger.log(ctx, "error", "Missing output chest configuration.")
             return "ERROR"
        end
        
        local ok, err = farming.deposit(ctx, {
            safeHeight = 2,
            chests = pf.chests,
            keepItems = { ["minecraft:potato"] = 64 },
            trashItems = { "minecraft:poisonous_potato" },
            refuel = true
        })

        if not ok then
            logger.log(ctx, "error", "Deposit failed: " .. tostring(err))
            return "ERROR"
        end
        
        pf.state = "WAIT"
        return "POTATOFARM"

    elseif pf.state == "WAIT" then
        logger.log(ctx, "info", "Waiting for growth...")
        sleep(60)
        
        pf.state = "SCAN"
        pf.nextX = 0
        pf.nextZ = 0
        return "POTATOFARM"
    end

    return "POTATOFARM"
end

return POTATOFARM
