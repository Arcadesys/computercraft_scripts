---@diagnostic disable: undefined-global
--[[
State: TREEFARM
Grid-based tree farming logic.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local wizard = require("lib_wizard")
local startup = require("lib_startup")

local function selectSapling(ctx)
    inventory.scan(ctx)
    local state = ctx.inventory
    if not state or not state.slots then return false end
    
    for slot, info in pairs(state.slots) do
        if info.name and info.name:find("sapling") then
            if turtle.select(slot) then
                return true
            end
        end
    end
    return false
end

local function TREEFARM(ctx)
    logger.log(ctx, "info", "TREEFARM State (Fix Applied)")
    local tf = ctx.treefarm
    if not tf then return "INITIALIZE" end

    -- 1. Fuel Check
    if not startup.runFuelCheck(ctx, tf.chests) then
        return "TREEFARM"
    end

    -- 2. State Machine
    if tf.state == "SCAN" then
        -- Interpret width/height as number of trees
        local treeW, treeH = tf.width, tf.height
        local limitX = (treeW * 2) - 1
        local limitZ = (treeH * 2) - 1
        
        if tf.nextX == 0 and tf.nextZ == 0 then
            logger.log(ctx, "info", "Starting patrol run. Grid: " .. treeW .. "x" .. treeH .. " trees.")

            -- Pre-run fuel check
            local totalSpots = (limitX + 1) * (limitZ + 1)
            local fuelPerSpot = 16 -- Descent/Ascent + Travel
            local needed = (totalSpots * fuelPerSpot) + 200
            local current = turtle.getFuelLevel()
            
            if current ~= "unlimited" and type(current) == "number" and current < needed then
                logger.log(ctx, "warn", string.format("Pre-run fuel check: Have %d, Need %d", current, needed))
                
                -- 1. Try inventory
                fuelLib.refuel(ctx, { target = needed, excludeItems = { "sapling", "log" } })
                current = turtle.getFuelLevel()
                if current == "unlimited" then current = math.huge end
                if type(current) ~= "number" then current = 0 end
                
                logger.log(ctx, "debug", string.format("Fuel check: current=%s needed=%s", tostring(current), tostring(needed)))

                -- 2. Try fuel chest
                if current < (needed or 0) and tf.chests and tf.chests.fuel then
                    logger.log(ctx, "info", "Insufficient fuel. Visiting fuel depot.")
                    movement.goTo(ctx, { x=0, y=0, z=0 })
                    movement.face(ctx, tf.chests.fuel)
                    
                    local attempts = 0
                    while current < (needed or 0) and attempts < 16 do
                        if not turtle.suck() then
                            logger.log(ctx, "warn", "Fuel chest empty or inventory full!")
                            break
                        end
                        fuelLib.refuel(ctx, { target = (needed or 0), excludeItems = { "sapling", "log" } })
                        current = turtle.getFuelLevel()
                        if current == "unlimited" then current = math.huge end
                        if type(current) ~= "number" then current = 0 end
                        attempts = attempts + 1
                    end
                end
            end
        end

        if tf.nextZ > limitZ then
            tf.state = "DEPOSIT"
            return "TREEFARM"
        end
        
        local x = tf.nextX
        local z = tf.nextZ
        
        logger.log(ctx, "debug", "Checking sector " .. x .. "," .. z)

        -- Fly over to avoid obstacles
        local hoverHeight = 6
        -- Offset by 2 to avoid home base and provide a return path
        local xOffset = 2
        local zOffset = 2
        local target = { x = x + xOffset, y = hoverHeight, z = -(z + zOffset) }
        
        -- Move to target
        if not movement.goTo(ctx, target, { axisOrder = { "y", "x", "z" } }) then
            logger.log(ctx, "warn", "Path blocked to " .. x .. "," .. z)
            -- Try to clear path?
            -- For now, skip or retry
        else
            -- Descend and harvest
            -- We are at (x, hoverHeight, -z)
            while movement.getPosition(ctx).y > 1 do
                local hasDown, dataDown = turtle.inspectDown()
                if hasDown and (dataDown.name:find("log") or dataDown.name:find("leaves")) then
                    turtle.digDown()
                    sleep(0.2)
                    while turtle.suckDown() do sleep(0.1) end
                elseif hasDown and not dataDown.name:find("air") then
                    turtle.digDown()
                    sleep(0.2)
                    while turtle.suckDown() do sleep(0.1) end
                end
                if not movement.down(ctx) then
                    turtle.digDown() -- Try again
                    sleep(0.2)
                    while turtle.suckDown() do sleep(0.1) end
                end
            end
            
            -- Now at y=1. Check base (y=0).
            local hasDown, dataDown = turtle.inspectDown()
            if hasDown and dataDown.name:find("log") then
                logger.log(ctx, "info", "Timber! Found a tree at " .. x .. "," .. z .. ". Chopping it down.")
                turtle.digDown()
                sleep(0.2)
                while turtle.suckDown() do sleep(0.1) end
                hasDown = false
            end
            
            -- Replant
            local isGridSpot = (x % 2 == 0) and (z % 2 == 0)
            if isGridSpot and (not hasDown or dataDown.name:find("air") or dataDown.name:find("sapling")) then
                -- Try to find any sapling
                if selectSapling(ctx) then
                    logger.log(ctx, "info", "Replanting sapling at " .. x .. "," .. z .. ".")
                    turtle.placeDown()
                end
            end
        end
        
        -- Next
        tf.nextX = tf.nextX + 1
        if tf.nextX > limitX then
            tf.nextX = 0
            tf.nextZ = tf.nextZ + 1
        end
        
        return "TREEFARM"

    elseif tf.state == "DEPOSIT" then
        logger.log(ctx, "info", "Inventory full (or scan done). Heading home to unload.")
        
        -- Go to above home to avoid obstacles
        movement.goTo(ctx, { x=0, y=6, z=0 })
        
        -- Descend to 0, digging if needed (in case tree grew at 0,0)
        while movement.getPosition(ctx).y > 0 do
             local hasDown, dataDown = turtle.inspectDown()
             if hasDown and not dataDown.name:find("air") and not dataDown.name:find("chest") then
                 -- Don't dig chests if we somehow are above them (unlikely at 0,0)
                 turtle.digDown()
             end
             if not movement.down(ctx) then
                 turtle.digDown()
             end
        end
        
        -- 1. Output Logs (South)
        logger.log(ctx, "info", "Dropping off logs.")
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

        -- 2. Fuel Maintenance (West)
        logger.log(ctx, "info", "Checking fuel reserves.")
        movement.face(ctx, tf.chests.fuel)
        turtle.suck() -- Grab some fuel
        fuelLib.refuel(ctx, { target = 1000, excludeItems = { "sapling", "log" } })
        
        -- 3. Trash (East)
        logger.log(ctx, "info", "Taking out the trash.")
        movement.face(ctx, tf.chests.trash)
        for i=1, 16 do
            local item = turtle.getItemDetail(i)
            if item then
                local isLog = item.name:find("log")
                local isSapling = item.name:find("sapling")
                
                turtle.select(i)
                if isLog then
                    -- Skip logs (should be gone)
                elseif isSapling then
                    -- Keep 16 saplings, dump rest
                    if turtle.getItemCount(i) > 16 then
                        turtle.drop(turtle.getItemCount(i) - 16)
                    end
                else
                    -- Check if it is fuel
                    if turtle.refuel(0) then
                        -- Keep fuel
                    else
                        -- Not fuel, not log, not sapling. Trash.
                        turtle.drop()
                    end
                end
            end
        end
        
        tf.state = "WAIT"
        return "TREEFARM"

    elseif tf.state == "WAIT" then
        logger.log(ctx, "info", "All done for now. Taking a nap while trees grow.")
        sleep(30)
        
        tf.state = "SCAN"
        tf.nextX = 0
        tf.nextZ = 0
        return "TREEFARM"
    end

    return "TREEFARM"
end

return TREEFARM
