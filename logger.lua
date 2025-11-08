-- Automated tree farming turtle for ComputerCraft.
-- Place the turtle facing the first tree trunk. The turtle will chop straight trees
-- (oak, spruce, birch, etc.), collect drops, and replant saplings.

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
    print(string.format("[Logger] %s", message))
end

local fuelKeywords = {"coal", "charcoal", "lava_bucket", "blaze_rod", "coke"}

local function isUnlimitedFuel()
    local level = turtle.getFuelLevel()
    return level == "unlimited" or level == math.huge
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
    printStatus("Low fuel. Add fuel to the turtle and press Enter.")
    read()
    turtle.select(initialSlot)
    return ensureFuel(stepsNeeded)
end

local function digForward()
    while turtle.detect() do
        turtle.dig()
        sleep(0.2)
    end
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
            sleep(0.4)
        end
    end
    return true
end

local function moveBackward()
    ensureFuel(1)
    if turtle.back() then
        return true
    end
    turtle.turnLeft()
    turtle.turnLeft()
    local moved = moveForward()
    turtle.turnLeft()
    turtle.turnLeft()
    return moved
end

local function selectSaplingSlot()
    local saplingKeywords = {"sapling", "propagule"}
    local initialSlot = turtle.getSelectedSlot()
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name then
            local lower = string.lower(detail.name)
            for _, keyword in ipairs(saplingKeywords) do
                if string.find(lower, keyword, 1, true) then
                    turtle.select(slot)
                    return initialSlot
                end
            end
        end
    end
    return nil
end

local function clearSurroundings()
    for direction = 1, 4 do
        local hasBlock, detail = turtle.inspect()
        if hasBlock and detail.name then
            local lower = string.lower(detail.name)
            if string.find(lower, "log", 1, true) or string.find(lower, "leaves", 1, true) then
                turtle.dig()
            end
        end
        turtle.turnRight()
    end
end

local function harvestTree()
    digForward()
    if not ensureFuel(4) then
        return
    end
    moveForward()
    local climbed = 0
    while true do
        clearSurroundings()
        local hasBlock, detail = turtle.inspectUp()
        if hasBlock and detail.name and string.find(string.lower(detail.name), "log", 1, true) then
            turtle.digUp()
            turtle.up()
            climbed = climbed + 1
        else
            break
        end
    end
    clearSurroundings()
    while climbed > 0 do
        turtle.down()
        climbed = climbed - 1
    end
    moveBackward()
    clearSurroundings()
    local previousSlot = selectSaplingSlot()
    if previousSlot then
        if not turtle.place() then
            printStatus("Unable to replant. Check for obstructions or missing water.")
        end
        turtle.select(previousSlot)
    else
        printStatus("No saplings available to replant this tree.")
    end
end

local function walkToNextTree(spacing)
    if spacing <= 0 then
        return
    end
    for _ = 1, spacing do
        moveForward()
    end
end

local function returnToStart(totalSpacing)
    for _ = 1, totalSpacing do
        moveBackward()
    end
end

local function main()
    printStatus("Configure logging run.")
    local treeCount = promptForNumber("Trees to harvest", 4)
    local spacingBetweenTrees = promptForNumber("Spacing between trees (blocks)", 4)

    for index = 1, treeCount do
        printStatus(string.format("Harvesting tree %d of %d", index, treeCount))
        harvestTree()
        if index < treeCount then
            walkToNextTree(spacingBetweenTrees)
        end
    end
    local totalSpacing = spacingBetweenTrees * (treeCount - 1)
    if totalSpacing > 0 then
        returnToStart(totalSpacing)
    end
    printStatus("Logging run finished. Turtle is back at the starting tree.")
end

main()
