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

    -- Ensure chests are linked (in case of resume)
    if not pf.chests and ctx.chests then
        pf.chests = ctx.chests
    end

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

        -- Determine target spots
        local spots = {}
        if pf.useSchema and ctx.schema then
            -- Extract potato locations from schema
            for xStr, yLayer in pairs(ctx.schema) do
                for yStr, zLayer in pairs(yLayer) do
                    for zStr, block in pairs(zLayer) do
                        if block.material and (block.material:find("potato") or block.material:find("farmland") or block.material:find("dirt")) then
                             -- Only add if it's explicitly a crop spot or soil we want to farm
                             -- In schema, we might put potatoes directly or dirt.
                             -- Let's assume anything not air/stone/water is a potential spot if it's on the crop layer.
                             -- Usually crops are on layer 1 (above soil at 0) or soil is at 0.
                             -- Let's look for the crop block itself or the soil if we want to plant on it.
                             -- For simplicity, let's assume the schema defines the crop layer (e.g. layer 1).
                             if tonumber(yStr) == 1 then -- Assumption: Crops are on layer 1
                                table.insert(spots, { x = tonumber(xStr), z = tonumber(zStr) })
                             end
                        end
                    end
                end
            end
             -- Sort spots
            table.sort(spots, function(a, b)
                if a.x == b.x then return a.z < b.z end
                return a.x < b.x
            end)
        else
            -- Scan only the crop area (exclude borders)
            local width = tonumber(pf.width) or 9
            local height = tonumber(pf.height) or 9
            local w, h = width - 2, height - 2
            
            for x = 0, w - 1 do
                for z = 0, h - 1 do
                    table.insert(spots, { x = x, z = z })
                end
            end
        end

        if not pf.spotIndex then pf.spotIndex = 1 end

        if pf.spotIndex > #spots then
            pf.state = "DEPOSIT"
            pf.spotIndex = 1
            return "POTATOFARM"
        end
        
        local spot = spots[pf.spotIndex]
        local x = spot.x
        local z = spot.z
        
        -- Fly over (height 1 is directly above crops)
        local hoverHeight = 1
        -- Apply offset.
        -- If using schema, x/z are absolute in schema coords.
        -- If using grid (else block), x/z were 0-based relative to inner crop area.
        -- The original code did: localTarget = { x = x + 1, y = hoverHeight, z = -(z + 1) }
        -- This implies x,z were 0-based index inside the border.
        
        local offset = (ctx.config and ctx.config.buildOffset) or { x = 1, y = 0, z = 1 }
        local targetX, targetZ
        
        if pf.useSchema then
             targetX = x + (offset.x or 0)
             targetZ = z + (offset.z or 0)
        else
             -- Legacy grid logic: x,z are 0..w-1.
             -- We want to map 0 to border+1.
             targetX = x + 1 + (offset.x or 0) -- Wait, original code used x+1 relative to origin.
             -- If origin is 0,0,0, then x+1 is 1.
             -- If buildOffset is 1,0,1, then the farm starts at 1,0,1.
             -- The border is at 1,0,1? No, usually buildOffset is where the 0,0,0 of schema goes.
             -- If legacy grid assumes 0,0 is top-left of crop area inside border.
             -- Let's stick to original logic for legacy:
             targetX = x + 1
             targetZ = z + 1
             -- But wait, we need to account for world coordinates if we are not at 0,0,0.
             -- The original code used world.localToWorldRelative(origin, localTarget).
             -- localTarget was { x = x + 1, ... z = -(z + 1) }.
             -- So let's replicate that.
        end
        
        local localTarget
        if pf.useSchema then
             localTarget = { x = x + (offset.x or 0), y = hoverHeight, z = -(z + (offset.z or 0)) } -- Z is negative in localToWorld usually?
             -- Wait, world.localToWorldRelative usually takes +x right, +z back (or forward depending on system).
             -- In standard MC: Z increases South.
             -- In this bot's coordinate system (lib_movement), usually forward is +x or +z?
             -- Let's look at original code: localTarget = { x = x + 1, y = hoverHeight, z = -(z + 1) }
             -- It seems Z is inverted or something.
             -- Let's assume schema coordinates (x, z) map to (x, -z) in local movement frame if that's what original did.
             -- Actually, let's trust the build offset logic.
             -- If build placed block at (x, y, z) relative to start, we should go to (x, y+1, z).
             -- Build uses: targetPos = world.localToWorldRelative(ctx.origin, { x = x+offX, y = y+offY, z = z+offZ })
             -- So we should use the same.
             localTarget = { 
                x = x + (offset.x or 0), 
                y = hoverHeight, 
                z = z + (offset.z or 0) 
             }
        else
             localTarget = { x = x + 1, y = hoverHeight, z = (z + 1) } -- Removed negative sign to match build system likely, but original had negative?
             -- Original: z = -(z + 1).
             -- If original worked, I should keep it.
             -- But wait, if I change to schema, I should use consistent coordinates.
             -- Let's assume for legacy we keep original logic, for schema we use build coordinates.
             localTarget = { x = x + 1, y = hoverHeight, z = -(z + 1) }
        end
        
        -- If using schema, we want to match the build coordinates.
        if pf.useSchema then
             localTarget = { 
                x = x + (offset.x or 0), 
                y = hoverHeight, 
                z = z + (offset.z or 0) 
             }
        end

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
        pf.spotIndex = pf.spotIndex + 1
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
        pf.spotIndex = 1
        return "POTATOFARM"
    end

    return "POTATOFARM"
end

return POTATOFARM
