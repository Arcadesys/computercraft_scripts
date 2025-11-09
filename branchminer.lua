-- Configuration and state
local config = {
    branchLength = 20,
    branchSpacing = 3,
    branchWidth = 3,
    branchHeight = 3,
    torchInterval = 8,
    refuelThreshold = 100,
    replaceBlocks = true,  -- when false, do not place replacement blocks after digging
    replaceWithSlot = nil, -- set programmatically to slot with cobble
    chestSlot = nil,       -- slot containing chest for placeChest()
    verbose = false,       -- when true, print extra debug information
    trashSlot = nil,       -- slot containing wall patch blocks
    trashKeywords = { "trash", "cobble", "deepslate", "tuff", "basalt" },
}

local state = {
    x = 0, y = 0, z = 0, -- relative coordinates
    heading = 0,        -- 0=north,1=east,2=south,3=west
    startPosSaved = false,
    returnStack = {},   -- stack to save return path
}

-- Verbose print helper
local function vprint(fmt, ...)
    if not config.verbose then return end
    if select('#', ...) > 0 then
        print(string.format(fmt, ...))
    else
        print(tostring(fmt))
    end
end

-- Portable short delay helper (ComputerCraft exposes either sleep or os.sleep).
local function delay(seconds)
    if os and os.sleep then
        os.sleep(seconds)
    elseif _G.sleep then
        _G.sleep(seconds)
    end
end

-- Simple logging helper so branch behaviour is visible even when verbose mode
-- is disabled. Prefix messages so they are easy to spot in the turtle terminal.
local function logBranch(message, ...)
    local prefix = "[BranchMiner] "
    if select('#', ...) > 0 then
        print(prefix .. string.format(message, ...))
    else
        print(prefix .. tostring(message))
    end
end

-- Helpers: movement with safety checks and state tracking
local function selectSlotWithItems(predicate)
    -- Selects the first slot with items that satisfy predicate(itemDetail).
    -- If no predicate supplied, selects the first non-empty slot.
    predicate = predicate or function() return true end
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            local detail = turtle.getItemDetail(i)
            if predicate(detail) then
                turtle.select(i)
                return i, detail
            end
        end
    end
    return nil
end

local waitForReplacement -- forward declaration so helpers can refer to it

local function getFuelLevelValue()
    local level = turtle.getFuelLevel()
    if level == "unlimited" then
        return math.huge
    end
    return tonumber(level) or 0
end

local function ensureFuel(requiredMoves)
    requiredMoves = requiredMoves or 1
    local desiredLevel = math.max(requiredMoves, config.refuelThreshold or requiredMoves)

    if getFuelLevelValue() >= desiredLevel then
        return true
    end

    local originalSlot = turtle.getSelectedSlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            if turtle.refuel and turtle.refuel(0) then
                turtle.refuel()
                if getFuelLevelValue() >= desiredLevel then
                    turtle.select(originalSlot)
                    return true
                end
            end
        end
    end

    turtle.select(originalSlot)

    if getFuelLevelValue() >= requiredMoves then
        return true
    end

    print("Out of fuel. Add fuel to the turtle and press Enter to continue.")
    read()
    return ensureFuel(requiredMoves)
end

local function findCobbleSlot()
    local fallbackSlot = nil
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)
            local name = detail and detail.name or ""
            local lowerName = name:lower()
            if lowerName:find("cobble", 1, true) then
                return slot, detail
            end
            if not fallbackSlot then
                fallbackSlot = slot
            end
        end
    end
    return fallbackSlot
end

local function checkCobbleSlot()
    if not config.replaceBlocks then
        return false
    end

    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        return true
    end

    local slot = findCobbleSlot()
    if not slot then
        if waitForReplacement then
            slot = waitForReplacement()
        else
            return false
        end
    end

    if slot then
        config.replaceWithSlot = slot
        return true
    end

    return false
end

local function placeReplacementGeneric(placeFunc, digDirection)
    if not config.replaceBlocks then
        return true
    end

    if not checkCobbleSlot() then
        return false
    end

    local originalSlot = turtle.getSelectedSlot()
    turtle.select(config.replaceWithSlot)

    local function attempt()
        return placeFunc()
    end

    local placed = attempt()
    if not placed and digDirection then
        if digDirection == "down" then
            turtle.digDown()
        elseif digDirection == "up" then
            turtle.digUp()
        elseif digDirection == "forward" then
            turtle.dig()
        end
        placed = attempt()
    end

    turtle.select(originalSlot)
    return placed
end

local function placeReplacementDown()
    return placeReplacementGeneric(turtle.placeDown, "down")
end

local function placeReplacementUp()
    return placeReplacementGeneric(turtle.placeUp, "up")
end

local function placeReplacementForward()
    return placeReplacementGeneric(turtle.place, "forward")
end

local function ensureTrashSlot()
    if config.trashSlot and turtle.getItemCount(config.trashSlot) > 0 then
        return true
    end

    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        config.trashSlot = config.replaceWithSlot
        return true
    end

    local keywords = config.trashKeywords or {}
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)
            local name = (detail and detail.name or ""):lower()
            for _, keyword in ipairs(keywords) do
                if keyword ~= "" and name:find(keyword, 1, true) then
                    config.trashSlot = slot
                    return true
                end
            end
        end
    end

    return false
end

local function placeTrashForward()
    if not ensureTrashSlot() then
        return false
    end

    local originalSlot = turtle.getSelectedSlot()
    turtle.select(config.trashSlot)

    local placed = turtle.place()
    if not placed and turtle.detect() then
        turtle.dig()
        placed = turtle.place()
    end

    turtle.select(originalSlot)
    return placed
end

local function isTrashBlock(name)
    name = (name or ""):lower()
    if name == "" then
        return false
    end

    for _, keyword in ipairs(config.trashKeywords or {}) do
        if keyword ~= "" and name:find(keyword, 1, true) then
            return true
        end
    end

    return false
end

-- Utility: returns the lowercase name of the block beneath the turtle or nil if
-- no block is present or the inspect call is unavailable.
local function getBlockBelowName()
    if not turtle.inspectDown then
        return nil
    end

    local ok, detail = turtle.inspectDown()
    if ok and detail then
        return (detail.name or ""):lower(), detail
    end
    return nil
end

-- Ensures the block below the turtle is replaced with the configured
-- replacement material when possible. Leaves bedrock or already-placed cobble
-- untouched. Returns true when the floor is in the desired state.
local digIfBlock -- forward declaration for block removal helper

local function ensureFloorReplaced()
    local nameBelow = getBlockBelowName()
    if nameBelow then
        if nameBelow:find("bedrock", 1, true) then
            return true
        end
        if isTrashBlock(nameBelow) then
            return true
        end
    end

    digIfBlock("down")

    if not config.replaceBlocks then
        return true
    end

    if not placeReplacementDown() then
        logBranch("Floor replacement skipped - supply more cobble")
        return false
    end

    return true
end

digIfBlock = function(direction)
    local detectFunc, digFunc, attackFunc
    if direction == "forward" then
        detectFunc = turtle.detect
        digFunc = turtle.dig
        attackFunc = turtle.attack
    elseif direction == "up" then
        detectFunc = turtle.detectUp
        digFunc = turtle.digUp
        attackFunc = turtle.attackUp
    elseif direction == "down" then
        detectFunc = turtle.detectDown
        digFunc = turtle.digDown
        attackFunc = turtle.attackDown
    else
        error("digIfBlock: invalid direction '" .. tostring(direction) .. "'")
    end

    if not detectFunc then
        return false
    end

    local removed = false
    local attempts = 0
    while detectFunc() do
        if digFunc() then
            removed = true
        else
            if attackFunc then attackFunc() end
            delay(0.1)
        end
        attempts = attempts + 1
        if attempts > 10 then
            break
        end
    end
    return removed
end

local function turnLeftSafe()
    turtle.turnLeft()
end

local function turnRightSafe()
    turtle.turnRight()
end

local function turnAround()
    turtle.turnLeft()
    turtle.turnLeft()
end

local function moveForwardSafe()
    ensureFuel(1)
    digIfBlock("forward")
    local attempts = 0
    while not turtle.forward() do
        attempts = attempts + 1
        if digIfBlock("forward") then
            -- keep trying after clearing
        else
            turtle.attack()
            delay(0.1)
        end
        if attempts > 20 then
            return false
        end
    end
    return true
end

local function moveBackSafe()
    ensureFuel(1)
    if turtle.back() then
        return true
    end
    turnAround()
    local moved = moveForwardSafe()
    turnAround()
    return moved
end

local function moveUpSafe()
    ensureFuel(1)
    local attempts = 0
    while not turtle.up() do
        attempts = attempts + 1
        if digIfBlock("up") then
            -- cleared obstacle above
        else
            turtle.attackUp()
            delay(0.1)
        end
        if attempts > 20 then
            return false
        end
    end
    return true
end

local function moveDownSafe()
    ensureFuel(1)
    local attempts = 0
    while not turtle.down() do
        attempts = attempts + 1
        if digIfBlock("down") then
            -- cleared obstacle below
        else
            turtle.attackDown()
            delay(0.1)
        end
        if attempts > 20 then
            return false
        end
    end
    return true
end

local function patchSideWall(direction, height)
    height = math.max(1, height or 1)

    local turn = direction == "right" and turnRightSafe or turnLeftSafe
    local undo = direction == "right" and turnLeftSafe or turnRightSafe

    local climbed = 0

    local function digForwardForPatch()
        if not turtle.detect then
            return false
        end

        local removed = false
        local attempts = 0
        while turtle.detect() do
            if turtle.dig() then
                removed = true
            else
                turtle.attack()
                delay(0.1)
            end
            attempts = attempts + 1
            if attempts > 10 then
                break
            end
        end
        return removed
    end

    local function processLevel(level)
        local hasBlock, detail = turtle.inspect()
        local name = detail and detail.name or ""

        if hasBlock and isTrashBlock(name) then
            return
        end

        local dug = digForwardForPatch()
        if dug or not hasBlock then
            if not placeTrashForward() then
                logBranch("Wall patch missing blocks on %s side (level %d)", direction, level)
            end
        end
    end

    turn()
    processLevel(0)

    for level = 1, height - 1 do
        if not moveUpSafe() then
            logBranch("Wall patch blocked at level %d on %s side", level, direction)
            break
        end
        climbed = climbed + 1
        processLevel(level)
    end

    while climbed > 0 do
        moveDownSafe()
        climbed = climbed - 1
    end

    undo()
end

if _ENV then
    _ENV.findCobbleSlot = findCobbleSlot
    _ENV.checkCobbleSlot = checkCobbleSlot
else
    _G.findCobbleSlot = findCobbleSlot
    _G.checkCobbleSlot = checkCobbleSlot
end

-- If no replacement block is found, pause and wait for the user to add blocks to the turtle.
-- This is a safety helper that prints the inventory and polls until at least one
-- slot contains items. Returns the slot number selected (first non-empty).
local function waitForReplacement()
    print("No replacement blocks found in turtle inventory.")
    print("Add placeable blocks (cobble/stone/etc.) to the turtle, then the script will continue.")
    print("To abort the program use Ctrl+T in the turtle terminal.")
    while true do
        -- print inventory snapshot (non-verbose because this is important)
        print("Inventory snapshot:")
        for s = 1, 16 do
            local c = turtle.getItemCount(s)
            local d = turtle.getItemDetail(s)
            if c > 0 then
                print(string.format("%2d: count=%d name=%s", s, c, tostring(d and d.name)))
            else
                print(string.format("%2d: empty", s))
            end
        end

        -- look for any non-empty slot and return it
        for i = 1, 16 do
            if turtle.getItemCount(i) > 0 then
                print(string.format("Detected items in slot %d, resuming.", i))
                return i
            end
        end

        -- nothing yet; wait and poll again
        print("Waiting for replacement blocks... (place items into the turtle)")
        delay(3)
    end
end

-- Find a slot containing torches. Returns slot or nil.
local function findTorchSlot()
    for i = 1, 16 do
        local count = turtle.getItemCount(i)
        if count > 0 then
            local detail = turtle.getItemDetail(i) or {}
            local name = (detail.name or ""):lower()
            if name:find("torch") then
                return i
            end
        end
    end
    return nil
end

-- Place a chest behind the turtle using config.chestSlot (auto-find if nil).
-- The turtle ends up facing the same direction as before.
-- Returns true on success.
local function placeChestBehind()
    -- find chest slot if not provided
    if not config.chestSlot or turtle.getItemCount(config.chestSlot) == 0 then
        -- try to find any chest-like item
        for i = 1, 16 do
            local count = turtle.getItemCount(i)
            if count > 0 then
                local detail = turtle.getItemDetail(i) or {}
                local name = (detail.name or ""):lower()
                if name:find("chest") or name:find("barrel") then
                    config.chestSlot = i
                    break
                end
            end
        end
    end

    if not config.chestSlot or turtle.getItemCount(config.chestSlot) == 0 then
        return false
    end

    local prev = turtle.getSelectedSlot()
    turtle.select(config.chestSlot)

    -- turn around, place chest forward (behind original), then turn back
    turnRightSafe()
    turnRightSafe()
    -- try to place; if blocked, attempt to dig once and place again
    if not turtle.place() then
        if turtle.detect() then
            turtle.dig()
            delay(0.05)
            turtle.place()
        end
    end
    -- face original direction
    turnRightSafe()
    turnRightSafe()
    turtle.select(prev)
    return true
end

-- Deposit items into a chest placed behind the turtle.
-- This will:
--  1) Place a chest behind (using placeChestBehind)
--  2) Turn to face the chest and drop all non-essential items into it
--  3) Return to original facing
-- It will skip depositing:
--   - the configured replacement slot (cobble)
--   - the chest slot itself
--   - the currently selected slot (to avoid surprising the caller)
local function depositToChest()
    -- attempt to place a chest behind
    if not placeChestBehind() then
        return false, "no chest available to place"
    end

    -- face chest (turn around)
    turnRightSafe()
    turnRightSafe()

    local originalSelected = turtle.getSelectedSlot()
    for i = 1, 16 do
        -- skip chest slot so we don't accidentally drop the chest item into itself
        if i ~= config.chestSlot and i ~= config.replaceWithSlot and i ~= originalSelected then
            local count = turtle.getItemCount(i)
            if count > 0 then
                turtle.select(i)
                -- drop everything in this slot into the chest in front
                -- if drop fails, continue to next slot
                turtle.drop()
            end
        end
    end

    -- restore selection and face original direction
    turtle.select(originalSelected)
    turnRightSafe()
    turnRightSafe()

    return true
end

-- Core behaviours
-- forward-declare branchTunnel so mainTunnel can call it (it's defined later)
local branchTunnel

local function mainTunnel(width, height)
    -- Create a straight main tunnel by repeatedly clearing a cross-section
    -- in front of the turtle and advancing. Default is a 3x3 tunnel (width=3,height=3).
    --
    -- width  - number of blocks across (must be odd; only centered odd widths are supported here)
    -- height - vertical clearance in blocks (e.g. 3 => turtle clears 2 blocks above itself)
    --
    -- This implementation is written to be cc:tweaked-friendly and does not rely on
    -- the other helper stubs in the file (it uses the turtle API directly).
    width = width or 3
    height = height or 3

    if (width % 2) ~= 1 then
        error("mainTunnel: width must be an odd number (centered tunnel).")
    end
    if height < 1 then
        error("mainTunnel: height must be >= 1.")
    end

    -- How many forward steps to take for the main tunnel
    local tunnelLength = config.branchLength or 16

    -- Small local safety helpers that attempt to dig/attack until movement succeeds.
    local function ensureClearForward()
        while turtle.detect() do
            turtle.dig()
            delay(0.05)
        end
    end

    local function safeForward()
        ensureClearForward()
        while not turtle.forward() do
            -- try to clear any mob blocking the way
            turtle.attack()
            delay(0.1)
        end
    end

    local function safeBack()
        while not turtle.back() do
            turtle.attack()
            delay(0.1)
        end
    end

    -- Dig repeated blocks above current position to reach the requested height
    -- Clear ceiling up to the requested height. This function now uses an
    -- internal counter to decide when to only dig and climb (intermediate
    -- layers) and when to dig and place a replacement block (topmost layer).
    -- It will return the turtle to its original vertical level before
    -- returning so callers don't need to manage vertical position.
    local function clearCeiling(stepState)
        stepState = stepState or { placedUp = false }
        local movedUp = 0
        local heightToClear = math.max(0, height - 1)

        for i = 1, heightToClear do
            -- If there's a block above, remove it. Use the loop index 'i' to
            -- decide whether this is an intermediate layer (we should dig and
            -- move up without placing) or the final/top layer (dig and place
            -- the replacement on the ceiling).
            if digIfBlock("up") then
                if i < heightToClear then
                    -- intermediate layer: dig and climb up to continue clearing
                    vprint("mainTunnel: ceiling offset %d/%d - digging and moving up (no place)", i, heightToClear)
                    if moveUpSafe() then
                        movedUp = movedUp + 1
                    else
                        -- failed to move up: try to restore ceiling if we haven't
                        -- placed it yet for this step to avoid leaving an open gap.
                        vprint("mainTunnel: failed to move up at offset %d - attempting to restore ceiling", i)
                        if not stepState.placedUp then
                            placeReplacementUp()
                            stepState.placedUp = true
                        end
                        break
                    end
                else
                    -- topmost layer: place a replacement block on the ceiling
                    if not stepState.placedUp then
                        placeReplacementUp()
                        stepState.placedUp = true
                        vprint("mainTunnel: placed replacement on ceiling at offset %d", i)
                    else
                        vprint("mainTunnel: skipped duplicate ceiling placement at offset %d", i)
                    end
                end
            else
                vprint("mainTunnel: nothing to dig on ceiling at offset %d", i)
            end
            delay(0.02)
        end

        -- If we climbed up during clearing, return back down to the original
        -- level so callers don't need to manage vertical position.
        if movedUp > 0 then
            vprint("mainTunnel: returning down %d levels after ceiling clear", movedUp)
            for j = 1, movedUp do
                if not moveDownSafe() then
                    vprint("mainTunnel: failed to move down after ceiling clearing (iteration=%d)", j)
                    break
                end
            end
        end

        -- expose movedUp count for callers/debugging if they inspect stepState
        stepState.movedUp = movedUp
    end

    -- Basic fuel check (works whether fuel is numeric or "unlimited")
    local function checkFuel()
        local level = turtle.getFuelLevel()
        if type(level) == "number" and level <= 0 then
            error("mainTunnel: out of fuel")
        end
    end

    -- Main tunnel loop: clear center column, clear left column, clear right column, advance.
    for step = 1, tunnelLength do
        vprint("mainTunnel: step %d/%d", step, tunnelLength)
        checkFuel()

        -- Ensure the forward space is clear (we'll step into it after clearing sides)
        vprint("mainTunnel: ensuring center forward space is clear")
        ensureClearForward()

        -- 3) Clear the left column one block to the left-forward, including its floor and ceiling.
        vprint("mainTunnel: moving into left column to clear")
        turnLeftSafe()
        safeForward()            -- move into left column
        -- replace floor and clear ceiling in the left column
        if digIfBlock("down") then
            placeReplacementDown()
            vprint("mainTunnel: replaced floor in left column at step %d", step)
        end
        vprint("mainTunnel: clearing left column ceiling")
        clearCeiling()          -- clear above that left column
        vprint("mainTunnel: returning to center from left column")
        safeBack()              -- return to center
        turnRightSafe()         -- face original forward

        -- 4) Clear the right column one block to the right-forward, including its floor and ceiling.
        vprint("mainTunnel: moving into right column to clear")
        turnRightSafe()
        safeForward()           -- move into right column
        -- replace floor and clear ceiling in the right column
        if digIfBlock("down") then
            placeReplacementDown()
            vprint("mainTunnel: replaced floor in right column at step %d", step)
        end
        vprint("mainTunnel: clearing right column ceiling")
        clearCeiling()          -- clear above that right column
        vprint("mainTunnel: returning to center from right column")
        safeBack()              -- return to center
        turnLeftSafe()          -- face original forward

        -- 5) Now that left and right forward columns are cleared, advance into the center forward cell
        vprint("mainTunnel: advancing into center forward cell to clear its ceiling")
        safeForward()

        -- Clear and replace the ceiling above the new center position
        vprint("mainTunnel: clearing center ceiling to height %d", height)
        clearCeiling()

        -- Replace the floor under the turtle to keep the walkway consistent
        if digIfBlock("down") then
            placeReplacementDown()
            vprint("mainTunnel: replaced floor under turtle at step %d", step)
        end

        vprint("mainTunnel: advanced to step %d", step)

        -- Launch perpendicular branches every `config.branchSpacing` steps.
        if config.branchSpacing and config.branchSpacing > 0 and (step % config.branchSpacing) == 0 then
            local branchLength = config.branchLength or 8
            local branchWidth = config.branchWidth or 1
            local branchHeight = config.branchHeight or 2

            vprint(
                "mainTunnel: launching branches at step %d (length=%d width=%d height=%d)",
                step,
                branchLength,
                branchWidth,
                branchHeight
            )

            local function runBranch(side)
                local turnToBranch = side == "left" and turnLeftSafe or turnRightSafe
                local turnReturn = side == "left" and turnRightSafe or turnLeftSafe
                local realign = side == "left" and turnLeftSafe or turnRightSafe

                logBranch("Launching %s branch at main step %d (length=%d width=%d height=%d)",
                    side, step, branchLength, branchWidth, branchHeight)

                turnToBranch()

                local success, status, detail, extra = pcall(branchTunnel, branchLength, branchWidth, branchHeight, side)
                local traversed = 0

                if not success then
                    vprint("mainTunnel: %s branch raised an error at step %d: %s", side, step, tostring(status))
                    logBranch("%s branch error: %s", side, tostring(status))
                    traversed = 0
                elseif status ~= true then
                    vprint("mainTunnel: %s branch aborted at step %d (%s)", side, step, tostring(detail))
                    logBranch("%s branch aborted early (%s)", side, tostring(detail))
                    traversed = tonumber(extra) or 0
                else
                    traversed = tonumber(detail) or branchLength
                    logBranch("%s branch completed (%d blocks mined)", side, traversed)
                end

                traversed = math.max(0, math.min(traversed or 0, branchLength))

                turnReturn(); turnReturn()
                if traversed <= 0 then
                    logBranch("%s branch return skipped (no forward progress)", side)
                end
                for offset = 1, traversed do
                    if not moveForwardSafe() then
                        vprint("mainTunnel: %s branch return path blocked at offset %d", side, offset)
                        logBranch("%s branch return blocked at offset %d", side, offset)
                        break
                    end
                end
                realign()
                logBranch("Realigned after %s branch", side)
            end

            runBranch("left")
            runBranch("right")
        end
    end

    return true
end

-- Branch helpers -----------------------------------------------------------

-- Clears the vertical column at the turtle's current position, replacing the
-- floor with cobble and opening the ceiling up to the requested height. When a
-- climb is required to reach higher blocks, the turtle returns to the original
-- level before exiting.
local function clearColumn(height, options)
    height = math.max(1, height or 1)
    options = options or {}
    local skipCeiling = options.skipCeiling

    ensureFloorReplaced()

    if height <= 1 then
        return false
    end

    local climbed = 0
    local topCleared = false

    for level = 1, height - 1 do
        local isTop = (level == height - 1)
        local removed = digIfBlock("up")

        if not isTop then
            if moveUpSafe() then
                climbed = climbed + 1
            else
                break
            end
        else
            if removed then
                topCleared = true
                if not skipCeiling then
                    placeReplacementUp()
                end
            end
        end
    end

    while climbed > 0 do
        if not moveDownSafe() then
            break
        end
        climbed = climbed - 1
    end

    return topCleared
end

local function replaceColumnCeiling(height)
    height = math.max(1, height or 1)

    if height < 2 or not config.replaceBlocks then
        return true
    end

    local climbLevels = math.max(0, height - 2)
    local climbed = 0

    for _ = 1, climbLevels do
        if not moveUpSafe() then
            while climbed > 0 do
                moveDownSafe()
                climbed = climbed - 1
            end
            return false, "blocked while climbing to ceiling"
        end
        climbed = climbed + 1
    end

    local placed = placeReplacementUp()

    while climbed > 0 do
        moveDownSafe()
        climbed = climbed - 1
    end

    if not placed then
        return false, "no replacement blocks available"
    end

    return true
end

-- Digs forward into the next branch cell, replaces the floor, and clears the
-- vertical space up to the requested height. Returns false if movement is
-- blocked so the caller can abort early.
local function advanceBranchStep(height)
    digIfBlock("forward")
    if not moveForwardSafe() then
        return false, "blocked moving forward"
    end

    local topCleared = clearColumn(height, { skipCeiling = true })
    return true, topCleared
end

-- Attempts to drop a torch at the configured interval so finished branches
-- stay lit for future visits. Torches are placed on the floor under the turtle
-- after the slice has been cleared.
local function placeBranchTorch(step, branchSide)
    if not config.torchInterval or config.torchInterval <= 0 then
        return
    end
    if step % config.torchInterval ~= 0 then
        return
    end

    local torchSlot = findTorchSlot()
    if not torchSlot then
        vprint("branchTunnel: torch requested at step %d but none available", step)
        logBranch("No torch available for step %d", step)
        return
    end

    local previous = turtle.getSelectedSlot()
    turtle.select(torchSlot)
    if turtle.placeDown() then
        logBranch("Placed torch at step %d (%s branch)", step, branchSide or "unknown")
    else
        vprint("branchTunnel: failed to place torch at step %d", step)
        logBranch("Torch placement failed at step %d (%s branch)", step, branchSide or "unknown")
    end
    turtle.select(previous)
end

-- branchTunnel creates a perpendicular mining branch. Each step clears the
-- block ahead, replaces the floor and ceiling, patches the exposed side walls
-- with trash blocks, and optionally drops a torch for lighting.
function branchTunnel(length, width, height, branchSide)
    length = length or config.branchLength or 8
    width = width or config.branchWidth or 1
    height = height or config.branchHeight or 2
    branchSide = branchSide or "left"

    if length <= 0 then
        return true, 0
    end
    if height < 1 then
        height = 1
    end
    local stepsCompleted = 0

    logBranch("branchTunnel start: side=%s length=%d width=%d height=%d", branchSide, length, width, height)

    for step = 1, length do
        vprint("branchTunnel: step %d/%d", step, length)
        logBranch("branch %s: step %d/%d", branchSide, step, length)
        ensureFuel(1 + height)

        local advanced, advanceDetail = advanceBranchStep(height)
        if not advanced then
            local reason = string.format("%s at step %d", advanceDetail or "advance failure", step)
            logBranch("branchTunnel aborted (%s, steps=%d)", reason, stepsCompleted)
            return false, reason, stepsCompleted
        end

        local ceilingCleared = advanceDetail and true or false

        -- Avoid patching the open hallway entrance on the first step so the
        -- turtle does not seal the main tunnel. The wall adjacent to the
        -- main tunnel depends on which side the branch exits from.
        local skipLeftPatch = (step == 1 and branchSide == "right")
        local skipRightPatch = (step == 1 and branchSide == "left")

        if not skipLeftPatch then
            patchSideWall("left", height)
        end
        if not skipRightPatch then
            patchSideWall("right", height)
        end

        if ceilingCleared and config.replaceBlocks then
            local replaced, reason = replaceColumnCeiling(height)
            if not replaced then
                logBranch("Ceiling replacement skipped (%s)", reason or "unknown reason")
            end
        end

        placeBranchTorch(step, branchSide)
        stepsCompleted = step
    end

    logBranch("branchTunnel complete: side=%s steps=%d", branchSide, stepsCompleted)
    return true, stepsCompleted
end

-- High level flow
local function run(...)
    local rawArgs = {...}
    -- Support flags like -v / --verbose in addition to positional args
    local args = {}
    for i = 1, #rawArgs do
        local a = rawArgs[i]
        if a == "-v" or a == "--verbose" then
            config.verbose = true
        elseif a == "-i" or a == "--inventory" then
            -- inventory dump request
            local function dumpInv()
                print("Inventory:")
                for s = 1, 16 do
                    local c = turtle.getItemCount(s)
                    local d = turtle.getItemDetail(s)
                    if c > 0 then
                        print(string.format("%2d: count=%d name=%s", s, c, tostring(d and d.name)))
                    else
                        print(string.format("%2d: empty", s))
                    end
                end
            end
            dumpInv()
            return
        else
            table.insert(args, a)
        end
    end

    -- CLI usage: branchminer.lua [branchLength] [branchSpacing] [branchHeight]
    if #args >= 1 then config.branchLength = tonumber(args[1]) or config.branchLength end
    if #args >= 2 then config.branchSpacing = tonumber(args[2]) or config.branchSpacing end
    if #args >= 3 then config.branchHeight = tonumber(args[3]) or config.branchHeight end

    print(string.format("Starting branchminer with length=%d spacing=%d height=%d",
        config.branchLength, config.branchSpacing, config.branchHeight))

    -- quick fuel check
    ensureFuel()

    -- run main tunnel (short 3-wide, height from config)
    print("Digging main tunnel...")
    local mt_ok, mt_err_or_res = pcall(mainTunnel, 3, config.branchHeight)
    if not mt_ok then
        -- mainTunnel threw an error; report and stop before running branches
        error("mainTunnel failed: " .. tostring(mt_err_or_res))
    end
    if mt_err_or_res ~= true then
        -- mainTunnel returned false or unexpected value; do not proceed
        error("mainTunnel did not complete successfully; aborting branch mining")
    end

    -- Branches are launched from mainTunnel at configured spacing.

    print("Branch mining complete.")
end

-- CLI entry: call run with passed args and print errors if they occur
local function main(...)
    local ok, err = pcall(run, ...)
    if not ok then
        print("ERROR: " .. tostring(err))
    end
end

-- Entry point: avoid using '...' at top-level (some loaders — e.g. pastebin.run —
-- execute the chunk without varargs). Prefer the global `arg` table if
-- available; otherwise call `main()` with no arguments.
local entry_args = {}
if type(arg) == "table" then
    for i = 1, #arg do entry_args[i] = arg[i] end
end

main(table.unpack(entry_args))
