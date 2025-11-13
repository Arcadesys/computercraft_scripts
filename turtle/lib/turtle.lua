--[[
  Turtle Helper Library
  Deprecation-safe façade that now delegates to the factory/lib modules.

  Modules:
  - factory/lib/movement.lua  (navigation and position tracking)
  - factory/lib/inventory.lua (item and block placement helpers)
  - factory/lib/service.lua   (fuel budgeting and diagnostics)
]]

local Movement = require("factory.lib.movement")
local Inventory = require("factory.lib.inventory")
local Service = require("factory.lib.service")

local TurtleLib = {}

TurtleLib.position = Movement.position
TurtleLib.homePosition = Movement.homePosition

local function export(source, names)
    for _, name in ipairs(names) do
        TurtleLib[name] = source[name]
    end
end

export(Movement, {
    "initPosition",
    "getPosition",
    "turnRight",
    "turnLeft",
    "turnToFace",
    "forward",
    "back",
    "up",
    "down",
    "goTo",
    "goHome"
})

export(Inventory, {
    "safePlace",
    "safePlaceUp",
    "safePlaceDown",
    "findItem",
    "countItem",
    "findEmptySlot",
    "getEmptySlotCount",
    "findItemInChest",
    "depositItems"
})

export(Service, {
    "needsRefuel",
    "distanceToHome",
    "canReturnHome",
    "refuelFromInventory",
    "ensureFuel",
    "printPosition",
    "getTrackedState"
})

--- Convenience wrapper to exercise every module from one call.
function TurtleLib.runAllTests()
    print("[turtle] Running delegated self-tests")
    Movement.runSelfTest()
    Inventory.runSelfTest()
    Service.runSelfTest()
    print("[turtle] Self-tests complete")
end

return TurtleLib
