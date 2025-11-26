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
local farming = require("lib_farming")

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
        local treeW = tonumber(tf.width) or 8
        local treeH = tonumber(tf.height) or 8
        local limitX = (treeW * 2) - 1
        local limitZ = (treeH * 2) - 1
        
        if type(tf.nextX) ~= "number" then tf.nextX = 0 end
        if type(tf.nextZ) ~= "number" then tf.nextZ = 0 end
        
        if tf.nextX == 0 and tf.nextZ == 0 then
            logger.log(ctx, "info", "Starting patrol run. Grid: " .. treeW .. "x" .. treeH .. " trees.")

            -- Pre-run fuel check
            local totalSpots = (limitX + 1) * (limitZ + 1)
            local fuelPerSpot = 16 -- Descent/Ascent + Travel
            local needed = (totalSpots * fuelPerSpot) + 200
            if type(needed) ~= "number" then needed = 1000 end
            
            local function getFuel()
                local l = turtle.getFuelLevel()
                if l == "unlimited" then return math.huge end
                if type(l) ~= "number" then return 0 end
                return l
            end
            
            local current = getFuel()

            if current < needed then
                logger.log(ctx, "warn", string.format("Pre-run fuel check: Have %s, Need %s", tostring(current), tostring(needed)))
                
                -- 1. Try inventory
                fuelLib.refuel(ctx, { target = needed, excludeItems = { "sapling", "log" } })
                current = getFuel()
                
                logger.log(ctx, "debug", string.format("Fuel check: current=%s needed=%s", tostring(current), tostring(needed)))

                -- 2. Try fuel chest
                if current < needed and tf.chests and tf.chests.fuel then
                    logger.log(ctx, "info", "Insufficient fuel. Visiting fuel depot.")
                    movement.goTo(ctx, { x=0, y=0, z=0 })
                    movement.face(ctx, tf.chests.fuel)
                    
                    local attempts = 0
                    while current < needed and attempts < 16 do
                        if not turtle.suck() then
                            logger.log(ctx, "warn", "Fuel chest empty or inventory full!")
                            break
                        end
                        fuelLib.refuel(ctx, { target = needed, excludeItems = { "sapling", "log" } })
                        current = getFuel()
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
        local ok, err = farming.deposit(ctx, {
            safeHeight = 6,
            chests = tf.chests,
            keepItems = { ["sapling"] = 16 },
            refuel = true
        })
        
        if not ok then
            logger.log(ctx, "error", "Deposit failed: " .. tostring(err))
            return "ERROR"
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
