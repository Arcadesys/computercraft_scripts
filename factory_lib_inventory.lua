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
    if not itemName then return nil end
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
    if not itemName then return 0 end
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

local function suckBehind(amount)
    turnAround()
    local result = { turtle.suck(amount) }
    turnAround()
    return table.unpack(result)
end

local function dropBehind(amount)
    turnAround()
    local result = { turtle.drop(amount) }
    turnAround()
    return table.unpack(result)
end

local directions = {
    front = {
        suck = turtle.suck,
        drop = turtle.drop,
        side = "front"
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
    local chest = peripheralLib.wrap(info.side)
    return chest, info
end

--- Search the attached chest for an item and pull up to the requested quantity.
-- @return success, amountPulled
function Inventory.findItemInChest(itemName, quantity, direction)
    if not itemName then return false, 0 end
    local search = string.lower(itemName)
    local request = quantity or math.huge
    local chest, info = getChest(direction or "front")
    if not info then
        return false, 0
    end
    local pulled = 0

    if chest then
        for slot = 1, chest.size() do
            if pulled >= request then break end
            local detail = chest.getItemDetail(slot)
            if detail and string.find(string.lower(detail.name), search, 1, true) then
                local amount = math.min(request - pulled, detail.count)
                local targetSlot = Inventory.findItem(search) or Inventory.findEmptySlot()
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
        if not slot then break end
        turtle.select(slot)
        if info and info.suck and info.suck(request - pulled) then
            local detail = turtle.getItemDetail()
            if detail and string.find(string.lower(detail.name), search, 1, true) then
                pulled = pulled + detail.count
            else
                -- Wrong item; leave it in the slot for manual sorting.
            end
        else
            break
        end
    end
    return pulled > 0, pulled
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

    for _, direction in ipairs({"front", "back", "up", "down"}) do
        local ok, detail = inspectDirection(direction)
        if ok and detail and detail.name then
            log("Block %s: %s", direction, detail.name)
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

    local pulled = select(2, Inventory.findItemInChest("", 1, "front"))
    log("Chest probe pulled %d item(s) (0 means none or no chest)", pulled)

    local deposited = Inventory.depositItems("__unlikely_item_name__", "front")
    log("depositItems on fake name moved %d item(s)", deposited)

    log("Self-test complete")

    return table.concat(transcript, "\n")
end

local moduleName = ...
if moduleName == nil then
    Inventory.runSelfTest()
end

return Inventory
