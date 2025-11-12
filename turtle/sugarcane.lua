-- Sugar cane harvesting turtle for ComputerCraft.
-- Position the turtle at the south-west corner of your sugar cane field, facing east.
-- The turtle will trim each cane column, replant the base, and traverse the field in
-- a serpentine pattern.

local function promptForNumber(promptText, defaultValue)
    write(string.format("%s [%d]: ", promptText, defaultValue))
    local response = read()
    local numeric = tonumber(response)
    if numeric and numeric > 0 then
        return math.floor(numeric)
    end
    return defaultValue
end

local function printStatus(message)
    print(string.format("[SugarCane] %s", message))
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
    printStatus("Out of fuel. Add fuel and press Enter.")
    read()
    turtle.select(initialSlot)
    return ensureFuel(stepsNeeded)
end

local function moveForward()
    ensureFuel(1)
    local attempts = 0
    while not turtle.forward() do
        attempts = attempts + 1
        if turtle.detect() then
            turtle.dig()
        else
            turtle.attack()
        end
        if attempts > 10 then
            sleep(0.3)
        end
    end
end

local function selectSugarCaneSlot()
    local initialSlot = turtle.getSelectedSlot()
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name and string.find(string.lower(detail.name), "sugar_cane", 1, true) then
            turtle.select(slot)
            return initialSlot
        end
    end
    return nil
end

local function harvestColumn()
    local hasBlock, detail = turtle.inspect()
    if not hasBlock then
        return
    end
    if not detail.name or not string.find(string.lower(detail.name), "sugar_cane", 1, true) then
        return
    end
    turtle.dig()
    sleep(0.2)
    turtle.suck()
    local previousSlot = selectSugarCaneSlot()
    if previousSlot then
        if not turtle.place() then
            printStatus("Unable to replant sugar cane. Check water adjacency.")
        end
        turtle.select(previousSlot)
    else
        printStatus("No sugar cane in inventory to replant this column.")
    end
end

local function harvestField(lengthPerRow, rowCount)
    for row = 1, rowCount do
        for column = 1, lengthPerRow do
            harvestColumn()
            if column < lengthPerRow then
                moveForward()
            end
        end
        if row < rowCount then
            if row % 2 == 1 then
                turtle.turnRight()
                moveForward()
                turtle.turnRight()
            else
                turtle.turnLeft()
                moveForward()
                turtle.turnLeft()
            end
        end
    end
    printStatus("Field pass complete. Returning to starting corner.")
    if rowCount % 2 == 1 then
        turtle.turnRight()
        turtle.turnRight()
        for _ = 1, math.max(lengthPerRow - 1, 0) do
            moveForward()
        end
    end
    turtle.turnRight()
    for _ = 1, math.max(rowCount - 1, 0) do
        moveForward()
    end
    turtle.turnRight()
end

local function main()
    printStatus("Configure sugar cane harvest.")
    local rowLength = promptForNumber("Columns per row", 12)
    local rowCount = promptForNumber("Number of rows", 2)
    harvestField(rowLength, rowCount)
    printStatus("Harvest finished.")
end

main()
