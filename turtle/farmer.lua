-- Row-based crop farmer for ComputerCraft turtles.
-- Place the turtle at the south-west corner (looking east) of your field.
-- The turtle will walk the field in a serpentine pattern, harvesting mature crops
-- and replanting seeds. Ensure it has seeds in its inventory.

local function promptForNumber(promptText, defaultValue)
    write(string.format("%s [%d]: ", promptText, defaultValue))
    local response = read()
    local numeric = tonumber(response)
    if numeric and numeric > 0 then
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
    local results = {}
    for entry in string.gmatch(response, "[^,]+") do
        table.insert(results, string.lower(string.gsub(entry, "^%s*(.-)%s*$", "%1")))
    end
    return results
end

local function printStatus(message)
    print(string.format("[Farmer] %s", message))
end

local supportedCropAges = {
    ["minecraft:wheat"] = 7,
    ["minecraft:carrots"] = 7,
    ["minecraft:potatoes"] = 7,
    ["minecraft:beetroots"] = 3,
    ["minecraft:nether_wart"] = 3,
}

local function isUnlimitedFuel()
    local level = turtle.getFuelLevel()
    return level == "unlimited" or level == math.huge
end

local function ensureFuel(stepsNeeded)
    if isUnlimitedFuel() then
        return true
    end
    if turtle.getFuelLevel() >= stepsNeeded then
        return true
    end
    local fuelHints = {"coal", "charcoal", "lava_bucket", "blaze_rod", "coke"}
    local function isFuel(detail)
        if not detail or not detail.name then
            return false
        end
        local lower = string.lower(detail.name)
        for _, keyword in ipairs(fuelHints) do
            if string.find(lower, keyword, 1, true) then
                return true
            end
        end
        return false
    end
    local initialSlot = turtle.getSelectedSlot()
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if isFuel(detail) then
            turtle.select(slot)
            if turtle.refuel() then
                if initialSlot then
                    turtle.select(initialSlot)
                end
                if turtle.getFuelLevel() >= stepsNeeded then
                    return true
                end
            else
                if initialSlot then
                    turtle.select(initialSlot)
                end
            end
        end
    end
    printStatus("Out of fuel. Add fuel and press Enter to resume.")
    read()
    if initialSlot then
        turtle.select(initialSlot)
    end
    return ensureFuel(stepsNeeded)
end

local function moveForward()
    ensureFuel(1)
    while not turtle.forward() do
        if turtle.detect() then
            turtle.dig()
        else
            turtle.attack()
        end
        sleep(0.2)
    end
end

local function turn(direction)
    if direction == "left" then
        turtle.turnLeft()
    else
        turtle.turnRight()
    end
end

local function isMatureCrop(blockData)
    if not blockData then
        return false
    end
    if supportedCropAges[blockData.name] then
        local maxAge = supportedCropAges[blockData.name]
        local age = blockData.state and blockData.state.age
        if age then
            return tonumber(age) == maxAge
        end
        return true
    end
    return false
end

local function selectSeedSlot(preferredItems)
    local previousSlot = turtle.getSelectedSlot()
    for _, seedName in ipairs(preferredItems) do
        for slot = 1, 16 do
            local detail = turtle.getItemDetail(slot)
            if detail and string.lower(detail.name) == seedName then
                turtle.select(slot)
                return previousSlot
            end
        end
    end
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name then
            local lowerName = string.lower(detail.name)
            if string.find(lowerName, "seed", 1, true) or string.find(lowerName, "wart", 1, true) then
                turtle.select(slot)
                return previousSlot
            end
        end
    end
    return nil
end

local function tendCrop(preferredSeeds)
    local hasBlock, blockData = turtle.inspectDown()
    if hasBlock and isMatureCrop(blockData) then
        turtle.digDown()
        local previousSlot = selectSeedSlot(preferredSeeds)
        if previousSlot then
            if not turtle.placeDown() then
                printStatus("Failed to replant. Inventory may be missing seeds.")
            end
            turtle.select(previousSlot)
        else
            printStatus("No seeds found for replanting.")
        end
    end
end

local function farmField(fieldLength, fieldWidth, preferredSeeds)
    for row = 1, fieldWidth do
        for column = 1, fieldLength do
            tendCrop(preferredSeeds)
            if column < fieldLength then
                moveForward()
            end
        end
        if row < fieldWidth then
            if row % 2 == 1 then
                turn("right")
                moveForward()
                turn("right")
            else
                turn("left")
                moveForward()
                turn("left")
            end
        end
    end
    printStatus("Field pass complete. Returning to starting position.")
    if fieldWidth % 2 == 1 then
        turn("right")
        turn("right")
        for _ = 1, math.max(fieldLength - 1, 0) do
            moveForward()
        end
    end
    turn("right")
    for _ = 1, math.max(fieldWidth - 1, 0) do
        moveForward()
    end
    turn("right")
end

local function main()
    printStatus("Configure farming run.")
    local length = promptForNumber("Number of blocks per row", 9)
    local width = promptForNumber("Number of rows", 9)
    local seedDefaults = {
        "minecraft:wheat_seeds",
        "minecraft:carrot",
        "minecraft:potato",
        "minecraft:beetroot_seeds",
        "minecraft:nether_wart",
    }
    local preferredSeeds = promptForList("Preferred seed items (comma separated)", seedDefaults)

    farmField(length, width, preferredSeeds)
    printStatus("Farming run finished.")
end

main()
