--[[
State: TREEFARM
Grid-based tree farming logic.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local wizard = require("lib_wizard")

local function TREEFARM(ctx)
    local tf = ctx.treefarm
    if not tf then return "INITIALIZE" end

    -- 1. Fuel Check
    if turtle.getFuelLevel() < 200 then
        logger.log(ctx, "warn", "Fuel low (" .. turtle.getFuelLevel() .. "). Attempting refuel...")
        -- Try to refuel from inventory first
        fuelLib.refuel(ctx, { target = 1000 })
        
        if turtle.getFuelLevel() < 200 then
            -- Go to fuel chest if defined
            if tf.chests and tf.chests.fuel then
                logger.log(ctx, "info", "Going to fuel chest...")
                movement.goTo(ctx, { x=0, y=0, z=0 })
                movement.face(ctx, tf.chests.fuel)
                turtle.suck()
                fuelLib.refuel(ctx, { target = 1000 })
            end
        end
        
        if turtle.getFuelLevel() < 200 then
             logger.log(ctx, "error", "Critical fuel shortage. Waiting.")
             sleep(10)
             return "TREEFARM"
        end
    end

    -- 2. State Machine
    if tf.state == "SETUP" then
        logger.log(ctx, "info", "Setting up Tree Farm " .. tf.width .. "x" .. tf.height)
        
        -- Define chest locations relative to origin (0,0,0)
        tf.chests = {
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
        
        tf.state = "SCAN"
        tf.nextX = 0
        tf.nextZ = 0
        return "TREEFARM"

    elseif tf.state == "SCAN" then
        local w, h = tf.width, tf.height
        
        if tf.nextZ >= h then
            tf.state = "DEPOSIT"
            return "TREEFARM"
        end
        
        local x = tf.nextX
        local z = tf.nextZ
        
        -- Fly over to avoid obstacles
        local hoverHeight = 6
        local target = { x = x, y = hoverHeight, z = -z }
        
        -- Move to target
        if not movement.goTo(ctx, target) then
            logger.log(ctx, "warn", "Path blocked to " .. x .. "," .. z)
            -- Try to clear path?
            -- For now, skip or retry
        else
            -- Descend and harvest
            -- We are at (x, hoverHeight, -z)
            while ctx.curr.y > 1 do
                local hasDown, dataDown = turtle.inspectDown()
                if hasDown and (dataDown.name:find("log") or dataDown.name:find("leaves")) then
                    turtle.digDown()
                elseif hasDown and not dataDown.name:find("air") then
                    turtle.digDown()
                end
                if not movement.down(ctx) then
                    turtle.digDown() -- Try again
                end
            end
            
            -- Now at y=1. Check base (y=0).
            local hasDown, dataDown = turtle.inspectDown()
            if hasDown and dataDown.name:find("log") then
                logger.log(ctx, "info", "Harvesting tree at " .. x .. "," .. z)
                turtle.digDown()
                hasDown = false
            end
            
            -- Replant
            if not hasDown or dataDown.name:find("air") or dataDown.name:find("sapling") then
                -- Try to find any sapling
                if inventory.selectMaterial(ctx, "sapling") then
                    turtle.placeDown()
                end
            end
        end
        
        -- Next
        tf.nextX = tf.nextX + 1
        if tf.nextX >= w then
            tf.nextX = 0
            tf.nextZ = tf.nextZ + 1
        end
        
        return "TREEFARM"

    elseif tf.state == "DEPOSIT" then
        logger.log(ctx, "info", "Depositing items...")
        
        -- Go to above home to avoid obstacles
        movement.goTo(ctx, { x=0, y=6, z=0 })
        
        -- Descend to 0, digging if needed (in case tree grew at 0,0)
        while ctx.curr.y > 0 do
             local hasDown, dataDown = turtle.inspectDown()
             if hasDown and not dataDown.name:find("air") and not dataDown.name:find("chest") then
                 -- Don't dig chests if we somehow are above them (unlikely at 0,0)
                 turtle.digDown()
             end
             if not movement.down(ctx) then
                 turtle.digDown()
             end
        end
        
        -- Output (South)
        movement.face(ctx, tf.chests.output)
        for i=1, 16 do
            local item = turtle.getItemDetail(i)
            if item and item.name:find("log") then
                turtle.select(i)
                while not turtle.drop() do
                    logger.log(ctx, "warn", "Output chest full. Waiting...")
                    sleep(5)
                end
            end
        end
        
        -- Trash (East)
        movement.face(ctx, tf.chests.trash)
        for i=1, 16 do
            local item = turtle.getItemDetail(i)
            if item then
                local isTrash = item.name:find("apple") or item.name:find("stick")
                local isSapling = item.name:find("sapling")
                
                if isTrash then
                    turtle.select(i)
                    turtle.drop()
                elseif isSapling then
                    -- Keep 16 saplings, dump rest
                    if turtle.getItemCount(i) > 16 then
                        turtle.select(i)
                        turtle.drop(turtle.getItemCount(i) - 16)
                    end
                end
            end
        end
        
        tf.state = "WAIT"
        return "TREEFARM"

    elseif tf.state == "WAIT" then
        logger.log(ctx, "info", "Waiting for growth...")
        sleep(30)
        
        tf.state = "SCAN"
        tf.nextX = 0
        tf.nextZ = 0
        return "TREEFARM"
    end

    return "TREEFARM"
end

return TREEFARM
