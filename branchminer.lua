-- Branch mining turtle script for ComputerCraft.
-- The turtle creates a straight tunnel and digs left/right branches at intervals.
-- Usage: place the turtle at the start of the tunnel, facing the direction you
--        want to dig. Ensure it has fuel, cobblestone, and inventory space.

local function promptForNumber(promptText, defaultValue)
    write(string.format("%s [%d]: ", promptText, defaultValue))
    local userInput = read()
    local numericValue = tonumber(userInput)
    if numericValue and numericValue > 0 then
        return math.floor(numericValue)
    end
    return defaultValue
end

local function printStatus(message)
    print(string.format("[BranchMiner] %s", message))
end

local function isUnlimitedFuel()
    local currentFuel = turtle.getFuelLevel()
    return currentFuel == "unlimited" or currentFuel == math.huge
end

local fuelKeywords = {
    "coal",
    "charcoal",
    "lava_bucket",
    "blaze_rod",
    "coal_block",
    "coke",
}

local function isFuelItem(itemDetail)
    if not itemDetail or not itemDetail.name then
        return false
    end
    local lowerName = string.lower(itemDetail.name)
    for _, keyword in ipairs(fuelKeywords) do
        if string.find(lowerName, keyword, 1, true) then
            return true
        end
    end
    return false
end

local function selectSlotMatching(predicate)
    local previousSlot = turtle.getSelectedSlot()
    for slotIndex = 1, 16 do
        local itemDetail = turtle.getItemDetail(slotIndex)
        if predicate(itemDetail) then
            turtle.select(slotIndex)
            return previousSlot
        end
    end
    return nil
end

local function selectFuelSlot()
    local originalSlot = selectSlotMatching(isFuelItem)
    if originalSlot then
        return originalSlot, turtle.getSelectedSlot()
    end
    return nil, nil
end

local function refuelFromInventory()
    if isUnlimitedFuel() then
        return true
    end
    local previousSlot, fuelSlot = selectFuelSlot()
    if not fuelSlot then
        return false
    end
    local refuelSucceeded = turtle.refuel()
    turtle.select(previousSlot or turtle.getSelectedSlot())
    return refuelSucceeded
end

local function ensureFuel(requiredMoves)
    if isUnlimitedFuel() then
        return true
    end
    local availableFuel = turtle.getFuelLevel()
    if availableFuel >= requiredMoves then
        return true
    end
    if refuelFromInventory() then
        availableFuel = turtle.getFuelLevel()
        if availableFuel >= requiredMoves then
            return true
        end
    end
    printStatus("Insufficient fuel. Add fuel and press Enter to retry.")
    read()
    if refuelFromInventory() then
        availableFuel = turtle.getFuelLevel()
        if availableFuel >= requiredMoves then
            return true
        end
    end
    return false
end

local function isOreBlock(blockData)
    if not blockData then
        return false
    end
    if blockData.tags then
        for tagName in pairs(blockData.tags) do
            if string.find(tagName, "ore", 1, true) then
                return true
            end
        end
    end
    local blockName = string.lower(blockData.name or "")
    return string.find(blockName, "ore", 1, true) ~= nil
end

local function selectCobblestoneSlot()
    local function isCobblestone(itemDetail)
        if not itemDetail or not itemDetail.name then
            return false
        end
        return string.find(string.lower(itemDetail.name), "cobblestone", 1, true) ~= nil
    end
    local previousSlot = selectSlotMatching(isCobblestone)
    if previousSlot then
        return previousSlot, turtle.getSelectedSlot()
    end
    return nil, nil
end

local function placeCobblestone(placeFunction)
    local previousSlot, cobbleSlot = selectCobblestoneSlot()
    if not cobbleSlot then
        return false
    end
    local placed = placeFunction()
    turtle.select(previousSlot or turtle.getSelectedSlot())
    return placed
end

local function clearBlock(inspectFunction, digFunction, placeFunction)
    local hasBlock, blockData = inspectFunction()
    local targetWasOre = isOreBlock(blockData)
    local targetPresent = hasBlock

    local digAttempts = 0
    while hasBlock do
        if digFunction() then
            sleep(0.1)
        else
            turtle.attack()
            sleep(0.2)
        end
        digAttempts = digAttempts + 1
        if digAttempts > 10 then
            sleep(0.4)
        end
        hasBlock, blockData = inspectFunction()
    end

    if targetWasOre and placeFunction then
        placeCobblestone(placeFunction)
        refuelFromInventory()
    end

    return targetPresent, targetWasOre
end

local function clearForward()
    return clearBlock(turtle.inspect, turtle.dig, turtle.place)
end

local function clearUp()
    return clearBlock(turtle.inspectUp, turtle.digUp, turtle.placeUp)
end

local function clearDown()
    return clearBlock(turtle.inspectDown, turtle.digDown, turtle.placeDown)
end

local function moveForward()
    if not ensureFuel(1) then
        error("Unable to continue without additional fuel.")
    end
    local attempt = 0
    while not turtle.forward() do
        attempt = attempt + 1
        if turtle.detect() then
            clearForward()
        else
            turtle.attack()
            sleep(0.2)
        end
        if attempt > 20 then
            printStatus("Blocked ahead. Waiting briefly before retrying...")
            sleep(1)
        end
    end
    clearUp()
    return true
end

local function scanForSideOres()
    turtle.turnLeft()
    local hasBlock, blockData = turtle.inspect()
    if hasBlock and isOreBlock(blockData) then
        clearForward()
    end
    turtle.turnRight()
    turtle.turnRight()
    hasBlock, blockData = turtle.inspect()
    if hasBlock and isOreBlock(blockData) then
        clearForward()
    end
    turtle.turnLeft()
end

local function digFloorIfNeeded()
    local hasBlock, blockData = turtle.inspectDown()
    if not hasBlock then
        return
    end
    if isOreBlock(blockData) then
        clearDown()
        placeCobblestone(turtle.placeDown)
    end
end

local function turnAround()
    turtle.turnLeft()
    turtle.turnLeft()
end

local function mineBranch(direction, branchLength)
    if branchLength <= 0 then
        return
    end

    if direction == "left" then
        turtle.turnLeft()
    else
        turtle.turnRight()
    end

    local stepsAdvanced = 0
    for step = 1, branchLength do
        if not ensureFuel(1) then
            printStatus("Branch halted due to low fuel.")
            break
        end

        if not turtle.detect() then
            printStatus(string.format("Open space detected %s at %d blocks. Returning to tunnel.", direction, step))
            break
        end

        clearForward()
        moveForward()
        stepsAdvanced = stepsAdvanced + 1
        clearUp()
        scanForSideOres()
        digFloorIfNeeded()
    end

    turnAround()
    for _ = 1, stepsAdvanced do
        moveForward()
    end

    if direction == "left" then
        turtle.turnLeft()
    else
        turtle.turnRight()
    end
end

local function mineTunnel(mainLength, branchLength, branchSpacing)
    printStatus("Starting branch mining run.")
    for distance = 1, mainLength do
        clearForward()
        moveForward()
        clearUp()
        scanForSideOres()
        digFloorIfNeeded()

        if branchSpacing > 0 and branchLength > 0 and distance % branchSpacing == 0 then
            mineBranch("left", branchLength)
            mineBranch("right", branchLength)
        end
    end
    printStatus("Main tunnel complete. Returning to start.")
    turnAround()
    for _ = 1, mainLength do
        moveForward()
    end
    turnAround()
    printStatus("Run finished. You are back at the starting position.")
end

local function main()
    printStatus("Configure your branch mining run.")
    local tunnelLength = promptForNumber("Main tunnel length (blocks)", 64)
    local branchLength = promptForNumber("Branch length (blocks)", 16)
    local branchSpacing = promptForNumber("Branch spacing (blocks)", 8)

    if not ensureFuel(tunnelLength + branchLength * 2) then
        error("Unable to start without sufficient fuel.")
    end

    mineTunnel(tunnelLength, branchLength, branchSpacing)
end

main()