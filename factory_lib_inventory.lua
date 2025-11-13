--[[
  Inventory Module
  Offers convenience helpers for item lookup, placement, and chest IO.

  Features:
  - Safe block placement in all directions
  - Slot scanning utilities for item lookup and counting
  - Chest interaction helpers for pulling and depositing items
  - Built-in self-test to probe inventory state and attempt a placement
]]

local Inventory = {}

--- Attempt to place a block in front of the turtle.
-- @param slotNumber Optional slot to select before placing.
function Inventory.safePlace(slotNumber)
    if slotNumber then turtle.select(slotNumber) end
    local item = turtle.getItemDetail()
    if not item then
        return false, "No item selected"
    end
    if turtle.detect() then
        return false, "Block already present"
    end
    if turtle.place() then
        return true
    end
    return false, "Failed to place block"
end

--- Attempt to place a block above the turtle.
function Inventory.safePlaceUp(slotNumber)
    if slotNumber then turtle.select(slotNumber) end
    local item = turtle.getItemDetail()
    if not item then
        return false, "No item selected"
    end
    if turtle.detectUp() then
        return false, "Block already present"
    end
    if turtle.placeUp() then
        return true
    end
    return false, "Failed to place block"
end

--- Attempt to place a block below the turtle.
function Inventory.safePlaceDown(slotNumber)
    if slotNumber then turtle.select(slotNumber) end
    local item = turtle.getItemDetail()
    if not item then
        return false, "No item selected"
    end
    if turtle.detectDown() then
        return false, "Block already present"
    end
    if turtle.placeDown() then
        return true
    end
    return false, "Failed to place block"
end

--- Locate the first slot that matches the provided item name fragment.
-- @param itemName Name or partial name to search for.
function Inventory.findItem(itemName)
    if type(itemName) ~= "string" then return nil end
    if itemName:match("^%s*$") then return nil end
    local search = string.lower(itemName)
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            if string.find(string.lower(detail.name), search, 1, true) then
                return slot
            end
        end
    end
    return nil
end

--- Count all items whose name contains the provided fragment.
function Inventory.countItem(itemName)
    if type(itemName) ~= "string" then return 0 end
    if itemName:match("^%s*$") then return 0 end
    local search = string.lower(itemName)
    local total = 0
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and string.find(string.lower(detail.name), search, 1, true) then
            total = total + detail.count
        end
    end
    return total
end

--- Find the first empty slot.
function Inventory.findEmptySlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return slot
        end
    end
    return nil
end

--- Count how many empty slots remain.
function Inventory.getEmptySlotCount()
    local free = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            free = free + 1
        end
    end
    return free
end

-- Rotate twice so we can reuse forward-facing APIs for rear interactions.
local function turnAround()
    turtle.turnLeft()
    turtle.turnLeft()
end

local function withFacing(rotate, action)
    rotate("enter")
    local result = { action() }
    rotate("exit")
    return table.unpack(result)
end

local function rotateBack(phase)
    if phase == "enter" then
        turnAround()
    else
        turnAround()
    end
end

local function rotateLeft(phase)
    if phase == "enter" then
        turtle.turnLeft()
    else
        turtle.turnRight()
    end
end

local function rotateRight(phase)
    if phase == "enter" then
        turtle.turnRight()
    else
        turtle.turnLeft()
    end
end

local function suckBehind(amount)
    return withFacing(rotateBack, function()
        return turtle.suck(amount)
    end)
end

local function dropBehind(amount)
    return withFacing(rotateBack, function()
        return turtle.drop(amount)
    end)
end

local function suckLeft(amount)
    return withFacing(rotateLeft, function()
        return turtle.suck(amount)
    end)
end

local function dropLeft(amount)
    return withFacing(rotateLeft, function()
        return turtle.drop(amount)
    end)
end

local function suckRight(amount)
    return withFacing(rotateRight, function()
        return turtle.suck(amount)
    end)
end

local function dropRight(amount)
    return withFacing(rotateRight, function()
        return turtle.drop(amount)
    end)
end

local directions = {
    front = {
        suck = turtle.suck,
        drop = turtle.drop,
        side = "front"
    },
    left = {
        suck = suckLeft,
        drop = dropLeft,
        side = "left"
    },
    right = {
        suck = suckRight,
        drop = dropRight,
        side = "right"
    },
    up = {
        suck = turtle.suckUp,
        drop = turtle.dropUp,
        side = "top"
    },
    down = {
        suck = turtle.suckDown,
        drop = turtle.dropDown,
        side = "bottom"
    },
    back = {
        suck = suckBehind,
        drop = dropBehind,
        side = "back"
    }
}


local function inspectDirection(direction)
    if direction == "front" then
        if turtle.inspect then
            return turtle.inspect()
        end
    elseif direction == "back" then
        if turtle.inspect then
            turnAround()
            local ok, detail = turtle.inspect()
            turnAround()
            return ok, detail
        end
    elseif direction == "left" then
        if turtle.inspect then
            turtle.turnLeft()
            local ok, detail = turtle.inspect()
            turtle.turnRight()
            return ok, detail
        end
    elseif direction == "right" then
        if turtle.inspect then
            turtle.turnRight()
            local ok, detail = turtle.inspect()
            turtle.turnLeft()
            return ok, detail
        end
    elseif direction == "up" then
        if turtle.inspectUp then
            return turtle.inspectUp()
        end
    elseif direction == "down" then
        if turtle.inspectDown then
            return turtle.inspectDown()
        end
    end
    return false, nil
end

local function isInventoryDetail(detail)
    if not detail then return false end
    local name = detail.name and string.lower(detail.name) or ""
    if name ~= "" then
        local keywords = {
            "chest", "barrel", "drawer", "cabinet", "crate", "storage",
            "locker", "bin", "box", "shelf", "container", "cupboard", "safe"
        }
        for _, keyword in ipairs(keywords) do
            if name:find(keyword, 1, true) then
                return true
            end
        end
    end
    if detail.tags then
        local tagKeywords = {
            "inventory", "storage", "container", "drawer", "cabinet",
            "locker", "chest", "bin", "box", "shelf", "cupboard", "safe"
        }
        for tag, present in pairs(detail.tags) do
            if present then
                local lowerTag = string.lower(tag)
                for _, keyword in ipairs(tagKeywords) do
                    if lowerTag:find(keyword, 1, true) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Internal helper to access a chest peripheral when available.
local function getChest(direction)
    local info = directions[direction or "front"]
    if not info then return nil, nil end
    local env = _ENV or _G
    local peripheralLib
    if type(env) == "table" then
        peripheralLib = rawget(env, "peripheral")
    end
    if type(peripheralLib) ~= "table" and type(peripheralLib) ~= "userdata" then
        return nil, info
    end
    if type(peripheralLib.wrap) ~= "function" then
        return nil, info
    end
    if info.side == "back" then
        turnAround()
        local chest = peripheralLib.wrap("front")
        turnAround()
        if chest then
            return chest, info
        end
        return nil, info
    end
    local chest = peripheralLib.wrap(info.side)
    return chest, info
end

local function snapshotChestViaTurtleIO(info)
    if not info or not info.suck or not info.drop then
        return nil, "No turtle IO available for snapshot"
    end

    local entries = {}
    local stagingSlots = {}
    local failureMessage
    local attempts = 0
    local maxAttempts = 256
    local originalSlot
    if turtle.getSelectedSlot then
        originalSlot = turtle.getSelectedSlot()
    end

    while attempts < maxAttempts do
        attempts = attempts + 1

        local emptySlot = Inventory.findEmptySlot()
        if not emptySlot then
            failureMessage = "Turtle inventory is full while scanning chest"
            break
        end

        turtle.select(emptySlot)
        local pulled = info.suck()
        if not pulled then
            break
        end

        local detail = turtle.getItemDetail()
        if not detail then
            failureMessage = "Unable to inspect item pulled from chest"
            break
        end

        entries[#entries + 1] = {
            displayName = detail.displayName or detail.name or "unknown",
            name = detail.name or "unknown",
            count = detail.count or 0,
        }

        stagingSlots[#stagingSlots + 1] = emptySlot
    end

    if attempts >= maxAttempts then
        failureMessage = failureMessage or "Reached snapshot attempt limit while scanning chest"
    end

    local dropFailure
    for index = 1, #stagingSlots do
        local slot = stagingSlots[index]
        turtle.select(slot)
        local count = turtle.getItemCount(slot)
        if count > 0 then
            local dropped = info.drop(count)
            if not dropped then
                dropFailure = dropFailure or string.format("Unable to return items from turtle slot %d", slot)
            elseif turtle.getItemCount(slot) > 0 then
                dropFailure = dropFailure or string.format("Items remained in turtle slot %d after return", slot)
            end
        end
    end

    if originalSlot then
        turtle.select(originalSlot)
    end

    if dropFailure then
        return nil, dropFailure
    end

    if failureMessage then
        return nil, failureMessage
    end

    return entries, nil
end

-- Passing nil or an empty string will match the first available item.
-- Note: when no chest peripheral is available the turtle needs a free slot to stage items.
-- @return success, amountPulled
function Inventory.findItemInChest(itemName, quantity, direction)
    local search
    if itemName == nil then
        search = nil
    elseif type(itemName) == "string" then
        if itemName:match("%S") then
            search = string.lower(itemName)
        else
            search = nil
        end
    else
        local text = tostring(itemName)
        search = text:match("%S") and string.lower(text) or nil
    end
    local request = quantity or math.huge
    local chest, info = getChest(direction or "front")
    if not info then
        return false, 0
    end
    local pulled = 0
    local failureReason

    if chest then
        for slot = 1, chest.size() do
            if pulled >= request then break end
            local detail = chest.getItemDetail(slot)
            if detail and (not search or string.find(string.lower(detail.name), search, 1, true)) then
                local amount = math.min(request - pulled, detail.count)
                local targetSlot
                if search then
                    targetSlot = Inventory.findItem(search) or Inventory.findEmptySlot()
                else
                    targetSlot = Inventory.findEmptySlot()
                end
                if not targetSlot then
                    return pulled > 0, pulled
                end
                turtle.select(targetSlot)
                local moved = chest.pushItems and chest.pushItems(info.side, slot, amount) or 0
                pulled = pulled + (moved or 0)
            end
        end
        return pulled > 0, pulled
    end

    -- Fallback: blind sucking when no peripheral access is available.
    local attempts = 0
    while pulled < request and attempts < 64 do
        attempts = attempts + 1
        local slot = Inventory.findEmptySlot()
        if not slot and search then
            slot = Inventory.findItem(search)
        end
        if not slot then
            failureReason = "No free inventory slot to stage chest items"
            break
        end
        local before = turtle.getItemCount(slot)
        turtle.select(slot)
        if info and info.suck and info.suck(request - pulled) then
            local detail = turtle.getItemDetail()
            if detail then
                local matches = not search or string.find(string.lower(detail.name), search, 1, true)
                local delta = detail.count - before
                if matches and delta > 0 then
                    pulled = pulled + delta
                elseif delta > 0 then
                    if info.drop then
                        info.drop(delta)
                    end
                    failureReason = failureReason or "Chest beamed back an unexpected item; returned to source"
                end
            end
        else
            failureReason = failureReason or "Turtle IO could not pull items (chest empty or access blocked)"
            break
        end
    end
    return pulled > 0, pulled, failureReason
end

--- Drop items that match the provided name into the adjacent chest.
-- Passing nil drops everything.
function Inventory.depositItems(itemName, direction)
    local _, info = getChest(direction or "front")
    if not info then
        info = directions[direction or "front"]
    end
    local dropFunc = info and info.drop or turtle.drop
    local total = 0
    local search = itemName and string.lower(itemName) or nil

    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            local shouldDrop = false
            if search then
                shouldDrop = string.find(string.lower(detail.name), search, 1, true) ~= nil
            else
                shouldDrop = true
            end

            if shouldDrop then
                turtle.select(slot)
                if dropFunc(detail.count) then
                    total = total + detail.count
                end
            end
        end
    end
    return total
end

--- Retrieve a snapshot of the adjacent chest contents when peripheral access is available.
-- @return table|nil contents keyed by slot number, or nil when unavailable; second return is message on failure
function Inventory.listChestContents(direction)
    local chest, info = getChest(direction or "front")
    if not chest then
        if info and info.suck then
            return nil, "No chest peripheral detected"
        end
        return nil, "No chest in that direction"
    end

    local items = {}

    local function capture(detail, slot)
        if detail then
            items[slot] = {
                name = detail.name,
                count = detail.count,
                displayName = detail.displayName,
            }
        end
    end

    if type(chest.list) == "function" then
        local ok, data = pcall(chest.list, chest)
        if ok and type(data) == "table" then
            for slot, detail in pairs(data) do
                capture(detail, slot)
            end
            return items
        end
    end

    local size
    if type(chest.size) == "function" then
        local okSize, value = pcall(chest.size, chest)
        if okSize then
            size = tonumber(value) or 0
        end
    end

    if type(chest.getItemDetail) == "function" and size and size > 0 then
        for slot = 1, size do
            local okDetail, detail = pcall(chest.getItemDetail, chest, slot)
            if okDetail and detail then
                capture(detail, slot)
            end
        end
        return items
    end

    return nil, "Chest does not expose list/size APIs"
end

--- Produce a simple slot-indexed view of a chest's contents.
-- Attempts peripheral access first, then falls back to draining the chest via turtle IO.
-- When turtle IO is used the slot numbers reflect the order items were retrieved, since
-- the turtle cannot observe true chest slot indices without a peripheral wrapper.
-- @return table|nil mapping slot numbers to {displayName, name, count}; second return is message on failure; third return is the method used
function Inventory.readChest(direction)
    direction = direction or "front"

    local contents, peripheralErr = Inventory.listChestContents(direction)
    if contents then
        local layout = {}
        for slot, detail in pairs(contents) do
            local index = tonumber(slot) or slot
            layout[index] = {
                displayName = (detail and detail.displayName) or (detail and detail.name) or "unknown",
                name = detail and detail.name or "unknown",
                count = detail and detail.count or 0,
            }
        end
        return layout, nil, "peripheral"
    end

    local chest, info = getChest(direction)
    if not info or not info.suck or not info.drop then
        return nil, peripheralErr or "No chest access available"
    end

    local snapshot, drainErr = snapshotChestViaTurtleIO(info)
    if snapshot then
        return snapshot, nil, "turtle_io"
    end

    return nil, drainErr or peripheralErr or "Unable to read chest"
end

--- Pull up to one full stack of items from a chest in the given direction.
-- Respects named filters and tries peripheral transfer first.
-- @return success:boolean, pulledCount:number, message:string|nil
function Inventory.pullStack(direction, itemName)
    direction = direction or "front"
    local chest, info = getChest(direction)
    if not info then
        return false, 0, "Unsupported direction"
    end

    local search
    if itemName then
        if type(itemName) == "string" and itemName:match("%S") then
            search = string.lower(itemName)
        else
            search = string.lower(tostring(itemName))
        end
    end

    local targetSlot = Inventory.findEmptySlot()
    if not targetSlot and search then
        targetSlot = Inventory.findItem(search)
    end
    if not targetSlot then
        return false, 0, "No available slot for stack pull"
    end

    turtle.select(targetSlot)

    if chest and type(chest.pullItems) == "function" then
        local sizeFunc = chest.size or chest.getInventorySize
        local chestSize = sizeFunc and sizeFunc(chest) or 0
        chestSize = tonumber(chestSize) or 27

        for slot = 1, chestSize do
            local detail = chest.getItemDetail and chest.getItemDetail(slot)
            if detail and (not search or string.find(string.lower(detail.name), search, 1, true)) then
                local stackSize = detail.count or 0
                if stackSize > 0 then
                    local target = Inventory.findItem(detail.name) or targetSlot
                    turtle.select(target)
                    local moved = chest.pullItems(info.side, slot, stackSize)
                    if moved and moved > 0 then
                        return true, moved, nil
                    end
                end
            end
        end
        return false, 0, "No matching stack in chest"
    end

    if info.suck then
        local before = turtle.getItemCount(targetSlot)
        local pulled = info.suck()
        if not pulled then
            return false, 0, "Chest did not provide items"
        end
        local detail = turtle.getItemDetail()
        if not detail then
            return false, 0, "Unable to inspect pulled stack"
        end
        if search and not string.find(string.lower(detail.name), search, 1, true) then
            if info.drop then info.drop(detail.count) end
            return false, 0, "Pulled stack does not match filter"
        end
        local after = turtle.getItemCount(targetSlot)
        return true, after - before, nil
    end

    return false, 0, "Chest cannot be accessed for stack pull"
end

--- Sample a chest using turtle suck/drop when no peripheral wrapper is available.
-- Only inspects the first few accessible items and immediately returns them.
-- @return table|nil counts keyed by item name, number of items sampled, error message on failure
function Inventory.sampleChestContents(direction, maxSamples)
    local chest, info = getChest(direction or "front")
    if chest then
        return nil, 0, "Peripheral available; prefer listChestContents"
    end
    if not info or not info.suck or not info.drop then
        return nil, 0, "No turtle IO available for direction"
    end

    local slot = Inventory.findEmptySlot()
    if not slot then
        return nil, 0, "No empty slot to stage sample"
    end

    local samples = {}
    local total = 0
    local limit = maxSamples or 16

    for _ = 1, limit do
        turtle.select(slot)
        local sucked = info.suck(1)
        if not sucked then
            break
        end

        local detail = turtle.getItemDetail(slot)
        if not detail then
            break
        end

        samples[detail.name] = (samples[detail.name] or 0) + 1
        total = total + 1

        local returned = info.drop(detail.count)
        if not returned then
            return nil, total, "Failed to return sampled item to chest"
        end
        local leftover = turtle.getItemCount(slot)
        if leftover > 0 then
            local cleared = info.drop(leftover)
            if not cleared then
                return nil, total, "Unable to clear leftover items after sampling"
            end
        end
    end

    return samples, total, nil
end

--- Self-test routine that inspects inventory state and performs sample actions.
function Inventory.runSelfTest()
    local transcript = {}

    local function log(message, ...)
        local text
        if select('#', ...) > 0 then
            text = string.format(message, ...)
        else
            text = tostring(message)
        end
        text = "[inventory] " .. text
        print(text)
        transcript[#transcript + 1] = text
    end

    log("Starting self-test")
    local emptySlots = Inventory.getEmptySlotCount()
    log("Empty slots: %d", emptySlots)

    local foundInventories = {}

    for _, direction in ipairs({"front", "back", "left", "right", "up", "down"}) do
        local ok, detail = inspectDirection(direction)
        if ok and detail and detail.name then
            log("Block %s: %s", direction, detail.name)
            if detail.tags then
                local tags = {}
                local count = 0
                for tag, present in pairs(detail.tags) do
                    if present then
                        tags[#tags + 1] = tag
                        count = count + 1
                        if count >= 4 then break end
                    end
                end
                if #tags > 0 then
                    log("  tags: %s", table.concat(tags, ", "))
                end
            end
        else
            log("Block %s: none detected", direction)
        end

        local chest, info = getChest(direction)
        if chest then
            local slotCount = 0
            if type(chest.size) == "function" then
                local okSize, value = pcall(chest.size, chest)
                slotCount = okSize and tonumber(value) or 0
            elseif type(chest.getInventorySize) == "function" then
                local okSize, value = pcall(chest.getInventorySize, chest)
                slotCount = okSize and tonumber(value) or 0
            end
            log("Chest peripheral detected on %s (%d slot(s))", direction, slotCount or 0)
            table.insert(foundInventories, direction)
        elseif ok and isInventoryDetail(detail) then
            local blockName = (detail and detail.name) or "unknown"
            log("Inventory block accessible on %s (%s); turtle IO will be used", direction, blockName)
            table.insert(foundInventories, direction)
        elseif info then
            log("No peripheral on %s; fallback will use turtle access (%s)", direction, info.side)
        else
            log("Direction %s not supported by chest helper", direction)
        end
    end

    local firstFilledSlot
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            firstFilledSlot = slot
            break
        end
    end

    if firstFilledSlot then
        turtle.select(firstFilledSlot)
        local detail = turtle.getItemDetail()
        log("Sample item: slot %d -> %s x%d", firstFilledSlot, detail.name, detail.count)

        local located = Inventory.findItem(detail.name)
        log("findItem('%s') -> %s", detail.name, tostring(located))

        local count = Inventory.countItem(detail.name)
        log("countItem('%s') -> %d", detail.name, count)

        local success, reason = Inventory.safePlace()
        if success then
            log("Placed block in front successfully")
        else
            log("Placement blocked: %s", reason or "unknown")
        end

        local upSuccess, upReason = Inventory.safePlaceUp()
        log("safePlaceUp -> %s (%s)", tostring(upSuccess), upReason or "")

        local downSuccess, downReason = Inventory.safePlaceDown()
        log("safePlaceDown -> %s (%s)", tostring(downSuccess), downReason or "")
    else
        log("No items detected; add a block to demonstrate placement")
    end

    local chestDirection = foundInventories[1] or "front"
    if #foundInventories == 0 then
        log("No obvious inventory detected; defaulting chest tests to front")
    elseif chestDirection ~= "front" then
        log("Using %s for chest interaction tests", chestDirection)
    end

    local _, pulled, probeMessage = Inventory.findItemInChest("", 1, chestDirection)
    if pulled > 0 then
        log("Chest probe (%s) pulled %d item(s)", chestDirection, pulled)
    else
        if probeMessage then
            log("Chest probe (%s) pulled 0 item(s) -> %s", chestDirection, probeMessage)
        else
            log("Chest probe (%s) pulled 0 item(s) (chest empty or access failed)", chestDirection)
        end
    end

    local stackSuccess, stackPulled, stackMessage = Inventory.pullStack(chestDirection)
    if stackSuccess then
        log("pullStack on %s grabbed %d item(s)", chestDirection, stackPulled)
    else
        log("pullStack on %s failed: %s", chestDirection, stackMessage or "unknown reason")
    end

    local deposited = Inventory.depositItems("__unlikely_item_name__", chestDirection)
    log("depositItems on fake name via %s moved %d item(s)", chestDirection, deposited)

    local readable, readableErr, readableMethod = Inventory.readChest(chestDirection)
    if readable then
        local keys = {}
        for slot in pairs(readable) do
            keys[#keys + 1] = slot
        end
        table.sort(keys, function(a, b)
            if type(a) == "number" and type(b) == "number" then
                return a < b
            end
            return tostring(a) < tostring(b)
        end)
        if #keys == 0 then
            log("readChest (%s) reports chest %s is empty", readableMethod or "unknown", chestDirection)
        else
            log("readChest (%s) summary for chest on %s", readableMethod or "unknown", chestDirection)
            for _, slot in ipairs(keys) do
                local entry = readable[slot] or readable[tostring(slot)]
                local displaySlot = tonumber(slot) or slot
                log("  slot %s: %s x%d", displaySlot, entry and (entry.displayName or entry.name or "unknown") or "unknown", entry and entry.count or 0)
            end
        end
    else
        log("readChest failed (%s)", readableErr or "unknown reason")
        local samples, sampleCount, sampleReason = Inventory.sampleChestContents(chestDirection, 1)
        if samples and sampleCount > 0 then
            log("Sampled %d item(s) from chest on %s via turtle IO", sampleCount, chestDirection)
            for name, count in pairs(samples) do
                log("  sample: %s x%d", name, count)
            end
        elseif sampleReason then
            log("Chest sampling failed: %s", sampleReason)
        end
    end

    log("Self-test complete")

    return table.concat(transcript, "\n")
end

local moduleName = ...
if moduleName == nil then
    Inventory.runSelfTest()
end

return Inventory
