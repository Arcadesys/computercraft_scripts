-- Animal breeding assistant for ComputerCraft turtles.
-- Place the turtle in the middle of your animal pen. It will rotate in place, feed
-- animals using the configured items, and optionally collect drops beneath it.

local function promptForNumber(promptText, defaultValue)
    write(string.format("%s [%d]: ", promptText, defaultValue))
    local response = read()
    local numeric = tonumber(response)
    if numeric and numeric >= 0 then
        return math.floor(numeric)
    end
    return defaultValue
end

local function promptForList(promptText, defaultList)
    write(string.format("%s [%s]: ", promptText, table.concat(defaultList, ",")))
    local response = read()
    if response == nil or response == "" then
        return defaultList
    end
    local result = {}
    for entry in string.gmatch(response, "[^,]+") do
        table.insert(result, string.lower(string.gsub(entry, "^%s*(.-)%s*$", "%1")))
    end
    return result
end

local function printStatus(message)
    print(string.format("[Rancher] %s", message))
end

local fuelKeywords = {"coal", "charcoal", "lava_bucket", "blaze_rod", "coke"}

local function isUnlimitedFuel()
    local fuelLevel = turtle.getFuelLevel()
    return fuelLevel == "unlimited" or fuelLevel == math.huge
end

local function isFuel(detail)
    if not detail or not detail.name then
        return false
    end
    local lower = string.lower(detail.name)
    for _, keyword in ipairs(fuelKeywords) do
        if string.find(lower, keyword, 1, true) then
            return true
        end
    end
    return false
end

local function ensureFuel(stepsNeeded)
    if isUnlimitedFuel() then
        return true
    end
    if turtle.getFuelLevel() >= stepsNeeded then
        return true
    end
    local initialSlot = turtle.getSelectedSlot()
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if isFuel(detail) then
            turtle.select(slot)
            if turtle.refuel() then
                turtle.select(initialSlot)
                if turtle.getFuelLevel() >= stepsNeeded then
                    return true
                end
            else
                turtle.select(initialSlot)
            end
        end
    end
    printStatus("Fuel depleted. Add fuel and press Enter.")
    read()
    turtle.select(initialSlot)
    return ensureFuel(stepsNeeded)
end

local function selectFeedSlot(feedItems)
    local initialSlot = turtle.getSelectedSlot()
    for _, itemName in ipairs(feedItems) do
        for slot = 1, 16 do
            local detail = turtle.getItemDetail(slot)
            if detail and detail.name and string.lower(detail.name) == itemName then
                turtle.select(slot)
                return initialSlot
            end
        end
    end
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name then
            local lower = string.lower(detail.name)
            if string.find(lower, "wheat", 1, true) or string.find(lower, "carrot", 1, true) or string.find(lower, "seeds", 1, true) then
                turtle.select(slot)
                return initialSlot
            end
        end
    end
    return nil
end

local function feedDirection(feedItems, attempts)
    local fedAny = false
    for _ = 1, attempts do
        local previousSlot = selectFeedSlot(feedItems)
        if not previousSlot then
            printStatus("Out of feed items.")
            return fedAny
        end
        if turtle.place() then
            fedAny = true
        else
            -- If place fails, try animals below (e.g., when turtle hovers)
            if turtle.placeDown() then
                fedAny = true
            end
        end
        if previousSlot then
            turtle.select(previousSlot)
        end
    end
    return fedAny
end

local function collectDrops()
    turtle.suck()
    turtle.suckDown()
    turtle.suckUp()
end

local function runBreedingCycle(feedItems, attemptsPerSide, collectLoot)
    local fedThisCycle = false
    for _ = 1, 4 do
        if feedDirection(feedItems, attemptsPerSide) then
            fedThisCycle = true
        end
        if collectLoot then
            collectDrops()
        end
        turtle.turnRight()
    end
    if not fedThisCycle then
        printStatus("No animals were fed this cycle. Refill feed or reposition the turtle.")
    elseif collectLoot then
        printStatus("Feeding complete. Drops collected from all sides.")
    end
end

local function main()
    printStatus("Configure ranching routine.")
    local cycles = promptForNumber("Number of breeding cycles", 3)
    local attemptsPerSide = promptForNumber("Feed attempts per side", 4)
    local cooldownSeconds = promptForNumber("Seconds between cycles", 300)
    local feedDefaults = {
        "minecraft:wheat",
        "minecraft:carrot",
        "minecraft:potato",
        "minecraft:beetroot",
        "minecraft:seeds",
    }
    local feedItems = promptForList("Preferred feed items (comma separated)", feedDefaults)
    local collectLootAnswer = promptForNumber("Collect drops each cycle? 1=yes, 0=no", 1)
    local collectLootFlag = collectLootAnswer ~= 0

    for cycle = 1, cycles do
        printStatus(string.format("Starting cycle %d of %d", cycle, cycles))
        ensureFuel(1)
        runBreedingCycle(feedItems, attemptsPerSide, collectLootFlag)
        if cycle < cycles and cooldownSeconds > 0 then
            printStatus(string.format("Cooling down for %d seconds", cooldownSeconds))
            sleep(cooldownSeconds)
        end
    end

    printStatus("Ranching routine complete.")
end

main()
