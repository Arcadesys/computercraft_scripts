--[[
  Service Module
    Combines fuel budgeting, position reporting, inventory restocking, and safety helpers.

  Features:
  - Fuel threshold monitoring with optional auto-refuel
  - Distance calculations to the recorded home position
    - Item restocking helpers that pull supplies from adjacent chests
    - Convenience print helpers for quick diagnostics
  - Built-in self-test that reports fuel state and attempts a top-up
]]

local function safeRequire(moduleName)
    local attempts = {}

    local candidates = {moduleName}
    local underscored = moduleName:gsub("%.", "_")
    if underscored ~= moduleName then
        table.insert(candidates, underscored)
    end

    local lastError = nil
    for _, candidate in ipairs(candidates) do
        local ok, result = pcall(require, candidate)
        if ok then
            if candidate ~= moduleName and type(package) == "table" and type(package.loaded) == "table" then
                package.loaded[moduleName] = result
            end
            return result
        end
        lastError = result
        attempts[#attempts + 1] = string.format("require('%s') -> %s", candidate, tostring(result))
    end

    -- Fallback for ComputerCraft where package.path may not include the script directory.
    local env = _ENV or _G
    local function getEnvField(name)
        if type(env) ~= "table" then
            return nil
        end
        return rawget(env, name)
    end

    local fs = getEnvField("fs")
    local shell = getEnvField("shell")

    if not fs or not shell or not shell.getRunningProgram then
        error(string.format(
            "Unable to require '%s': %s",
            moduleName,
            tostring(lastError or "filesystem APIs unavailable")
        ))
    end

    local searchRoots = {}

    local programPath = shell.getRunningProgram() or ""
    if programPath ~= "" and fs.getDir then
        local programDir = fs.getDir(programPath)
        if programDir and programDir ~= "" then
            table.insert(searchRoots, programDir)
            local parentDir = fs.getDir(programDir)
            if parentDir and parentDir ~= programDir then
                table.insert(searchRoots, parentDir)
            end
        end
    end

    if shell.dir then
        local workingDir = shell.dir()
        if workingDir and workingDir ~= "" then
            table.insert(searchRoots, workingDir)
        end
    end

    table.insert(searchRoots, "")

    local seen = {}
    for _, root in ipairs(searchRoots) do
        if not seen[root] then
            seen[root] = true
            for _, candidateName in ipairs(candidates) do
                local candidatePath = candidateName .. ".lua"
                if root ~= "" then
                    candidatePath = fs.combine(root, candidatePath)
                end

                if fs.exists(candidatePath) and not fs.isDir(candidatePath) then
                    local chunk, loadErr = loadfile(candidatePath)
                    if chunk then
                        local okChunk, moduleValue = pcall(chunk, candidateName)
                        if okChunk then
                            if type(package) == "table" and type(package.loaded) == "table" then
                                package.loaded[candidateName] = moduleValue
                                package.loaded[moduleName] = moduleValue
                            end
                            return moduleValue
                        else
                            table.insert(attempts, string.format("%s (runtime failure: %s)", candidatePath, tostring(moduleValue)))
                        end
                    else
                        table.insert(attempts, string.format("%s (load failure: %s)", candidatePath, tostring(loadErr)))
                    end
                else
                    table.insert(attempts, string.format("%s (not found)", candidatePath))
                end
            end
        end
    end

    error(string.format(
        "Unable to require '%s'. Attempts: %s",
        moduleName,
        table.concat(attempts, "; ")
    ))
end

local Movement = safeRequire("factory_lib_movement")
local Inventory = safeRequire("factory_lib_inventory")

local Service = {}

Service.defaultSupplyDirections = {"front", "down", "back"}

Service.defaultFuelCatalog = {
    {search = "minecraft:lava_bucket", fuelValue = 1000},
    {search = "minecraft:coal_block", fuelValue = 800},
    {search = "minecraft:charcoal_block", fuelValue = 800},
    {search = "minecraft:blaze_rod", fuelValue = 180},
    {search = "minecraft:dried_kelp_block", fuelValue = 200},
    {search = "minecraft:charcoal", fuelValue = 80},
    {search = "minecraft:coal", fuelValue = 80},
    {search = "create:coal_coke", fuelValue = 320},
    {search = "immersiveengineering:coal_coke", fuelValue = 320},
    {search = "mekanism:block_charcoal", fuelValue = 800},
    {search = "mekanism:block_coal", fuelValue = 800},
    {search = "thermal:coal_coke", fuelValue = 320},
    {search = ":log", fuelValue = 15},
    {search = ":planks", fuelValue = 15},
}

local function numericFuelLevel()
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then
        return math.huge
    end
    return tonumber(fuelLevel) or 0
end

local function fuelLimit()
    if turtle.getFuelLimit then
        local limit = turtle.getFuelLimit()
        if limit == "unlimited" then
            return math.huge
        end
        return tonumber(limit) or math.huge
    end
    return math.huge
end

--- Determine whether the turtle should refuel soon.
function Service.needsRefuel(threshold)
    threshold = threshold or 100
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then
        return false
    end
    return fuelLevel < threshold
end

--- Manhattan distance from the current position to home.
function Service.distanceToHome()
    local pos = Movement.position
    local home = Movement.homePosition
    return math.abs(pos.x - home.x) + math.abs(pos.y - home.y) + math.abs(pos.z - home.z)
end

--- Check whether we can return home with a safety buffer.
function Service.canReturnHome(safetyMargin)
    safetyMargin = safetyMargin or 20
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then
        return true
    end
    return fuelLevel >= (Service.distanceToHome() + safetyMargin)
end

--- Attempt to refuel using inventory items until the target level is hit.
function Service.refuelFromInventory(targetFuel)
    local fuelLevel = numericFuelLevel()
    if fuelLevel == math.huge then
        return true, fuelLevel
    end

    targetFuel = math.min(targetFuel or math.huge, fuelLimit())

    local originalSlot = turtle.getSelectedSlot and turtle.getSelectedSlot()

    for slot = 1, 16 do
        if fuelLevel >= targetFuel then
            if originalSlot then turtle.select(originalSlot) end
            return true, fuelLevel
        end

        turtle.select(slot)
        local detail = turtle.getItemDetail()
        if detail and turtle.refuel and turtle.refuel(0) then
            local consumed = 0
            repeat
                local ok = turtle.refuel(1)
                if not ok then
                    break
                end
                consumed = consumed + 1
                fuelLevel = numericFuelLevel()
            until fuelLevel >= targetFuel
        end
    end

    if originalSlot then turtle.select(originalSlot) end

    return fuelLevel >= targetFuel, fuelLevel
end

--- Ensure the turtle has enough fuel, optionally returning home to refuel.
local function validateDirections(directions)
    if type(directions) == "string" then
        return {directions}
    end
    if type(directions) ~= "table" then
        return Service.defaultSupplyDirections
    end
    local filtered = {}
    for _, entry in ipairs(directions) do
        if type(entry) == "string" and entry ~= "" then
            filtered[#filtered + 1] = entry
        end
    end
    if #filtered == 0 then
        return Service.defaultSupplyDirections
    end
    return filtered
end

local function normalizeFuelCatalog(catalog)
    if type(catalog) ~= "table" then
        return Service.defaultFuelCatalog
    end
    local normalized = {}
    for _, entry in ipairs(catalog) do
        if type(entry) == "string" then
            normalized[#normalized + 1] = {search = entry, fuelValue = 80}
        elseif type(entry) == "table" then
            local search = entry.search or entry.name or entry.item
            if type(search) == "string" and search ~= "" then
                normalized[#normalized + 1] = {
                    search = search,
                    fuelValue = entry.fuelValue or entry.value or entry.energy or 80,
                    maxPull = entry.maxPull,
                }
            end
        end
    end
    if #normalized == 0 then
        return Service.defaultFuelCatalog
    end
    return normalized
end

local function tryRefuelFromSupply(targetFuel, options)
    if not Inventory or not Inventory.findItemInChest then
        return false, numericFuelLevel(), "inventory_module_unavailable"
    end

    local directions = validateDirections(options and options.supplyDirections or Service.defaultSupplyDirections)
    local catalog = normalizeFuelCatalog(options and options.fuelCatalog or Service.defaultFuelCatalog)
    local allowPartial = options and options.allowPartialSupply

    local currentFuel = numericFuelLevel()
    local baselineFuel = currentFuel
    if currentFuel >= targetFuel then
        return true, currentFuel
    end

    local target = math.min(targetFuel, fuelLimit())

    local resultLog = {}
    for _, direction in ipairs(directions) do
        for _, candidate in ipairs(catalog) do
            if currentFuel >= target then
                break
            end

            local search = candidate.search
            local perItem = candidate.fuelValue or 80
            if perItem <= 0 then
                perItem = 80
            end
            local missing = target - currentFuel
            local quantity = math.max(1, math.ceil(missing / perItem))
            if candidate.maxPull then
                quantity = math.min(quantity, candidate.maxPull)
            end

            local ok, pulled = Inventory.findItemInChest(search, quantity, direction)
            if ok and pulled and pulled > 0 then
                Service.refuelFromInventory(target)
                currentFuel = numericFuelLevel()
                resultLog[#resultLog + 1] = {
                    direction = direction,
                    search = search,
                    pulled = pulled,
                    after = currentFuel,
                }
            end
        end
    end

    local success = currentFuel >= target
    if not success and allowPartial and currentFuel > baselineFuel then
        success = true
    end

    return success, currentFuel, resultLog
end

function Service.ensureFuel(requiredFuel, returnHomeOnLow, options)
    local opts
    if type(requiredFuel) == "table" and returnHomeOnLow == nil and options == nil then
        opts = requiredFuel
        requiredFuel = opts.targetFuel or opts.minimumFuel or opts.requiredFuel or 0
        returnHomeOnLow = opts.returnHomeOnLow
    elseif type(returnHomeOnLow) == "table" and options == nil then
        opts = returnHomeOnLow
        returnHomeOnLow = opts.returnHomeOnLow
    else
        opts = options or {}
    end

    if opts.returnHomeOnLow == nil then
        opts.returnHomeOnLow = returnHomeOnLow or false
    end

    requiredFuel = tonumber(requiredFuel) or 0
    local targetFuel = opts.targetFuel or requiredFuel or 0
    targetFuel = math.max(targetFuel, opts.minimumFuel or 0)
    targetFuel = math.min(targetFuel, fuelLimit())

    local fuelLevel = numericFuelLevel()
    if fuelLevel == math.huge then
        return true, fuelLevel
    end

    if fuelLevel >= targetFuel then
        return true, fuelLevel
    end

    local fromInventory, updated = Service.refuelFromInventory(targetFuel)
    fuelLevel = updated
    if fromInventory and fuelLevel >= targetFuel then
        return true, fuelLevel
    end

    local fromSupply, supplyLevel = tryRefuelFromSupply(targetFuel, opts)
    fuelLevel = supplyLevel or fuelLevel
    if fromSupply and fuelLevel >= targetFuel then
        return true, fuelLevel
    end

    if not opts.returnHomeOnLow then
        return false, fuelLevel
    end

    local origin = Movement.getPosition()
    if not Movement.goHome(false) then
        return false, fuelLevel
    end

    local homeRefueled, homeLevel = Service.refuelFromInventory(targetFuel)
    fuelLevel = homeLevel or fuelLevel
    if not homeRefueled then
        local _, supplyAtHome = tryRefuelFromSupply(targetFuel, opts)
        fuelLevel = supplyAtHome or fuelLevel
    end

    local success = fuelLevel >= targetFuel
    Movement.goTo(origin.x, origin.y, origin.z, false)
    return success, fuelLevel
end

--- Pretty-print the current position and fuel state for quick diagnostics.
function Service.printPosition()
    local facingNames = {"North", "East", "South", "West"}
    local pos = Movement.position
    local facing = facingNames[pos.facing + 1]
    local fuel = turtle.getFuelLevel()
    print(string.format(
        "Position: (%d, %d, %d) Facing: %s Fuel: %s",
        pos.x,
        pos.y,
        pos.z,
        facing,
        tostring(fuel)
    ))
end

--- Intentional export to allow other modules to reuse the raw position tracker.
function Service.getTrackedState()
    return Movement.getPosition(), Movement.homePosition
end

local function cloneTable(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function normalizeItemSpec(spec, sharedOptions)
    local combined = {}
    if type(spec) == "table" then
        for key, value in pairs(spec) do
            combined[key] = value
        end
    else
        combined.search = spec
    end

    if type(sharedOptions) == "table" then
        for key, value in pairs(sharedOptions) do
            if combined[key] == nil then
                combined[key] = value
            end
        end
    end

    combined.search = combined.search or combined.name or combined.item
    if type(combined.search) ~= "string" or combined.search == "" then
        return nil, "item search string required"
    end

    combined.minimum = combined.minimum or combined.min or combined.need or combined.required or 1
    combined.target = combined.target or combined.desired or combined.want or combined.minimum
    if combined.target < combined.minimum then
        combined.target = combined.minimum
    end

    if type(combined.directions) == "string" then
        combined.directions = {combined.directions}
    elseif type(combined.directions) ~= "table" then
        combined.directions = nil
    end

    combined.directions = combined.directions or combined.supplyDirections or Service.defaultSupplyDirections
    combined.directions = validateDirections(combined.directions)

    combined.allowPartial = not not combined.allowPartial

    return combined
end

--- Ensure the turtle carries at least `minimum` of the requested item.
-- When insufficient, the turtle will pull from nearby chests using Inventory helpers.
function Service.ensureItem(spec, override)
    if not Inventory then
        return false, 0, {status = "inventory_module_unavailable", pulls = {}}
    end

    local normalized, err = normalizeItemSpec(spec, override)
    if not normalized then
        return false, 0, {status = "invalid_spec", message = err, pulls = {}}
    end

    local count = Inventory.countItem(normalized.search)
    if count >= normalized.minimum then
        return true, count, {
            status = "already_satisfied",
            pulls = {},
            message = "inventory already satisfies requirement",
        }
    end

    local target = math.max(normalized.target, normalized.minimum)
    local needed = target - count

    local pulls = {}
    for _, direction in ipairs(normalized.directions) do
        if needed <= 0 then break end
        local ok, pulled = Inventory.findItemInChest(normalized.search, needed, direction)
        if ok and pulled and pulled > 0 then
            count = count + pulled
            needed = math.max(0, target - count)
            pulls[#pulls + 1] = {direction = direction, pulled = pulled}
        end
    end

    if count >= normalized.minimum then
        return true, count, {
            status = "restocked",
            pulls = pulls,
            message = "restock successful",
        }
    end

    if normalized.allowPartial and count > 0 then
        return true, count, {
            status = "partial",
            pulls = pulls,
            message = "partial restock",
        }
    end

    return false, count, {
        status = "insufficient",
        pulls = pulls,
        message = "insufficient stock in supply chests",
    }
end

--- Ensure multiple resource specifications are satisfied.
-- Returns true when every specification succeeds.
function Service.ensureItems(plan, sharedOptions)
    if type(plan) ~= "table" then
        return false, {}
    end

    local results = {}
    local allOk = true
    for index, spec in ipairs(plan) do
        local ok, count, detail = Service.ensureItem(spec, sharedOptions)
        results[index] = {
            ok = ok,
            count = count,
            detail = detail,
            spec = cloneTable(type(spec) == "table" and spec or {search = spec}),
        }
        if not ok then
            allOk = false
        end
    end

    return allOk, results
end

--- Self-test routine that reports position, fuel state, and performs a refuel attempt.
function Service.runSelfTest()
    print("[service] Starting self-test")
    Movement.initPosition(0, 0, 0, 0)
    Service.printPosition()

    local fuelLevel = turtle.getFuelLevel()
    print(string.format("[service] Current fuel level: %s", tostring(fuelLevel)))

    local distance = Service.distanceToHome()
    print(string.format("[service] distanceToHome() -> %d", distance))

    local threshold = 50
    print(string.format("[service] needsRefuel(%d) -> %s", threshold, tostring(Service.needsRefuel(threshold))))
    print(string.format("[service] canReturnHome(20) -> %s", tostring(Service.canReturnHome(20))))

    local ensured, ensuredLevel = Service.ensureFuel(threshold, {returnHomeOnLow = false, allowPartialSupply = true})
    print(string.format("[service] ensureFuel(%d) -> %s (fuel=%s)", threshold, tostring(ensured), tostring(ensuredLevel)))
    Service.printPosition()

    local refueled = Service.refuelFromInventory(threshold)
    print(string.format("[service] refuelFromInventory(%d) -> %s", threshold, tostring(refueled)))

    local posCopy, homeCopy = Service.getTrackedState()
    print(string.format("[service] getTrackedState() -> pos(%d,%d,%d) home(%d,%d,%d)", posCopy.x, posCopy.y, posCopy.z, homeCopy.x, homeCopy.y, homeCopy.z))

    print("[service] Self-test complete")
end

local moduleName = ...
if moduleName == nil then
    Service.runSelfTest()
end

return Service
