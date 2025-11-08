-- Configuration and state
local config = {
    branchLength = 20,
    branchSpacing = 3,
    branchHeight = 3,
    torchInterval = 8,
    refuelThreshold = 100,
    replaceWithSlot = nil, -- set programmatically to slot with cobble
    chestSlot = nil,       -- slot containing chest for placeChest()
    verbose = false,       -- when true, print extra debug information
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

local function ensureFuel()
    -- Ensure we have at least config.refuelThreshold fuel or attempt to refuel.
    local level = turtle.getFuelLevel()
    vprint("ensureFuel: current fuel level = %s", tostring(level))
    if level == "unlimited" then return true end
    if type(level) == "number" and level >= (config.refuelThreshold or 0) then return true end

    local before = turtle.getFuelLevel()
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            turtle.select(i)
            -- try to consume one item as fuel; refuel returns true if successful
            vprint("ensureFuel: trying slot %d (count=%d)", i, turtle.getItemCount(i))
            if turtle.refuel(1) then
                vprint("ensureFuel: refuel succeeded using slot %d", i)
                return true
            end
        end
    end

    if type(before) == "number" and turtle.getFuelLevel() > before then
        vprint("ensureFuel: fuel increased after attempts")
        return true
    end

    error("ensureFuel: unable to refuel (set config.refuelThreshold or add fuel to inventory)")
end

local function moveForwardSafe(retries)
    -- Moves forward, digging/attacking obstructions. Returns true on success, false otherwise.
    retries = retries or 12
    for i = 1, retries do
        if not turtle.detect() then
            if turtle.forward() then return true end
        else
            turtle.dig()
        end
        -- try to clear mobs that may block movement
        turtle.attack()
        os.sleep(0.08)
    end
    return false
end

local function moveUpSafe(retries)
    retries = retries or 8
    for i = 1, retries do
        if not turtle.detectUp() then
            if turtle.up() then return true end
        else
            turtle.digUp()
        end
        turtle.attackUp()
        os.sleep(0.06)
    end
    return false
end

local function moveDownSafe(retries)
    retries = retries or 8
    for i = 1, retries do
        if not turtle.detectDown() then
            if turtle.down() then return true end
        else
            turtle.digDown()
        end
        os.sleep(0.06)
    end
    return false
end

local function turnLeftSafe()
    turtle.turnLeft()
    state.heading = (state.heading + 3) % 4
end

local function turnRightSafe()
    turtle.turnRight()
    state.heading = (state.heading + 1) % 4
end

-- Block helpers

-- Attempts to dig in the given direction ("forward", "up", "down").
-- Returns true if a block was removed (or an action was taken), false otherwise.
local function digIfBlock(direction)
    if direction == "forward" then
        if turtle.detect() then
            -- try to remove block; try multiple times to handle protected/laggy servers
            if turtle.dig() then return true end
            -- fight mobs if they block the dig
            turtle.attack()
            os.sleep(0.05)
            return turtle.dig()
        end
        return false
    elseif direction == "up" then
        if turtle.detectUp() then
            if turtle.digUp() then return true end
            turtle.attackUp()
            os.sleep(0.05)
            return turtle.digUp()
        end
        return false
    elseif direction == "down" then
        if turtle.detectDown() then
            if turtle.digDown() then return true end
            os.sleep(0.05)
            return turtle.digDown()
        end
        return false
    else
        error("digIfBlock: unknown direction '" .. tostring(direction) .. "'")
    end
end

-- Place a replacement block under the turtle using config.replaceWithSlot (auto-discover if nil).
-- Returns true if placement succeeded.
local function placeReplacementDown()
    -- ensure we have a slot reserved for replacement blocks
    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        turtle.select(config.replaceWithSlot)
        vprint("placeReplacementDown: placing from configured slot %d", config.replaceWithSlot)
        return turtle.placeDown()
    end

    local slot = findCobbleSlot()
    if not slot then
        vprint("placeReplacementDown: no replacement slot available")
        return false
    end
    config.replaceWithSlot = slot
    turtle.select(slot)
    vprint("placeReplacementDown: placing from discovered slot %d", slot)
    return turtle.placeDown()
end

-- Place a replacement block above the turtle
local function placeReplacementUp()
    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        turtle.select(config.replaceWithSlot)
        vprint("placeReplacementUp: placing from configured slot %d", config.replaceWithSlot)
        return turtle.placeUp()
    end

    local slot = findCobbleSlot()
    if not slot then
        vprint("placeReplacementUp: no replacement slot available")
        return false
    end
    config.replaceWithSlot = slot
    turtle.select(slot)
    vprint("placeReplacementUp: placing from discovered slot %d", slot)
    return turtle.placeUp()
end

-- Place a replacement block in front of the turtle
local function placeReplacementForward()
    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        turtle.select(config.replaceWithSlot)
        vprint("placeReplacementForward: placing from configured slot %d", config.replaceWithSlot)
        return turtle.place()
    end

    local slot = findCobbleSlot()
    if not slot then
        vprint("placeReplacementForward: no replacement slot available")
        return false
    end
    config.replaceWithSlot = slot
    turtle.select(slot)
    vprint("placeReplacementForward: placing from discovered slot %d", slot)
    return turtle.place()
end

-- Inventory / chest helpers

-- Find a slot containing cobblestone (or similar replacement block).
-- Preference: use config.replaceWithSlot if valid.
local function findCobbleSlot()
    -- respect an already-configured slot if it still contains items
    if config.replaceWithSlot and turtle.getItemCount(config.replaceWithSlot) > 0 then
        return config.replaceWithSlot
    end

    for i = 1, 16 do
        local count = turtle.getItemCount(i)
        if count > 0 then
            local detail = turtle.getItemDetail(i) or {}
            local name = (detail.name or ""):lower()
            -- match common cobble-like names; adjust if your modpack uses different ids
            -- include 'cobb' to catch 'cobbled_deepslate' and similar ids
            if name:find("cobb") or name:find("cobblestone") or name:find("cobble") or (name:find("stone") and name:find("polished") == nil) then
                vprint("findCobbleSlot: found candidate slot %d -> %s (count=%d)", i, tostring(detail.name), count)
                return i
            end
        end
    end
    vprint("findCobbleSlot: no cobble-like slot found — falling back to first non-empty slot")
    -- fallback: return first non-empty slot to allow placement of any block
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            vprint("findCobbleSlot: fallback using slot %d", i)
            return i
        end
    end
    return nil
end

-- Backwards-compatible wrapper (some older code/messages reference checkCobbleSlot)
local function checkCobbleSlot()
    return findCobbleSlot()
end

-- Expose helpers as globals for compatibility with older pastebin versions
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
        sleep(3)
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
            os.sleep(0.05)
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
    local tunnelLength = config.branchLength or 20

    -- Small local safety helpers that attempt to dig/attack until movement succeeds.
    local function ensureClearForward()
        while turtle.detect() do
            turtle.dig()
            os.sleep(0.05)
        end
    end

    local function safeForward()
        ensureClearForward()
        while not turtle.forward() do
            -- try to clear any mob blocking the way
            turtle.attack()
            os.sleep(0.1)
        end
    end

    local function safeBack()
        while not turtle.back() do
            turtle.attack()
            os.sleep(0.1)
        end
    end

    -- Dig repeated blocks above current position to reach the requested height
    local function clearCeiling()
        for i = 1, math.max(0, height - 1) do
            -- use robust dig helper and place replacement on the ceiling
            if digIfBlock("up") then
                placeReplacementUp()
                vprint("mainTunnel: placed replacement on ceiling at offset %d", i)
            else
                vprint("mainTunnel: nothing to dig on ceiling at offset %d", i)
            end
            -- small pause to let server update
            os.sleep(0.02)
        end
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
    end

    -- finished main tunnel
end

local function branchTunnel(length, width)
    -- Default values if not specified
    length = length or config.branchLength
    width = width or 3

    -- Check for valid width (must be odd for centered tunnel)
    if (width % 2) ~= 1 then
        error("branchTunnel: width must be an odd number (centered tunnel).")
    end

    -- Helper function to dig and replace a block
    local function digAndReplace(digFunc, placeFunc)
        -- Prefer using the robust digIfBlock helper for the three primary dig
        -- directions so we get retries, attacks, and consistent behavior.
        local ok = false

        if digFunc == turtle.dig then
            ok = digIfBlock("forward")
        elseif digFunc == turtle.digUp then
            ok = digIfBlock("up")
        elseif digFunc == turtle.digDown then
            ok = digIfBlock("down")
        elseif type(digFunc) == "function" then
            local success, res = pcall(digFunc)
            if not success then
                vprint("digAndReplace: digFunc raised error: %s", tostring(res))
                ok = false
            else
                ok = res
            end
        else
            vprint("digAndReplace: no dig function provided")
        end

        if ok then
            vprint("digAndReplace: removed block")
            if type(placeFunc) == "function" then
                local psuccess, pres = pcall(placeFunc)
                if not psuccess then
                    vprint("digAndReplace: placeFunc raised error: %s", tostring(pres))
                else
                    vprint("digAndReplace: placement result = %s", tostring(pres))
                end
            end
        else
            vprint("digAndReplace: nothing to remove or dig failed")
        end
    end

    -- Main branch tunnel loop
    for step = 1, length do
        -- Check fuel level
        vprint("branchTunnel: starting step %d/%d", step, length)
        ensureFuel()

        -- Clear and replace the floor
        digAndReplace(turtle.digDown, placeReplacementDown)

        -- Clear and replace the ceiling
        digAndReplace(turtle.digUp, placeReplacementUp)

        -- Clear forward space
        digAndReplace(turtle.dig, nil)  -- Don't replace forward blocks

        -- Place torch if needed
        if step % config.torchInterval == 0 then
            local torchSlot = findTorchSlot()
            if torchSlot then
                vprint("branchTunnel: placing torch from slot %d", torchSlot)
                turtle.select(torchSlot)
                turtle.placeDown()
            else
                vprint("branchTunnel: no torch found for placement at step %d", step)
            end
        end

        -- Move forward safely
        vprint("branchTunnel: moving forward from step %d", step)
        if not moveForwardSafe() then
            vprint("branchTunnel: moveForwardSafe failed at step %d", step)
            return false
        end

        -- Handle side blocks for wider tunnels
        if width > 1 then
            local half = (width - 1) / 2

            -- helper to move back safely (turn around, forward, turn back)
            local function moveBackSafe()
                turnRightSafe(); turnRightSafe()
                local ok = moveForwardSafe()
                turnRightSafe(); turnRightSafe()
                return ok
            end

            -- Clear left side columns by stepping into each side column, clearing
            -- the column (floor/ceiling) and the wall block that faces the main tunnel.
            turtle.turnLeft()
            for i = 1, half do
                -- step into side column
                if not moveForwardSafe() then return false end

                -- face original forward to clear the wall at this lateral offset
                turnRightSafe()
                digAndReplace(turtle.dig, placeReplacementForward)
                digAndReplace(turtle.digUp, placeReplacementUp)
                digAndReplace(turtle.digDown, placeReplacementDown)
                -- face lateral direction again to continue stepping outwards
                turnLeftSafe()
            end

            -- return to center column
            for i = 1, half do
                if not moveBackSafe() then return false end
            end
            -- now face original forward orientation
            turnRightSafe()

            -- Clear right side columns (mirror of left)
            turtle.turnRight()
            for i = 1, half do
                if not moveForwardSafe() then return false end

                -- face original forward to clear the wall at this lateral offset
                turnLeftSafe()
                digAndReplace(turtle.dig, placeReplacementForward)
                digAndReplace(turtle.digUp, placeReplacementUp)
                digAndReplace(turtle.digDown, placeReplacementDown)
                -- face lateral direction again
                turnRightSafe()
            end

            -- return to center for right side
            for i = 1, half do
                if not moveBackSafe() then return false end
            end
            -- restore original forward orientation
            turnLeftSafe()
        end
    end

    return true
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
    mainTunnel(3, config.branchHeight)

    -- run a single branch run for now (you can extend to do multiple branches later)
    print("Digging branch tunnel...")
    local ok = branchTunnel(config.branchLength, 3)
    if not ok then
        error("branchTunnel failed or was interrupted")
    end

    print("Branch mining complete.")
end

-- CLI entry: call run with passed args and print errors if they occur
local function main(...)
    local ok, err = pcall(run, ...)
    if not ok then
        print("ERROR: " .. tostring(err))
    end
end

main(...)