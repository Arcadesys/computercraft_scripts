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
-- For simplicity this version does NOT physically path back to origin mid-layer.
-- Chest/fuel access is assumed adjacent to current position. A future enhancement
-- can push movement history and compute reverse paths to the origin before restocking.
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

-- Use fully-qualified module path so we can run from anywhere
-- Require setup for flat file structure ---------------------------------
-- CC:Tweaked's require searches ROM module paths by default. We extend
-- package.path so that `require("modular_cell_manifest")` works when the
-- file sits next to this script (flat layout) or at the root.
-- Simple flat require: assume script executed from the directory containing
-- modular_cell_manifest.lua (turtle's working directory). If you need to run
-- from elsewhere, `shell.run("cd factory")` first or copy the manifest file.
local manifest = require("modular_cell_manifest")
local manifest = require("factory.modular_cell_manifest")

-- STATE NAME CONSTANTS --------------------------------------------------
local STATE_INITIALIZE = "INITIALIZE"
local STATE_BUILD      = "BUILD"
local STATE_RESTOCK    = "RESTOCK"
local STATE_REFUEL     = "REFUEL"
local STATE_ERROR      = "ERROR"
local STATE_DONE       = "DONE"

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
  local seen = {}
  for k in pairs(manifest.legend) do seen[k] = true end

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

local function selectSlotForItem(itemName)
  -- Prefer merging with an existing stack before occupying an empty slot.
  -- 1) Try same exact ID with space to merge
  for slot = 1, 15 do
    local detail = turtle.getItemDetail(slot)
    if detail and detail.name == itemName and detail.count < 64 then
      turtle.select(slot)
      return slot
    end
  end
  -- 2) Try same family (tiered variants) with space to merge
  for slot = 1, 15 do
    local detail = turtle.getItemDetail(slot)
    if detail and isSameFamily(itemName, detail.name) and detail.count < 64 then
      turtle.select(slot)
      return slot
    end
  end
  for slot = 1, 15 do
    if turtle.getItemCount(slot) == 0 then
      turtle.select(slot)
      return slot
    end
  end
  return nil
end

local function isInventoryBlock(name)
  if not name then return false end
  return name:find("chest") or name:find("barrel") or name:find("drawer") or name:find("shulker_box")
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

local function dropUnexpectedGains(gains, allowedName, dropFn)
  -- (Legacy single-allowed version retained for fuel logic.)
  local allowedSet = {[allowedName] = true}
  local multi = false
  return dropUnexpectedGainsMulti(gains, allowedSet, dropFn, multi)
end

-- New multi-allowed variant: do NOT drop items if they are also missing.
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

local function placeBlockWithRestock(blockName, pendingRequirements)
  if not blockName or blockName == AIR_BLOCK then return true end

  if not placeBlock(blockName) then
    -- Attempt a quick, non-blocking restock from adjacent storage.
    local ok = ensureMaterialsAvailable(pendingRequirements, blockName, false)
    if ok then
      if not placeBlock(blockName) then
        log("⚠ Missing "..blockName)
        return false
      end
    else
      -- Still missing; skip this spot without stalling the whole build.
      log("⚠ Skipping (missing) "..blockName)
      return false
    end
  end

  if pendingRequirements then
    pendingRequirements[blockName] = math.max((pendingRequirements[blockName] or 1) - 1, 0)
  end
  return true
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

local function resetRow(zLen)
  turnLeft(); turnLeft()
  for i=1,zLen-1 do forward() end
  turnLeft(); forward(); turnLeft()
end

-- Return-to-origin helpers using movement history -----------------------
local function performInverse(op)
  if op == 'F' then
    -- Prefer a simple back-step to avoid extra spinning on restock return.
    -- If back() is blocked (we can't dig behind), fall back to turn-around + forward.
    if turtle.back() then
      return true
    end
    -- Fallback: 180 + forward + 180 (maintains heading but looks like a spin).
    turnRight(false); turnRight(false)
    if not forward(nil, false) then return false end
    turnRight(false); turnRight(false)
    return true
  elseif op == 'U' then
    return down(nil, false)
  elseif op == 'D' then
    return up(nil, false)
  elseif op == 'R' then
    turnLeft(false); return true
  elseif op == 'L' then
    turnRight(false); return true
  end
  return false
end

local function performForward(op)
  if op == 'F' then
    return forward(nil, true)
  elseif op == 'U' then
    return up(nil, true)
  elseif op == 'D' then
    return down(nil, true)
  elseif op == 'R' then
    turnRight(true); return true
  elseif op == 'L' then
    turnLeft(true); return true
  end
  return false
end

local function goToOriginByHistory()
  if not context or not context.movementHistory then return {} end
  local path = {}
  while #context.movementHistory > 0 do
    local op = table.remove(context.movementHistory)
    table.insert(path, op)
    if not performInverse(op) then
      log("Failed to backtrack op "..tostring(op))
      break
    end
  end
  return path
end

local function returnAlongPath(path)
  for i = #path, 1, -1 do
    local op = path[i]
    if not performForward(op) then
      log("Failed to reapply op "..tostring(op))
      return false
    end
  end
  return true
end

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
  depth  = manifest.meta.size.z or manifest.meta.size.x, -- assuming square footprint if z missing
  manifestOK = false,
  lastError = nil,
  previousState = nil,
  missingBlockName = nil,
  inventorySummary = {},
  origin = {x = 0, y = 0, z = 0, facing = 0}, -- placeholder; movement system could update this
  layerCache = {}, -- cache of resolved layers
  movementHistory = {}, -- sequence of moves from origin (for return-to-origin)
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
      currentState = STATE_ERROR
      return
    end
    context.currentX = context.currentX + 1
    return
  end

  -- End of row: perform serpentine turn if more rows remain
  if context.currentZ < #layer then
    if context.currentZ % 2 == 1 then
      turnRight(); if not forward() then context.lastError = "Blocked during serpentine (right)"; context.previousState = currentState; currentState = STATE_ERROR; return end; turnRight()
    else
      turnLeft();  if not forward() then context.lastError = "Blocked during serpentine (left)";  context.previousState = currentState; currentState = STATE_ERROR; return end; turnLeft()
    end
    context.currentZ = context.currentZ + 1
    context.currentX = 1
    return
  end

  -- End of layer: return to origin, ascend
  if (#layer % 2 == 0) then
    turnRight(); for i=1,#layer-1 do if not forward() then context.lastError = "Return-to-origin failed (even rows)"; context.previousState = currentState; currentState = STATE_ERROR; return end end; turnRight()
  else
    turnLeft();  for i=1,#layer-1 do if not forward() then context.lastError = "Return-to-origin failed (odd rows)"; context.previousState = currentState; currentState = STATE_ERROR; return end end; turnLeft()
  end
  if not up() then
    context.lastError = "Unable to ascend to next layer"
    context.previousState = currentState
    currentState = STATE_ERROR
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
  if not placed then
    -- quick opportunistic restock (non-blocking)
    local ok = ensureMaterialsAvailable(context.remainingMaterials, blockName, false)
    if ok then
      placed = placeBlock(blockName)
    end
  end
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
  print("Initializing builder for "..ctx.manifest.meta.name)
  ctx.manifestOK = validateManifest()
  if not ctx.manifestOK then
    log("Manifest issues detected; continuing but placement accuracy may suffer.")
  end
  -- Detect at least one adjacent storage (chest/barrel/etc.) so RESTOCK/REFUEL can succeed.
  local function detectAnyAdjacentStorage()
    local function noop() end
    local function turnAround() turtle.turnRight(); turtle.turnRight() end
    local dirs = {
      {prep=noop, clean=noop,       inspect=turtle.inspect},
      {prep=turtle.turnRight, clean=turtle.turnLeft, inspect=turtle.inspect},
      {prep=turnAround,      clean=turnAround,      inspect=turtle.inspect},
      {prep=turtle.turnLeft,  clean=turtle.turnRight, inspect=turtle.inspect},
      {prep=noop, clean=noop,       inspect=turtle.inspectUp},
      {prep=noop, clean=noop,       inspect=turtle.inspectDown},
    }
    for _,d in ipairs(dirs) do
      d.prep()
      local ok, data = d.inspect()
      d.clean()
      if ok and data and isInventoryBlock(data.name) then return true end
    end
    return false
  end
  if isFuelUnlimited() then
    print("Fuel: unlimited")
  else
    print("Fuel level at start: "..tostring(turtle.getFuelLevel()).." (threshold="..RESTOCK_AT..")")
    if turtle.getFuelLevel() <= RESTOCK_AT then refuel() end
  end
  ctx.remainingMaterials = cloneTable(MATERIAL_REQUIREMENTS)
  ctx.inventorySummary = tallyInventory()
  -- Optional up-front chest presence check per spec
  if not detectAnyAdjacentStorage() and not PRELOAD_MATERIALS then
    if AUTO_MODE then
      log("Warning: No adjacent storage detected; RESTOCK/REFUEL may be impossible. Proceeding in AUTO_MODE.")
    else
      ctx.lastError = "No adjacent storage detected; RESTOCK/REFUEL may be impossible"
      ctx.previousState = STATE_INITIALIZE
      currentState = STATE_ERROR
      return
    end
  end
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

  -- NEW: Step up into known-safe air lane before moving horizontally, to avoid damaging the current layer.
  local steppedUpFromWork = tryUpNoDig()

  -- Non-serpentine service storage seek: ascend then minimal outward search.
  local serviceMoves = findServiceStorageNonSerpentine(ctx)
  local droppedToChestHeight = false -- reserved if future logic wants vertical adjustment
  -- Bulk restock strategy: acquire baseline stacks of ALL needed items, then prioritize the most requested one.
  local function restockBaselineAndPriority(targetBlock)
    local function countFreeSlots()
      local free = 0
      for slot=1,15 do if turtle.getItemCount(slot) == 0 then free = free + 1 end end
      return free
    end
    local function inventoryTotals() return tallyInventory() end

    local inv = inventoryTotals()
    -- Build table of baseline deficits (up to one stack per item)
    local baselineMissing = {}
    for item, remain in pairs(ctx.remainingMaterials) do
      if remain and remain > 0 then
        local have = countFamilyInInventory(inv, item)
        if have < math.min(64, remain) then
          local want = math.min(64 - have, remain)
          if want > 0 then baselineMissing[item] = want end
        end
      end
    end

    -- Perform limited passes attempting to pull baseline stacks.
    local pass = 1
    while pass <= RESTOCK_MAX_BASELINE_PASSES and next(baselineMissing) ~= nil do
      attemptChestRestock(baselineMissing, ctx.remainingMaterials)
      inv = inventoryTotals()
      -- Recompute remaining baseline deficits
      local stillMissing = {}
      for item, _ in pairs(baselineMissing) do
        local remain = ctx.remainingMaterials[item]
        if remain and remain > 0 then
          local have = countFamilyInInventory(inv, item)
            if have < math.min(64, remain) then
              local want = math.min(64 - have, remain)
              if want > 0 then stillMissing[item] = want end
            end
        end
      end
      baselineMissing = stillMissing
      pass = pass + 1
    end

    -- Determine priority item (largest remaining requirement)
    local priorityItem, maxRemain = nil, -1
    for item, remain in pairs(ctx.remainingMaterials) do
      if remain and remain > maxRemain and remain > 0 then
        priorityItem, maxRemain = item, remain
      end
    end
    if priorityItem then
      local have = countFamilyInInventory(inv, priorityItem)
      local freeSlots = countFreeSlots()
      -- If we already have at least one stack, try to pull extra stacks (up to configured limit & remaining requirement)
      local remainingNeeded = math.max(ctx.remainingMaterials[priorityItem] - have, 0)
      if remainingNeeded > 0 and freeSlots > 0 then
        -- Request up to EXTRA_STACKS full stacks (each 64) or remaining requirement or slot capacity.
        local maxExtra = RESTOCK_PRIORITY_EXTRA_STACKS * 64
        local capacity = freeSlots * 64
        local want = math.min(remainingNeeded, maxExtra, capacity)
        if want > 0 then
          local priorityMissing = {[priorityItem] = want}
          attemptChestRestock(priorityMissing, ctx.remainingMaterials)
        end
      end
    end
    -- Success criteria: we obtained at least one of the targetBlock family.
    local haveTarget = targetBlock and countFamilyInInventory(inventoryTotals(), targetBlock) or 0
    return (haveTarget or 0) > 0
  end

  local ok = restockBaselineAndPriority(ctx.missingBlockName)
  -- Fallback: if target block still missing, enter blocking single-item acquisition loop.
  if not ok then
    ok = ensureMaterialsAvailable(ctx.remainingMaterials, ctx.missingBlockName, true)
  end
  if ok then
    -- Double-check we actually have at least one of the requested family now;
    -- this guards against any false positives from requirement tables.
    local haveNow = countFamilyInInventory(tallyInventory(), ctx.missingBlockName)
    if haveNow > 0 then
      print("Restock successful for "..ctx.missingBlockName)
      ctx.inventorySummary = tallyInventory()
      ctx.missingBlockName = nil
      -- Before returning, if we descended at origin for chest access, step back up to the safe lane.
      if droppedToChestHeight then tryUpNoDig() end
      -- Reverse outward service moves (horizontal) instead of serpentine history replay.
      reverseServiceMoves(serviceMoves)
      -- Finally, if we stepped up at the start, return to the work layer without digging.
      if steppedUpFromWork then tryDownNoDig() end
      currentState = ctx.previousState or STATE_BUILD
    else
      print("Restock reported success, but item still missing. Load materials and press Enter to retry.")
      read()
      -- Stay in RESTOCK; do not clear missingBlockName so we retry
      return
    end
  else
    ctx.lastError = "Unable to restock material: "..ctx.missingBlockName
    currentState = STATE_ERROR
  end
end

states[STATE_REFUEL] = function(ctx)
  print("Refueling attempt...")
  -- Step up into known-safe air lane.
  local steppedUp = tryUpNoDig()
  -- Seek storage outward minimally (non-serpentine) then refuel.
  local serviceMoves = findServiceStorageNonSerpentine(ctx)
  refuel()
  -- Reverse horizontal service travel.
  reverseServiceMoves(serviceMoves)
  if steppedUp then tryDownNoDig() end
  if isFuelUnlimited() or turtle.getFuelLevel() > RESTOCK_AT then
    print("Refuel complete. Fuel level: "..tostring(turtle.getFuelLevel()))
    ctx.inventorySummary = tallyInventory()
    currentState = ctx.previousState or STATE_BUILD
  else
    ctx.lastError = "Refuel failed; insufficient fuel sources"
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
