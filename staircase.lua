-- staircase.lua
-- Usage: staircase.lua <width> <length>
--
-- Builds an ascending staircase in front of the turtle. The turtle should
-- start at the bottom-left corner of the desired staircase, facing the
-- forward direction of the staircase (the direction you want the stairs to go).
--
-- Arguments:
--   width  - number of blocks across for each step (columns)
--   length - number of steps (height)
--
-- Behavior summary:
--   For each step from 1..length:
--     - Place 'width' blocks along the forward direction (building the step surface)
--     - Move back to the left side, move forward one block (to shift), and move up one
--   This creates a staircase where each higher step is shifted forward by 1.
--
-- Requirements & assumptions:
--   - The turtle needs placeable blocks in its inventory. The script will use
--     the first non-empty slot it can place from; if a placement fails it scans
--     other slots.
--   - The turtle must have enough fuel for movement (or be in creative / have no fuel limits).
--   - The turtle will attempt to dig obstructing blocks in the way while moving.
--
-- Quick Lua / ComputerCraft tips (short):
--   - Arguments are available as `...` (varargs). Convert with `tonumber`.
--   - Use `turtle.select(n)` to change inventory slot, `turtle.placeDown()` to place below.
--   - Movement helpers below retry and dig obstructions automatically.

local args = {...}

local function usage()
  print("Usage: staircase.lua <width> <length>")
  print("Example: staircase.lua 3 10  -- build 10-step staircase, 3 blocks wide")
end

if #args < 2 then
  usage()
  return
end

local width = tonumber(args[1])
local length = tonumber(args[2])

if not width or not length or width < 1 or length < 1 then
  print("Invalid numeric arguments.")
  usage()
  return
end

-- Movement helpers: try to move, but dig obstructing blocks and retry.
local function tryForward()
  while not turtle.forward() do
    if turtle.detect() then
      -- try to dig blocking block and retry
      turtle.dig()
    else
      -- unknown reason, give a short pause then retry
      sleep(0.2)
    end
  end
end

local function tryBack()
  -- Use turtle.back() directly; if it fails try to clear the way by
  -- turning around, digging forward, and turning back.
  while not turtle.back() do
    turtle.turnLeft(); turtle.turnLeft()
    if turtle.detect() then
      turtle.dig()
    end
    turtle.turnLeft(); turtle.turnLeft()
    sleep(0.2)
  end
end

local function tryUp()
    local attempts = 0
    while not turtle.up() do
        attempts = attempts + 1
        -- If there's a block above, try to dig it. Otherwise try to attack mobs.
        if turtle.detectUp and turtle.detectUp() then
            turtle.digUp()
        else
            turtle.attackUp()
        end
        -- After a few attempts print a brief status so the user isn't left guessing
        if attempts % 10 == 0 then
            print(string.format("tryUp: still blocked after %d attempts; digging/attacking up and retrying...", attempts))
        end
        sleep(0.2)
    end
end

local function tryDown()
  while not turtle.down() do
    if turtle.detectDown then
      if turtle.detectDown() then turtle.digDown() end
    end
    sleep(0.2)
  end
end

-- Select any non-empty slot. Returns true when a slot is selected.
local function selectAnySlot()
  for i = 1,16 do
    if turtle.getItemCount(i) > 0 then
      turtle.select(i)
      return true
    end
  end
  return false
end

-- Try to place a block down from the current selected slot. If placement fails,
-- try other slots that contain items until one succeeds.
local function placeDownTrySlots()
  -- First quick attempt with current selection
  local ok, reason = turtle.placeDown()
  if ok then return true end

  -- Try other slots
  local current = turtle.getSelectedSlot()
  for i = 1,16 do
    if i ~= current and turtle.getItemCount(i) > 0 then
      turtle.select(i)
      ok, reason = turtle.placeDown()
      if ok then return true end
    end
  end

  -- Still failed
  print("Failed to place block down: " .. tostring(reason))
  return false
end

-- Start: ensure we have at least one slot with items
if not selectAnySlot() then
  print("No blocks found in inventory. Please fill the turtle with placeable blocks.")
  return
end

print(string.format("Building staircase: width=%d length=%d", width, length))

-- Build loop
for step = 1, length do
  -- Build one row of 'width' blocks. We place below our feet as we go.
  for col = 1, width do
    -- Place block under us
    if not placeDownTrySlots() then
      print(string.format("Stopping: out of placeable blocks at step %d col %d", step, col))
      return
    end

    -- Move forward unless this is the last column of the row
    if col < width then
      tryForward()
    end
  end

  -- If this was the last step, we're done.
  if step >= length then
    break
  end

  -- Move back to the leftmost block of the current row
  for i = 1, (width - 1) do
    tryBack()
  end

  -- Move forward once to shift start by one for the next step
  tryForward()

  -- Move up one to place the next step higher
  tryUp()
end

print("Staircase complete.")

-- End of script
-- Staircase builder for ComputerCraft turtles.
-- Usage: staircase <width> <length>
-- Width is how many blocks wide each step should be (perpendicular to your forward direction).
-- Length is how many steps to build upward.
-- Place the turtle at the bottom-left corner of where you want the stairs to start, facing up the staircase.

local args = {...}

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
    print(string.format("[Staircase] %s", message))
end

local function parseDimension(argValue, promptText, defaultValue)
    if argValue then
        local numeric = tonumber(argValue)
        if numeric and numeric > 0 then
            return math.floor(numeric)
        end
        printStatus(string.format("Invalid value '%s'.", tostring(argValue)))
    end
    return promptForNumber(promptText, defaultValue)
end

local function isUnlimitedFuel()
    local level = turtle.getFuelLevel()
    return level == "unlimited" or level == math.huge
end

local fuelKeywords = {
    "coal",
    "charcoal",
    "lava_bucket",
    "blaze_rod",
    "coke",
    "coal_block",
}

local function selectSlotMatching(predicate)
    local initialSlot = turtle.getSelectedSlot()
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if predicate(detail) then
            turtle.select(slot)
            return initialSlot, slot
        end
    end
    return nil, nil
end

local function isFuelItem(itemDetail)
    if not itemDetail or not itemDetail.name then
        return false
    end
    local lower = string.lower(itemDetail.name)
    for _, keyword in ipairs(fuelKeywords) do
        if string.find(lower, keyword, 1, true) then
            return true
        end
    end
    return false
end

local function refuelFromInventory()
    local previousSlot, fuelSlot = selectSlotMatching(isFuelItem)
    if not fuelSlot then
        return false
    end
    if turtle.refuel() then
        if previousSlot then
            turtle.select(previousSlot)
        end
        return true
    end
    if previousSlot then
        turtle.select(previousSlot)
    end
    return false
end

local function ensureFuel(requiredMoves)
    if isUnlimitedFuel() then
        return true
    end
    while turtle.getFuelLevel() < requiredMoves do
        if not refuelFromInventory() then
            printStatus("Add fuel and press Enter to continue.")
            read()
        end
    end
    return true
end

local buildKeywords = {
    "stone",
    "cobblestone",
    "plank",
    "brick",
    "deep_slate",
    "concrete",
}

local function selectBuildingBlock()
    local function matchesPreferred(detail)
        if not detail or not detail.name then
            return false
        end
        local lower = string.lower(detail.name)
        for _, keyword in ipairs(buildKeywords) do
            if string.find(lower, keyword, 1, true) then
                return true
            end
        end
        return false
    end

    local previousSlot, blockSlot = selectSlotMatching(matchesPreferred)
    if blockSlot then
        return previousSlot, blockSlot
    end

    local function anyItem(detail)
        return detail ~= nil
    end
    return selectSlotMatching(anyItem)
end

local function placeSupportBlock()
    if turtle.detectDown() then
        return true
    end
    while true do
        local previousSlot, blockSlot = selectBuildingBlock()
        if not blockSlot then
            printStatus("Out of building blocks. Load more and press Enter.")
            read()
        else
            if turtle.placeDown() then
                if previousSlot then
                    turtle.select(previousSlot)
                end
                return true
            else
                turtle.digDown()
                sleep(0.1)
            end
        end
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
            sleep(0.3)
        end
    end
    return true
end

local function moveUp()
    ensureFuel(1)
    local attempts = 0
    while not turtle.up() do
        attempts = attempts + 1
        if turtle.detectUp and turtle.detectUp() then
            -- try to remove a blocking block above
            turtle.digUp()
        else
            -- try to clear mobs
            turtle.attackUp()
        end

        -- After several attempts, print a helpful diagnostic so you can see what's blocking
        if attempts == 8 then
            print(string.format("moveUp: still blocked after %d attempts; digging up and retrying...", attempts))
        elseif attempts == 20 then
            print("moveUp: too many attempts, showing inventory snapshot and pausing. Press Enter in the turtle to continue after resolving the blockage.")
            for s = 1,16 do
                local c = turtle.getItemCount(s)
                local d = turtle.getItemDetail(s)
                if c > 0 then
                    print(string.format("%2d: count=%d name=%s", s, c, tostring(d and d.name)))
                else
                    print(string.format("%2d: empty", s))
                end
            end
            print("Press Enter to continue (or Ctrl+T to stop)")
            read()
        end

        if attempts > 10 then
            sleep(0.3)
        end
    end
    return true
end

local function moveRight()
    turtle.turnRight()
    moveForward()
    turtle.turnLeft()
end

local function moveLeft()
    turtle.turnLeft()
    moveForward()
    turtle.turnRight()
end

local function layStepRow(stepWidth)
    for column = 1, stepWidth do
        placeSupportBlock()
        if column < stepWidth then
            moveRight()
        end
    end
    for _ = 1, stepWidth - 1 do
        moveLeft()
    end
end

local function advanceToNextStep()
    -- Clear forward then move into the next column for the next step
    turtle.dig()
    moveForward()

    -- Try to ensure the space above is clear before and after placing the support block.
    -- Some servers/mods may have placement latency; dig any above-blocks first so moveUp
    -- isn't silently blocked by a misplaced block.
    if turtle.detectUp and turtle.detectUp() then
        turtle.digUp()
    end

    placeSupportBlock()

    -- Defensive second attempt to clear above (in case placement accidentally left a block)
    if turtle.detectUp and turtle.detectUp() then
        turtle.digUp()
        sleep(0.05)
    end

    moveUp()
end

local function buildStaircase(stepWidth, stepCount)
    printStatus(string.format("Building staircase width %d, length %d", stepWidth, stepCount))
    placeSupportBlock()
    for stepIndex = 1, stepCount do
        layStepRow(stepWidth)
        if stepIndex < stepCount then
            advanceToNextStep()
        end
    end
    printStatus("Staircase complete. Turtle is at the top step.")
end

local function estimateFuel(width, length)
    local movesPerStep = width * 2 + 3
    return movesPerStep * length + 8
end

local function main()
    local width = parseDimension(args[1], "Stair width", 2)
    local length = parseDimension(args[2], "Number of steps", 10)

    ensureFuel(estimateFuel(width, length))
    buildStaircase(width, length)
end

main()
