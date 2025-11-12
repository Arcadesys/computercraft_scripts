-- factorybuilder.lua  ----------------------------------------------------
-- Modular Factory Cell Builder (State Machine Version)
--
-- This refactors the original monolithic build loop into a CLEAR, EXTENSIBLE
-- STATE MACHINE. Each state lives in the `states` table and is invoked once
-- per tick (loop iteration) via a central dispatcher.
--
-- ADDING / MODIFYING STATES
-- 1. Define a new function: `states["YOUR_STATE_NAME"] = function(context) ... end`
-- 2. Read or mutate `context` (shared persistent data: indices, inventory, errors).
-- 3. To transition: set `currentState = "OTHER_STATE"` (must be a key in `states`).
-- 4. Keep side-effects (movement, digging, placing, chest access) inside helpers;
--    states should focus on DECISION LOGIC & TRANSITIONS.
-- 5. If an error occurs: set `context.lastError = "message"`; set
--    `context.previousState = currentState`; then `currentState = STATE_ERROR`.
--
-- LOOP CONTRACT
-- while true do
--   local fn = states[currentState]; if not fn then error("Unknown state") end
--   fn(context); if currentState == STATE_DONE then break end
-- end
--
-- CONTEXT FIELDS
--   manifest            : build manifest table
--   remainingMaterials  : counts of blocks still to place
--   currentY,currentZ,currentX : position indices (1-based) inside manifest
--   width,height,depth  : cached meta.size values
--   lastError           : last error string (nil if none)
--   previousState       : last non-error state
--   missingBlockName    : name of block we failed to place triggering RESTOCK
--   manifestOK          : whether validation passed
--   chestDirection      : direction to chest from origin ('front','right','behind','left','up','down')
--   movementHistory     : sequence of moves from origin (for return-to-origin)
--
-- IMPLEMENTED STATES
--   INITIALIZE : validate manifest; prepare counters & materials; -> BUILD or ERROR
--   BUILD      : place next block; fuel low -> REFUEL; missing block -> RESTOCK; end -> DONE
--   RESTOCK    : (simplified) attempt blocking fetch of missing block from adjacent storage; -> BUILD or ERROR
--   REFUEL     : attempt fuel replenishment; -> previousState or ERROR
--   ERROR      : display message; wait for Enter; resume previousState
--   DONE       : terminal state (break loop)
--
-- NOTE ON RETURN-TO-ORIGIN (RESTOCK / REFUEL)
-- RESTOCK and REFUEL states now properly return to origin:
-- 1. Ascend to safe height above the build (non-destructive)
-- 2. Reverse movementHistory to return to origin
-- 3. Access chest/fuel storage at origin (remembered position from INITIALIZE)
-- 4. Return along the saved path to resume building
--
-- ORIGINAL FEATURES PRESERVED
-- - Auto fuel search & consumption
-- - Opportunistic (non-blocking) material restock while building
-- - Tier-equivalent item family handling
-- - Manifest validation and material requirement computation
--
-- Lua Tips (quick):
-- - Tables are associative arrays; use `pairs` for unordered keys, `ipairs` for arrays.
-- - `local` keeps scope limited, reducing accidental global pollution.
-- - Functions are first-class; you can store them in tables (like our states).
-- - Always nil-check values before indexing (`if x then ... end`).
--

-- - Auto-fuel searching & refuel threshold logic
-- - Family equivalence for tiered Mekanism components

-- MANIFEST LOADING ------------------------------------------------------
-- Try loading from factory subdirectory first, then fall back to current directory.
local manifest
local ok, result = pcall(require, "factory.modular_cell_manifest")
if ok then
  manifest = result
else
  manifest = require("modular_cell_manifest")
end

-- STATE NAME CONSTANTS --------------------------------------------------
local STATE_INITIALIZE = "INITIALIZE"
local STATE_BUILD      = "BUILD"
local STATE_RESTOCK    = "RESTOCK"
local STATE_REFUEL     = "REFUEL"
local STATE_ERROR      = "ERROR"
local STATE_DONE       = "DONE"
local STATE_BLOCKED    = "BLOCKED" -- new: handle non-destructive go-home-and-return when blocked

local currentState = STATE_INITIALIZE  -- global per spec
local states = {}                      -- container for state functions

-- Forward-declare the shared state context so utility functions defined earlier
-- can safely reference it (movement history, etc.). It will be initialized later.
local context

-- CONFIG -----------------------------------------------------------------
local REFUEL_SLOT = 16           -- slot containing fuel
local RESTOCK_AT  = 50           -- go refuel if fuel < this
local VERBOSE     = true
local DEBUG_RESTOCK = true      -- extra debug prints for restocking logic
local DEBUG_FUEL   = false      -- extra debug prints for fuel restocking logic
local PRELOAD_MATERIALS = false -- set true to force gathering all materials before build
local SAFETY_MAX_MOVE_RETRIES = 20 -- max tries for moving before giving up
local FUEL_RESTOCK_MAX_PULLS = 16 -- max suck attempts per container while seeking fuel
local AUTO_MODE   = true         -- set-and-forget: never prompt; auto-wait and retry
local RESTOCK_RETRY_SECONDS = 5  -- wait time between material restock retries in AUTO_MODE
local ERROR_RETRY_SECONDS   = 5  -- wait time before auto-resume from ERROR in AUTO_MODE
local RESTOCK_MAX_BASELINE_PASSES = 3 -- number of attempts to acquire baseline stacks this restock cycle
local RESTOCK_PRIORITY_EXTRA_STACKS = 4 -- attempt up to this many additional stacks of priority item beyond baseline

-- Startup requirement config: must have a TREASURE CHEST directly behind.
-- If you find a different mod id, add it to TREASURE_CHEST_MATCHERS below.
local REQUIRE_TREASURE_SPECIFIC = true
local TREASURE_CHEST_MATCHERS = {
  "supplementaries:treasure_chest",
  "treasure2:chest",
  "minecraft:chest",
}

-- Identify the legend entry that represents empty space so we can ignore it.
local AIR_BLOCK   = manifest.legend["."] or "minecraft:air"

-- UTILS ------------------------------------------------------------------
local function log(msg)
  if VERBOSE then print(msg) end
end

local function debug(msg)
  if DEBUG_RESTOCK then print("[DEBUG] "..msg) end
end

local function cloneTable(source)
  local copy = {}
  for key, value in pairs(source) do
    copy[key] = value
  end
  return copy
end

local function sortedKeys(tbl)
  local keys = {}
  for key in pairs(tbl) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

-- Forward declare for early references
local tallyInventory

-- Item family helpers (treat Mekanism tiered transports/cables as equivalent)
local function splitModAndId(name)
  if not name then return nil, nil end
  local mod, id = name:match("([^:]+):(.+)")
  return mod, id
end

local function stripTierPrefix(id)
  if not id then return nil end
  return (id
    :gsub("^basic_", "")
    :gsub("^advanced_", "")
    :gsub("^elite_", "")
    :gsub("^ultimate_", ""))
end

local function isSameFamily(expectedName, actualName)
  if expectedName == actualName then return true end
  local emod, eid = splitModAndId(expectedName)
  local amod, aid = splitModAndId(actualName)
  if not (emod and eid and amod and aid) then return false end
  if emod ~= amod then return false end
  local ebase = stripTierPrefix(eid)
  local abase = stripTierPrefix(aid)
  return ebase == abase
end

local function countFamilyInInventory(inventoryTotals, expectedName)
  local count = 0
  for actualName, n in pairs(inventoryTotals) do
    if isSameFamily(expectedName, actualName) then
      count = count + (n or 0)
    end
  end
  return count
end

local function fetchLayer(yIndex)
  -- Resolve manifest layer, following SAME_AS references recursively.
  local layer = manifest.layers[yIndex]
  if type(layer) == "table" then return layer end
  if type(layer) == "string" then
    local ref = layer:match("SAME_AS%[(%d+)%]")
    if ref then return fetchLayer(tonumber(ref)) end
  end
  error(("Invalid layer definition at Y=%d"):format(yIndex))
end

local function collectRequiredMaterials()
  -- Count every non-air block needed to complete the manifest once.
  local requirements = {}
  local size = manifest.meta.size
  for yIndex = 1, size.y do
    local layer = fetchLayer(yIndex)
    for _, row in ipairs(layer) do
      for column = 1, #row do
        local symbol = row:sub(column, column)
        local blockName = manifest.legend[symbol]
        if blockName == nil then
          log("⚠ Unknown manifest symbol: " .. symbol)
        elseif blockName ~= AIR_BLOCK then
          requirements[blockName] = (requirements[blockName] or 0) + 1
        end
      end
    end
  end
  return requirements
end

local MATERIAL_REQUIREMENTS = collectRequiredMaterials()

local function validateManifest()
  local ok = true
  local size = manifest.meta.size

  for y = 1, size.y do
    local layer = fetchLayer(y)
    if type(layer) ~= "table" then
      log("Manifest warning: layer "..y.." did not resolve to a table")
      ok = false
    else
      for z, row in ipairs(layer) do
        local len = #row
        if len ~= size.x then
          log(string.format("Manifest warning: layer %d row %d has length %d (expected %d)", y, z, len, size.x))
          ok = false
        end
        for i = 1, len do
          local sym = row:sub(i,i)
          if manifest.legend[sym] == nil then
            log(string.format("Manifest warning: unknown symbol '%s' at y=%d z=%d x=%d", sym, y, z, i))
            ok = false
          end
        end
      end
    end
  end
  return ok
end

local function isInventoryBlock(name)
  if not name then return false end
  return name:find("chest") or name:find("barrel") or name:find("drawer") or name:find("shulker_box")
end

-- Determine if a block id qualifies as a TREASURE CHEST per startup requirement.
-- Rules:
-- - Exact match against known ids in TREASURE_CHEST_MATCHERS
-- - Or (case-insensitive) contains both "treasure" and "chest"
-- If REQUIRE_TREASURE_SPECIFIC=false, we also accept vanilla chest variants.
local function isTreasureChestId(blockId)
  if not blockId then return false end
  local lname = string.lower(blockId)
  -- Exact known ids
  for _, known in ipairs(TREASURE_CHEST_MATCHERS) do
    if lname == known then return true end
  end
  -- Heuristic: claims to be treasure + chest
  if string.find(lname, "treasure", 1, true) and string.find(lname, "chest", 1, true) then
    return true
  end
  if not REQUIRE_TREASURE_SPECIFIC then
    if lname == "minecraft:chest" or lname == "minecraft:trapped_chest" then
      return true
    end
    -- accept any mod chest as a fallback when not strict
    if string.find(lname, "chest", 1, true) then return true end
  end
  return false
end

-- Inspect the block directly behind the turtle without recording movement history.
-- Returns (isTreasureChest:boolean, blockId:string|nil)
local function checkTreasureChestBehind()
  local function turnAround() turtle.turnRight(); turtle.turnRight() end
  turnAround()
  local ok, data = turtle.inspect()
  turnAround()
  local name = (ok and data and data.name) or nil
  return isTreasureChestId(name), name, data
end

-- Scan all adjacent blocks and find storage (chest/barrel/etc.).
-- Returns: direction string ('front','right','behind','left','up','down') or nil if not found.
local function findAdjacentStorageDirection()
  local function noop() end
  local function turnAround() turtle.turnRight(); turtle.turnRight() end
  
  local directions = {
    {label = "front",  prepare = noop,             cleanup = noop,             inspect = turtle.inspect},
    {label = "right",  prepare = turtle.turnRight, cleanup = turtle.turnLeft,  inspect = turtle.inspect},
    {label = "behind", prepare = turnAround,       cleanup = turnAround,       inspect = turtle.inspect},
    {label = "left",   prepare = turtle.turnLeft,  cleanup = turtle.turnRight, inspect = turtle.inspect},
    {label = "up",     prepare = noop,             cleanup = noop,             inspect = turtle.inspectUp},
    {label = "down",   prepare = noop,             cleanup = noop,             inspect = turtle.inspectDown},
  }
  
  for _, spec in ipairs(directions) do
    spec.prepare()
    local ok, data = spec.inspect()
    spec.cleanup()
    if ok and data and isInventoryBlock(data.name) then
      if VERBOSE then log("Found storage at origin: "..spec.label.." ("..data.name..")") end
      return spec.label
    end
  end
  return nil
end

local function snapshotInventory()
  return tallyInventory()
end

local function diffGains(before, after)
  local gains = {}
  for name, afterCount in pairs(after) do
    local delta = afterCount - (before[name] or 0)
    if delta > 0 then gains[name] = delta end
  end
  return gains
end

-- Multi-allowed variant: do NOT drop items if they are also missing.
-- gains: table name->delta picked up this burst
-- allowedSet: table of itemName -> true for all items still missing (deficit > 0)
-- dropFn: function to drop items back in the direction we sucked from
-- multiMode: true if caller passed a set; false when wrapping legacy call
function dropUnexpectedGainsMulti(gains, allowedSet, dropFn, multiMode)
  local toDrop = {}
  for name, count in pairs(gains) do
    if count > 0 then
      local keep = false
      -- Keep if exact match or family match with ANY allowed item symbol
      for allowedName in pairs(allowedSet) do
        if isSameFamily(allowedName, name) then
          keep = true; break
        end
      end
      if not keep then toDrop[name] = count end
    end
  end
  if next(toDrop) == nil then return end
  if DEBUG_RESTOCK then
    for n,c in pairs(toDrop) do
      print(string.format('[DEBUG] Restock dropping non-required gain: %s x%d', n, c))
    end
  end
  for slot = 1, 15 do
    local detail = turtle.getItemDetail(slot)
    if detail and toDrop[detail.name] and toDrop[detail.name] > 0 then
      turtle.select(slot)
      local need = toDrop[detail.name]
      local give = math.min(need, detail.count)
      if give > 0 then
        dropFn(give)
        toDrop[detail.name] = need - give
      end
    end
  end
  turtle.select(1)
end

-- Attempt to pull any usable fuel from adjacent storage and refuel up to targetLevel.
-- Returns two values:
--   pulledFuel: true if we consumed at least one unit of fuel from adjacent storage
--   foundContainer: true if any adjacent storage was found (even if no fuel was available)
local function attemptFuelRestock(targetLevel)

  local pulledFuel = false
  local foundContainer = false

  local function isNameFuel(name)
    if not name then return false end
    for slot = 1, 16 do
      local detail = turtle.getItemDetail(slot)
      if detail and detail.name == name then
        local sel = turtle.getSelectedSlot()
        turtle.select(slot)
        local ok = turtle.refuel and turtle.refuel(0)
        turtle.select(sel)
        if ok then return true end
      end
    end
    return false
  end

  local function tryConsumeFuelToTarget(level)
    local started = turtle.getFuelLevel()
    for slot = 1, 16 do
      local detail = turtle.getItemDetail(slot)
      if detail then
        local sel = turtle.getSelectedSlot()
        turtle.select(slot)
        if turtle.refuel and turtle.refuel(0) then
          if DEBUG_FUEL then print(string.format("[DEBUG] Fuel: consuming %s x%d", detail.name, detail.count)) end
          while turtle.getFuelLevel() <= level and turtle.refuel(1) do
            pulledFuel = true
          end
        end
        turtle.select(sel)
        if turtle.getFuelLevel() > level then break end
      end
    end
    return turtle.getFuelLevel() > started
  end

  local function noop() end
  local function turnAround()
    turtle.turnRight(); turtle.turnRight()
  end

  local directions = {
    {label = "in front",   prepare = noop,        cleanup = noop,       inspect = turtle.inspect,   suck = turtle.suck,   drop = turtle.drop},
    {label = "to the right",prepare = turtle.turnRight, cleanup = turtle.turnLeft, inspect = turtle.inspect, suck = turtle.suck, drop = turtle.drop},
    {label = "behind",      prepare = turnAround,  cleanup = turnAround, inspect = turtle.inspect, suck = turtle.suck, drop = turtle.drop},
    {label = "to the left", prepare = turtle.turnLeft,  cleanup = turtle.turnRight, inspect = turtle.inspect, suck = turtle.suck, drop = turtle.drop},
    {label = "above",       prepare = noop,        cleanup = noop,       inspect = turtle.inspectUp, suck = turtle.suckUp, drop = turtle.dropUp},
    {label = "below",       prepare = noop,        cleanup = noop,       inspect = turtle.inspectDown, suck = turtle.suckDown, drop = turtle.dropDown},
  }

  for _, spec in ipairs(directions) do
    if turtle.getFuelLevel() > targetLevel then break end

    spec.prepare()
    local ok, data = spec.inspect()
    if ok and data and isInventoryBlock(data.name) then
      foundContainer = true
      if DEBUG_FUEL then print("[DEBUG] Fuel: searching storage "..data.name.." "..spec.label) end

      local beforeAll = snapshotInventory()
      local pulls = 0
      while turtle.getFuelLevel() <= targetLevel and pulls < FUEL_RESTOCK_MAX_PULLS do
        if not spec.suck(64) then break end
        pulls = pulls + 1
        -- Try consuming any fuel we just picked up
        tryConsumeFuelToTarget(targetLevel)
      end

      -- Return all non-fuel items we inadvertently pulled during this burst
      local afterAll = snapshotInventory()
      local gains = diffGains(beforeAll, afterAll)
      local toDrop = {}
      for name, count in pairs(gains) do
        if count > 0 and not isNameFuel(name) then
          toDrop[name] = count
        end
      end
      if next(toDrop) ~= nil then
        for slot = 1, 16 do
          local detail = turtle.getItemDetail(slot)
          if detail and toDrop[detail.name] and toDrop[detail.name] > 0 then
            turtle.select(slot)
            local need = toDrop[detail.name]
            local give = math.min(need, detail.count)
            if give > 0 then
              spec.drop(give)
              toDrop[detail.name] = need - give
            end
          end
        end
      end
    end
    spec.cleanup()
  end

  return pulledFuel or turtle.getFuelLevel() > targetLevel, foundContainer
end

-- Attempt to restock required materials from any adjacent storage.
-- missing: table of deficits for the current target(s) only
-- allowedUniverse: table of remaining requirements for the entire build; used to keep
--                  any items that are still needed elsewhere instead of dropping them.
local function attemptChestRestock(missing, allowedUniverse)
  -- Search every adjacent block for storage and pull required materials.
  local pulledSomething = false
  local foundContainer = false

  local function pullFromDirection(spec)
    spec.prepare()
    local ok, data = spec.inspect()
    if ok and data and isInventoryBlock(data.name) then
      foundContainer = true
      log("Detected storage " .. data.name .. " " .. spec.label)
      for itemName, deficit in pairs(missing) do
        local remaining = deficit
        local beforeAll = snapshotInventory()
        local tries = 0
        local MAX_BURST = 16 -- buffer up to 16 pulls before returning extras
        while remaining > 0 and tries < MAX_BURST do
          if not spec.suck(64) then break end
          tries = tries + 1
          local afterNow = snapshotInventory()
          local gainsNow = diffGains(beforeAll, afterNow)
          local gainedRequested = 0
          for gname, gcount in pairs(gainsNow) do
            if isSameFamily(itemName, gname) then
              gainedRequested = gainedRequested + gcount
            end
          end
          debug(string.format("Restock burst %s: needed %d, gained-so-far %d (tries %d)", itemName, remaining, gainedRequested, tries))
          if gainedRequested >= remaining then break end
        end
        local afterAll = snapshotInventory()
        local gainsTotal = diffGains(beforeAll, afterAll)
        local gainedRequestedTotal = 0
        for gname, gcount in pairs(gainsTotal) do
          if isSameFamily(itemName, gname) then
            gainedRequestedTotal = gainedRequestedTotal + gcount
          end
        end
        remaining = math.max(remaining - gainedRequestedTotal, 0)
        if gainedRequestedTotal > 0 then pulledSomething = true end
        -- Build a set of ALL still-missing item names across the whole build so we keep
        -- items useful for other deficits, not just the current target.
        local allowedSet = {}
        local source = allowedUniverse or missing
        for n, deficitVal in pairs(source) do
          if deficitVal and deficitVal > 0 then allowedSet[n] = true end
        end
        dropUnexpectedGainsMulti(gainsTotal, allowedSet, spec.drop, true)

        missing[itemName] = remaining
      end
    end
    spec.cleanup()
  end

  local function noop() end
  local function turnAround()
    turtle.turnRight()
    turtle.turnRight()
  end

  local directions = {
    {label = "in front", prepare = noop, cleanup = noop, inspect = turtle.inspect,   suck = turtle.suck,   drop = turtle.drop},
    {label = "to the right", prepare = turtle.turnRight, cleanup = turtle.turnLeft, inspect = turtle.inspect, suck = turtle.suck, drop = turtle.drop},
    {label = "behind", prepare = turnAround, cleanup = turnAround, inspect = turtle.inspect, suck = turtle.suck, drop = turtle.drop},
    {label = "to the left", prepare = turtle.turnLeft, cleanup = turtle.turnRight, inspect = turtle.inspect, suck = turtle.suck, drop = turtle.drop},
    {label = "above", prepare = noop, cleanup = noop, inspect = turtle.inspectUp, suck = turtle.suckUp, drop = turtle.dropUp},
    {label = "below", prepare = noop, cleanup = noop, inspect = turtle.inspectDown, suck = turtle.suckDown, drop = turtle.dropDown},
  }

  local function hasOutstandingNeeds()
    for _, deficit in pairs(missing) do
      if deficit and deficit > 0 then return true end
    end
    return false
  end

  for _, spec in ipairs(directions) do
    if not hasOutstandingNeeds() then break end
    pullFromDirection(spec)
  end

  turtle.select(1)
  return pulledSomething, foundContainer
end

-- Bind to the earlier forward declaration `local tallyInventory`
tallyInventory = function()
  -- Build a frequency table of items currently held by the turtle.
  local inventoryTotals = {}
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail then
      inventoryTotals[detail.name] = (inventoryTotals[detail.name] or 0) + detail.count
    end
  end
  return inventoryTotals
end

local function printMaterialManifest(required, missing)
  -- Display a sorted manifest so the player knows what to load.
  local orderedBlocks = {}
  for blockName in pairs(required) do
    orderedBlocks[#orderedBlocks + 1] = blockName
  end
  table.sort(orderedBlocks)

  print("Material manifest:")
  for _, blockName in ipairs(orderedBlocks) do
    local requiredCount = required[blockName]
    if requiredCount and requiredCount > 0 then
      local missingCount = missing and missing[blockName] or 0
      if missingCount > 0 then
        print(('- %s x%d (missing %d)'):format(blockName, requiredCount, missingCount))
      else
        print(('- %s x%d'):format(blockName, requiredCount))
      end
    end
  end
end

local function promptForMaterials(required)
  print("Total materials required for this build:")
  printMaterialManifest(required)
  print("Load these materials into the turtle or adjacent storage, then press Enter to begin.")
  read()
end

-- Ensure required materials are available.
-- When blocking=true, this will prompt the user to load items if missing.
-- When blocking=false, this will attempt a quick restock from adjacent storage
-- and return false if still missing, allowing the builder to continue without stalling.
local function ensureMaterialsAvailable(pendingRequirements, targetBlock, blocking)
  if blocking == nil then blocking = true end
  local neededCounts = pendingRequirements or MATERIAL_REQUIREMENTS
  while true do
    local inventoryTotals = tallyInventory()
    local missing = {}
    local hasAllMaterials = true

    local function requireAmount(blockName, desiredCount)
      if desiredCount <= 0 then return end
      -- Count family equivalents (tier variants) too
      local availableCount = countFamilyInInventory(inventoryTotals, blockName)
      if availableCount < desiredCount then
        missing[blockName] = desiredCount - availableCount
        hasAllMaterials = false
      end
    end

    if targetBlock then
      -- Important: when checking availability for a specific immediate placement,
      -- we must require AT LEAST one of that item family even if our global
      -- remainingRequirements table says 0 (it can be out of sync or we might be
      -- placing an extra copy due to manifest specifics). Using a minimum of 1
      -- ensures we actually verify inventory and trigger restock if empty.
      local desired = 1
      requireAmount(targetBlock, desired)
    else
      for blockName, requiredCount in pairs(neededCounts) do
        if requiredCount and requiredCount > 0 then
          requireAmount(blockName, requiredCount)
        end
      end
    end

    if hasAllMaterials then return true end

    -- Try to pull from adjacent containers first
    local pulled, foundContainer = attemptChestRestock(missing, neededCounts)
    if pulled then
      if targetBlock then
        print("Pulled "..targetBlock.." from nearby storage. Rechecking...")
        debug("After pull count for "..targetBlock.." = "..countFamilyInInventory(tallyInventory(), targetBlock))
      else
        print("Pulled additional materials from nearby storage. Rechecking...")
      end
    else
      -- No materials nearby.
      if not blocking then
        -- Non-blocking: return false so the builder can continue and retry later.
        if foundContainer then
          log("No required materials found in nearby storage for "..tostring(targetBlock or "this step").." (non-blocking)")
        end
        return false
      end

      -- Blocking mode: AUTO_MODE waits and retries without human input; otherwise prompt.
      if AUTO_MODE then
        if foundContainer then
          print("Waiting for materials to appear in nearby storage...")
        else
          print("Waiting for materials (no storage detected nearby)...")
        end
        if targetBlock then
          local deficit = missing[targetBlock] or 0
          print(('- Need %d more of %s; rechecking in %ds'):format(deficit, targetBlock, RESTOCK_RETRY_SECONDS))
        else
          print('(Rechecking inventory and storage in '..RESTOCK_RETRY_SECONDS..'s)')
        end
        sleep(RESTOCK_RETRY_SECONDS)
        -- loop continues and rechecks
      else
        if foundContainer then
          print("Nearby storage is missing required materials.")
        else
          print("Insufficient materials detected.")
        end
        if targetBlock then
          local deficit = missing[targetBlock] or 0
          print(('- Need %d more of %s'):format(deficit, targetBlock))
        else
          printMaterialManifest(neededCounts, missing)
        end
        print("Load the missing items into the turtle or adjacent storage, then press Enter to retry.")
        read()
      end
    end
  end
end

local function isFuelUnlimited()
  if turtle.getFuelLimit then
    local lim = turtle.getFuelLimit()
    if lim == "unlimited" or lim == math.huge then return true end
  end
  return false
end

local function tryRefuelFromSlot(slot, targetLevel)
  if isFuelUnlimited() then return true end
  if not slot then return false end
  local selected = turtle.getSelectedSlot()
  turtle.select(slot)
  local consumed = false
  while turtle.refuel(1) do
    consumed = true
    if turtle.getFuelLevel() > targetLevel then break end
  end
  turtle.select(selected)
  return consumed
end

local function refuel()
  if isFuelUnlimited() then return end
  local level = turtle.getFuelLevel()
  if level > RESTOCK_AT then return end
  -- Prefer slot 16, then scan all slots for any valid fuel
  if tryRefuelFromSlot(REFUEL_SLOT, RESTOCK_AT) then
    log("Refueled from slot "..REFUEL_SLOT..": "..turtle.getFuelLevel())
    return
  end
  for s = 1, 16 do
    if s ~= REFUEL_SLOT then
      if tryRefuelFromSlot(s, RESTOCK_AT) then
        log("Refueled from slot "..s..": "..turtle.getFuelLevel())
        return
      end
    end
  end
  -- Try to pull fuel from adjacent storage
  local pulled, found = attemptFuelRestock(RESTOCK_AT)
  if pulled then
    log("Refueled from nearby storage: "..turtle.getFuelLevel())
    return
  end
  if found then
    log("Fuel low ("..tostring(level)..") but nearby storage had no usable fuel")
  else
    log("Fuel low ("..tostring(level)..") and no usable fuel found in inventory")
  end
end

-- Service-travel helpers: attempt to step up/down ONCE without digging.
-- We avoid our up()/down() wrappers here to guarantee no block destruction on service entry/exit.
local function tryUpNoDig()
  -- If fuel is exhausted or headspace blocked, we simply don't ascend.
  local before = turtle.getFuelLevel()
  local ok = turtle.up()
  if ok then return true end
  -- If not unlimited fuel and we failed due to 0 fuel, report once.
  if (not isFuelUnlimited()) and before == 0 then
    log("Skipped safe-ascend: no fuel to go up")
  end
  return false
end

local function tryDownNoDig()
  local ok = turtle.down()
  return ok
end

-- SAFE, NON-DESTRUCTIVE TRAVEL HELPERS ---------------------------------
-- These helpers only use raw movement (no digging/attacking). If blocked,
-- they wait (AUTO_MODE) or prompt until the path clears.
local function safeWaitMove(stepFn, label)
  label = label or "move"
  while true do
    if stepFn() then return true end
    if AUTO_MODE then
      log("Waiting for path to clear ("..label..")...")
      sleep(1)
    else
      print("Path blocked during "..label..". Clear the way, then press Enter to retry.")
      read()
    end
  end
end

local function safePerformInverse(op)
  if op == 'F' then
    safeWaitMove(turtle.back, 'back')
    return true
  elseif op == 'U' then
    safeWaitMove(turtle.down, 'down')
    return true
  elseif op == 'D' then
    safeWaitMove(turtle.up, 'up')
    return true
  elseif op == 'R' then
    turtle.turnLeft()
    return true
  elseif op == 'L' then
    turtle.turnRight()
    return true
  end
  return false
end

local function safePerformForward(op)
  if op == 'F' then
    safeWaitMove(turtle.forward, 'forward')
    return true
  elseif op == 'U' then
    safeWaitMove(turtle.up, 'up')
    return true
  elseif op == 'D' then
    safeWaitMove(turtle.down, 'down')
    return true
  elseif op == 'R' then
    turtle.turnRight()
    return true
  elseif op == 'L' then
    turtle.turnLeft()
    return true
  end
  return false
end

local function goToOriginSafely()
  if not context or not context.movementHistory then return {} end
  local path = {}
  while #context.movementHistory > 0 do
    local op = table.remove(context.movementHistory)
    table.insert(path, op)
    if not safePerformInverse(op) then break end
  end
  return path
end

local function returnAlongPathSafely(path)
  for i = #path, 1, -1 do
    local op = path[i]
    if not safePerformForward(op) then return false end
  end
  -- Restore movement history to original (we returned to where we left off)
  context.movementHistory = {}
  for i = 1, #path do context.movementHistory[i] = path[i] end
  return true
end

-- CHEST ACCESS AT ORIGIN HELPERS ----------------------------------------
-- These functions orient the turtle to access the chest at origin based on
-- the remembered direction from INITIALIZE.
local function orientToChest()
  if not context.chestDirection then return false end
  local dir = context.chestDirection
  if dir == "front" then
    -- already facing chest
    return true
  elseif dir == "right" then
    turtle.turnRight()
    return true
  elseif dir == "behind" then
    turtle.turnRight()
    turtle.turnRight()
    return true
  elseif dir == "left" then
    turtle.turnLeft()
    return true
  elseif dir == "up" or dir == "down" then
    -- vertical chest; no rotation needed
    return true
  end
  return false
end

local function getChestAccessFunctions()
  -- Returns table with inspect, suck, and drop functions for the chest direction.
  if not context.chestDirection then return nil end
  local dir = context.chestDirection
  
  if dir == "up" then
    return {
      inspect = turtle.inspectUp,
      suck = turtle.suckUp,
      drop = turtle.dropUp,
      label = "above"
    }
  elseif dir == "down" then
    return {
      inspect = turtle.inspectDown,
      suck = turtle.suckDown,
      drop = turtle.dropDown,
      label = "below"
    }
  else
    -- horizontal direction: orient first, then use forward functions
    orientToChest()
    return {
      inspect = turtle.inspect,
      suck = turtle.suck,
      drop = turtle.drop,
      label = context.chestDirection or "front"
    }
  end
end

-- Restock from the chest at origin (using remembered chest direction).
-- missing: table of deficits for items to pull
-- allowedUniverse: table of all remaining requirements (to keep extra items that are still needed)
-- Returns: (pulledSomething, foundContainer)
local function restockFromOriginChest(missing, allowedUniverse)
  if not context.chestDirection then
    log("Cannot restock: chest direction not known")
    return false, false
  end
  
  local chestFns = getChestAccessFunctions()
  if not chestFns then
    log("Cannot restock: failed to get chest access functions")
    return false, false
  end
  
  local ok, data = chestFns.inspect()
  if not ok or not data or not isInventoryBlock(data.name) then
    log("Cannot restock: no storage block found at "..chestFns.label)
    return false, false
  end
  
  if VERBOSE then log("Restocking from origin chest: "..data.name.." ("..chestFns.label..")") end
  
  local pulledSomething = false
  for itemName, deficit in pairs(missing) do
    if deficit <= 0 then goto continue end
    
    local remaining = deficit
    local beforeAll = snapshotInventory()
    local tries = 0
    local MAX_BURST = 16
    
    while remaining > 0 and tries < MAX_BURST do
      if not chestFns.suck(64) then break end
      tries = tries + 1
      
      local afterNow = snapshotInventory()
      local gainsNow = diffGains(beforeAll, afterNow)
      local gainedRequested = 0
      for gname, gcount in pairs(gainsNow) do
        if isSameFamily(itemName, gname) then
          gainedRequested = gainedRequested + gcount
        end
      end
      
      debug(string.format("Origin restock burst %s: needed %d, gained %d (tries %d)", itemName, remaining, gainedRequested, tries))
      if gainedRequested >= remaining then break end
    end
    
    local afterAll = snapshotInventory()
    local gainsTotal = diffGains(beforeAll, afterAll)
    local gainedRequestedTotal = 0
    for gname, gcount in pairs(gainsTotal) do
      if isSameFamily(itemName, gname) then
        gainedRequestedTotal = gainedRequestedTotal + gcount
      end
    end
    
    remaining = math.max(remaining - gainedRequestedTotal, 0)
    if gainedRequestedTotal > 0 then pulledSomething = true end
    
    -- Drop unexpected items (keep only items still needed elsewhere)
    local allowedSet = {}
    local source = allowedUniverse or missing
    for n, deficitVal in pairs(source) do
      if deficitVal and deficitVal > 0 then allowedSet[n] = true end
    end
    dropUnexpectedGainsMulti(gainsTotal, allowedSet, chestFns.drop, true)
    
    missing[itemName] = remaining
    ::continue::
  end
  
  turtle.select(1)
  return pulledSomething, true
end

-- Refuel from the chest at origin (using remembered chest direction).
-- targetLevel: desired fuel level to reach
-- Returns: (refueled:bool, foundContainer:bool)
local function refuelFromOriginChest(targetLevel)
  if not context.chestDirection then
    log("Cannot refuel: chest direction not known")
    return false, false
  end
  
  local chestFns = getChestAccessFunctions()
  if not chestFns then
    log("Cannot refuel: failed to get chest access functions")
    return false, false
  end
  
  local ok, data = chestFns.inspect()
  if not ok or not data or not isInventoryBlock(data.name) then
    log("Cannot refuel: no storage block found at "..chestFns.label)
    return false, false
  end
  
  if DEBUG_FUEL then log("Refueling from origin chest: "..data.name.." ("..chestFns.label..")") end
  
  local function isNameFuel(name)
    if not name then return false end
    for slot = 1, 16 do
      local detail = turtle.getItemDetail(slot)
      if detail and detail.name == name then
        local sel = turtle.getSelectedSlot()
        turtle.select(slot)
        local isFuel = turtle.refuel and turtle.refuel(0)
        turtle.select(sel)
        if isFuel then return true end
      end
    end
    return false
  end
  
  local function tryConsumeFuelToTarget(level)
    local started = turtle.getFuelLevel()
    for slot = 1, 16 do
      local detail = turtle.getItemDetail(slot)
      if detail then
        local sel = turtle.getSelectedSlot()
        turtle.select(slot)
        if turtle.refuel and turtle.refuel(0) then
          if DEBUG_FUEL then print(string.format("[DEBUG] Fuel: consuming %s x%d", detail.name, detail.count)) end
          while turtle.getFuelLevel() <= level and turtle.refuel(1) do end
        end
        turtle.select(sel)
        if turtle.getFuelLevel() > level then break end
      end
    end
    return turtle.getFuelLevel() > started
  end
  
  local refueled = false
  local beforeAll = snapshotInventory()
  local pulls = 0
  
  while turtle.getFuelLevel() <= targetLevel and pulls < FUEL_RESTOCK_MAX_PULLS do
    if not chestFns.suck(64) then break end
    pulls = pulls + 1
    tryConsumeFuelToTarget(targetLevel)
  end
  
  refueled = turtle.getFuelLevel() > targetLevel
  
  -- Return all non-fuel items
  local afterAll = snapshotInventory()
  local gains = diffGains(beforeAll, afterAll)
  local toDrop = {}
  for name, count in pairs(gains) do
    if count > 0 and not isNameFuel(name) then
      toDrop[name] = count
    end
  end
  
  if next(toDrop) ~= nil then
    for slot = 1, 16 do
      local detail = turtle.getItemDetail(slot)
      if detail and toDrop[detail.name] and toDrop[detail.name] > 0 then
        turtle.select(slot)
        local need = toDrop[detail.name]
        local give = math.min(need, detail.count)
        if give > 0 then
          chestFns.drop(give)
          toDrop[detail.name] = need - give
        end
      end
    end
  end
  
  turtle.select(1)
  return refueled, true
end

-- SERVICE STORAGE LOCATION LOGIC -----------------------------------------
-- Instead of replaying full serpentine movement history (which drags us over
-- every placed block), service routines (REFUEL / RESTOCK) should:
-- 1. Ascend one block to the "service lane" (already handled before calls).
-- 2. Probe for storage adjacent without moving horizontally.
-- 3. If not found, step outward in a short search pattern just outside the build
--    footprint, minimizing traversal. We record each horizontal step so we can
--    reverse it later and return above our original build coordinate.
-- 4. We DO NOT dig while searching (non-destructive); if blocked we skip that direction.
-- Pattern chosen: F, B, R, L, F,F (extend outward), then stop.
-- Assumption: at least one chest/barrel etc. is placed somewhere adjacent or
-- just one block outside the starting origin perimeter.
local function findServiceStorageNonSerpentine(ctx)
  local serviceMoves = {}

  local function record(moveCode)
    serviceMoves[#serviceMoves+1] = moveCode
  end

  local function tryStep(stepFn, code)
    local fuelBefore = turtle.getFuelLevel()
    if (not isFuelUnlimited()) and fuelBefore <= 0 then return false end
    local ok = stepFn()
    if ok then record(code) end
    return ok
  end

  local probes = {
    {label="in place", prep=function() end, cleanup=function() end, inspect=turtle.inspect},
    {label="right", prep=turtle.turnRight, cleanup=turtle.turnLeft, inspect=turtle.inspect},
    {label="behind", prep=function() turtle.turnRight(); turtle.turnRight(); end, cleanup=function() turtle.turnRight(); turtle.turnRight(); end, inspect=turtle.inspect},
    {label="left", prep=turtle.turnLeft, cleanup=turtle.turnRight, inspect=turtle.inspect},
    {label="up", prep=function() end, cleanup=function() end, inspect=turtle.inspectUp},
    {label="down", prep=function() end, cleanup=function() end, inspect=turtle.inspectDown},
  }

  local function scanAdjacency()
    for _,p in ipairs(probes) do
      p.prep()
      local ok,data = p.inspect()
      p.cleanup()
      if ok and data and isInventoryBlock(data.name) then
        if VERBOSE then log("Service storage found "..p.label.." -> "..data.name) end
        return true
      end
    end
    return false
  end

  if scanAdjacency() then
    return serviceMoves -- no horizontal movement needed
  end

  -- Horizontal outward search pattern (non-digging). We use raw turtle movement
  -- and always restore orientation after lateral steps. Every successful step is recorded.
  local function stepForward()
    local ok = turtle.forward()
    if ok then record('F') end
    return ok
  end
  local function stepBack()
    local ok = turtle.back()
    if ok then record('B') end
    return ok
  end
  local function stepRight()
    turtle.turnRight()
    local ok = turtle.forward()
    if ok then record('R') end
    turtle.turnLeft()
    return ok
  end
  local function stepLeft()
    turtle.turnLeft()
    local ok = turtle.forward()
    if ok then record('L') end
    turtle.turnRight()
    return ok
  end

  -- Sequence of candidate displacements with storage scan after each.
  local searchPlan = {
    {fn=stepForward},
    {fn=stepBack},
    {fn=stepRight},
    {fn=stepLeft},
    {fn=stepForward},
    {fn=stepForward},
  }

  for _,step in ipairs(searchPlan) do
    step.fn()
    if scanAdjacency() then return serviceMoves end
  end

  return serviceMoves -- may be empty or partial path; caller will attempt restock/refuel anyway
end

local function reverseServiceMoves(serviceMoves)
  -- Undo horizontal offsets exactly; codes:
  -- F: forward  -> reverse with back
  -- B: back     -> reverse with forward
  -- R: strafe right (turnRight, forward, turnLeft) -> reverse with strafe left
  -- L: strafe left  (turnLeft, forward, turnRight) -> reverse with strafe right
  for i = #serviceMoves, 1, -1 do
    local code = serviceMoves[i]
    if code == 'F' then
      turtle.back()
    elseif code == 'B' then
      turtle.forward()
    elseif code == 'R' then
      turtle.turnLeft(); turtle.forward(); turtle.turnRight()
    elseif code == 'L' then
      turtle.turnRight(); turtle.forward(); turtle.turnLeft()
    end
  end
end

local function placeBlock(blockName)
  -- Places the specified block below the turtle, but first checks if the
  -- existing block already matches the desired target. If so, we skip digging
  -- and placement and treat it as a success so the builder moves on.
  -- Note: We intentionally scan all 16 slots, not just 1..15, so placements work even
  -- if restock put building blocks into slot 16 (which is usually reserved for fuel).
  if not blockName or blockName == AIR_BLOCK then return true end

  -- Skip if the block below already matches the desired family
  local ok, data = turtle.inspectDown()
  if ok and data and (data.name == blockName or isSameFamily(blockName, data.name)) then
    if VERBOSE then log("Skipping: target already present below ("..tostring(data.name)..")") end
    return true
  end

  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and (detail.name == blockName or isSameFamily(blockName, detail.name)) then
      turtle.select(slot)
      -- Try to place; if blocked, dig and try once more. Return whether it actually placed.
      if turtle.placeDown() then return true end
      turtle.digDown()
      return turtle.placeDown()
    end
  end
  return false
end

-- MOVEMENT ---------------------------------------------------------------
local function recordMove(op)
  -- Access global 'context' defined later; guard until initialized
  if context and context.movementHistory then
    table.insert(context.movementHistory, op)
  end
end

local function forward(maxRetries, record)
  maxRetries = maxRetries or SAFETY_MAX_MOVE_RETRIES
  if record == nil then record = true end
  local tries = 0
  while tries < maxRetries do
    refuel()
    if turtle.forward() then
      if record then recordMove('F') end
      return true
    end
    turtle.attack()
    turtle.dig()
    sleep(0.2)
    tries = tries + 1
    if (not isFuelUnlimited()) and turtle.getFuelLevel() <= 0 then
      log("Out of fuel: forward() cannot proceed")
      return false
    end
  end
  log("Move blocked: forward() failed after "..maxRetries.." attempts")
  return false
end

local function up(maxRetries, record)
  maxRetries = maxRetries or SAFETY_MAX_MOVE_RETRIES
  if record == nil then record = true end
  local tries = 0
  while tries < maxRetries do
    refuel()
    if turtle.up() then
      if record then recordMove('U') end
      return true
    end
    turtle.attackUp()
    turtle.digUp()
    sleep(0.2)
    tries = tries + 1
    if (not isFuelUnlimited()) and turtle.getFuelLevel() <= 0 then
      log("Out of fuel: up() cannot proceed")
      return false
    end
  end
  log("Move blocked: up() failed after "..maxRetries.." attempts")
  return false
end

local function down(maxRetries, record)
  maxRetries = maxRetries or SAFETY_MAX_MOVE_RETRIES
  if record == nil then record = true end
  local tries = 0
  while tries < maxRetries do
    refuel()
    if turtle.down() then
      if record then recordMove('D') end
      return true
    end
    turtle.attackDown()
    turtle.digDown()
    sleep(0.2)
    tries = tries + 1
    if (not isFuelUnlimited()) and turtle.getFuelLevel() <= 0 then
      log("Out of fuel: down() cannot proceed")
      return false
    end
  end
  log("Move blocked: down() failed after "..maxRetries.." attempts")
  return false
end

local function turnRight(record)
  if record == nil then record = true end
  turtle.turnRight()
  if record then recordMove('R') end
end
local function turnLeft(record)
  if record == nil then record = true end
  turtle.turnLeft()
  if record then recordMove('L') end
end

-- Return-to-origin helpers using movement history -----------------------
-- CORE BUILDER -----------------------------------------------------------
-- STATE MACHINE CONTEXT -------------------------------------------------
context = {
  manifest = manifest,
  remainingMaterials = nil, -- set in INITIALIZE
  currentY = 1,
  currentZ = 1,
  currentX = 1,
  width  = manifest.meta.size.x,
  height = manifest.meta.size.y,
  depth  = manifest.meta.size.z or manifest.meta.size.x,
  manifestOK = false,
  lastError = nil,
  previousState = nil,
  missingBlockName = nil,
  inventorySummary = {},
  layerCache = {}, -- cache of resolved layers
  movementHistory = {}, -- sequence of moves from origin (for return-to-origin)
  chestDirection = nil, -- direction to chest from origin (detected in INITIALIZE)
}

-- Helper: fetch & cache layer for context (avoids repeat resolution)
local function getLayer(y)
  if not context.layerCache[y] then
    context.layerCache[y] = fetchLayer(y)
  end
  return context.layerCache[y]
end

-- Helper: compute block symbol/name for current coordinates
local function getCurrentBlock()
  -- Map the current turtle position to the manifest symbol, accounting for
  -- serpentine traversal: odd-numbered rows go left->right, even-numbered rows
  -- go right->left. We keep currentX as the step count within the row and
  -- compute the actual x-index accordingly.
  local layer = getLayer(context.currentY)
  local row = layer[context.currentZ]
  if not row then return nil end
  local rowLen = #row
  local xIndex
  if context.currentZ % 2 == 1 then
    xIndex = context.currentX
  else
    xIndex = rowLen - (context.currentX - 1)
  end
  if xIndex < 1 or xIndex > rowLen then return nil end
  local sym = row:sub(xIndex, xIndex)
  if not sym then return nil end
  return manifest.legend[sym]
end

-- Advance build cursor (serpentine traversal identical to original) -----
local function advanceCursorAfterPlacement()
  local layer = getLayer(context.currentY)
  local rowLen = #layer[1]
  -- Move to next X within row
  if context.currentX < rowLen then
    if not forward() then
      context.lastError = "Movement blocked while advancing along X"
      context.previousState = currentState
      currentState = STATE_BLOCKED
      return
    end
    context.currentX = context.currentX + 1
    return
  end

  -- End of row: perform serpentine turn if more rows remain
  if context.currentZ < #layer then
    if context.currentZ % 2 == 1 then
      turnRight(); if not forward() then context.lastError = "Blocked during serpentine (right)"; context.previousState = currentState; currentState = STATE_BLOCKED; return end; turnRight()
    else
      turnLeft();  if not forward() then context.lastError = "Blocked during serpentine (left)";  context.previousState = currentState; currentState = STATE_BLOCKED; return end; turnLeft()
    end
    context.currentZ = context.currentZ + 1
    context.currentX = 1
    return
  end

  -- End of layer: return to origin, ascend
  if (#layer % 2 == 0) then
    turnRight(); for i=1,#layer-1 do if not forward() then context.lastError = "Return-to-origin failed (even rows)"; context.previousState = currentState; currentState = STATE_BLOCKED; return end end; turnRight()
  else
    turnLeft();  for i=1,#layer-1 do if not forward() then context.lastError = "Return-to-origin failed (odd rows)"; context.previousState = currentState; currentState = STATE_BLOCKED; return end end; turnLeft()
  end
  if not up() then
    context.lastError = "Unable to ascend to next layer"
    context.previousState = currentState
    currentState = STATE_BLOCKED
    return
  end
  context.currentY = context.currentY + 1
  context.currentZ = 1
  context.currentX = 1
end

-- Wrapper for placement that signals missing material ------------------
local function attemptPlaceCurrent(blockName)
  if blockName == AIR_BLOCK or blockName == nil then
    return true -- nothing to place
  end
  local placed = placeBlock(blockName)
  if placed then
    -- decrement remaining count
    if context.remainingMaterials[blockName] then
      context.remainingMaterials[blockName] = math.max(context.remainingMaterials[blockName] - 1, 0)
    end
  end
  return placed
end

-- STATES ----------------------------------------------------------------
states[STATE_INITIALIZE] = function(ctx)
  -- Strict startup requirement: a treasure chest must be directly behind the turtle.
  do
    local okChest, seenId, raw = checkTreasureChestBehind()
    if VERBOSE then
      local meta = raw and raw.state or {}
      -- Defensive: textutils may not be available if this runs outside CC:Tweaked environment.
      local serialized
      local tu = rawget(_G, 'textutils')
      if type(tu) == 'table' and type(tu.serialize) == 'function' then
        serialized = tu.serialize(meta)
      else
        serialized = '(textutils unavailable)'
      end
      print(string.format("Startup: behind id=%s; treasureChest=%s; state=%s", tostring(seenId or "none"), tostring(okChest), serialized))
    end
    if not okChest then
      print("Startup check failed: a treasure chest must be directly behind the turtle.")
      print("Detected behind block id: "..tostring(seenId or "none"))
      print("If this is the correct treasure chest, add its id to TREASURE_CHEST_MATCHERS or set REQUIRE_TREASURE_SPECIFIC=false.")
      error("Treasure chest required behind. Halting.")
    end
  end

  print("Initializing builder for "..ctx.manifest.meta.name)
  ctx.manifestOK = validateManifest()
  if not ctx.manifestOK then
    log("Manifest issues detected; continuing but placement accuracy may suffer.")
  end
  
  -- Find and remember the chest direction for later return-to-origin service calls
  ctx.chestDirection = findAdjacentStorageDirection()
  if not ctx.chestDirection then
    if AUTO_MODE then
      log("Warning: No adjacent storage detected; RESTOCK/REFUEL may be impossible. Proceeding in AUTO_MODE.")
    else
      ctx.lastError = "No adjacent storage detected; RESTOCK/REFUEL may be impossible"
      ctx.previousState = STATE_INITIALIZE
      currentState = STATE_ERROR
      return
    end
  else
    print("Storage direction saved: "..ctx.chestDirection)
  end
  if isFuelUnlimited() then
    print("Fuel: unlimited")
  else
    print("Fuel level at start: "..tostring(turtle.getFuelLevel()).." (threshold="..RESTOCK_AT..")")
    if turtle.getFuelLevel() <= RESTOCK_AT then refuel() end
  end
  ctx.remainingMaterials = cloneTable(MATERIAL_REQUIREMENTS)
  ctx.inventorySummary = tallyInventory()
  if PRELOAD_MATERIALS then
    promptForMaterials(ctx.remainingMaterials)
    for _, blockName in ipairs(sortedKeys(ctx.remainingMaterials)) do
      ensureMaterialsAvailable(ctx.remainingMaterials, blockName, true)
    end
  else
    print("Preload disabled; on-demand restock active.")
    if VERBOSE then
      print("Material requirements (first pass):")
      printMaterialManifest(ctx.remainingMaterials)
    end
  end
  currentState = STATE_BUILD
end

states[STATE_BUILD] = function(ctx)
  -- Completion check
  if ctx.currentY > ctx.height then
    currentState = STATE_DONE
    return
  end

  -- Fuel check first (non-blocking guidance)
  if (not isFuelUnlimited()) and turtle.getFuelLevel() <= RESTOCK_AT then
    ctx.previousState = STATE_BUILD
    currentState = STATE_REFUEL
    return
  end

  local blockName = getCurrentBlock()
  -- PROACTIVE RESTOCK CHECK -------------------------------------------------
  -- If we have zero of the required block family in inventory BEFORE trying
  -- to place (even if the block below already matches and we would skip), we
  -- enter RESTOCK immediately. This prevents silent progress over existing
  -- blocks leaving us unaware we've run out until a later coordinate.
  if blockName and blockName ~= AIR_BLOCK then
    local haveCount = countFamilyInInventory(tallyInventory(), blockName)
    local stillNeeded = (ctx.remainingMaterials[blockName] or 0) > 0
    if haveCount == 0 and stillNeeded then
      ctx.missingBlockName = blockName
      ctx.previousState = STATE_BUILD
      if VERBOSE then log("Proactive RESTOCK: none of required block "..blockName)
      end
      currentState = STATE_RESTOCK
      return
    end
  end
  if VERBOSE then
    log(string.format("Placing Y%02d Z%02d X%02d : %s", ctx.currentY, ctx.currentZ, ctx.currentX, tostring(blockName)))
  end
  local placed = attemptPlaceCurrent(blockName)
  if not placed and blockName ~= AIR_BLOCK then
    -- Missing material -> RESTOCK (blocking fetch)
    ctx.missingBlockName = blockName
    ctx.previousState = STATE_BUILD
    if VERBOSE then log("Entering RESTOCK after failed placement of "..blockName) end
    currentState = STATE_RESTOCK
    return
  end

  -- Advance cursor; may transition to ERROR inside helper
  advanceCursorAfterPlacement()
  if ctx.currentY > ctx.height then
    currentState = STATE_DONE
  end
end

states[STATE_RESTOCK] = function(ctx)
  if not ctx.missingBlockName then
    ctx.lastError = "RESTOCK invoked without a missingBlockName"
    ctx.previousState = STATE_BUILD
    currentState = STATE_ERROR
    return
  end
  print("Restocking missing item: "..ctx.missingBlockName)

  -- RETURN-TO-ORIGIN RESTOCK STRATEGY:
  -- 1. Ascend above the build height to travel safely
  -- 2. Reverse movementHistory to return to origin
  -- 3. Access the chest at origin
  -- 4. Return along the saved path to resume building
  
  -- Step 1: Ascend above the build to safe travel height
  local safeHeight = ctx.height + 2  -- go 2 blocks above max build height
  local ascendSteps = safeHeight - ctx.currentY
  if ascendSteps > 0 then
    print("Ascending "..ascendSteps.." blocks to safe travel height...")
    for i = 1, ascendSteps do
      if not tryUpNoDig() then
        ctx.lastError = "Failed to ascend to safe height for return-to-origin"
        ctx.previousState = STATE_BUILD
        currentState = STATE_ERROR
        return
      end
    end
  end
  
  -- Step 2: Return to origin safely (non-destructive)
  print("Returning to origin for restock...")
  local returnPath = goToOriginSafely()
  
  -- Step 3: Attempt to pull required materials from origin chest
  local missing = {[ctx.missingBlockName] = 1}  -- need at least 1 of the missing item
  local pulled, foundChest = restockFromOriginChest(missing, ctx.remainingMaterials)
  
  -- If still missing after first attempt, wait/retry
  if missing[ctx.missingBlockName] and missing[ctx.missingBlockName] > 0 then
    if AUTO_MODE then
      print("Material not available at origin. Waiting "..RESTOCK_RETRY_SECONDS.."s...")
      sleep(RESTOCK_RETRY_SECONDS)
      -- Retry pull
      missing = {[ctx.missingBlockName] = 1}
      pulled, foundChest = restockFromOriginChest(missing, ctx.remainingMaterials)
    else
      print("Load "..ctx.missingBlockName.." into origin chest, then press Enter.")
      read()
      missing = {[ctx.missingBlockName] = 1}
      pulled, foundChest = restockFromOriginChest(missing, ctx.remainingMaterials)
    end
  end
  
  -- Step 4: Return to work position
  print("Returning to work position...")
  local returnOk = returnAlongPathSafely(returnPath)
  if not returnOk then
    ctx.lastError = "Failed to return to work position after restock"
    ctx.previousState = STATE_BUILD
    currentState = STATE_ERROR
    return
  end
  
  -- Step 5: Descend back to work layer
  if ascendSteps > 0 then
    for i = 1, ascendSteps do
      if not tryDownNoDig() then
        ctx.lastError = "Failed to descend back to work layer after restock"
        ctx.previousState = STATE_BUILD
        currentState = STATE_ERROR
        return
      end
    end
  end
  
  -- Step 6: Verify we got the materials and resume
  local haveNow = countFamilyInInventory(tallyInventory(), ctx.missingBlockName)
  if haveNow > 0 then
    print("Restock successful for "..ctx.missingBlockName.." ("..haveNow.." obtained)")
    ctx.inventorySummary = tallyInventory()
    ctx.missingBlockName = nil
    currentState = ctx.previousState or STATE_BUILD
  else
    ctx.lastError = "Unable to restock material: "..ctx.missingBlockName
    currentState = STATE_ERROR
  end
end

states[STATE_REFUEL] = function(ctx)
  print("Refueling attempt...")
  
  -- RETURN-TO-ORIGIN REFUEL STRATEGY:
  -- 1. Ascend above the build height to travel safely
  -- 2. Reverse movementHistory to return to origin
  -- 3. Access the chest at origin for fuel
  -- 4. Return along the saved path to resume building
  
  -- Step 1: Ascend above the build to safe travel height
  local safeHeight = ctx.height + 2
  local ascendSteps = safeHeight - ctx.currentY
  if ascendSteps > 0 then
    print("Ascending "..ascendSteps.." blocks to safe travel height...")
    for i = 1, ascendSteps do
      if not tryUpNoDig() then
        ctx.lastError = "Failed to ascend to safe height for refuel"
        ctx.previousState = STATE_BUILD
        currentState = STATE_ERROR
        return
      end
    end
  end
  
  -- Step 2: Return to origin safely
  print("Returning to origin for refuel...")
  local returnPath = goToOriginSafely()
  
  -- Step 3: Attempt to refuel from origin chest
  local targetLevel = RESTOCK_AT * 2  -- refuel to double the threshold
  local refueled, foundChest = refuelFromOriginChest(targetLevel)
  
  -- If still low on fuel, wait/retry
  if turtle.getFuelLevel() <= RESTOCK_AT and not isFuelUnlimited() then
    if AUTO_MODE then
      print("Fuel not available at origin. Waiting "..RESTOCK_RETRY_SECONDS.."s...")
      sleep(RESTOCK_RETRY_SECONDS)
      refueled, foundChest = refuelFromOriginChest(targetLevel)
    else
      print("Load fuel into origin chest, then press Enter.")
      read()
      refueled, foundChest = refuelFromOriginChest(targetLevel)
    end
  end
  
  -- Step 4: Return to work position
  print("Returning to work position...")
  local returnOk = returnAlongPathSafely(returnPath)
  if not returnOk then
    ctx.lastError = "Failed to return to work position after refuel"
    ctx.previousState = STATE_BUILD
    currentState = STATE_ERROR
    return
  end
  
  -- Step 5: Descend back to work layer
  if ascendSteps > 0 then
    for i = 1, ascendSteps do
      if not tryDownNoDig() then
        ctx.lastError = "Failed to descend back to work layer after refuel"
        ctx.previousState = STATE_BUILD
        currentState = STATE_ERROR
        return
      end
    end
  end
  
  -- Step 6: Verify fuel level and resume
  if isFuelUnlimited() or turtle.getFuelLevel() > RESTOCK_AT then
    print("Refuel complete. Fuel level: "..tostring(turtle.getFuelLevel()))
    ctx.inventorySummary = tallyInventory()
    currentState = ctx.previousState or STATE_BUILD
  else
    ctx.lastError = "Refuel failed; insufficient fuel sources at origin"
    currentState = STATE_ERROR
  end
end

states[STATE_ERROR] = function(ctx)
  print("ERROR STATE: "..tostring(ctx.lastError))
  if AUTO_MODE then
    print("Auto-retry in "..ERROR_RETRY_SECONDS.."s (previous="..tostring(ctx.previousState)..")...")
    sleep(ERROR_RETRY_SECONDS)
  else
    print("Press Enter to attempt resume (previous state="..tostring(ctx.previousState)..")...")
    read()
  end
  if ctx.previousState then
    currentState = ctx.previousState
  else
    currentState = STATE_INITIALIZE
  end
  ctx.lastError = nil
end

-- NEW: BLOCKED STATE (non-destructive go home and return) --------------
states[STATE_BLOCKED] = function(ctx)
  print("Blocked: "..tostring(ctx.lastError or "movement obstruction"))
  -- Go to origin safely (no digging) using recorded history
  local path = goToOriginSafely()
  -- Brief wait at home to allow player/world to clear obstruction
  if AUTO_MODE then
    sleep(ERROR_RETRY_SECONDS)
  else
    print("At home. Clear the obstruction, then press Enter to resume.")
    read()
  end
  -- Return along the saved path safely
  local ok = returnAlongPathSafely(path)
  if not ok then
    ctx.lastError = "Failed to safely return to work position"
    currentState = STATE_ERROR
    return
  end
  -- Resume original state (usually BUILD)
  currentState = ctx.previousState or STATE_BUILD
  ctx.lastError = nil
end

states[STATE_DONE] = function(ctx)
  print("✅ Cell build complete.")
end

-- MAIN DISPATCH LOOP ----------------------------------------------------
while true do
  local fn = states[currentState]
  if not fn then error("Unknown state: "..tostring(currentState)) end
  fn(context)
  if currentState == STATE_DONE then break end
  sleep(0) -- yield; adjust if throttling needed
end
print("Done.")
