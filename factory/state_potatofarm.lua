--[[
State: POTATOFARM
Grid-based potato farming logic.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local wizard = require("lib_wizard")

local function POTATOFARM(ctx)
    local pf = ctx.potatofarm
    if not pf then return "INITIALIZE" end

    -- 1. Fuel Check
    if turtle.getFuelLevel() < 200 then
        logger.log(ctx, "warn", "Fuel low (" .. turtle.getFuelLevel() .. "). Attempting refuel...")
        fuelLib.refuel(ctx, { target = 1000 })
        
        if turtle.getFuelLevel() < 200 then
            if pf.chests and pf.chests.fuel then
                logger.log(ctx, "info", "Going to fuel chest...")
                movement.goTo(ctx, { x=0, y=0, z=0 })
                movement.face(ctx, pf.chests.fuel)
                turtle.suck()
                fuelLib.refuel(ctx, { target = 1000 })
            end
        end
        
        if turtle.getFuelLevel() < 200 then
             logger.log(ctx, "error", "Critical fuel shortage. Waiting.")
             sleep(10)
             return "POTATOFARM"
        end
    end

    -- 2. State Machine
    if pf.state == "SETUP" then
        logger.log(ctx, "info", "Setting up Potato Farm " .. pf.width .. "x" .. pf.height)
        
        pf.chests = {
            output = "south", -- Behind
            trash = "east",   -- Right
            fuel = "west"     -- Left
        }
        
        -- Run Wizard
        wizard.runChestSetup(ctx, {
            south = { type = "chest", name = "Output Chest" },
            east = { type = "chest", name = "Trash Chest" },
            west = { type = "chest", name = "Fuel Chest" }
        })
        
        pf.state = "SCAN"
        pf.nextX = 0
        pf.nextZ = 0
        return "POTATOFARM"

    elseif pf.state == "SCAN" then
        local w, h = pf.width, pf.height
        
        if pf.nextZ >= h then
            pf.state = "DEPOSIT"
            return "POTATOFARM"
        end
        
        local x = pf.nextX
        local z = pf.nextZ
        
        -- Fly over (height 1 is directly above crop)
        local hoverHeight = 1
        local target = { x = x, y = hoverHeight, z = -z }
        
        if not movement.goTo(ctx, target) then
            logger.log(ctx, "warn", "Path blocked to " .. x .. "," .. z)
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
                    logger.log(ctx, "info", "Harvesting potato at " .. x .. "," .. z)
                    turtle.digDown()
                    -- Replant
                    if inventory.selectMaterial(ctx, "minecraft:potato") then
                        turtle.placeDown()
                    end
                end
            elseif not hasDown or dataDown.name == "minecraft:air" then
                 -- Empty spot, plant
                 if inventory.selectMaterial(ctx, "minecraft:potato") then
                    turtle.placeDown()
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
        logger.log(ctx, "info", "Depositing items...")
        movement.goTo(ctx, { x=0, y=1, z=0 }) -- Return to start, hover height
        
        -- Output (South)
        movement.face(ctx, pf.chests.output)
        
        local keptPotatoes = 0
        local keepAmount = 64 -- Keep one stack for replanting
        
        -- First pass: Count potatoes we already have in "safe" slots? 
        -- No, just iterate and decide.
        
        for i=1, 16 do
            local item = turtle.getItemDetail(i)
            if item then
                if item.name == "minecraft:potato" then
                    if keptPotatoes < keepAmount then
                        local canKeep = keepAmount - keptPotatoes
                        if item.count <= canKeep then
                            keptPotatoes = keptPotatoes + item.count
                        else
                            -- Split stack
                            local toDrop = item.count - canKeep
                            turtle.select(i)
                            if not turtle.drop(toDrop) then
                                logger.log(ctx, "warn", "Output chest full.")
                                sleep(5)
                            end
                            keptPotatoes = keptPotatoes + canKeep
                        end
                    else
                        -- Dump all
                        turtle.select(i)
                        if not turtle.drop() then
                             logger.log(ctx, "warn", "Output chest full.")
                             sleep(5)
                        end
                    end
                elseif item.name == "minecraft:poisonous_potato" then
                    -- Dump to output
                    turtle.select(i)
                    turtle.drop()
                elseif not fuelLib.isFuel(item.name) and not item.name:find("chest") then
                    -- Trash
                    movement.face(ctx, pf.chests.trash)
                    turtle.select(i)
                    turtle.drop()
                    movement.face(ctx, pf.chests.output)
                end
            end
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
