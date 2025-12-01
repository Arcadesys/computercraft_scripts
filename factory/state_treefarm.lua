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
        -- Determine target spots
        local spots = {}
        if tf.useSchema and ctx.schema then
            -- Extract sapling locations from schema
            for xStr, yLayer in pairs(ctx.schema) do
                for yStr, zLayer in pairs(yLayer) do
                    for zStr, block in pairs(zLayer) do
                        if block.material and (block.material:find("sapling") or block.material:find("log")) then
                            table.insert(spots, { x = tonumber(xStr), z = tonumber(zStr) })
                        end
                    end
                end
            end
            -- Sort spots for consistent traversal
            table.sort(spots, function(a, b)
                if a.x == b.x then return a.z < b.z end
                return a.x < b.x
            end)
        else
            -- Generate grid spots
            local treeW = tonumber(tf.width) or 8
            local treeH = tonumber(tf.height) or 8
            local limitX = (treeW * 2) - 1
            local limitZ = (treeH * 2) - 1
            for x = 0, limitX do
                for z = 0, limitZ do
                    if (x % 2 == 0) and (z % 2 == 0) then
                        table.insert(spots, { x = x, z = z })
                    end
                end
            end
        end

        if not tf.spotIndex then tf.spotIndex = 1 end
        
        if tf.spotIndex > #spots then
            tf.state = "DEPOSIT"
            tf.spotIndex = 1
            return "TREEFARM"
        end

        local spot = spots[tf.spotIndex]
        local x = spot.x
        local z = spot.z
        
        logger.log(ctx, "debug", "Checking tree at " .. x .. "," .. z)

        -- Fly over to avoid obstacles
        local hoverHeight = 6
        -- Offset by 2 to avoid home base and provide a return path (adjust as needed based on schema origin)
        -- If using schema, we assume schema coordinates are relative to start.
        -- Existing logic used xOffset=2, zOffset=2. Let's keep it for now but might need adjustment for schema.
        -- Actually, for schema, the coordinates are usually 0-based from the start.
        -- The build offset in state_build was {x=1, y=0, z=1}.
        -- So if schema has a block at 0,0,0, it was built at world relative 1,0,1.
        -- We should probably respect that offset.
        local offset = (ctx.config and ctx.config.buildOffset) or { x = 1, y = 0, z = 1 }
        local target = { 
            x = x + (offset.x or 0), 
            y = hoverHeight, 
            z = z + (offset.z or 0) 
        }
        
        -- Move to target
        if not movement.goTo(ctx, target, { axisOrder = { "y", "x", "z" } }) then
            logger.log(ctx, "warn", "Path blocked to " .. x .. "," .. z)
            -- Try to clear path?
            -- For now, skip or retry
        else
            -- Descend and harvest
            -- We are at (x, hoverHeight, z)
            while movement.getPosition(ctx).y > 1 do
                local hasDown, dataDown = turtle.inspectDown()
                if hasDown and (dataDown.name:find("log") or dataDown.name:find("leaves")) then
                    turtle.digDown()
                    sleep(0.2)
                    while turtle.suckDown() do sleep(0.1) end
                elseif hasDown and not dataDown.name:find("air") then
                    -- Don't dig non-tree blocks if using schema, unless it's leaves/logs
                    -- But trees grow leaves.
                    -- If we are strictly above the sapling spot, we should be fine digging down to it.
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
            -- If using schema, we know this is a spot.
            if not hasDown or dataDown.name:find("air") or dataDown.name:find("sapling") then
                -- Try to find any sapling
                if selectSapling(ctx) then
                    logger.log(ctx, "info", "Replanting sapling at " .. x .. "," .. z .. ".")
                    turtle.placeDown()
                end
            end
        end
        
        -- Next
        tf.spotIndex = tf.spotIndex + 1
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
        tf.spotIndex = 1
        return "TREEFARM"
    end

    return "TREEFARM"
end

return TREEFARM
