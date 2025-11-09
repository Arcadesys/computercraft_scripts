---@diagnostic disable: undefined-global, undefined-field
-- (The 'turtle' global is provided at runtime by ComputerCraft / CC:Tweaked.)
-- Configuration and state
local config = {
    branchLength = 16,     -- number of blocks each branch will extend
    branchSpacing = 3,     -- frequency (in main tunnel steps) for launching new branches
    branchWidth = 3,       -- branch tunnel width used when clearing side passages
    branchHeight = 3,      -- vertical clearance inside each branch tunnel
    torchInterval = 8,     -- steps between torch placements within branches
    torchDynamic = true,   -- when true, place torches based on distance since last torch (approximates light level)
    mainTorchSpacing = 12, -- steps between torches in the main tunnel (12 is safe for 1.18+ where mobs spawn at light level 0)
    branchTorchSpacing = 10, -- steps between torches in branches (slightly tighter by default)
    torchWallMode = "alternate", -- place torches on walls: "left", "right", or "alternate"
    -- Torch placement strategy:
    --   'behind'  = reliability-first: always place torches behind the turtle (turn-around), minimal movement.
    --   'wall'    = aesthetic-first: try wall torches using torchWallMode; will not fall back to floor.
    --   'auto'    = best-effort: try wall, then behind, then floor-down, then step-back.
    torchPlacementMode = "wall",
    retreatElevate = true, -- when true, turtle attempts to move up one block before retreating a branch to avoid mining floor torches
    refuelThreshold = 100, -- minimum fuel level the turtle should maintain
    replaceBlocks = true,  -- when false, do not place replacement blocks after digging
    replaceWithSlot = nil, -- set programmatically to slot with cobble
    chestSlot = nil,       -- slot containing chest for placeChest()
    verbose = false,       -- when true, print extra debug information
    trashSlot = nil,       -- slot containing wall patch blocks
    trashKeywords = { "trash", "cobble", "deepslate", "tuff", "basalt" },
    sealOpenEnds = true,  -- when true, seal open-air cavities discovered in branches (can block hallways)
    dumpRetreatMax = 128,  -- maximum blocks to retreat searching for an existing chest when inventory is full
}

local state = {
    x = 0, y = 0, z = 0, -- relative coordinates
    heading = 0,        -- 0=north,1=east,2=south,3=west
    startPosSaved = false,
    returnStack = {},   -- stack to save return path
    torchSide = "left", -- for alternating wall torch placement
}

-- Trash classification helpers are defined early so inventory logic can identify
-- filler blocks without risking valuables like lapis.
local TRASH_EXACT = {
    ["minecraft:cobblestone"] = true,
    ["minecraft:stone"] = true,
    ["minecraft:deepslate"] = true,
    -- Common replacement in 1.18+: treat as expendable
    ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:tuff"] = true,
    ["minecraft:basalt"] = true,
}

local TRASH_SUFFIXES = {
    ":stone",
    ":cobblestone",
    ":deepslate",
    -- handle variants like polished_deepslate, cobbled_deepslate, etc.
    "_deepslate",
    ":tuff",
    ":basalt",
    ":granite",
    ":diorite",
    ":andesite",
}

local function isLikelyValuable(name)
    if not name or name == "" then
        return false
    end

    return name:find("ore", 1, true)
        or name:find("ancient_debris", 1, true)
        or name:find("diamond", 1, true)
        or name:find("emerald", 1, true)
        or name:find("lapis", 1, true)
        or name:find("redstone", 1, true)
        or name:find("gold", 1, true)
end

local function isTrashBlock(name)
    name = (name or ""):lower()
    if name == "" then
        return false
    end

    if isLikelyValuable(name) then
        return false
    end

    if TRASH_EXACT[name] then
        return true
    end

    for _, suffix in ipairs(TRASH_SUFFIXES) do
        if name:sub(-#suffix) == suffix then
            return true
        end
    end

    for _, keyword in ipairs(config.trashKeywords or {}) do
        keyword = (keyword or ""):lower()
        if keyword ~= "" then
            if keyword:find(":", 1, true) then
                if name == keyword then
                    return true
                end
            else
                local keywordSuffix = ":" .. keyword
                if name:sub(-#keywordSuffix) == keywordSuffix then
                    return true
                end
            end
        end
    end

    return false
end

local function isTrashDetail(detail)
    if not detail or not detail.name then
        return false
    end
    return isTrashBlock(detail.name)
end

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
    -- CC:Tweaked exposes 'sleep'. Classic ComputerCraft may expose os.sleep.
    -- We guard accesses to avoid static analysis warnings when running outside CC.
    if type(os) == "table" and type(os.sleep) == "function" then
        os.sleep(seconds)
    elseif type(_G.sleep) == "function" then
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
    local fallbackSlot, fallbackDetail = nil, nil
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)
            local name = detail and detail.name or ""
            local lowerName = name:lower()
            if lowerName:find("cobble", 1, true) and isTrashDetail(detail) then
                return slot, detail
            end
            if not fallbackSlot and isTrashDetail(detail) then
                fallbackSlot = slot
                fallbackDetail = detail
            end
        end
    end
    return fallbackSlot, fallbackDetail
end

local function checkCobbleSlot()
    if not config.replaceBlocks then
        return false
    end

    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        local detail = turtle.getItemDetail(config.replaceWithSlot)
        if isTrashDetail(detail) then
            return true
        end
        config.replaceWithSlot = nil
    end

    local slot, detail = findCobbleSlot()
    if not slot then
        if waitForReplacement then
            slot = waitForReplacement()
            detail = slot and turtle.getItemDetail(slot) or nil
        else
            return false
        end
    end

    if slot and detail and isTrashDetail(detail) then
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
        local detail = turtle.getItemDetail(config.trashSlot)
        if isTrashDetail(detail) then
            return true
        end
        config.trashSlot = nil
    end

    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        local detail = turtle.getItemDetail(config.replaceWithSlot)
        if isTrashDetail(detail) then
            config.trashSlot = config.replaceWithSlot
            return true
        end
    end

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)
            if isTrashDetail(detail) then
                config.trashSlot = slot
                return true
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

local function getBlockForwardDetail()
    if not turtle.inspect then
        return nil, nil
    end

    local ok, detail = turtle.inspect()
    if ok and detail then
        return detail.name or "", detail
    end
    return nil, nil
end

local function formatBlockName(name)
    if not name or name == "" then
        return "unknown block"
    end
    local simple = name:gsub("^minecraft:", "")
    simple = simple:gsub(":", " ")
    return simple
end

-- Ensures the block below the turtle is replaced with the configured
-- replacement material when possible. Leaves bedrock or already-placed cobble
-- untouched. Returns true when the floor is in the desired state.
local digIfBlock -- forward declaration for block removal helper

-- Inventory helpers ---------------------------------------------------------

local function countEmptySlots()
    local empty = 0
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then empty = empty + 1 end
    end
    return empty
end

local function isInventoryFull()
    return countEmptySlots() == 0
end

local function isTorchDetail(detail)
    local nm = detail and detail.name or ""
    return nm:lower():find("torch", 1, true) ~= nil
end

-- Place (or reuse) a chest behind and dump items, keeping one stack of trash
-- and avoiding dropping the chest itself, the replacement block slot, and current selection.
local function performDumpingState()
    logBranch("Inventory full with valuable ahead: entering dumping state")

    -- Helper to identify a storage block
    local function isChestLike(detail)
        if not detail or not detail.name then return false end
        local n = detail.name:lower()
        return n:find("chest",1,true) or n:find("barrel",1,true)
    end

    -- First try to place a new chest behind (fast path)
    local placedChest = placeChestBehind()
    if placedChest then
        local ok, reason = depositToChest()
        if not ok then
            logBranch("Dumping failed after placing chest: %s", tostring(reason))
            return false, reason
        end
        logBranch("Dumping complete (new chest placed); resuming mining")
        return true
    end

    -- Fallback: search for existing chest by retreating backward up to dumpRetreatMax blocks
    logBranch("Chest placement failed; attempting retreat up to %d blocks to locate existing chest", config.dumpRetreatMax or 64)
    local stepsRetreated = 0
    turnAround() -- face backward direction
    local foundChest = false
    while stepsRetreated < (config.dumpRetreatMax or 64) do
        -- Inspect front for chest
        if turtle.inspect then
            local ok, detail = turtle.inspect()
            if ok and isChestLike(detail) then
                foundChest = true
                break
            end
        end
        if not moveForwardSafe() then
            logBranch("Retreat blocked at %d steps while searching for chest", stepsRetreated)
            break
        end
        stepsRetreated = stepsRetreated + 1
    end

    if not foundChest then
        -- turn back to original orientation
        turnAround()
        logBranch("No existing chest found within retreat limit; dumping aborted")
        return false, "no-existing-chest"
    end

    -- We are facing the chest. Perform deposit without placing another chest.
    local originalSelected = turtle.getSelectedSlot()
    local keptTrashSlot = nil
    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        local d = turtle.getItemDetail(config.replaceWithSlot)
        if isTrashDetail(d) then keptTrashSlot = config.replaceWithSlot end
    end
    if not keptTrashSlot then
        for i = 1,16 do
            local c = turtle.getItemCount(i)
            if c > 0 then
                local d = turtle.getItemDetail(i)
                if isTrashDetail(d) then keptTrashSlot = i break end
            end
        end
    end
    for i = 1,16 do
        local c = turtle.getItemCount(i)
        if c > 0 and i ~= keptTrashSlot and i ~= originalSelected and i ~= config.chestSlot then
            local detail = turtle.getItemDetail(i)
            if not isTorchDetail(detail) then
                turtle.select(i)
                turtle.drop() -- drop into chest in front
            end
        end
    end
    turtle.select(originalSelected)

    -- Return to original mining position
    -- Turn back to original heading (currently facing chest, which was backward direction)
    turnAround()
    while stepsRetreated > 0 do
        if not moveForwardSafe() then
            logBranch("Warning: could not advance forward to return after dumping (remaining=%d)", stepsRetreated)
            break
        end
        stepsRetreated = stepsRetreated - 1
    end
    logBranch("Dumping complete (existing chest); resuming mining")
    return true
end

-- Forward declare to allow referencing before definition
local depositToChest

local function ensureFloorReplaced()
    local nameBelow = getBlockBelowName()
    if nameBelow then
        if nameBelow:find("bedrock", 1, true) then
            return true
        end
        -- If a torch is already below the turtle we DO NOT want to dig it up
        -- for cobble replacement, otherwise we immediately delete freshly
        -- placed lighting. Torches occupy the block space and turtle.placeDown
        -- would fail, triggering a digDown fallback that destroys the torch.
        if nameBelow:find("torch", 1, true) then
            logBranch("Floor replacement skipped - torch present below")
            return true
        end
        if isTrashBlock(nameBelow) then
            return true
        end
    end

    local removedFloor = digIfBlock("down")

    if removedFloor and config.replaceBlocks then
        -- Step into the trench to reveal the block below before sealing the floor.
        if moveDownSafe() then
            digIfBlock("down")
            if not moveUpSafe() then
                error("Floor probe failed: unable to return to tunnel level")
            end
        else
            logBranch("Floor probe skipped - unable to step into cleared space")
        end
    end

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
        -- If we're about to dig forward and inventory is full while a valuable
        -- block is ahead, perform a dumping cycle first to avoid losing drops.
        if direction == "forward" and isInventoryFull then
            -- guard in case called outside CC where helpers may be nil
            if type(isInventoryFull) == "function" and isInventoryFull() then
                local nameAhead = select(1, getBlockForwardDetail())
                if nameAhead and nameAhead ~= "" and isLikelyValuable(nameAhead) then
                    -- Try elevated dumping so we don't disturb floor torches
                    local elevated = false
                    if config.retreatElevate and moveUpSafe then
                        elevated = moveUpSafe()
                    end
                    if performDumpingState then performDumpingState() end
                    if elevated and moveDownSafe then moveDownSafe() end
                end
            end
        end
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
    local attempts = 0
    while true do
        digIfBlock("forward")
        if turtle.forward() then
            return true
        end

        attempts = attempts + 1
        turtle.attack()
        delay(0.1)

        if attempts >= 20 then
            local blockName = nil
            if turtle.detect and turtle.detect() then
                blockName = select(1, getBlockForwardDetail())
            end
            local reason
            if blockName and blockName ~= "" then
                reason = "blocked by " .. formatBlockName(blockName)
            else
                reason = "blocked by unknown obstacle"
            end
            logBranch("Unable to move forward after %d attempts (%s)", attempts, reason)
            return false, reason
        end
    end
end

local function moveBackSafe()
    ensureFuel(1)
    if turtle.back() then
        return true
    end
    turnAround()
    local moved, reason = moveForwardSafe()
    turnAround()
    return moved, reason
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

local function patchSideWall(direction, height, options)
    height = math.max(1, height or 1)
    options = options or {}
    local sealOpen = options.sealOpen
    if sealOpen == nil then
        sealOpen = true
    end

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

        -- Never patch over a placed torch on the wall; keep lighting intact.
        if hasBlock and name ~= "" and name:lower():find("torch", 1, true) then
            return
        end

        if hasBlock and isTrashBlock(name) then
            return
        end

        local dug = digForwardForPatch()
        if dug then
            if not placeTrashForward() then
                logBranch("Wall patch missing blocks on %s side (level %d)", direction, level)
            end
        elseif not hasBlock then
            if sealOpen then
                if not placeTrashForward() then
                    logBranch("Wall patch missing blocks on %s side (level %d)", direction, level)
                end
            end
        else
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
-- This helper now only accepts items flagged as trash so ores and valuables stay untouched.
-- Returns the slot number selected (first acceptable trash block).
local function waitForReplacement()
    print("No replacement blocks found in turtle inventory.")
    print("Add placeable trash blocks (cobble/stone/etc.) to the turtle, then the script will continue.")
    print("To abort the program use Ctrl+T in the turtle terminal.")
    local keywordList = table.concat(config.trashKeywords or {}, ", ")
    if keywordList ~= "" then
        print("Trash keywords: " .. keywordList)
    end
    while true do
        -- print inventory snapshot (non-verbose because this is important)
        print("Inventory snapshot (* marks usable trash blocks):")
        local candidateSlot, candidateDetail = nil, nil
        for s = 1, 16 do
            local c = turtle.getItemCount(s)
            local d = turtle.getItemDetail(s)
            local marker = " "
            if c > 0 and isTrashDetail(d) then
                marker = "*"
                if not candidateSlot then
                    candidateSlot = s
                    candidateDetail = d
                end
            end
            if c > 0 then
                print(string.format("%s%2d: count=%d name=%s", marker, s, c, tostring(d and d.name)))
            else
                print(string.format(" %2d: empty", s))
            end
        end

        if candidateSlot then
            print(string.format(
                "Detected usable trash blocks in slot %d (%s). Resuming.",
                candidateSlot,
                tostring(candidateDetail and candidateDetail.name)
            ))
            return candidateSlot
        end

        -- nothing yet; wait and poll again
        print("Waiting for replacement blocks... (place trash items into the turtle)")
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

-- Torch helpers: non-destructive placement (no floor digging), with clear logs.
local function hasTorchBelow()
    if turtle.inspectDown then
        local ok, detail = turtle.inspectDown()
        if ok and detail then
            local nm = (detail.name or ""):lower()
            return nm:find("torch", 1, true) ~= nil, nm
        end
        return false, ok and "air" or "unknown"
    end
    return false, "no inspect capability"
end

local function tryPlaceTorchDownNoDig(contextLabel, sideLabel)
    local torchSlot = findTorchSlot()
    if not torchSlot then
        logBranch("Torch placement skipped (%s%s): no torches in inventory", contextLabel or "", sideLabel and ("/"..sideLabel) or "")
        return false
    end

    local already, nm = hasTorchBelow()
    if already then
        logBranch("Torch already present below (%s%s)", contextLabel or "", sideLabel and ("/"..sideLabel) or "")
        return true
    end

    local prev = turtle.getSelectedSlot()
    turtle.select(torchSlot)
    local placed = turtle.placeDown()
    if placed then
        logBranch("Placed torch on floor (%s%s)", contextLabel or "", sideLabel and ("/"..sideLabel) or "")
    else
        local reason = "unknown"
        if turtle.detectDown and turtle.inspectDown then
            local ok, detail = turtle.inspectDown()
            if ok and detail then
                local b = (detail.name or "unknown block"):lower()
                if b:find("torch", 1, true) then
                    reason = "torch detected after placement attempt"
                else
                    reason = "occupied by " .. b
                end
            elseif turtle.detectDown() then
                reason = "occupied (detectDown)"
            else
                reason = "no support block below"
            end
        end
        logBranch("Torch placement failed (%s%s): %s", contextLabel or "", sideLabel and ("/"..sideLabel) or "", reason)
    end
    turtle.select(prev)
    return placed
end

-- Step back one block, place a floor torch, then return forward.
-- Avoids creating holes: no digging of the floor is performed.
local function placeTorchBehindStepBack(contextLabel, sideLabel)
    local movedBack = moveBackSafe()
    if not movedBack then
        logBranch("Cannot step back to place torch (%s%s): path blocked", contextLabel or "", sideLabel and ("/"..sideLabel) or "")
        return false
    end

    local placed = tryPlaceTorchDownNoDig(contextLabel or "behind", sideLabel)

    local movedFwd = moveForwardSafe()
    if not movedFwd then
        logBranch("Warning: could not return to position after placing torch (%s%s)", contextLabel or "", sideLabel and ("/"..sideLabel) or "")
        -- We intentionally keep going without forcing recovery here.
    end
    return placed
end

-- Place a torch into the block space in front of the turtle (no digging).
-- This is the correct way to drop a floor torch: the front blockspace must be air
-- and there must be a solid top surface below that space. We log detailed reasons.
local function tryPlaceTorchForwardNoDig(contextLabel)
    local torchSlot = findTorchSlot()
    if not torchSlot then
        logBranch("Torch placement skipped (%s): no torches in inventory", contextLabel or "forward")
        return false
    end

    -- If something occupies the front space, we cannot place a torch there.
    if turtle.detect and turtle.detect() then
        local occ = "occupied"
        if turtle.inspect then
            local ok, detail = turtle.inspect()
            if ok and detail then occ = "occupied by " .. (detail.name or "unknown") end
        end
        logBranch("Torch placement failed (%s): %s", contextLabel or "forward", occ)
        return false
    end

    local prev = turtle.getSelectedSlot()
    turtle.select(torchSlot)
    local placed = turtle.place()
    if placed then
        logBranch("Placed torch (forward, %s)", contextLabel or "")
    else
        -- Likely no support below the front space (e.g., a drop or fluid)
        local reason = "unknown"
        if turtle.inspectDown then
            -- Peek the block below the front space by stepping forward one and back safely? Too invasive.
            -- Instead, give a generic message.
            reason = "no support or placement rule prevented torch"
        end
        logBranch("Torch placement failed (%s): %s", contextLabel or "forward", reason)
    end
    turtle.select(prev)
    return placed
end

-- Turn around, place a torch in the cell we just came from, and turn back.
-- This avoids moving and places torches on the floor correctly.
local function placeTorchBehindTurnAround(contextLabel)
    turnAround()
    local placed = tryPlaceTorchForwardNoDig(contextLabel or "behind")
    turnAround()
    return placed
end

-- Place a torch on the side wall without digging.
-- preferredSide: "left" | "right" | nil (nil uses config/state rules)
local function placeTorchOnWall(preferredSide, contextLabel)
    local torchSlot = findTorchSlot()
    if not torchSlot then
        logBranch("Torch placement skipped (%s): no torches in inventory", contextLabel or "wall")
        return false
    end

    -- Determine attempt order based on config and state toggle
    local order = {}
    local mode = (config.torchWallMode or "alternate"):lower()
    if preferredSide == "left" or preferredSide == "right" then
        order = { preferredSide, preferredSide == "left" and "right" or "left" }
    elseif mode == "left" then
        order = { "left", "right" }
    elseif mode == "right" then
        order = { "right", "left" }
    else
        local first = state.torchSide == "right" and "right" or "left"
        order = { first, first == "left" and "right" or "left" }
    end

    local function turnFor(side)
        if side == "left" then return turnLeftSafe, turnRightSafe end
        return turnRightSafe, turnLeftSafe
    end

    local prev = turtle.getSelectedSlot()
    turtle.select(torchSlot)

    local placed = false
    local reason = ""
    for _, side in ipairs(order) do
        local turn, undo = turnFor(side)
        turn()
        -- For wall torches, the front space must be air; the torch attaches to the block behind that air.
        local frontOccupied = (turtle.detect and turtle.detect()) or false
        if frontOccupied then
            -- The immediate front cell isn't air (likely the side column was not cleared). Try the other side.
            reason = "front space blocked on " .. side .. " side"
            undo()
        else
            if turtle.place() then
                logBranch("Placed wall torch (%s, %s side)", contextLabel or "wall", side)
                placed = true
                undo()
                if (config.torchWallMode or "alternate"):lower() == "alternate" then
                    state.torchSide = (side == "left") and "right" or "left"
                end
                break
            else
                -- Placement failed even though front was air: probably no solid support behind that air (or fluid present).
                local occ = "no support behind air"
                if turtle.inspect then
                    local ok, detail = turtle.inspect()
                    if ok and detail then occ = (detail.name or "unknown"):lower() end
                end
                logBranch("Wall torch placement failed (%s, %s side) - %s", contextLabel or "wall", side, occ)
                undo()
            end
        end
    end

    if not placed then
        logBranch("Wall torch placement gave up (%s): %s", contextLabel or "wall", reason ~= "" and reason or "both sides failed")
    end

    turtle.select(prev)
    return placed
end

-- Centralized torch placement router honoring config.torchPlacementMode.
-- Modes:
--   behind: place torch behind (turn-around). Simple and reliable.
--   wall:   place torch on a side wall, using config.torchWallMode for side selection.
--   auto:   try wall -> behind -> floor-down -> step-back.
local function placeTorchByMode(contextLabel, sideLabel)
    local mode = (config.torchPlacementMode or "behind"):lower()
    if mode == "behind" then
        -- Primary: behind. Single gentle fallback: floor-down (non-destructive) if behind fails.
        return placeTorchBehindTurnAround(contextLabel)
            or tryPlaceTorchDownNoDig(contextLabel, sideLabel)
    elseif mode == "wall" then
        -- Wall preferred; if both sides fail (e.g. narrow shaft) fall back
        -- to behind then floor so lighting still happens.
        return placeTorchOnWall(nil, contextLabel)
            or placeTorchBehindTurnAround(contextLabel)
            or tryPlaceTorchDownNoDig(contextLabel, sideLabel)
    else -- auto
        -- Best-effort chain
        return placeTorchOnWall(nil, contextLabel)
            or placeTorchBehindTurnAround(contextLabel)
            or tryPlaceTorchDownNoDig(contextLabel, sideLabel)
            or placeTorchBehindStepBack(contextLabel, sideLabel)
    end
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

    local function tryPlaceChest()
        if turtle.place() then
            return true
        end
        if turtle.detect() then
            if turtle.dig() then
                delay(0.05)
                return turtle.place()
            end
        end
        return false
    end

    local placed = tryPlaceChest()

    -- face original direction
    turnRightSafe()
    turnRightSafe()
    turtle.select(prev)

    if not placed then
        logBranch("Chest placement failed - clear the block behind the turtle")
        return false, "blocked"
    end

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
    -- Assumes there is or will be a chest behind via placeChestBehind().
    -- Here we only perform the deposit, keeping exactly one stack of trash.
    -- attempt to place a chest behind if not already present
    if not placeChestBehind() then
        return false, "no chest available to place"
    end

    -- face chest (turn around)
    turnRightSafe()
    turnRightSafe()

    local originalSelected = turtle.getSelectedSlot()
    local keptTrashSlot = nil

    -- First pass: decide which trash stack to keep (prefer current replaceWithSlot; else first trash stack found)
    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        local d = turtle.getItemDetail(config.replaceWithSlot)
        if isTrashDetail(d) then keptTrashSlot = config.replaceWithSlot end
    end
    if not keptTrashSlot then
        for i = 1, 16 do
            local c = turtle.getItemCount(i)
            if c > 0 then
                local d = turtle.getItemDetail(i)
                if isTrashDetail(d) then
                    keptTrashSlot = i
                    break
                end
            end
        end
    end

    -- Second pass: drop everything we can except chest item, kept trash stack, torches, and current selection.
    for i = 1, 16 do
        local count = turtle.getItemCount(i)
        if count > 0 then
            if i ~= config.chestSlot and i ~= originalSelected and i ~= keptTrashSlot then
                local detail = turtle.getItemDetail(i)
                local name = detail and detail.name or ""
                -- Skip torches so lighting supply remains
                if not isTorchDetail(detail) then
                    turtle.select(i)
                    turtle.drop()
                end
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
    -- Always maintain a three-wide hallway; ignore caller-provided width to protect layout symmetry.
    width = 3
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

    -- Clear ceiling up to the requested height.
    -- Behaviour:
    --  - Always climbs through open air for intermediate layers so the turtle
    --    reaches the intended roof height (not only when there is a block to dig).
    --  - On the top layer, it will attempt to place a replacement block even
    --    if the space was already open-air, ensuring a sealed ceiling to deter mobs.
    --  - Returns the turtle to its original vertical level before exiting.
    local function clearCeiling(stepState)
        stepState = stepState or { placedUp = false }
        local movedUp = 0
        local heightToClear = math.max(0, height - 1)

        for i = 1, heightToClear do
            local isTop = (i == heightToClear)

            -- Always clear the block directly above if present
            digIfBlock("up")

            if not isTop then
                -- For intermediate layers, climb even if it was already open air
                if moveUpSafe() then
                    movedUp = movedUp + 1
                else
                    -- If we cannot climb to the intended roof height, place a
                    -- safety ceiling at the current level (lower than planned)
                    -- to avoid leaving an open shaft, then stop.
                    vprint("mainTunnel: failed to move up at offset %d - placing safety ceiling at lower height", i)
                    if not stepState.placedUp then
                        placeReplacementUp()
                        stepState.placedUp = true
                    end
                    break
                end
            else
                -- Topmost layer: place a roof block even if nothing was dug (open air)
                if not stepState.placedUp then
                    local placed = placeReplacementUp()
                    stepState.placedUp = placed or stepState.placedUp
                    if placed then
                        vprint("mainTunnel: placed ceiling at top offset %d (handles open air)", i)
                    else
                        vprint("mainTunnel: failed to place ceiling at top offset %d (no blocks to place?)", i)
                    end
                else
                    vprint("mainTunnel: ceiling already placed earlier; skipping duplicate at top")
                end
            end

            delay(0.02)
        end

        -- Return to original level after any climbs
        if movedUp > 0 then
            vprint("mainTunnel: returning down %d levels after ceiling clear", movedUp)
            for j = 1, movedUp do
                if not moveDownSafe() then
                    vprint("mainTunnel: failed to move down after ceiling clearing (iteration=%d)", j)
                    break
                end
            end
        end

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
    local lastTorchAt = 0
    for step = 1, tunnelLength do
        vprint("mainTunnel: step %d/%d", step, tunnelLength)
        checkFuel()

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

        -- Dynamic / interval-based torch placement for the main tunnel.
        if config.torchDynamic then
            local spacing = config.mainTorchSpacing or config.torchInterval or 8
            local since = step - lastTorchAt
            if since >= spacing then
                local placed = placeTorchByMode("main step " .. step, "center")
                if placed then lastTorchAt = step end
            end
        else
            if config.torchInterval and config.torchInterval > 0 and (step % config.torchInterval) == 0 then
                local placed = placeTorchByMode("main interval step " .. step, "center")
                if placed then lastTorchAt = step end
            end
        end

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
                local realignToMain = side == "left" and turnRightSafe or turnLeftSafe

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

                if traversed <= 0 then
                    logBranch("%s branch retreat skipped (no forward progress)", side)
                else
                    -- Elevate retreat one block to avoid destroying any floor torches.
                    local elevated = false
                    -- Only attempt elevation if there might be headroom; if blocked, we just retreat at floor level.
                    if config.retreatElevate and moveUpSafe() then
                        elevated = true
                        vprint("%s branch: elevated retreat engaged (1 block up)", side)
                    end

                    local retreated = 0
                    for offset = 1, traversed do
                        local movedBack = moveBackSafe()
                        if not movedBack then
                            logBranch("%s branch retreat blocked at offset %d - continuing main tunnel", side, offset)
                            break
                        end
                        retreated = offset
                    end

                    -- Return to floor level after elevated retreat
                    if elevated then
                        if not moveDownSafe() then
                            logBranch("%s branch: warning - could not descend after elevated retreat", side)
                        end
                    end

                    if retreated > 0 then
                        logBranch("%s branch retreated %d step(s)", side, retreated)
                    end
                end

                realignToMain()
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

    -- Check one block higher than the maintained ceiling to surface hidden ores.
    if moveUpSafe() then
        digIfBlock("up")
        if not moveDownSafe() then
            error("Ceiling probe failed: unable to return to placement height")
        end
    else
        logBranch("Ceiling probe skipped - blocked above inspection point")
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
    local moved, reason = moveForwardSafe()
    if not moved then
        return false, reason or "blocked moving forward"
    end

    local topCleared = clearColumn(height, { skipCeiling = true })
    return true, topCleared
end

-- Attempts to drop a torch at the configured interval so finished branches
-- stay lit for future visits. Torches are placed on the floor under the turtle
-- after the slice has been cleared.
-- Branch periodic torch placement (now non-destructive).
local function placeBranchTorch(step, branchSide, stepsSinceLastTorch)
    if not config.torchDynamic then
        if not config.torchInterval or config.torchInterval <= 0 or (step % config.torchInterval) ~= 0 then
            return false
        end
    else
        local spacing = config.branchTorchSpacing or config.torchInterval or 8
        if stepsSinceLastTorch < spacing then
            return false
        end
    end

    local label = "branch step " .. step .. " (" .. (branchSide or "?") .. ")"
    return placeTorchByMode(label, branchSide)
end

-- branchTunnel creates a perpendicular mining branch. Each step clears the
-- block ahead, replaces the floor and ceiling, patches the exposed side walls
-- with trash blocks, and optionally drops a torch for lighting.
function branchTunnel(length, width, height, branchSide)
    length = length or config.branchLength or 8
    width = width or config.branchWidth or 1
    height = height or config.branchHeight or 2
    branchSide = (branchSide or "left"):lower()

    if length <= 0 then
        return true, 0
    end
    if height < 1 then
        height = 1
    end
    local stepsCompleted = 0

    logBranch("branchTunnel start: side=%s length=%d width=%d height=%d", branchSide, length, width, height)

    -- Place an intersection torch at the branch mouth (in the main tunnel cell)
    -- so the junction remains lit without being dug up during the retreat.
    do
        local hasTorchBelow = false
        if turtle.inspectDown then
            local ok, detail = turtle.inspectDown()
            if ok and detail then
                local nm = (detail.name or ""):lower()
                if nm:find("torch", 1, true) then
                    hasTorchBelow = true
                end
            end
        end
        if not hasTorchBelow then
            local torchSlot = findTorchSlot()
            if torchSlot then
                placeTorchByMode("branch intersection (" .. branchSide .. ")", branchSide)
            else
                logBranch("No torch available for %s branch intersection", branchSide)
            end
        end
    end

    local lastTorchAt = 0
    for step = 1, length do
        vprint("branchTunnel: step %d/%d", step, length)
        logBranch("branch %s: step %d/%d", branchSide, step, length)
        ensureFuel(1 + height)

        if turtle.detect and not turtle.detect() then
            -- Open air ahead likely means an existing hallway or cave; skip sealing by default
            if config.sealOpenEnds and stepsCompleted > 0 then
                logBranch("branch %s: open space ahead at step %d, sealing before retreat", branchSide, step)
                if not placeTrashForward() then
                    logBranch("branch %s: unable to seal open space - supply more trash blocks", branchSide)
                end
            else
                logBranch("branch %s: open space ahead at step %d, retreating without sealing", branchSide, step)
            end
            return false, "open space ahead", stepsCompleted
        end

        local advanced, advanceDetail = advanceBranchStep(height)
        if not advanced then
            local reason = string.format("%s at step %d", advanceDetail or "advance failure", step)
            logBranch("branchTunnel aborted (%s, steps=%d)", reason, stepsCompleted)
            return false, reason, stepsCompleted
        end

        local ceilingCleared = advanceDetail and true or false

        local leftOptions = nil
        local rightOptions = nil

        if step == 1 then
            leftOptions = { sealOpen = false }
            rightOptions = { sealOpen = false }
        end

        patchSideWall("left", height, leftOptions)
        patchSideWall("right", height, rightOptions)

        if ceilingCleared and config.replaceBlocks then
            local replaced, reason = replaceColumnCeiling(height)
            if not replaced then
                logBranch("Ceiling replacement skipped (%s)", reason or "unknown reason")
            end
        end

        local torchPlaced = placeBranchTorch(step, branchSide, step - lastTorchAt)
        if torchPlaced then
            lastTorchAt = step
        end
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

    -- place a starter chest before any digging happens
    local starterChestPlaced = placeChestBehind()
    if starterChestPlaced then
        logBranch("Starter chest placed behind the turtle")
    else
        logBranch("Starter chest not placed (no chest available or blocked space)")
    end

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
