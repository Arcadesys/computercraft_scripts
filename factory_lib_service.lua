--[[
  Service Module
  Combines fuel budgeting, position reporting, and safety helpers.

  Features:
  - Fuel threshold monitoring with optional auto-refuel
  - Distance calculations to the recorded home position
  - Convenience print helpers for quick diagnostics
  - Built-in self-test that reports fuel state and attempts a top-up
]]

local Movement = require("factory.lib.movement")

local Service = {}

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
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then
        return true
    end

    targetFuel = targetFuel or math.huge

    for slot = 1, 16 do
        if fuelLevel >= targetFuel then
            return true
        end
        turtle.select(slot)
        local detail = turtle.getItemDetail()
        if detail and turtle.refuel(0) then
            turtle.refuel(1)
            fuelLevel = turtle.getFuelLevel()
        end
    end

    return fuelLevel >= targetFuel
end

--- Ensure the turtle has enough fuel, optionally returning home to refuel.
function Service.ensureFuel(requiredFuel, returnHomeOnLow)
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then
        return true
    end

    if fuelLevel >= requiredFuel then
        return true
    end

    if Service.refuelFromInventory(requiredFuel) then
        return true
    end

    if not returnHomeOnLow then
        return false
    end

    local origin = Movement.getPosition()
    if not Movement.goHome(false) then
        return false
    end

    if Service.refuelFromInventory(requiredFuel) then
        return Movement.goTo(origin.x, origin.y, origin.z, false)
    end

    -- Could not locate fuel even at home.
    Movement.goTo(origin.x, origin.y, origin.z, false)
    return false
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

    local ensured = Service.ensureFuel(threshold, false)
    print(string.format("[service] ensureFuel(%d, false) -> %s", threshold, tostring(ensured)))
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
