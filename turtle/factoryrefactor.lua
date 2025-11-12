-- factoryrefactor.lua --------------------------------------------------------
-- Refactored factory builder for ComputerCraft turtles.
-- Implements the pseudocode design with a unified SERVICE state, movement
-- history tracking, and clear helper abstractions.
-- IMPORTANT: state handlers must take (ctx) and return next_state
-------------------------------------------------------------------------------

local fs = assert(rawget(_G, "fs"), "fs API unavailable")
local realTurtle = assert(rawget(_G, "turtle"), "turtle API unavailable")
local textutils = rawget(_G, "textutils")
local term = rawget(_G, "term")

local TurtleControl = require("lib.turtle")

local turtle = realTurtle

-------------------------------------------------------------------------------
-- SECTION 1: CONFIGURATION & CONSTANTS
-------------------------------------------------------------------------------

local STATE_INITIALIZE = "INITIALIZE"
local STATE_BUILD      = "BUILD"
local STATE_SERVICE    = "SERVICE"
local STATE_ERROR      = "ERROR"
local STATE_BLOCKED    = "BLOCKED"
local STATE_DONE       = "DONE"

local REFUEL_SLOT             = 16
local FUEL_THRESHOLD          = 500
local MAX_PULL_ATTEMPTS       = 8
local SAFETY_MAX_MOVE_RETRIES = 10
local AUTO_RETRY_SECONDS      = 5
local SAFE_WAIT_SECONDS       = 1
local INITIAL_STOCK_TARGET    = 64

local CONFIG = {
	verboseLogging   = true,
	autoMode         = true,
	preloadMaterials = false,
	mockMovements    = false,
	manifestSearchPaths = {
		"factory/manifest.lua",
		"factory/manifest.json",
		"manifest.lua",
		"manifest.json"
	}
}

local TREASURE_CHEST_IDS = {
	["supplementaries:treasure_chest"] = true,
	["treasure2:chest"] = true,
	["minecraft:chest"] = true
}

local FUEL_ALLOWED_ITEMS = {
	"minecraft:coal",
	"minecraft:charcoal",
	"minecraft:coal_block",
	"minecraft:lava_bucket",
	"minecraft:blaze_rod",
	"minecraft:dried_kelp_block"
}

local DIRECTION_ORDER = { "front", "right", "behind", "left", "up", "down" }

local HEADING_VECTORS = {
	[0] = { x = 0, z = -1 }, -- north
	[1] = { x = 1, z = 0 },  -- east
	[2] = { x = 0, z = 1 },  -- south
	[3] = { x = -1, z = 0 }  -- west
}

local function normalizeHeading(value)
	return (value % 4 + 4) % 4
end

local function directionToOffset(direction, heading)
	local h = normalizeHeading(heading or 0)
	if direction == "front" then
		return { x = HEADING_VECTORS[h].x, y = 0, z = HEADING_VECTORS[h].z }
	elseif direction == "right" then
		local vec = HEADING_VECTORS[normalizeHeading(h + 1)]
		return { x = vec.x, y = 0, z = vec.z }
	elseif direction == "behind" then
		local vec = HEADING_VECTORS[normalizeHeading(h + 2)]
		return { x = vec.x, y = 0, z = vec.z }
	elseif direction == "left" then
		local vec = HEADING_VECTORS[normalizeHeading(h + 3)]
		return { x = vec.x, y = 0, z = vec.z }
	elseif direction == "up" then
		return { x = 0, y = 1, z = 0 }
	elseif direction == "down" then
		return { x = 0, y = -1, z = 0 }
	end
	return nil
end

local function vectorToHeading(dx, dz)
	for heading, vec in pairs(HEADING_VECTORS) do
		if vec.x == dx and vec.z == dz then
			return heading
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- SECTION 2: GENERAL HELPERS
-------------------------------------------------------------------------------

local function log(message)
	if CONFIG.verboseLogging then
		print("[DEBUG] " .. message)
	end
end

local function cloneTable(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

local function normalizeItemFamilies(rawFamilies)
	local lookup = {}
	if type(rawFamilies) ~= "table" then
		return lookup
	end
	for familyName, members in pairs(rawFamilies) do
		if type(members) == "table" then
			for _, itemName in ipairs(members) do
				lookup[itemName] = familyName
			end
		end
	end
	return lookup
end

local itemFamilyMap = {}

-- forward declaration so helpers can reference it before it is populated
local turn -- movement turn helper will be defined later

local function normalizeName(name)
	if not name then
		return nil
	end
	return itemFamilyMap[name] or name
end

local function itemsShareFamily(nameA, nameB)
	return normalizeName(nameA) == normalizeName(nameB)
end

-------------------------------------------------------------------------------
-- SECTION 2A: TURTLE DRIVER SETUP
-------------------------------------------------------------------------------

local function promptYesNo(question, default)
	local suffix
	if default == nil then
		suffix = " [y/n]"
	elseif default then
		suffix = " [Y/n]"
	else
		suffix = " [y/N]"
	end
	while true do
		local promptText = question .. suffix .. " "
		if term and term.write then
			term.write(promptText)
		else
			print(promptText)
		end
		local response = read()
		if not response then
			return default
		end
		response = response:gsub("^%s+", ""):gsub("%s+$", "")
		if response == "" then
			if default ~= nil then
				return default
			end
		else
			local lowered = string.lower(response)
			if lowered == "y" or lowered == "yes" then
				return true
			elseif lowered == "n" or lowered == "no" then
				return false
			end
		end
		print("Please answer yes or no.")
	end
end

local function createMockTurtleDriver(real)
	local state = { x = 0, y = 0, z = 0, facing = 0 } -- simulated pose used for logs
	local headings = { "north", "east", "south", "west" }
	local forwardVectors = { -- heading offsets in manifest coordinates
		{ dx = 0, dz = -1 },
		{ dx = 1, dz = 0 },
		{ dx = 0, dz = 1 },
		{ dx = -1, dz = 0 }
	}

	local function headingName()
		return headings[state.facing + 1]
	end

	local function logPose(action)
		print(string.format("[MOCK] %s -> x=%d y=%d z=%d facing=%s", action, state.x, state.y, state.z, headingName()))
	end

	local function moveBy(dx, dy, dz, action)
		state.x = state.x + dx
		state.y = state.y + dy
		state.z = state.z + dz
		logPose(action)
		return true
	end

	local driver = {}

	driver.forward = function()
		local vec = forwardVectors[state.facing + 1]
		return moveBy(vec.dx, 0, vec.dz, "forward")
	end

	driver.back = function()
		local vec = forwardVectors[state.facing + 1]
		return moveBy(-vec.dx, 0, -vec.dz, "back")
	end

	driver.up = function()
		return moveBy(0, 1, 0, "up")
	end

	driver.down = function()
		return moveBy(0, -1, 0, "down")
	end

	driver.turnLeft = function()
		state.facing = (state.facing + 3) % 4
		logPose("turnLeft")
		return true
	end

	driver.turnRight = function()
		state.facing = (state.facing + 1) % 4
		logPose("turnRight")
		return true
	end

	local function logNoop(label)
		print("[MOCK] " .. label .. " (no action)")
		return true
	end

	driver.dig = function(...)
		return logNoop("dig front")
	end

	driver.digUp = function(...)
		return logNoop("dig up")
	end

	driver.digDown = function(...)
		return logNoop("dig down")
	end

	driver.place = function(...)
		return logNoop("place front")
	end

	driver.placeUp = function(...)
		return logNoop("place up")
	end

	driver.placeDown = function(...)
		return logNoop("place down")
	end

	driver.attack = function(...)
		return logNoop("attack front")
	end

	driver.attackUp = function(...)
		return logNoop("attack up")
	end

	driver.attackDown = function(...)
		return logNoop("attack down")
	end

	driver.inspect = function(...)
		print("[MOCK] inspect front -> simulated air")
		return false, "No block (mock)"
	end

	driver.inspectUp = function(...)
		print("[MOCK] inspect up -> simulated air")
		return false, "No block (mock)"
	end

	driver.inspectDown = function(...)
		print("[MOCK] inspect down -> simulated air")
		return false, "No block (mock)"
	end

	driver.drop = function(...)
		return logNoop("drop front")
	end

	driver.dropUp = function(...)
		return logNoop("drop up")
	end

	driver.dropDown = function(...)
		return logNoop("drop down")
	end

	driver.suck = function(...)
		print("[MOCK] suck front -> no items pulled (mock)")
		return false
	end

	driver.suckUp = function(...)
		print("[MOCK] suck up -> no items pulled (mock)")
		return false
	end

	driver.suckDown = function(...)
		print("[MOCK] suck down -> no items pulled (mock)")
		return false
	end

	driver.getFuelLevel = function()
		return 999999
	end

	driver.getFuelLimit = function()
		return 999999
	end

	driver.refuel = function(amount)
		print(string.format("[MOCK] refuel%s", amount and (" amount=" .. tostring(amount)) or ""))
		return true
	end

	driver.__mockState = state
	driver.__isMock = true

	return setmetatable(driver, {
		__index = function(_, key)
			return real[key]
		end
	})
end

local function initializeTurtleDriver()
	-- Ask the operator whether to enable the mock driver for this session.
	local enableMock = promptYesNo("Enable mock turtle driver (no real movement)?", CONFIG.mockMovements)
	CONFIG.mockMovements = enableMock
	if enableMock then
		turtle = createMockTurtleDriver(realTurtle)
		print("Mock driver active: movements, placement, and digging are simulated.")
	else
		turtle = realTurtle
		print("Mock driver disabled: turtle will interact with the world normally.")
	end
end

-------------------------------------------------------------------------------
-- SECTION 3: MANIFEST LOADING & VALIDATION
-------------------------------------------------------------------------------

local function readAll(path)
	if not fs.exists(path) then
		return nil, "file not found"
	end
	local handle = fs.open(path, "r")
	if not handle then
		return nil, "unable to open file"
	end
	local content = handle.readAll()
	handle.close()
	return content, nil
end

local function decodeLuaTable(text, chunkName)
	local chunk, chunkErr = load(text, chunkName or "manifest", "t", {})
	if not chunk then
		return nil, chunkErr
	end
	local ok, result = pcall(chunk)
	if not ok then
		return nil, result
	end
	if type(result) ~= "table" then
		return nil, "Lua manifest must return a table"
	end
	return result, nil
end

local function decodeJsonTable(text)
	if not textutils or type(textutils.unserializeJSON) ~= "function" then
		return nil, "JSON decoding unavailable"
	end
	local ok, result = pcall(textutils.unserializeJSON, text)
	if not ok then
		return nil, result
	end
	if type(result) ~= "table" then
		return nil, "JSON manifest did not decode to a table"
	end
	return result, nil
end

local selectedManifestPath

local function isManifestFilename(filename)
	if not filename then
		return false
	end
	local lowered = string.lower(filename)
	return lowered:find("manifest", 1, true) ~= nil
end

local function findManifestFiles(startPath, results)
	startPath = startPath or ""
	results = results or {}
	-- Recursively locate manifest files, skipping the bundled ROM assets to reduce noise.
	local ok, entries = pcall(fs.list, startPath)
	if not ok or not entries then
		return results
	end
	for _, entry in ipairs(entries) do
		local fullPath = fs.combine(startPath, entry)
		if fs.isDir(fullPath) then
			if entry ~= "rom" then
				findManifestFiles(fullPath, results)
			end
		elseif isManifestFilename(fs.getName(fullPath)) then
			results[#results + 1] = fullPath
		end
	end
	return results
end

local function gatherManifestCandidates()
	local seen = {}
	local candidates = {}
	local function addPath(path)
		if not path or seen[path] then
			return
		end
		if not fs.exists(path) or fs.isDir(path) then
			return
		end
		seen[path] = true
		candidates[#candidates + 1] = path
	end
	if type(CONFIG.manifestSearchPaths) == "table" then
		for _, path in ipairs(CONFIG.manifestSearchPaths) do
			addPath(path)
		end
	end
	local discovered = findManifestFiles()
	for _, path in ipairs(discovered) do
		addPath(path)
	end
	return candidates
end

local function promptManifestSelection(options)
	print("Select a manifest to build:")
	for index, path in ipairs(options) do
		print(string.format("  [%d] %s", index, path))
	end
	while true do
		if term and term.write then
			term.write("Enter choice number: ")
		else
			print("Enter choice number:")
		end
		local input = read()
		if not input then
			return nil, "Manifest selection aborted"
		end
		input = input:gsub("^%s+", ""):gsub("%s+$", "")
		local choice = tonumber(input, 10)
		if choice and options[choice] then
			return options[choice], nil
		end
		print("Invalid selection. Enter a number between 1 and " .. #options)
	end
end

local function loadManifest()
	local candidates = gatherManifestCandidates()
	if #candidates == 0 then
		return nil, "No manifest files located in filesystem"
	end

	local chosenPath
	if #candidates == 1 then
		chosenPath = candidates[1]
	else
		print("Discovered " .. #candidates .. " manifest files.")
		local selection, selectionErr = promptManifestSelection(candidates)
		if not selection then
			return nil, selectionErr or "Manifest selection cancelled"
		end
		chosenPath = selection
	end
	print("Using manifest: " .. chosenPath)

	local content, readErr = readAll(chosenPath)
	if not content then
		return nil, "Unable to read manifest '" .. chosenPath .. "': " .. tostring(readErr)
	end

	local manifest, decodeErr
	if chosenPath:match("%.lua$") then
		manifest, decodeErr = decodeLuaTable(content, chosenPath)
	else
		manifest, decodeErr = decodeJsonTable(content)
	end
	if not manifest then
		return nil, "Failed to decode manifest '" .. chosenPath .. "': " .. tostring(decodeErr)
	end

	selectedManifestPath = chosenPath
	log("Loaded manifest from " .. chosenPath)
	return manifest
end

local manifest, manifestErr = loadManifest()
if not manifest then
	error(manifestErr)
end

itemFamilyMap = normalizeItemFamilies(manifest.meta and manifest.meta.itemFamilies)

local function resolveLayer(index, cache, manifestTable)
	cache = cache or {}
	if cache[index] then
		return cache[index]
	end
	local layer = manifestTable.layers[index]
	if type(layer) == "string" then
		local reference = layer:match("SAME_AS%[(%d+)%]")
		if reference then
			layer = resolveLayer(tonumber(reference), cache, manifestTable)
		end
	end
	if type(layer) ~= "table" then
		error("Layer " .. tostring(index) .. " could not be resolved")
	end
	cache[index] = layer
	return layer
end

local function collectRequiredMaterials(manifestTable)
	local requirements = {}
	local size = manifestTable.meta and manifestTable.meta.size or {}
	local layerCache = {}
	for y = 1, size.y or #manifestTable.layers do
		local layer = resolveLayer(y, layerCache, manifestTable)
		for _, row in ipairs(layer) do
			for column = 1, #row do
				local symbol = row:sub(column, column)
				local blockName = manifestTable.legend[symbol]
				if blockName and blockName ~= "minecraft:air" then
					requirements[blockName] = (requirements[blockName] or 0) + 1
				end
			end
		end
	end
	return requirements
end

local function validateManifest(manifestTable)
	assert(type(manifestTable.legend) == "table", "Manifest missing legend")
	assert(type(manifestTable.layers) == "table", "Manifest missing layers")
	local size = manifestTable.meta and manifestTable.meta.size
	assert(type(size) == "table", "Manifest meta.size missing")
	local cache = {}
	for y = 1, size.y do
		local layer = resolveLayer(y, cache, manifestTable)
		assert(type(layer) == "table", "Layer " .. y .. " not a table")
		for z, row in ipairs(layer) do
			assert(#row == size.x, string.format("Layer %d row %d length mismatch", y, z))
			for column = 1, #row do
				local symbol = row:sub(column, column)
				assert(manifestTable.legend[symbol], string.format("Unknown symbol '%s' at Y=%d Z=%d X=%d", symbol, y, z, column))
			end
		end
	end
	return true
end

validateManifest(manifest)

initializeTurtleDriver()

local MATERIAL_REQUIREMENTS = collectRequiredMaterials(manifest)

-------------------------------------------------------------------------------
-- SECTION 4: INVENTORY HELPERS
-------------------------------------------------------------------------------

local function buildAllowedSet(source)
	local allowed = {}
	if type(source) == "table" then
		if #source > 0 then
			for _, name in ipairs(source) do
				allowed[normalizeName(name)] = true
			end
		else
			for key, value in pairs(source) do
				if type(key) == "string" then
					if type(value) ~= "number" or value > 0 then
						allowed[normalizeName(key)] = true
					end
				elseif type(value) == "string" then
					allowed[normalizeName(value)] = true
				end
			end
		end
	end
	return allowed
end

local function tallyInventory()
	local counts = {}
	for slot = 1, 16 do
		local detail = turtle.getItemDetail(slot)
		if detail and detail.name then
			counts[detail.name] = (counts[detail.name] or 0) + detail.count
		end
	end
	return counts
end

local function snapshotInventory()
	return tallyInventory()
end

local function diffGains(before, after)
	local gains = {}
	for name, afterCount in pairs(after) do
		local delta = afterCount - (before[name] or 0)
		if delta > 0 then
			gains[name] = delta
		end
	end
	return gains
end

local function countFamilyInInventory(inventory, targetName)
	if not targetName then
		return 0
	end
	local normalized = normalizeName(targetName)
	if CONFIG.mockMovements then
		return INITIAL_STOCK_TARGET
	end
	local source = inventory or tallyInventory()
	local total = 0
	for name, count in pairs(source) do
		if normalizeName(name) == normalized then
			total = total + count
		end
	end
	return total
end

local function countFamilyGains(beforeSnapshot, afterSnapshot, targetName)
	local normalized = normalizeName(targetName)
	local gains = diffGains(beforeSnapshot, afterSnapshot)
	local total = 0
	for name, delta in pairs(gains) do
		if normalizeName(name) == normalized then
			total = total + delta
		end
	end
	return total
end

local function selectSlotWithSpace(preferredName)
	local desiredFamily = normalizeName(preferredName)
	for slot = 1, 15 do
		local detail = turtle.getItemDetail(slot)
		if detail then
			local maxCount = detail.maxCount or 64
			if detail.count < maxCount and (not desiredFamily or normalizeName(detail.name) == desiredFamily) then
				turtle.select(slot)
				return slot
			end
		end
	end
	for slot = 1, 15 do
		if not turtle.getItemDetail(slot) then
			turtle.select(slot)
			return slot
		end
	end
	return nil
end

local function dropUnexpectedGainsMulti(gains, allowedSet, dropFunction)
	-- Build a normalized version of the allowed set for comparison
	local normalizedAllowed = {}
	for key in pairs(allowedSet) do
		normalizedAllowed[key] = true
	end
	
	-- Only check items that were actually gained (not entire inventory)
	-- This prevents dropping items that were already in inventory
	for gainedItemName, _ in pairs(gains) do
		-- Skip nil item names (can happen due to game bugs or edge cases)
		if gainedItemName then
			local normalizedGained = normalizeName(gainedItemName)
			log("Gained item: " .. gainedItemName .. " -> normalized: " .. normalizedGained)
			log("Is allowed? " .. tostring(normalizedAllowed[normalizedGained]))
			if not normalizedAllowed[normalizedGained] then
				log("Dropping unwanted item: " .. gainedItemName)
				-- Find and drop all instances of this unwanted item
				for slot = 1, 15 do
					local detail = turtle.getItemDetail(slot)
					if detail and normalizeName(detail.name) == normalizedGained then
						turtle.select(slot)
						dropFunction()
					end
				end
			end
		else
			log("WARNING: Gained item with nil name, skipping")
		end
	end
	turtle.select(1)
end

-------------------------------------------------------------------------------
-- SECTION 5: CHEST INTERACTION HELPERS
-------------------------------------------------------------------------------

local FUEL_ALLOWED_SET = buildAllowedSet(FUEL_ALLOWED_ITEMS)

local function pullAndFilterItems(chestFunctions, allowedSet, maxAttempts)
	local attempts = 0
	local pulledAnything = false
	while attempts < maxAttempts do
		if not selectSlotWithSpace() then
			log("Inventory full while pulling from chest")
			break
		end
		local before = snapshotInventory()
		-- Request full stack (64 items) of any allowed item from manifest
		if not chestFunctions.suck(64) then
			break
		end
		attempts = attempts + 1
		pulledAnything = true
		local after = snapshotInventory()
		local gains = diffGains(before, after)
		dropUnexpectedGainsMulti(gains, allowedSet, chestFunctions.drop)
	end
	return pulledAnything
end

local function restockItems(missingTable, allowedUniverse, chestFunctions, maxAttempts)
	local allowedSet = buildAllowedSet(allowedUniverse)
	log("=== Restocking Debug ===")
	log("Allowed items in set:")
	for item in pairs(allowedSet) do
		log("  - " .. item)
	end
	log("Missing items:")
	for item, count in pairs(missingTable) do
		log("  - " .. item .. " (need " .. count .. ")")
	end
	local pulledSomething = false
	for itemName, deficit in pairs(missingTable) do
		local remaining = deficit
		local attempts = 0
		while remaining > 0 and attempts < maxAttempts do
			if not selectSlotWithSpace(itemName) then
				log("Inventory full while restocking " .. itemName)
				break
			end
			local before = snapshotInventory()
			-- Request up to a full stack (64) or remaining needed amount, whichever is smaller
			local pullAmount = math.min(remaining, 64)
			if not chestFunctions.suck(pullAmount) then
				break
			end
			attempts = attempts + 1
			local after = snapshotInventory()
			local gained = countFamilyGains(before, after, itemName)
			if gained > 0 then
				pulledSomething = true
				remaining = math.max(remaining - gained, 0)
			end
			local gains = diffGains(before, after)
			dropUnexpectedGainsMulti(gains, allowedSet, chestFunctions.drop)
		end
		missingTable[itemName] = remaining
	end
	return pulledSomething
end

local function computeInitialMissing(requirements, stackTarget)
	local missing = {}
	local target = stackTarget or INITIAL_STOCK_TARGET
	for blockName, requiredCount in pairs(requirements) do
		if type(blockName) == "string" and requiredCount > 0 then
			local desired = math.min(requiredCount, target)
			local available = countFamilyInInventory(nil, blockName)
			if available < desired then
				missing[blockName] = desired - available
			end
		end
	end
	return missing
end

local function buildInitialAllowedUniverse(requirements)
	local allowed = {}
	for blockName, amount in pairs(requirements) do
		if type(blockName) == "string" then
			allowed[blockName] = amount
		end
	end
	for _, fuelName in ipairs(FUEL_ALLOWED_ITEMS) do
		allowed[fuelName] = (allowed[fuelName] or 0) + 1
	end
	return allowed
end

local function performInitialRestock(requirements, chestFunctions, stackTarget)
	if not chestFunctions then
		return false
	end
	if CONFIG.mockMovements then
		log("Mock restock: assuming initial materials are preloaded")
		return true
	end
	local missing = computeInitialMissing(requirements, stackTarget)
	if not next(missing) then
		return false
	end
	local allowedUniverse = buildInitialAllowedUniverse(requirements)
	return restockItems(missing, allowedUniverse, chestFunctions, MAX_PULL_ATTEMPTS)
end

-------------------------------------------------------------------------------
-- SECTION 6: FLOW HELPERS
-------------------------------------------------------------------------------

local function retryOperation(operationFunc, successCheckFunc, waitLabel)
	while true do
		operationFunc()
		if successCheckFunc() then
			return true
		end
		if CONFIG.autoMode then
			print(waitLabel .. " (auto retry)")
			sleep(AUTO_RETRY_SECONDS)
		else
			print(waitLabel .. " (press Enter to retry)")
			read()
		end
	end
end

local function transitionToState(context, newState, errorMessage, previousState)
	if errorMessage then
		context.lastError = errorMessage
	end
	if previousState then
		context.previousState = previousState
	end
	context.currentState = newState
end

-------------------------------------------------------------------------------
-- SECTION 7: STORAGE DETECTION & PERIPHERAL HELPERS
-------------------------------------------------------------------------------

local function isInventoryBlock(blockName)
	if not blockName then
		return false
	end
	return blockName:find("chest", 1, true)
		 or blockName:find("barrel", 1, true)
		 or blockName:find("drawer", 1, true)
		 or blockName:find("shulker_box", 1, true)
end

local function isTreasureChestId(blockId)
	if not blockId then
		return false
	end
	if TREASURE_CHEST_IDS[blockId] then
		return true
	end
	local lowered = string.lower(blockId)
	return lowered:find("treasure", 1, true) and lowered:find("chest", 1, true)
end

-- helpers for orientation-aware peripheral use ------------------------------

local function withOrientation(prepare, operation, cleanup)
	prepare()
	local result = { operation() }
	cleanup()
	return table.unpack(result)
end

local function getPeripheralFunctions(direction)
	if direction == "front" then
		return {
			label = "front",
			inspect = turtle.inspect,
			suck = function(amount)
				return turtle.suck(amount)
			end,
			drop = turtle.drop,
		}
	elseif direction == "up" then
		return {
			label = "up",
			inspect = turtle.inspectUp,
			suck = function(amount)
				return turtle.suckUp(amount)
			end,
			drop = turtle.dropUp,
		}
	elseif direction == "down" then
		return {
			label = "down",
			inspect = turtle.inspectDown,
			suck = function(amount)
				return turtle.suckDown(amount)
			end,
			drop = turtle.dropDown,
		}
	elseif direction == "right" then
		return {
			label = "right",
			inspect = function()
				return withOrientation(turtle.turnRight, turtle.inspect, turtle.turnLeft)
			end,
			suck = function(amount)
				return withOrientation(turtle.turnRight, function()
					return turtle.suck(amount)
				end, turtle.turnLeft)
			end,
			drop = function(amount)
				return withOrientation(turtle.turnRight, function()
					if amount then
						return turtle.drop(amount)
					end
					return turtle.drop()
				end, turtle.turnLeft)
			end,
		}
	elseif direction == "behind" then
		return {
			label = "behind",
			inspect = function()
				return withOrientation(function()
					turtle.turnLeft()
					turtle.turnLeft()
				end, turtle.inspect, function()
					turtle.turnRight()
					turtle.turnRight()
				end)
			end,
			suck = function(amount)
				return withOrientation(function()
					turtle.turnLeft()
					turtle.turnLeft()
				end, function()
					return turtle.suck(amount)
				end, function()
					turtle.turnRight()
					turtle.turnRight()
				end)
			end,
			drop = function(amount)
				return withOrientation(function()
					turtle.turnLeft()
					turtle.turnLeft()
				end, function()
					if amount then
						return turtle.drop(amount)
					end
					return turtle.drop()
				end, function()
					turtle.turnRight()
					turtle.turnRight()
				end)
			end,
		}
	elseif direction == "left" then
		return {
			label = "left",
			inspect = function()
				return withOrientation(turtle.turnLeft, turtle.inspect, turtle.turnRight)
			end,
			suck = function(amount)
				return withOrientation(turtle.turnLeft, function()
					return turtle.suck(amount)
				end, turtle.turnRight)
			end,
			drop = function(amount)
				return withOrientation(turtle.turnLeft, function()
					if amount then
						return turtle.drop(amount)
					end
					return turtle.drop()
				end, turtle.turnRight)
			end,
		}
	end
	return {
		label = direction or "unknown",
		inspect = function()
			return false, nil
		end,
		suck = function()
			return false
		end,
		drop = function()
			return false
		end,
	}
end

local function findAdjacentStorageDirection()
	if CONFIG.mockMovements then
		return "front"
	end
	for _, direction in ipairs(DIRECTION_ORDER) do
		local functions = getPeripheralFunctions(direction)
		local ok, data = functions.inspect()
		if ok and data and isInventoryBlock(data.name) then
			return direction
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- SECTION 8: FUEL MANAGEMENT
-------------------------------------------------------------------------------

local function isFuelUnlimited()
	if not turtle or not turtle.getFuelLimit then
		return true
	end
	local limit = turtle.getFuelLimit()
	return limit == "unlimited" or limit == math.huge or limit <= 0
end

local function tryRefuelFromSlot(slotNumber, targetLevel)
	if isFuelUnlimited() then
		return true
	end
	local previous = turtle.getSelectedSlot()
	turtle.select(slotNumber)
	local consumedAny = false
	while turtle.getFuelLevel() < targetLevel do
		if not turtle.refuel(1) then
			break
		end
		consumedAny = true
	end
	turtle.select(previous)
	return consumedAny
end

local function attemptFuelRestock(targetLevel)
	if CONFIG.mockMovements then
		return true, true
	end
	local pulledFuel = false
	local foundContainer = false
	for _, direction in ipairs(DIRECTION_ORDER) do
		if turtle.getFuelLevel() >= targetLevel then
			break
		end
		local chestFunctions = getPeripheralFunctions(direction)
		local ok, data = chestFunctions.inspect()
		if ok and data and isInventoryBlock(data.name) then
			foundContainer = true
			if pullAndFilterItems(chestFunctions, FUEL_ALLOWED_SET, MAX_PULL_ATTEMPTS) then
				if tryRefuelFromSlot(REFUEL_SLOT, targetLevel) then
					pulledFuel = true
				end
				for slot = 1, 15 do
					if turtle.getFuelLevel() >= targetLevel then
						break
					end
					if tryRefuelFromSlot(slot, targetLevel) then
						pulledFuel = true
					end
				end
			end
		end
	end
	return pulledFuel, foundContainer
end

local function refuel()
	if isFuelUnlimited() then
		return
	end
	if turtle.getFuelLevel() >= FUEL_THRESHOLD then
		return
	end
	if tryRefuelFromSlot(REFUEL_SLOT, FUEL_THRESHOLD) then
		return
	end
	for slot = 1, 15 do
		if tryRefuelFromSlot(slot, FUEL_THRESHOLD) then
			return
		end
	end
	local pulledFuel = attemptFuelRestock(FUEL_THRESHOLD)
	if not pulledFuel then
		log("Fuel low and no nearby fuel sources found")
	end
end

-------------------------------------------------------------------------------
-- SECTION 9: MATERIAL RESTOCKING
-------------------------------------------------------------------------------

local function attemptChestRestock(missingTable, allowedUniverse)
	if CONFIG.mockMovements then
		local hadEntries = false
		for blockName in pairs(missingTable) do
			hadEntries = true
			missingTable[blockName] = 0
		end
		return hadEntries, true
	end
	local pulledSomething = false
	local foundContainer = false
	for _, direction in ipairs(DIRECTION_ORDER) do
		local chestFunctions = getPeripheralFunctions(direction)
		local ok, data = chestFunctions.inspect()
		if ok and data and isInventoryBlock(data.name) then
			foundContainer = true
			if restockItems(missingTable, allowedUniverse, chestFunctions, MAX_PULL_ATTEMPTS) then
				pulledSomething = true
			end
		end
	end
	return pulledSomething, foundContainer
end

local function ensureMaterialsAvailable(requirements, targetBlock, blocking)
	if CONFIG.mockMovements then
		return true
	end
	while true do
		local missing = {}
		local hasAll = true
		if targetBlock then
			if countFamilyInInventory(nil, targetBlock) < 1 then
				missing[targetBlock] = 1
				hasAll = false
			end
		else
			for blockName, requiredCount in pairs(requirements) do
				if requiredCount > 0 then
					local available = countFamilyInInventory(nil, blockName)
					if available < requiredCount then
						missing[blockName] = requiredCount - available
						hasAll = false
					end
				end
			end
		end

		if hasAll then
			return true
		end

		local pulled, foundContainer = attemptChestRestock(missing, requirements)
		if pulled then
			goto continue
		end

		if not blocking then
			return false
		end

		if not foundContainer then
			print("No adjacent storage detected; waiting for manual restock")
		end

		if CONFIG.autoMode then
			print("Awaiting materials ...")
			sleep(AUTO_RETRY_SECONDS)
		else
			print("Load materials and press Enter")
			read()
		end

		::continue::
	end
end

-------------------------------------------------------------------------------
-- SECTION 10: CONTEXT & MOVEMENT HELPERS
-------------------------------------------------------------------------------

local context = {
	manifest = manifest,
	manifestPath = selectedManifestPath,
	remainingMaterials = cloneTable(MATERIAL_REQUIREMENTS),
	currentX = 1,
	currentY = 1,
	currentZ = 1,
	width = (manifest.meta and manifest.meta.size and manifest.meta.size.x) or 0,
	height = (manifest.meta and manifest.meta.size and manifest.meta.size.y) or 0,
	depth = (manifest.meta and manifest.meta.size and manifest.meta.size.z) or 0,
	manifestOK = true,
	lastError = nil,
	previousState = nil,
	serviceRequest = nil,
	inventorySummary = tallyInventory(),
	layerCache = {},
	movementHistory = {},
	chestDirection = nil,
	chestOffset = nil,
	chestPosition = nil,
	pose = { x = 0, y = 0, z = 0, heading = 0 },
	currentState = STATE_INITIALIZE,
}

context.airBlock = manifest.legend["."] or "minecraft:air"

local function recordMove(operation)
	context.movementHistory[#context.movementHistory + 1] = operation
end

local function applyPoseMove(direction)
	local pose = context.pose
	if not pose then
		return
	end
	if direction == "forward" then
		local vec = HEADING_VECTORS[pose.heading]
		pose.x = pose.x + vec.x
		pose.z = pose.z + vec.z
	elseif direction == "back" then
		local vec = HEADING_VECTORS[pose.heading]
		pose.x = pose.x - vec.x
		pose.z = pose.z - vec.z
	elseif direction == "up" then
		pose.y = pose.y + 1
	elseif direction == "down" then
		pose.y = pose.y - 1
	end
end

local function applyPoseTurn(direction)
	local pose = context.pose
	if not pose then
		return
	end
	if direction == "right" then
		pose.heading = normalizeHeading(pose.heading + 1)
	elseif direction == "left" then
		pose.heading = normalizeHeading(pose.heading - 1)
	elseif direction == "around" then
		pose.heading = normalizeHeading(pose.heading + 2)
	end
end

local turtleController = TurtleControl.new({
        turtle = turtle,
        refuel = refuel,
        maxRetries = SAFETY_MAX_MOVE_RETRIES,
        retryDelay = 0.2,
        autoWait = function()
                return CONFIG.autoMode
        end,
        waitSeconds = function()
                return SAFE_WAIT_SECONDS
        end,
        log = log,
        recordMove = recordMove,
        applyPoseMove = applyPoseMove,
        applyPoseTurn = applyPoseTurn,
        isFuelUnlimited = isFuelUnlimited,
})

local function move(direction, maxRetries, recordHistory)
        local ok = turtleController:move(direction, {
                maxRetries = maxRetries,
                recordHistory = recordHistory,
        })
        return ok
end

function turn(direction, recordHistory)
        return turtleController:turn(direction, {
                recordHistory = recordHistory,
        })
end

local function turnRightNoHistory()
        return turtleController:turn("right", { recordHistory = false })
end

local function turnLeftNoHistory()
        return turtleController:turn("left", { recordHistory = false })
end

local function turnAroundLeft()
        turtleController:turn("left", { recordHistory = false })
        return turtleController:turn("left", { recordHistory = false })
end

local function turnAroundRight()
        turtleController:turn("right", { recordHistory = false })
        return turtleController:turn("right", { recordHistory = false })
end

local function trySafeMove(direction)
        return turtleController:try(direction)
end

local function safeWaitMove(movementFunction, label, maxAttempts)
        return turtleController:waitFor(movementFunction, label, maxAttempts)
end

local function safePerformInverse(operation)
        return turtleController:performInverse(operation)
end

local function safePerformForward(operation)
        return turtleController:performForward(operation)
end

-------------------------------------------------------------------------------
-- SECTION: PATHFINDING (A* for non-destructive navigation)
-------------------------------------------------------------------------------

-- Helper to create a position key for the visited set
local function posKey(x, y, z)
	return string.format("%d,%d,%d", x, y, z)
end

-- Calculate Manhattan distance heuristic
local function manhattanDistance(x1, y1, z1, x2, y2, z2)
	return math.abs(x2 - x1) + math.abs(y2 - y1) + math.abs(z2 - z1)
end

-- Check if turtle can move in a specific direction without breaking blocks
local function canMoveNonDestructive(direction)
	local detectFunc, inspectFunc
	if direction == "forward" then
		detectFunc = turtle.detect
		inspectFunc = turtle.inspect
	elseif direction == "up" then
		detectFunc = turtle.detectUp
		inspectFunc = turtle.inspectUp
	elseif direction == "down" then
		detectFunc = turtle.detectDown
		inspectFunc = turtle.inspectDown
	else
		return false
	end
	
	-- If nothing detected, we can move
	if not detectFunc() then
		return true
	end
	
	-- Something is there - check if it's a mob or entity (which we can push through)
	local success, data = inspectFunc()
	if not success then
		-- Can't inspect = might be a mob/entity, try to move anyway
		return true
	end
	
	-- If there's a block, we can't move (non-destructive)
	return false
end

-- Try to move in a direction, return success
local function tryMoveDirection(direction, dryRun)
	if dryRun then
		return canMoveNonDestructive(direction)
	end
	
	if not canMoveNonDestructive(direction) then
		return false
	end
	
	return trySafeMove(direction)
end

-- A* pathfinding to navigate from current position to target
-- Returns a table of moves to execute, or nil if no path found
local function findPathAStar(targetX, targetY, targetZ, maxNodes)
	maxNodes = maxNodes or 500  -- Limit search to prevent infinite loops
	
	local startX, startY, startZ = context.pose.x, context.pose.y, context.pose.z
	local startHeading = context.pose.heading
	
	-- If already at target, no path needed
	if startX == targetX and startY == targetY and startZ == targetZ then
		return {}
	end
	
	-- Priority queue (open set) - nodes to explore
	-- Each node: {x, y, z, heading, g, h, f, parent, move}
	local openSet = {}
	local openSetKeys = {}  -- Track which positions are in open set
	local closedSet = {}    -- Positions we've fully explored
	
	-- Start node
	local startNode = {
		x = startX,
		y = startY,
		z = startZ,
		heading = startHeading,
		g = 0,  -- Cost from start
		h = manhattanDistance(startX, startY, startZ, targetX, targetY, targetZ),
		parent = nil,
		move = nil
	}
	startNode.f = startNode.g + startNode.h
	
	table.insert(openSet, startNode)
	openSetKeys[posKey(startX, startY, startZ)] = true
	
	local nodesExplored = 0
	
	while #openSet > 0 and nodesExplored < maxNodes do
		-- Find node with lowest f score
		local currentIndex = 1
		local currentNode = openSet[1]
		for i = 2, #openSet do
			if openSet[i].f < currentNode.f then
				currentIndex = i
				currentNode = openSet[i]
			end
		end
		
		-- Remove from open set
		table.remove(openSet, currentIndex)
		local currentKey = posKey(currentNode.x, currentNode.y, currentNode.z)
		openSetKeys[currentKey] = nil
		closedSet[currentKey] = true
		
		nodesExplored = nodesExplored + 1
		
		-- Check if we reached the goal
		if currentNode.x == targetX and currentNode.y == targetY and currentNode.z == targetZ then
			-- Reconstruct path
			local path = {}
			local node = currentNode
			while node.parent do
				table.insert(path, 1, node.move)
				node = node.parent
			end
			return path
		end
		
		-- Explore neighbors
		-- We need to temporarily set pose to current node to check moves
		local savedPose = {
			x = context.pose.x,
			y = context.pose.y,
			z = context.pose.z,
			heading = context.pose.heading
		}
		
		context.pose.x = currentNode.x
		context.pose.y = currentNode.y
		context.pose.z = currentNode.z
		context.pose.heading = currentNode.heading
		
		-- Try all possible moves: forward, up, down, turn left/right then forward
		local moves = {
			{dir = "forward", turnCost = 0},
			{dir = "up", turnCost = 0},
			{dir = "down", turnCost = 0},
			{dir = "right_forward", turnCost = 1},  -- Turn right then move forward
			{dir = "left_forward", turnCost = 1},   -- Turn left then move forward
		}
		
		for _, moveData in ipairs(moves) do
			local dir = moveData.dir
			local neighborX, neighborY, neighborZ, neighborHeading
			local moveCost = 1 + moveData.turnCost
			local moveCommands = {}
			
			if dir == "forward" then
				local vec = HEADING_VECTORS[currentNode.heading]
				neighborX = currentNode.x + vec.x
				neighborY = currentNode.y
				neighborZ = currentNode.z + vec.z
				neighborHeading = currentNode.heading
				if canMoveNonDestructive("forward") then
					moveCommands = {{type = "move", direction = "forward"}}
				else
					moveCommands = nil
				end
			elseif dir == "up" then
				neighborX = currentNode.x
				neighborY = currentNode.y + 1
				neighborZ = currentNode.z
				neighborHeading = currentNode.heading
				if canMoveNonDestructive("up") then
					moveCommands = {{type = "move", direction = "up"}}
				else
					moveCommands = nil
				end
			elseif dir == "down" then
				neighborX = currentNode.x
				neighborY = currentNode.y - 1
				neighborZ = currentNode.z
				neighborHeading = currentNode.heading
				if canMoveNonDestructive("down") then
					moveCommands = {{type = "move", direction = "down"}}
				else
					moveCommands = nil
				end
			elseif dir == "right_forward" then
				local newHeading = normalizeHeading(currentNode.heading + 1)
				local vec = HEADING_VECTORS[newHeading]
				neighborX = currentNode.x + vec.x
				neighborY = currentNode.y
				neighborZ = currentNode.z + vec.z
				neighborHeading = newHeading
				-- Temporarily turn to check
				context.pose.heading = newHeading
				if canMoveNonDestructive("forward") then
					moveCommands = {{type = "turn", direction = "right"}, {type = "move", direction = "forward"}}
				else
					moveCommands = nil
				end
				context.pose.heading = currentNode.heading
			elseif dir == "left_forward" then
				local newHeading = normalizeHeading(currentNode.heading - 1)
				local vec = HEADING_VECTORS[newHeading]
				neighborX = currentNode.x + vec.x
				neighborY = currentNode.y
				neighborZ = currentNode.z + vec.z
				neighborHeading = newHeading
				-- Temporarily turn to check
				context.pose.heading = newHeading
				if canMoveNonDestructive("forward") then
					moveCommands = {{type = "turn", direction = "left"}, {type = "move", direction = "forward"}}
				else
					moveCommands = nil
				end
				context.pose.heading = currentNode.heading
			end
			
			if moveCommands then
				local neighborKey = posKey(neighborX, neighborY, neighborZ)
				
				-- Skip if already fully explored
				if not closedSet[neighborKey] then
					local tentativeG = currentNode.g + moveCost
					
					-- Check if this neighbor is already in open set
					local existingNode = nil
					for _, node in ipairs(openSet) do
						if node.x == neighborX and node.y == neighborY and node.z == neighborZ then
							existingNode = node
							break
						end
					end
					
					if not existingNode or tentativeG < existingNode.g then
						local neighborNode = {
							x = neighborX,
							y = neighborY,
							z = neighborZ,
							heading = neighborHeading,
							g = tentativeG,
							h = manhattanDistance(neighborX, neighborY, neighborZ, targetX, targetY, targetZ),
							parent = currentNode,
							move = moveCommands
						}
						neighborNode.f = neighborNode.g + neighborNode.h
						
						if existingNode then
							-- Update existing node
							existingNode.g = tentativeG
							existingNode.f = neighborNode.f
							existingNode.heading = neighborHeading
							existingNode.parent = currentNode
							existingNode.move = moveCommands
						else
							-- Add new node
							table.insert(openSet, neighborNode)
							openSetKeys[neighborKey] = true
						end
					end
				end
			end
		end
		
		-- Restore pose
		context.pose.x = savedPose.x
		context.pose.y = savedPose.y
		context.pose.z = savedPose.z
		context.pose.heading = savedPose.heading
	end
	
	-- No path found
	return nil
end

-- Execute a path returned by findPathAStar
local function executePath(path)
	if not path or #path == 0 then
		return true
	end
	
	for i, moveSet in ipairs(path) do
		for _, command in ipairs(moveSet) do
			if command.type == "turn" then
				turn(command.direction, false)
			elseif command.type == "move" then
				local success = safeWaitMove(function()
					return trySafeMove(command.direction)
				end, "Following path step " .. i, SAFETY_MAX_MOVE_RETRIES)
				
				if not success then
					log(string.format("Path execution failed at step %d", i))
					return false
				end
			end
		end
	end
	
	return true
end

-- Navigate directly to origin (0,0,0) using pose tracking instead of reversing movement history
-- Returns the saved path for returning to the original position
local function goToOriginDirectly()
	if CONFIG.mockMovements then
		return {}
	end

	local savedPath = {}
	local startPose = { x = context.pose.x, y = context.pose.y, z = context.pose.z, heading = context.pose.heading }
	
	-- Try using A* pathfinding to navigate to origin non-destructively
	log(string.format("Pathfinding from (%d,%d,%d) to origin (0,0,0)", context.pose.x, context.pose.y, context.pose.z))
	local path = findPathAStar(0, 0, 0, 1000)
	
	if path then
		log(string.format("Path found with %d steps, executing...", #path))
		local success = executePath(path)
		if success then
			log("Successfully navigated to origin using pathfinding")
			savedPath.startPose = startPose
			return savedPath
		else
			log("Path execution failed, falling back to simple navigation")
		end
	else
		log("No path found with A*, using simple navigation")
	end
	
	-- Fallback: Simple direct navigation (original logic)
	-- Step 1: Navigate vertically to ground level (y = 0)
	while context.pose.y > 0 do
		local success = safeWaitMove(function()
			return trySafeMove("down")
		end, "Descending to ground level", SAFETY_MAX_MOVE_RETRIES)
		if not success then
			log("Failed to descend to ground level, continuing from y=" .. context.pose.y)
			break
		end
	end
	
	-- Step 2: Navigate horizontally to origin x,z position
	while context.pose.x ~= 0 or context.pose.z ~= 0 do
		-- Calculate desired direction
		local dx = 0 - context.pose.x
		local dz = 0 - context.pose.z
		
		-- Prioritize X movement first, then Z
		local targetHeading = nil
		if dx ~= 0 then
			-- Need to move along X axis
			if dx > 0 then
				targetHeading = 1  -- east (+x)
			else
				targetHeading = 3  -- west (-x)
			end
		elseif dz ~= 0 then
			-- Need to move along Z axis
			if dz > 0 then
				targetHeading = 2  -- south (+z)
			else
				targetHeading = 0  -- north (-z)
			end
		end
		
		-- Turn to face target heading
		if targetHeading then
			while context.pose.heading ~= targetHeading do
				local turnDiff = (targetHeading - context.pose.heading + 4) % 4
				if turnDiff == 1 or turnDiff == 3 then
					-- Turn right (1 step) or left (3 steps means right is shorter)
					if turnDiff == 1 then
						turn("right", false)
					else
						turn("left", false)
					end
				else
					-- 180 degree turn, just pick right
					turn("right", false)
				end
			end
			
			-- Move forward once in the target direction
			local success = safeWaitMove(function()
				return trySafeMove("forward")
			end, "Navigating to origin", SAFETY_MAX_MOVE_RETRIES)
			if not success then
				log(string.format("Blocked while navigating to origin at pose (%d,%d,%d)", context.pose.x, context.pose.y, context.pose.z))
				break
			end
		end
	end
	
	-- Save the path information for return journey
	savedPath.startPose = startPose
	return savedPath
end

local function goToOriginSafely()
	local savedPath = {}
	while #context.movementHistory > 0 do
		local operation = context.movementHistory[#context.movementHistory]
		context.movementHistory[#context.movementHistory] = nil
		savedPath[#savedPath + 1] = operation
		if not safePerformInverse(operation) then
			return savedPath
		end
	end
	return savedPath
end

-- Navigate directly back to a saved pose position
local function returnToPositionDirectly(savedPath)
	if CONFIG.mockMovements then
		return true
	end
	
	if not savedPath or not savedPath.startPose then
		log("No saved position to return to")
		return false
	end
	
	local targetPose = savedPath.startPose
	
	-- Try using A* pathfinding to navigate back non-destructively
	log(string.format("Pathfinding from (%d,%d,%d) to (%d,%d,%d)", 
		context.pose.x, context.pose.y, context.pose.z,
		targetPose.x, targetPose.y, targetPose.z))
	local path = findPathAStar(targetPose.x, targetPose.y, targetPose.z, 1000)
	
	if path then
		log(string.format("Return path found with %d steps, executing...", #path))
		local success = executePath(path)
		if success then
			-- Restore original heading
			while context.pose.heading ~= targetPose.heading do
				local turnDiff = (targetPose.heading - context.pose.heading + 4) % 4
				if turnDiff == 1 or turnDiff == 3 then
					if turnDiff == 1 then
						turn("right", false)
					else
						turn("left", false)
					end
				else
					turn("right", false)
				end
			end
			log("Successfully returned to position using pathfinding")
			return true
		else
			log("Path execution failed during return, falling back to simple navigation")
		end
	else
		log("No return path found with A*, using simple navigation")
	end
	
	-- Fallback: Simple direct navigation (original logic)
	-- Step 1: Navigate horizontally to target x,z position
	while context.pose.x ~= targetPose.x or context.pose.z ~= targetPose.z do
		-- Calculate desired direction
		local dx = targetPose.x - context.pose.x
		local dz = targetPose.z - context.pose.z
		
		-- Prioritize X movement first, then Z
		local targetHeading = nil
		if dx ~= 0 then
			-- Need to move along X axis
			if dx > 0 then
				targetHeading = 1  -- east (+x)
			else
				targetHeading = 3  -- west (-x)
			end
		elseif dz ~= 0 then
			-- Need to move along Z axis
			if dz > 0 then
				targetHeading = 2  -- south (+z)
			else
				targetHeading = 0  -- north (-z)
			end
		end
		
		-- Turn to face target heading
		if targetHeading then
			while context.pose.heading ~= targetHeading do
				local turnDiff = (targetHeading - context.pose.heading + 4) % 4
				if turnDiff == 1 or turnDiff == 3 then
					if turnDiff == 1 then
						turn("right", false)
					else
						turn("left", false)
					end
				else
					turn("right", false)
				end
			end
			
			-- Move forward once in the target direction
			local success = safeWaitMove(function()
				return trySafeMove("forward")
			end, "Returning to position", SAFETY_MAX_MOVE_RETRIES)
			if not success then
				log(string.format("Blocked while returning to position at pose (%d,%d,%d)", context.pose.x, context.pose.y, context.pose.z))
				return false
			end
		end
	end
	
	-- Step 2: Navigate vertically to target y position
	while context.pose.y < targetPose.y do
		local success = safeWaitMove(function()
			return trySafeMove("up")
		end, "Ascending to target height", SAFETY_MAX_MOVE_RETRIES)
		if not success then
			log("Failed to ascend to target height")
			return false
		end
	end
	
	while context.pose.y > targetPose.y do
		local success = safeWaitMove(function()
			return trySafeMove("down")
		end, "Descending to target height", SAFETY_MAX_MOVE_RETRIES)
		if not success then
			log("Failed to descend to target height")
			return false
		end
	end
	
	-- Step 3: Restore original heading
	while context.pose.heading ~= targetPose.heading do
		local turnDiff = (targetPose.heading - context.pose.heading + 4) % 4
		if turnDiff == 1 or turnDiff == 3 then
			if turnDiff == 1 then
				turn("right", false)
			else
				turn("left", false)
			end
		else
			turn("right", false)
		end
	end
	
	return true
end

local function returnAlongPathSafely(savedPath)
	for index = #savedPath, 1, -1 do
		local operation = savedPath[index]
		if not safePerformForward(operation) then
			return false
		end
		context.movementHistory[#context.movementHistory + 1] = operation
	end
	return true
end

local function getLayer(index)
	local cached = context.layerCache[index]
	if cached then
		return cached
	end
	local layer = resolveLayer(index, context.layerCache, context.manifest)
	context.layerCache[index] = layer
	return layer
end

local function getSerpentineX(rowIndex, cursorX, rowLength)
	if rowIndex % 2 == 1 then
		return cursorX
	end
	return rowLength - (cursorX - 1)
end

local function getCurrentBlock()
	if context.currentY > context.height then
		return nil
	end
	local layer = getLayer(context.currentY)
	local row = layer[context.currentZ]
	if not row then
		return nil
	end
	local rowLength = #row
	local xIndex = getSerpentineX(context.currentZ, context.currentX, rowLength)
	local symbol = row:sub(xIndex, xIndex)
	if not symbol then
		return nil
	end
	return context.manifest.legend[symbol]
end

local function advanceCursorAfterPlacement()
	local layer = getLayer(context.currentY)
	local rowLength = #layer[1]
	if context.currentX < rowLength then
		if not move("forward", SAFETY_MAX_MOVE_RETRIES, true) then
			transitionToState(context, STATE_BLOCKED, "Blocked while advancing row", STATE_BUILD)
			return
		end
		context.currentX = context.currentX + 1
		return
	end

	if context.currentZ < context.depth then
		local turnDirection = (context.currentZ % 2 == 1) and "right" or "left"
		if not turn(turnDirection, true) then
			transitionToState(context, STATE_BLOCKED, "Failed serpentine pivot", STATE_BUILD)
			return
		end
		if not move("forward", SAFETY_MAX_MOVE_RETRIES, true) then
			transitionToState(context, STATE_BLOCKED, "Blocked during serpentine advance", STATE_BUILD)
			return
		end
		if not turn(turnDirection, true) then
			transitionToState(context, STATE_BLOCKED, "Failed serpentine reorient", STATE_BUILD)
			return
		end
		context.currentZ = context.currentZ + 1
		context.currentX = 1
		return
	end

	local perimeterTurn = (context.depth % 2 == 0) and "right" or "left"
	if not turn(perimeterTurn, true) then
		transitionToState(context, STATE_BLOCKED, "Failed to align for layer exit", STATE_BUILD)
		return
	end
	for step = 1, context.depth - 1 do
		if not move("forward", SAFETY_MAX_MOVE_RETRIES, true) then
			transitionToState(context, STATE_BLOCKED, "Blocked while exiting layer", STATE_BUILD)
			return
		end
	end
	if not turn(perimeterTurn, true) then
		transitionToState(context, STATE_BLOCKED, "Failed to reset orientation after exit", STATE_BUILD)
		return
	end
	if not move("up", SAFETY_MAX_MOVE_RETRIES, true) then
		transitionToState(context, STATE_BLOCKED, "Unable to ascend to next layer", STATE_BUILD)
		return
	end
	context.currentY = context.currentY + 1
	context.currentZ = 1
	context.currentX = 1
end

local function placeBlock(blockName)
	if not blockName or blockName == context.airBlock then
		return true
	end
	if CONFIG.mockMovements then
		log("Mock placing block: " .. tostring(blockName))
		return true
	end
	local ok, data = turtle.inspectDown()
	if ok and data and itemsShareFamily(data.name, blockName) then
		log("Target already present: " .. blockName)
		return true
	end
	for slot = 1, 16 do
		local detail = turtle.getItemDetail(slot)
		if detail and itemsShareFamily(detail.name, blockName) then
			local previous = turtle.getSelectedSlot()
			turtle.select(slot)
			if turtle.placeDown() then
				turtle.select(previous)
				return true
			end
			turtle.digDown()
			if turtle.placeDown() then
				turtle.select(previous)
				return true
			end
			turtle.select(previous)
		end
	end
	return false
end

local function attemptPlaceCurrent(blockName)
	if not blockName or blockName == context.airBlock then
		return true
	end
	local placed = placeBlock(blockName)
	if placed and context.remainingMaterials[blockName] then
		context.remainingMaterials[blockName] = math.max(context.remainingMaterials[blockName] - 1, 0)
	end
	return placed
end

-------------------------------------------------------------------------------
-- SECTION 11: ORIGIN CHEST ACCESS
-------------------------------------------------------------------------------

function context.getChestAccessFunctions()
	-- Prefer a fixed orientation based on saved offset relative to current heading
	if context.chestOffset and context.pose then
		local h = context.pose.heading
		local rel = context.chestOffset
		local dirLabel = nil
		local f = directionToOffset("front", h)
		local r = directionToOffset("right", h)
		local b = directionToOffset("behind", h)
		local l = directionToOffset("left", h)
		if rel and f and rel.x == f.x and rel.y == f.y and rel.z == f.z then dirLabel = "front" end
		if not dirLabel and rel and r and rel.x == r.x and rel.y == r.y and rel.z == r.z then dirLabel = "right" end
		if not dirLabel and rel and b and rel.x == b.x and rel.y == b.y and rel.z == b.z then dirLabel = "behind" end
		if not dirLabel and rel and l and rel.x == l.x and rel.y == l.y and rel.z == l.z then dirLabel = "left" end
		if not dirLabel and rel then
			if rel.y == 1 then dirLabel = "up" elseif rel.y == -1 then dirLabel = "down" end
		end
		if dirLabel then
			return getPeripheralFunctions(dirLabel)
		end
	end
	local direction = context.chestDirection or "front"
	return getPeripheralFunctions(direction)
end

local function checkTreasureChestBehind()
	if CONFIG.mockMovements then
		return true, "supplementaries:treasure_chest", { name = "supplementaries:treasure_chest" }
	end
	local startingHeading = context.pose and context.pose.heading or 0
	turnLeftNoHistory()
	turnLeftNoHistory()
	local ok, data = turtle.inspect()
	turnRightNoHistory()
	turnRightNoHistory()
	if context.pose then
		context.pose.heading = startingHeading -- restore heading explicitly
	end
	if not ok or not data then
		return false, nil, nil
	end
	return isTreasureChestId(data.name), data.name, data
end

local function refuelFromOriginChest(targetLevel)
	if CONFIG.mockMovements then
		return true, true
	end
	local chestFunctions = context.getChestAccessFunctions()
	local ok, data = chestFunctions.inspect()
	if not ok or not data or not isInventoryBlock(data.name) then
		return false, false
	end
	if not pullAndFilterItems(chestFunctions, FUEL_ALLOWED_SET, MAX_PULL_ATTEMPTS) then
		return false, true
	end
	local refueled = false
	if tryRefuelFromSlot(REFUEL_SLOT, targetLevel) then
		refueled = true
	end
	for slot = 1, 15 do
		if turtle.getFuelLevel() >= targetLevel then
			break
		end
		if tryRefuelFromSlot(slot, targetLevel) then
			refueled = true
		end
	end
	return refueled or turtle.getFuelLevel() >= targetLevel or isFuelUnlimited(), true
end

local function restockFromOriginChest(missingTable, allowedUniverse)
	if CONFIG.mockMovements then
		for blockName in pairs(missingTable) do
			missingTable[blockName] = 0
		end
		return true, true
	end
	local chestFunctions = context.getChestAccessFunctions()
	local ok, data = chestFunctions.inspect()
	if not ok or not data or not isInventoryBlock(data.name) then
		return false, false
	end
	local pulled = restockItems(missingTable, allowedUniverse, chestFunctions, MAX_PULL_ATTEMPTS)
	return pulled, true
end

-------------------------------------------------------------------------------
-- SECTION 12: STATE MACHINE
-------------------------------------------------------------------------------

local states = {}

states[STATE_INITIALIZE] = function(ctx)
	local treasureOk = checkTreasureChestBehind()
	if not treasureOk then
		transitionToState(ctx, STATE_ERROR, "Treasure chest required behind turtle", STATE_INITIALIZE)
		return
	end

	-- Capture initial absolute chest position once at start based on detected chest direction
	if not ctx.chestPosition then
		local detectedDir = findAdjacentStorageDirection()
		ctx.chestDirection = detectedDir
		if detectedDir and ctx.pose then
			local offset = directionToOffset(detectedDir, ctx.pose.heading)
			if offset then
				ctx.chestOffset = offset
				ctx.chestPosition = { x = ctx.pose.x + offset.x, y = ctx.pose.y + offset.y, z = ctx.pose.z + offset.z }
				print(string.format("Chest mapped at relative offset (%d,%d,%d) heading=%d", offset.x, offset.y, offset.z, ctx.pose.heading))
			else
				print("Chest direction found but offset unknown")
			end
		else
			print("No chest mapped during initialization")
		end
	end

	print("Initializing builder ...")

	ctx.chestDirection = findAdjacentStorageDirection()
	if not ctx.chestDirection then
		if CONFIG.autoMode then
			log("No adjacent storage detected at origin (continuing)")
		else
			transitionToState(ctx, STATE_ERROR, "No adjacent storage detected at origin", STATE_INITIALIZE)
			return
		end
	end

	ctx.remainingMaterials = cloneTable(MATERIAL_REQUIREMENTS)

	local chestFunctions
	if ctx.chestDirection then
		chestFunctions = getPeripheralFunctions(ctx.chestDirection)
	else
		chestFunctions = getPeripheralFunctions("front")
	end

	if not isFuelUnlimited() then
		print("Starting fuel level: " .. turtle.getFuelLevel())
		refuel()
	end

	local chestReady = false
	if chestFunctions then
		local ok, data = chestFunctions.inspect()
		if ok and data and isInventoryBlock(data.name) then
			chestReady = true
		end
	end

	if chestReady then
		local pulledInitial = performInitialRestock(ctx.remainingMaterials, chestFunctions, INITIAL_STOCK_TARGET)
		if pulledInitial then
			print("Loaded starter materials from origin chest")
		else
			print("Inventory already holds starter materials")
		end
	else
		print("No valid origin chest for initial material stock")
	end

	if CONFIG.preloadMaterials then
		print("Preloading required materials (blocking mode)")
		ensureMaterialsAvailable(ctx.remainingMaterials, nil, true)
	else
		print("On-demand restock enabled")
	end

	ctx.inventorySummary = tallyInventory()

	print("Opening service corridor")
	if not move("forward", SAFETY_MAX_MOVE_RETRIES, true) then
		transitionToState(ctx, STATE_ERROR, "Unable to establish service corridor", STATE_INITIALIZE)
		return
	end

	transitionToState(ctx, STATE_BUILD, nil, nil)
end

states[STATE_BUILD] = function(ctx)
	if ctx.currentY > ctx.height then
		transitionToState(ctx, STATE_DONE, nil, nil)
		return
	end

	if not isFuelUnlimited() and turtle.getFuelLevel() < FUEL_THRESHOLD then
		ctx.serviceRequest = {
			type = "fuel",
			fuelTarget = FUEL_THRESHOLD * 2,
		}
		transitionToState(ctx, STATE_SERVICE, nil, STATE_BUILD)
		return
	end

	local blockName = getCurrentBlock()
	if blockName and blockName ~= ctx.airBlock then
		local inventoryCount = countFamilyInInventory(nil, blockName)
		local stillNeeded = (ctx.remainingMaterials[blockName] or 0) > 0
		if inventoryCount == 0 and stillNeeded then
			ctx.serviceRequest = {
				type = "material",
				materialName = blockName,
				requestedCount = 1,
			}
			log("Proactive restock trigger for " .. blockName)
			transitionToState(ctx, STATE_SERVICE, nil, STATE_BUILD)
			return
		end
	end

	log(string.format("Placing Y=%d Z=%d X=%d : %s", ctx.currentY, ctx.currentZ, ctx.currentX, tostring(blockName or "air")))
	local placed = attemptPlaceCurrent(blockName)
	if not placed and blockName and blockName ~= ctx.airBlock then
		ctx.serviceRequest = {
			type = "material",
			materialName = blockName,
			requestedCount = 1,
		}
		transitionToState(ctx, STATE_SERVICE, nil, STATE_BUILD)
		return
	end

	advanceCursorAfterPlacement()

	if ctx.currentY > ctx.height then
		transitionToState(ctx, STATE_DONE, nil, nil)
	end
end

states[STATE_SERVICE] = function(ctx)
	local request = ctx.serviceRequest
	if not request then
		transitionToState(ctx, STATE_ERROR, "SERVICE invoked without request", ctx.previousState)
		return
	end

	if request.type == "material" then
		print("Restocking: " .. request.materialName)
	elseif request.type == "fuel" then
		print("Refueling to level: " .. tostring(request.fuelTarget))
	else
		transitionToState(ctx, STATE_ERROR, "Unknown service type " .. tostring(request.type), ctx.previousState)
		return
	end

	-- Use direct navigation to origin instead of ascending and reversing movement history
	print(string.format("Navigating to origin from (%d,%d,%d)", ctx.pose.x, ctx.pose.y, ctx.pose.z))
	local returnPath = goToOriginDirectly()

	local performService
	local successCheck
	local retryLabel

	if request.type == "material" then
		local missing = { [request.materialName] = request.requestedCount or 1 }
		performService = function()
			restockFromOriginChest(missing, ctx.remainingMaterials)
		end
		successCheck = function()
			return (missing[request.materialName] or 1) <= 0
		end
		retryLabel = "Awaiting material restock"
	else
		performService = function()
			refuelFromOriginChest(request.fuelTarget)
		end
		successCheck = function()
			return isFuelUnlimited() or turtle.getFuelLevel() >= request.fuelTarget
		end
		retryLabel = "Awaiting fuel at origin"
	end

	retryOperation(performService, successCheck, retryLabel)

	-- Return directly to the saved position
	print(string.format("Returning to build position (%d,%d,%d)", returnPath.startPose.x, returnPath.startPose.y, returnPath.startPose.z))
	local returnOk = returnToPositionDirectly(returnPath)
	if not returnOk then
		transitionToState(ctx, STATE_ERROR, "Failed to return from service", STATE_SERVICE)
		return
	end

	if not successCheck() then
		transitionToState(ctx, STATE_ERROR, "Service verification failed", STATE_SERVICE)
		return
	end

	ctx.serviceRequest = nil
	local resume = ctx.previousState or STATE_BUILD
	transitionToState(ctx, resume, nil, nil)
end

states[STATE_BLOCKED] = function(ctx)
	print("Blocked: " .. tostring(ctx.lastError))
	local path = goToOriginDirectly()
	if CONFIG.autoMode then
		sleep(AUTO_RETRY_SECONDS)
	else
		print("Clear the obstruction and press Enter")
		read()
	end
	if not returnToPositionDirectly(path) then
		transitionToState(ctx, STATE_ERROR, "Failed to return after blockage", STATE_BLOCKED)
		return
	end
	transitionToState(ctx, ctx.previousState or STATE_BUILD, nil, nil)
	ctx.lastError = nil
end

states[STATE_ERROR] = function(ctx)
	print("ERROR: " .. tostring(ctx.lastError))
	if CONFIG.autoMode then
		print("Auto-retry in " .. AUTO_RETRY_SECONDS .. " seconds")
		sleep(AUTO_RETRY_SECONDS)
	else
		print("Press Enter to resume")
		read()
	end
	local resume = ctx.previousState or STATE_INITIALIZE
	transitionToState(ctx, resume, nil, nil)
	ctx.lastError = nil
end

states[STATE_DONE] = function()
	print("Build complete!")
end

-------------------------------------------------------------------------------
-- SECTION 13: MAIN EXECUTION LOOP
-------------------------------------------------------------------------------

local function main()
    print("Factory Builder v2.0 - Starting")
    print("Manifest: " .. context.manifestPath)
    print(string.format("Build size: %dx%dx%d", context.width, context.height, context.depth))
    
    while context.currentState ~= STATE_DONE do
        local handler = states[context.currentState]
        if not handler then
            error("No handler for state: " .. tostring(context.currentState))
        end
        handler(context)
        
        -- Prevent infinite loops in error states
        if context.currentState == STATE_ERROR or context.currentState == STATE_BLOCKED then
            sleep(0.1)
        end
    end
    
    print("Build complete! Returning to origin...")
    goToOriginDirectly()
    print("Factory build finished successfully.")
end

-- Start the program
main()
