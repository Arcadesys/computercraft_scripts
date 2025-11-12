-- factoryrefactor.lua - PSEUDOCODE BREAKDOWN
-- ============================================================================
-- This file contains a high-level pseudocode breakdown of factorybuilder.lua
-- to guide refactoring efforts. Each section outlines the purpose, inputs,
-- outputs, and logic flow without implementation details.
-- ============================================================================

--[[
OVERVIEW:
- Material restocking from origin chest
- Fuel management
- Error recovery
- Return-to-origin for service tasks

KEY DESIGN PATTERNS:
1. STATE MACHINE: Each state is a function that transitions to other states
2. CONTEXT: Shared state object passed between all states
3. MOVEMENT HISTORY: Records path for return-to-origin
4. ITEM FAMILIES: Treats tiered items (basic/advanced/elite) as equivalent
5. NON-DESTRUCTIVE SERVICE: Ascends above build for safe travel back to origin
6. UNIFIED SERVICE STATE: RESTOCK and REFUEL use same return-to-origin logic

-- ============================================================================
-- SECTION 1: CONFIGURATION & CONSTANTS
-- ============================================================================
--[[
PSEUDOCODE:
  DEFINE STATE constants (INITIALIZE, BUILD, SERVICE, ERROR, BLOCKED, DONE)
  DEFINE OPERATING constants
    - REFUEL_SLOT (default 16)
    - FUEL_THRESHOLD (trigger level)
    - MAX_PULL_ATTEMPTS (service chest pulls)
    - SAFETY_MAX_MOVE_RETRIES (movement retries)
    - FUEL_ALLOWED_SET (set of acceptable fuel item names)
  LOAD manifest from disk
    - Prefer factory/ subdirectory first
    - Fallback to current directory
    - Manifest provides layers, legend, meta size/name
  VALIDATE manifest structure
  PRECOMPUTE MATERIAL_REQUIREMENTS via collectRequiredMaterials()
  INITIALIZE context defaults (position indices, movement history, chestDirection=nil)
]]

-- 2.1 LOGGING & DEBUG
--[[
FUNCTION log(message)
  IF VERBOSE enabled THEN
    PRINT "[DEBUG] " + message
  END
END
]]

-- 2.2 TABLE OPERATIONS
--[[
FUNCTION cloneTable(source)
  newTable = empty table
  FOR each key, value in source DO
    newTable[key] = value
  END
  RETURN newTable
END

FUNCTION sortedKeys(source)
  keys = empty array
  FOR each key in source DO
    APPEND key to keys
  END
  SORT keys alphabetically
  RETURN keys
END

FUNCTION buildAllowedSet(sourceTable)
  allowed = empty table
  FOR each key in sourceTable DO
    allowed[key] = true
  END
  RETURN allowed
END
]]

-- 2.3 ITEM FAMILY HELPERS
--[[
FUNCTION countFamilyInInventory(inventory, targetName)
  IF inventory is nil THEN
    inventory = tallyInventory()
  END
  total = 0
  FOR each item in inventory DO
    IF item belongs to same family as targetName THEN
      total = total + item.count
    END
  END
  RETURN total
END

FUNCTION itemsShareFamily(nameA, nameB)
  LOOKUP family for nameA and nameB in ITEM_FAMILY_MAP
  RETURN familyA == familyB
END
]]

-- 2.4 MANIFEST HELPERS
--[[
FUNCTION collectRequiredMaterials(manifest)
  requirements = empty table
  FOR each layer in manifest.layers DO
    FOR each row in layer DO
      FOR each symbol in row DO
        blockName = manifest.legend[symbol]
        IF blockName is not air THEN
          requirements[blockName] = (requirements[blockName] or 0) + 1
        END
      END
    END
  END
  RETURN requirements
END

FUNCTION validateManifest(manifest)
  FOR each layer in manifest.layers DO
    ASSERT layer is table
    FOR each row in layer DO
      ASSERT row length matches manifest.meta.size.x
      FOR each symbol in row DO
        ASSERT manifest.legend[symbol] exists
      END
    END
  END
  RETURN true
END
]]

-- 2.5 INVENTORY MANAGEMENT
--[[
FUNCTION tallyInventory()
  inventory = empty table
  FOR slot 1 to 16
    GET item detail for slot
    IF slot has item THEN
      ADD item.count to inventory[item.name]
    END
  END
  RETURN inventory
END

FUNCTION snapshotInventory()
  RETURN tallyInventory()
END

FUNCTION diffGains(beforeSnapshot, afterSnapshot)
  gains = empty table
  FOR each item in afterSnapshot
    delta = afterSnapshot[item] - beforeSnapshot[item]
    IF delta > 0 THEN
      gains[item] = delta
    END
  END
  RETURN gains
END

FUNCTION countFamilyGains(beforeSnapshot, afterSnapshot, targetName)
  gains = diffGains(beforeSnapshot, afterSnapshot)
  total = 0
  FOR each itemName, gainedCount in gains
    IF itemName is in same family as targetName THEN
      total = total + gainedCount
    END
  END
  RETURN total
END

FUNCTION dropUnexpectedGainsMulti(gains, allowedSet, dropFunction)
  FOR each item in gains
    IF item not in allowedSet (considering families) THEN
      FIND slots containing item
      DROP item back using dropFunction
    END
  END
END

FUNCTION selectSlotForItem(itemName)
  // Prefer merging with existing stack
  FOR slot 1 to 15
    IF slot has same item with space THEN
      SELECT slot
      RETURN slot
    END
  END
  // Then try family equivalents
  FOR slot 1 to 15
    IF slot has same family with space THEN
      SELECT slot
      RETURN slot
    END
  END
  // Finally use empty slot
  FOR slot 1 to 15
    IF slot is empty THEN
      SELECT slot
      RETURN slot
    END
  END
  RETURN nil (inventory full)
END
]]

-- 2.6 SERVICE PULL HELPERS
--[[
FUNCTION pullAndFilterItems(chestFunctions, allowedSet, maxAttempts)
  beforeSnapshot = snapshotInventory()
  attempts = 0
  pulledAnything = false
  WHILE attempts < maxAttempts DO
    success = chestFunctions.suck()
    IF not success THEN BREAK END
    pulledAnything = true
    attempts = attempts + 1
  END
  IF not pulledAnything THEN RETURN false END
  gains = diffGains(beforeSnapshot, snapshotInventory())
  dropUnexpectedGainsMulti(gains, allowedSet, chestFunctions.drop)
  RETURN true
END

FUNCTION restockItems(missingTable, allowedUniverse, chestFunctions, maxAttempts)
  allowedSet = buildAllowedSet(allowedUniverse)
  pulledSomething = false
  FOR each itemName, deficit IN missingTable DO
    remaining = deficit
    attempts = 0
    WHILE remaining > 0 AND attempts < maxAttempts DO
      beforeSnapshot = snapshotInventory()
      IF NOT chestFunctions.suck() THEN BREAK END
      gained = countFamilyGains(beforeSnapshot, snapshotInventory(), itemName)
      remaining = remaining - gained
      attempts = attempts + 1
      IF gained > 0 THEN pulledSomething = true END
      gains = diffGains(beforeSnapshot, snapshotInventory())
      dropUnexpectedGainsMulti(gains, allowedSet, chestFunctions.drop)
    END
    missingTable[itemName] = remaining
  END
  RETURN pulledSomething
END
]]

-- 2.7 GENERIC FLOW HELPERS
--[[
FUNCTION retryOperation(operationFunc, successCheckFunc, waitLabel)
  WHILE true DO
    operationFunc()
    IF successCheckFunc() THEN RETURN true END
    IF AUTO_MODE THEN
      PRINT waitLabel .. " (auto retry)"
      SLEEP retry_seconds
    ELSE
      PRINT waitLabel .. " (press Enter to retry)"
      READ user input
    END
  END
END

FUNCTION transitionToState(context, newState, errorMessage, previousState)
  IF errorMessage THEN
    context.lastError = errorMessage
  END
  IF previousState THEN
    context.previousState = previousState
  END
  context.currentState = newState
  RETURN
END
]]

-- 2.8 STORAGE DETECTION
--[[
FUNCTION isInventoryBlock(blockName)
  RETURN true if name contains "chest", "barrel", "drawer", or "shulker_box"
END

FUNCTION isTreasureChestId(blockId)
  IF blockId matches known treasure chest patterns THEN RETURN true
  IF blockId contains both "treasure" and "chest" THEN RETURN true
  IF not strict mode AND blockId is any chest THEN RETURN true
  RETURN false
END

FUNCTION checkTreasureChestBehind()
  TURN around (180 degrees)
  INSPECT block ahead
  TURN back around (180 degrees)
  CHECK if block is treasure chest
  RETURN (isTreasureChest, blockId, blockData)
END

FUNCTION findAdjacentStorageDirection()
  FOR each direction (front, right, behind, left, up, down)
    ORIENT to face direction
    INSPECT block
    RESTORE orientation
    IF block is inventory THEN
      RETURN direction label
    END
  END
  RETURN nil (no storage found)
END
]]

-- ============================================================================
-- SECTION 3: FUEL MANAGEMENT
-- ============================================================================
--[[
FUNCTION isFuelUnlimited()
  IF fuel limit is "unlimited" or infinity THEN
    RETURN true
  END
  RETURN false
END

FUNCTION tryRefuelFromSlot(slotNumber, targetLevel)
  IF fuel is unlimited THEN RETURN true
  SELECT slot
  WHILE can refuel from slot AND fuel < target
    CONSUME one item for fuel
  END
  RETURN true if consumed any fuel
END

FUNCTION refuel()
  IF fuel is unlimited THEN RETURN
  IF fuel > threshold THEN RETURN
  
  // Try slot 16 first
  IF tryRefuelFromSlot(16, threshold) THEN
    RETURN
  END
  
  // Try all other slots
  FOR each slot 1 to 15
    IF tryRefuelFromSlot(slot, threshold) THEN
      RETURN
    END
  END
  
  // Try pulling from adjacent storage
  pulled, _ = attemptFuelRestock(threshold)
  IF pulled THEN
    LOG "Refueled from nearby storage"
  ELSE
    LOG "Fuel low and no sources available"
  END
END

FUNCTION attemptFuelRestock(targetLevel)
  pulledFuel = false
  foundContainer = false
  
  FOR each direction (front, right, behind, left, up, down)
    IF turtle.getFuelLevel() >= targetLevel THEN BREAK
    chestFunctions = getPeripheralFunctions(direction)
    IF chestFunctions.inspect() reports storage THEN
      foundContainer = true
      IF pullAndFilterItems(chestFunctions, FUEL_ALLOWED_SET, MAX_PULL_ATTEMPTS) THEN
        tryRefuelFromSlot(16, targetLevel)
        FOR slot 1 to 15 DO tryRefuelFromSlot(slot, targetLevel) END
  IF turtle.getFuelLevel() >= targetLevel THEN pulledFuel = true END
      END
    END
  END
  
  RETURN (pulledFuel, foundContainer)
END

FUNCTION refuelFromOriginChest(targetLevel)
  chestFunctions = getChestAccessFunctions()
  IF NOT chestFunctions.inspect() THEN RETURN (false, false)
  IF NOT pullAndFilterItems(chestFunctions, FUEL_ALLOWED_SET, MAX_PULL_ATTEMPTS) THEN
    RETURN (false, true)
  END
  tryRefuelFromSlot(16, targetLevel)
  FOR slot 1 to 15 DO tryRefuelFromSlot(slot, targetLevel) END
  refueled = turtle.getFuelLevel() >= targetLevel OR isFuelUnlimited()
  RETURN (refueled, true)
END
]]

-- ============================================================================
-- SECTION 4: MATERIAL RESTOCKING
-- ============================================================================
--[[
FUNCTION attemptChestRestock(missingTable, allowedUniverse)
  pulledSomething = false
  foundContainer = false
  
  FOR each direction (front, right, behind, left, up, down)
    chestFunctions = getPeripheralFunctions(direction)
    IF chestFunctions.inspect() reports storage THEN
      foundContainer = true
      IF restockItems(missingTable, allowedUniverse, chestFunctions, MAX_PULL_ATTEMPTS) THEN
        pulledSomething = true
      END
    END
  END

  RETURN (pulledSomething, foundContainer)
END
FUNCTION restockFromOriginChest(missingTable, allowedUniverse)
  chestFunctions = getChestAccessFunctions()
  IF NOT chestFunctions.inspect() THEN RETURN (false, false)
  pulled = restockItems(missingTable, allowedUniverse, chestFunctions, MAX_PULL_ATTEMPTS)
  RETURN (pulled, true)
END

FUNCTION ensureMaterialsAvailable(requirements, targetBlock, blocking)
  WHILE true
    SNAPSHOT current inventory
    missing = empty table
    hasAll = true
    
    IF checking specific block THEN
      available = countFamilyInInventory(targetBlock)
      IF available < 1 THEN
        missing[targetBlock] = 1
        hasAll = false
      END
    ELSE
      FOR each required block
        available = countFamilyInInventory(block)
        IF available < required THEN
          missing[block] = required - available
          hasAll = false
        END
      END
    END
    
    IF hasAll THEN RETURN true
    
    // Try pulling from nearby storage
    pulled, foundContainer = attemptChestRestock(missing, requirements)
    
    IF pulled THEN
      LOG "Pulled materials from storage"
      CONTINUE (loop to recheck)
    END
    
    IF not blocking THEN
      RETURN false  // Let caller continue
    END
    
    // Blocking mode
    IF AUTO_MODE THEN
      WAIT retry_seconds
      CONTINUE
    ELSE
      PROMPT user to load materials
      WAIT for enter key
      CONTINUE
    END
  END
END
]]

-- ============================================================================
-- SECTION 5: MOVEMENT & NAVIGATION
-- ============================================================================
--[[
FUNCTION recordMove(operation)
  IF context.movementHistory exists THEN
    APPEND operation to movementHistory
  END
END

FUNCTION move(direction, maxRetries, recordHistory)
  directionConfig = {
    forward = {move = turtle.forward, attack = turtle.attack, dig = turtle.dig, symbol = 'F'},
    back    = {move = turtle.back,    attack = turtle.attack, dig = turtle.dig, symbol = 'B'},
    up      = {move = turtle.up,      attack = turtle.attackUp, dig = turtle.digUp, symbol = 'U'},
    down    = {move = turtle.down,    attack = turtle.attackDown, dig = turtle.digDown, symbol = 'D'}
  }

  config = directionConfig[direction]
  IF config is nil THEN
    ERROR "Unknown move direction"
    RETURN false
  END

  tries = 0
  WHILE tries < maxRetries DO
    REFUEL if needed
    IF config.move() succeeds THEN
      IF recordHistory THEN recordMove(config.symbol) END
      RETURN true
    END
    config.attack()
    config.dig()
    SLEEP short interval
    tries = tries + 1
    IF turtle.getFuelLevel() == 0 THEN
      LOG "Move failed: out of fuel"
      RETURN false
    END
  END

  LOG "Move blocked after " .. tries .. " attempts"
  RETURN false
END

FUNCTION turn(direction, recordHistory)
  IF direction == "right" THEN
    turtle.turnRight()
    IF recordHistory THEN recordMove('R') END
    RETURN true
  ELSEIF direction == "left" THEN
    turtle.turnLeft()
    IF recordHistory THEN recordMove('L') END
    RETURN true
  ELSEIF direction == "around" THEN
    turtle.turnLeft()
    turtle.turnLeft()
    IF recordHistory THEN
      recordMove('L')
      recordMove('L')
    END
    RETURN true
  END

  ERROR "Unknown turn direction"
  RETURN false
END
]]

-- 5.1 SAFE (NON-DESTRUCTIVE) MOVEMENT
--[[
FUNCTION trySafeMove(direction)
  IF direction == "forward" THEN RETURN turtle.forward() END
  IF direction == "back" THEN RETURN turtle.back() END
  IF direction == "up" THEN RETURN turtle.up() END
  IF direction == "down" THEN RETURN turtle.down() END
  ERROR "Unknown safe move direction"
  RETURN false
END

FUNCTION safeWaitMove(movementFunction, label)
  WHILE true
    IF movementFunction() THEN RETURN true
    IF AUTO_MODE THEN
      WAIT 1 second
    ELSE
      PROMPT user to clear path
    END
  END
END

FUNCTION safePerformInverse(operation)
  // Reverse a recorded move without digging
  IF operation is 'F' THEN safeWaitMove(function() RETURN trySafeMove("back") END, "Moving back")
  ELSE IF operation is 'B' THEN safeWaitMove(function() RETURN trySafeMove("forward") END, "Moving forward")
  ELSE IF operation is 'U' THEN safeWaitMove(function() RETURN trySafeMove("down") END, "Moving down")
  ELSE IF operation is 'D' THEN safeWaitMove(function() RETURN trySafeMove("up") END, "Moving up")
  ELSE IF operation is 'R' THEN turn("left", false)
  ELSE IF operation is 'L' THEN turn("right", false)
  RETURN success
END

FUNCTION safePerformForward(operation)
  // Replay a recorded move without digging
  IF operation is 'F' THEN safeWaitMove(function() RETURN trySafeMove("forward") END, "Moving forward")
  ELSE IF operation is 'B' THEN safeWaitMove(function() RETURN trySafeMove("back") END, "Moving back")
  ELSE IF operation is 'U' THEN safeWaitMove(function() RETURN trySafeMove("up") END, "Moving up")
  ELSE IF operation is 'D' THEN safeWaitMove(function() RETURN trySafeMove("down") END, "Moving down")
  ELSE IF operation is 'R' THEN turn("right", false)
  ELSE IF operation is 'L' THEN turn("left", false)
  RETURN success
END

FUNCTION goToOriginSafely()
  savedPath = empty array
  WHILE movementHistory is not empty
    operation = POP from movementHistory
    APPEND operation to savedPath
    PERFORM inverse of operation safely
  END
  RETURN savedPath
END

FUNCTION returnAlongPathSafely(savedPath)
  FOR each operation in savedPath (reverse order)
    PERFORM operation forward safely
  END
  RESTORE movementHistory from savedPath
  RETURN success
END
]]

-- ============================================================================
-- SECTION 6: BLOCK PLACEMENT
-- ============================================================================
--[[
FUNCTION placeBlock(blockName)
  IF blockName is air or nil THEN RETURN true
  
  // Check if target already exists
  INSPECT down
  IF block below matches target family THEN
    LOG "Target already present"
    RETURN true
  END
  
  // Find item in inventory (check all 16 slots)
  FOR slot 1 to 16
    GET item detail
    IF item matches target family THEN
      SELECT slot
      IF turtle.placeDown() succeeds THEN
        RETURN true
      END
      // Try digging obstruction
      DIG down
      RETURN turtle.placeDown()
    END
  END
  
  RETURN false (not found in inventory)
END

FUNCTION attemptPlaceCurrent(blockName)
  IF blockName is air THEN RETURN true
  
  placed = placeBlock(blockName)
  IF placed THEN
    DECREMENT context.remainingMaterials[blockName]
  END
  RETURN placed
END
]]

-- ============================================================================
-- SECTION 7: BUILD CURSOR & NAVIGATION
-- ============================================================================
--[[
FUNCTION getLayer(yIndex)
  IF layer not in cache THEN
    CACHE layer = fetchLayer(yIndex)
  END
  RETURN cached layer
END

FUNCTION getSerpentineX(rowIndex, cursorX, rowLength)
  IF rowIndex is odd THEN
    RETURN cursorX
  ELSE
    RETURN rowLength - (cursorX - 1)
  END
END

FUNCTION getCurrentBlock()
  GET current layer
  GET current row from layer[Z]
  rowLength = length of current row
  
  // Handle serpentine traversal
  xIndex = getSerpentineX(currentZ, currentX, rowLength)
  
  GET symbol at position
  GET blockName from legend[symbol]
  RETURN blockName
END

FUNCTION advanceCursorAfterPlacement(context)
  GET current layer
  rowLength = length of first row
  
  // Advance along X within row
  IF currentX < rowLength THEN
    IF NOT move("forward", SAFETY_MAX_MOVE_RETRIES, true) THEN
      transitionToState(context, STATE_BLOCKED, "Blocked while traversing row", STATE_BUILD)
      RETURN
    END
    INCREMENT currentX
    RETURN
  END
  
  // End of row: perform serpentine turn
  IF currentZ < number of rows THEN
    turnDirection = (row is odd) ? "right" : "left"
    IF NOT turn(turnDirection, true) THEN
      transitionToState(context, STATE_BLOCKED, "Failed to pivot at row edge", STATE_BUILD)
      RETURN
    END
    IF NOT move("forward", SAFETY_MAX_MOVE_RETRIES, true) THEN
      transitionToState(context, STATE_BLOCKED, "Blocked during serpentine advance", STATE_BUILD)
      RETURN
    END
    IF NOT turn(turnDirection, true) THEN
      transitionToState(context, STATE_BLOCKED, "Failed to reorient after serpentine move", STATE_BUILD)
      RETURN
    END
    INCREMENT currentZ
    RESET currentX = 1
    RETURN
  END
  
  // End of layer: return to origin edge and ascend
  perimeterTurn = (layer has even number of rows) and "right" or "left"
  IF NOT turn(perimeterTurn, true) THEN
    transitionToState(context, STATE_BLOCKED, "Failed to align for layer ascent", STATE_BUILD)
    RETURN
  END
  FOR step 1 to (depth - 1)
    IF NOT move("forward", SAFETY_MAX_MOVE_RETRIES, true) THEN
      transitionToState(context, STATE_BLOCKED, "Blocked while exiting layer", STATE_BUILD)
      RETURN
    END
  END
  IF NOT turn(perimeterTurn, true) THEN
    transitionToState(context, STATE_BLOCKED, "Failed to reset orientation after exit", STATE_BUILD)
    RETURN
  END
  
  IF NOT move("up", SAFETY_MAX_MOVE_RETRIES, true) THEN
    transitionToState(context, STATE_BLOCKED, "Unable to ascend to next layer", STATE_BUILD)
    RETURN
  END
  
  INCREMENT currentY
  RESET currentZ = 1
  RESET currentX = 1
END
]]

-- ============================================================================
-- SECTION 8: CHEST ACCESS AT ORIGIN
-- ============================================================================
--[[
FUNCTION orientToChest()
  direction = context.chestDirection
  IF direction is "front" THEN already facing
  ELSE IF direction is "right" THEN turn("right", true)
  ELSE IF direction is "behind" THEN turn("around", true)
  ELSE IF direction is "left" THEN turn("left", true)
  ELSE IF direction is "up" or "down" THEN no rotation needed
  RETURN success
END

FUNCTION getPeripheralFunctions(direction)
  IF direction == "up" THEN
    RETURN {inspect=turtle.inspectUp, suck=turtle.suckUp, drop=turtle.dropUp, label="up"}
  ELSEIF direction == "down" THEN
    RETURN {inspect=turtle.inspectDown, suck=turtle.suckDown, drop=turtle.dropDown, label="down"}
  ELSEIF direction == "front" THEN
    RETURN {inspect=turtle.inspect, suck=turtle.suck, drop=turtle.drop, label="front"}
  ELSEIF direction == "right" THEN
    RETURN wrappers that turn right, perform turtle.inspect/suck/drop, then turn left
  ELSEIF direction == "behind" THEN
    RETURN wrappers that turn around, perform turtle.inspect/suck/drop, then turn back
  ELSEIF direction == "left" THEN
    RETURN wrappers that turn left, perform turtle.inspect/suck/drop, then turn right
  END
  RETURN {inspect=function() RETURN false END, suck=function() RETURN false END, drop=function() RETURN false END, label="unknown"}
END

FUNCTION getChestAccessFunctions()
  direction = context.chestDirection
  IF direction is nil THEN RETURN getPeripheralFunctions("front")
  IF direction is one of ("up", "down") THEN RETURN getPeripheralFunctions(direction)
  orientToChest()
  RETURN getPeripheralFunctions(direction)
END
]]

-- ============================================================================
-- SECTION 9: STATE MACHINE CONTEXT
-- ============================================================================
--[[
STRUCTURE context:
  manifest: loaded manifest table
  remainingMaterials: table of block counts still to place
  currentY, currentZ, currentX: position indices (1-based)
  width, height, depth: cached dimensions from manifest.meta.size
  manifestOK: boolean validation result
  lastError: string describing last error
  previousState: state to return to after error
  serviceRequest: {type, materialName, fuelTarget} for unified SERVICE state
  inventorySummary: cached inventory snapshot
  layerCache: table of resolved layers
  movementHistory: array of move operations from origin
  chestDirection: string direction to chest ("front", "right", etc.)
END

NOTE: serviceRequest replaces missingBlockName, making the system more flexible
]]

-- ============================================================================
-- SECTION 10: STATE MACHINE IMPLEMENTATION
-- ============================================================================

-- 10.1 UNIFIED SERVICE STATE (REPLACES RESTOCK + REFUEL)
--[[
INSIGHT: Both restocking materials and refueling follow the EXACT same pattern.
The only difference is WHAT we request from the chest.

STRUCTURE ServiceRequest:
  type: "material" or "fuel"
  materialName: (if type is "material") name of block needed
  fuelTarget: (if type is "fuel") desired fuel level
END

FUNCTION states.SERVICE(context)
  serviceRequest = context.serviceRequest
  IF serviceRequest is nil THEN
    transitionToState(context, STATE_ERROR, "SERVICE invoked without request", context.previousState)
    RETURN
  END

  IF serviceRequest.type == "material" THEN
    PRINT "Restocking: " .. serviceRequest.materialName
  ELSEIF serviceRequest.type == "fuel" THEN
    PRINT "Refueling to level: " .. serviceRequest.fuelTarget
  ELSE
    transitionToState(context, STATE_ERROR, "Unknown service type: " .. tostring(serviceRequest.type), context.previousState)
    RETURN
  END

  safeHeight = context.height + 2
  ascendSteps = safeHeight - context.currentY
  IF ascendSteps < 0 THEN ascendSteps = 0 END
  FOR step 1 to ascendSteps DO
    safeWaitMove(function() RETURN trySafeMove("up") END, "Rising to service corridor")
  END

  returnPath = goToOriginSafely()

  IF serviceRequest.type == "material" THEN
    missing = {[serviceRequest.materialName] = serviceRequest.requestedCount or 1}
    performService = FUNCTION()
      restockFromOriginChest(missing, context.remainingMaterials)
    END
    successCheck = FUNCTION()
      RETURN missing[serviceRequest.materialName] == 0
    END
    retryLabel = "Awaiting material restock"
  ELSE
    performService = FUNCTION()
      refuelFromOriginChest(serviceRequest.fuelTarget)
    END
    successCheck = FUNCTION()
      RETURN isFuelUnlimited() OR turtle.getFuelLevel() >= serviceRequest.fuelTarget
    END
    retryLabel = "Awaiting fuel at origin"
  END

  retryOperation(performService, successCheck, retryLabel)

  returnOk = returnAlongPathSafely(returnPath)
  IF NOT returnOk THEN
    transitionToState(context, STATE_ERROR, "Failed to return from service", STATE_SERVICE)
    RETURN
  END

  FOR step 1 to ascendSteps DO
    safeWaitMove(function() RETURN trySafeMove("down") END, "Descending from service corridor")
  END

  IF NOT successCheck() THEN
    transitionToState(context, STATE_ERROR, "Service verification failed", STATE_SERVICE)
    RETURN
  END

  context.serviceRequest = nil
  resumeState = context.previousState or STATE_BUILD
  transitionToState(context, resumeState, nil, nil)
END
]]

-- STATE: INITIALIZE
--[[
FUNCTION states.INITIALIZE(context)
  // Verify treasure chest is behind turtle
  CHECK treasure chest behind
  IF not found THEN
    ERROR "Treasure chest required behind"
  END
  
  PRINT "Initializing builder"
  VALIDATE manifest
  
  // Find and remember chest direction
  chestDirection = findAdjacentStorageDirection()
  IF no chest found THEN
    IF AUTO_MODE THEN
      LOG warning
    ELSE
      TRANSITION to ERROR
      RETURN
    END
  END
  
  // Check fuel
  IF fuel not unlimited THEN
    PRINT fuel level
    IF fuel low THEN REFUEL
  END
  
  // Clone material requirements
  remainingMaterials = clone(MATERIAL_REQUIREMENTS)
  
  // Preload materials if configured
  IF PRELOAD_MATERIALS THEN
    PROMPT user for materials
    FOR each required material
      ENSURE material available (blocking)
    END
  ELSE
    PRINT "On-demand restock active"
  END
  
  TRANSITION to STATE_BUILD
END
]]

-- STATE: BUILD
--[[
FUNCTION states.BUILD(context)
  // Check completion
  IF currentY > height THEN
    TRANSITION to STATE_DONE
    RETURN
  END
  
  // Check fuel (UNIFIED SERVICE)
  IF fuel not unlimited AND fuel < threshold THEN
    SAVE previousState = BUILD
    SET serviceRequest = {type = "fuel", fuelTarget = threshold * 2}
    TRANSITION to STATE_SERVICE
    RETURN
  END
  
  // Get block to place
  blockName = getCurrentBlock()
  
  // PROACTIVE RESTOCK CHECK (UNIFIED SERVICE)
  IF blockName is not air THEN
    haveCount = countFamilyInInventory(blockName)
    stillNeeded = remainingMaterials[blockName] > 0
    IF haveCount is 0 AND stillNeeded THEN
      SAVE previousState = BUILD
      SET serviceRequest = {type = "material", materialName = blockName}
      LOG "Proactive restock"
      TRANSITION to STATE_SERVICE
      RETURN
    END
  END
  
  // Attempt placement
  LOG "Placing Y Z X : blockName"
  placed = attemptPlaceCurrent(blockName)
  
  IF not placed AND blockName is not air THEN
    // Missing material (UNIFIED SERVICE)
    SAVE previousState = BUILD
    SET serviceRequest = {type = "material", materialName = blockName}
    TRANSITION to STATE_SERVICE
    RETURN
  END
  
  // Advance cursor
  advanceCursorAfterPlacement()
  
  IF currentY > height THEN
    TRANSITION to STATE_DONE
  END
END
]]


-- STATE: ERROR
--[[
FUNCTION states.ERROR(context)
  PRINT "ERROR: " + lastError
  
  IF AUTO_MODE THEN
    PRINT "Auto-retry in N seconds"
    WAIT retry_seconds
  ELSE
    PRINT "Press Enter to resume"
    WAIT for input
  END
  
  IF previousState exists THEN
    TRANSITION to previousState
  ELSE
    TRANSITION to INITIALIZE
  END
  
  CLEAR lastError
END
]]

-- STATE: BLOCKED
--[[
FUNCTION states.BLOCKED(context)
  PRINT "Blocked: " + lastError
  
  // Go home safely (non-destructive)
  path = goToOriginSafely()
  
  // Wait for obstruction to clear
  IF AUTO_MODE THEN
    WAIT retry_seconds
  ELSE
    PROMPT user
  END
  
  // Return to work position
  ok = returnAlongPathSafely(path)
  IF not ok THEN
    SET error "Failed to return"
    TRANSITION to ERROR
    RETURN
  END
  
  // Resume
  TRANSITION to previousState
  CLEAR lastError
END
]]

-- STATE: DONE
--[[
FUNCTION states.DONE(context)
  PRINT "Build complete"
  // Terminal state - loop will break
END
]]

-- ============================================================================
-- SECTION 11: MAIN EXECUTION LOOP
-- ============================================================================
--[[
FUNCTION main()
  INITIALIZE context with:
    - manifest
    - starting position (1,1,1)
    - dimensions from manifest
    - empty movement history
    - nil chest direction
    - etc.
  
  currentState = STATE_INITIALIZE
  
  WHILE true
    GET state function for currentState
    IF state function not found THEN
      ERROR "Unknown state"
    END
    
    EXECUTE state function with context
    
    IF currentState is DONE THEN
      BREAK
    END
    
    YIELD (sleep 0)
  END
  
  PRINT "Done"
END

CALL main()
]]