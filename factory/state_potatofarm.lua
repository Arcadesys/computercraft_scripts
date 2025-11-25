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
        local target = { x = x + 1, y = hoverHeight, z = -(z + 1) }
        
        if not movement.goTo(ctx, target) then
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
                        inventory.findEmptySlot(ctx)
                        turtle.placeDown()
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
                    while turtle.suckDown() do
                        sleep(0.1)
                    end
                    
                    -- Replant if needed
                    local hPost, dPost = turtle.inspectDown()
                    if not hPost or dPost.name == "minecraft:air" then
                        if inventory.selectMaterial(ctx, "minecraft:potato") then
                            turtle.placeDown()
                        end
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
        movement.goTo(ctx, { x=0, y=2, z=0 }) -- Return to start, safe height
        
        -- Descend to 0 to access chests
        while movement.getPosition(ctx).y > 0 do
             if not movement.down(ctx) then
                 turtle.digDown()
             end
        end
        
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
                else
                    -- Check if it is fuel
                    turtle.select(i)
                    if not turtle.refuel(0) and not item.name:find("chest") then
                        -- Trash
                        movement.face(ctx, pf.chests.trash)
                        turtle.drop()
                        movement.face(ctx, pf.chests.output)
                    end
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
