--[[
  Movement Module
  Handles position tracking and navigation for ComputerCraft turtles.

  Features:
  - Relative position tracking with facing direction
  - Destructive and safe movement helpers
  - Simple pathing helpers for grid-aligned travel
  - Built-in self-test that walks a square and returns home
]]

local Movement = {}

-- The turtle's current offset from the starting location.
Movement.position = {
    x = 0,     -- East(+)/West(-)
    y = 0,     -- Up(+)/Down(-)
    z = 0,     -- South(+)/North(-)
    facing = 0 -- 0=North, 1=East, 2=South, 3=West
}

-- Home is the anchor used for return trips and fuel budgeting.
Movement.homePosition = {x = 0, y = 0, z = 0}

-- Facing vectors for the horizontal plane.
local directionVectors = {
    [0] = {x = 0, z = -1},
    [1] = {x = 1, z = 0},
    [2] = {x = 0, z = 1},
    [3] = {x = -1, z = 0}
}

-- Clamp helper used by movement retries.
local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

--- Initialize the tracked position and facing information.
-- @param homeX Optional start X (default 0)
-- @param homeY Optional start Y (default 0)
-- @param homeZ Optional start Z (default 0)
-- @param homeFacing Optional facing (default 0 = North)
function Movement.initPosition(homeX, homeY, homeZ, homeFacing)
    Movement.position.x = homeX or 0
    Movement.position.y = homeY or 0
    Movement.position.z = homeZ or 0
    Movement.position.facing = clamp(homeFacing or 0, 0, 3)

    Movement.homePosition.x = Movement.position.x
    Movement.homePosition.y = Movement.position.y
    Movement.homePosition.z = Movement.position.z
end

--- Return a copy of the tracked position so callers cannot mutate state.
function Movement.getPosition()
    return {
        x = Movement.position.x,
        y = Movement.position.y,
        z = Movement.position.z,
        facing = Movement.position.facing
    }
end

--- Rotate the turtle clockwise and update facing data.
function Movement.turnRight()
    if turtle.turnRight() then
        Movement.position.facing = (Movement.position.facing + 1) % 4
        return true
    end
    return false
end

--- Rotate the turtle counter-clockwise and update facing data.
function Movement.turnLeft()
    if turtle.turnLeft() then
        Movement.position.facing = (Movement.position.facing - 1) % 4
        return true
    end
    return false
end

--- Spin to face a specific orientation (0=N, 1=E, 2=S, 3=W).
-- Returns true when the heading matches the target.
function Movement.turnToFace(targetFacing)
    targetFacing = clamp(targetFacing % 4, 0, 3)
    local safety = 0

    while Movement.position.facing ~= targetFacing and safety < 8 do
        local diff = (targetFacing - Movement.position.facing) % 4
        if diff <= 2 then
            Movement.turnRight()
        else
            Movement.turnLeft()
        end
        safety = safety + 1
    end

    return Movement.position.facing == targetFacing
end

-- Generic block clearing helper used when destructive travel is enabled.
local function clearBlock(direction)
    if direction == "forward" then
        if turtle.detect() then
            if not turtle.dig() then return false end
        elseif turtle.attack() then
            sleep(0.5)
        else
            return false
        end
        return true
    elseif direction == "up" then
        if turtle.detectUp() then
            if not turtle.digUp() then return false end
        elseif turtle.attackUp() then
            sleep(0.5)
        else
            return false
        end
        return true
    elseif direction == "down" then
        if turtle.detectDown() then
            if not turtle.digDown() then return false end
        elseif turtle.attackDown() then
            sleep(0.5)
        else
            return false
        end
        return true
    end
    return false
end

--- Move forward while updating the tracked position.
-- @param destructive When true, break or attack blocking nodes.
function Movement.forward(destructive)
    if destructive then
        while not turtle.forward() do
            if not clearBlock("forward") then
                return false
            end
        end
    else
        if not turtle.forward() then
            return false
        end
    end

    local dir = directionVectors[Movement.position.facing]
    Movement.position.x = Movement.position.x + dir.x
    Movement.position.z = Movement.position.z + dir.z
    return true
end

--- Move backward while updating the tracked position.
function Movement.back()
    if not turtle.back() then
        return false
    end
    local dir = directionVectors[Movement.position.facing]
    Movement.position.x = Movement.position.x - dir.x
    Movement.position.z = Movement.position.z - dir.z
    return true
end

--- Move upward while updating tracking.
-- @param destructive When true, dig blocks in the way.
function Movement.up(destructive)
    if destructive then
        while not turtle.up() do
            if not clearBlock("up") then
                return false
            end
        end
    else
        if not turtle.up() then
            return false
        end
    end
    Movement.position.y = Movement.position.y + 1
    return true
end

--- Move downward while updating tracking.
-- @param destructive When true, dig blocks in the way.
function Movement.down(destructive)
    if destructive then
        while not turtle.down() do
            if not clearBlock("down") then
                return false
            end
        end
    else
        if not turtle.down() then
            return false
        end
    end
    Movement.position.y = Movement.position.y - 1
    return true
end

--- Navigate to a specific coordinate one axis at a time.
-- @param targetX Target X coordinate
-- @param targetY Target Y coordinate
-- @param targetZ Target Z coordinate
-- @param destructive When true, dig through obstacles
function Movement.goTo(targetX, targetY, targetZ, destructive)
    destructive = destructive or false

    while Movement.position.y < targetY do
        if not Movement.up(destructive) then return false end
    end
    while Movement.position.y > targetY do
        if not Movement.down(destructive) then return false end
    end

    local deltaX = targetX - Movement.position.x
    if deltaX > 0 then
        if not Movement.turnToFace(1) then return false end
        for _ = 1, deltaX do
            if not Movement.forward(destructive) then return false end
        end
    elseif deltaX < 0 then
        if not Movement.turnToFace(3) then return false end
        for _ = 1, -deltaX do
            if not Movement.forward(destructive) then return false end
        end
    end

    local deltaZ = targetZ - Movement.position.z
    if deltaZ > 0 then
        if not Movement.turnToFace(2) then return false end
        for _ = 1, deltaZ do
            if not Movement.forward(destructive) then return false end
        end
    elseif deltaZ < 0 then
        if not Movement.turnToFace(0) then return false end
        for _ = 1, -deltaZ do
            if not Movement.forward(destructive) then return false end
        end
    end

    return true
end

--- Return to the recorded home position.
function Movement.goHome(destructive)
    return Movement.goTo(
        Movement.homePosition.x,
        Movement.homePosition.y,
        Movement.homePosition.z,
        destructive
    )
end

--- Helper to format the tracked position for printing.
local function formatPosition()
    local facingNames = {"North", "East", "South", "West"}
    return string.format(
        "(%d, %d, %d) facing %s",
        Movement.position.x,
        Movement.position.y,
        Movement.position.z,
        facingNames[Movement.position.facing + 1]
    )
end

--- Exercise the movement helpers with a square walk.
-- Runs when the module is executed as a script with no arguments.
function Movement.runSelfTest()
    print("[movement] Starting self-test")
    Movement.initPosition(0, 0, 0, 0)
    print("[movement] Home set at " .. formatPosition())

    local actions = {
        {label = "forward", fn = function() return Movement.forward(true) end},
        {label = "turnRight", fn = Movement.turnRight},
        {label = "forward", fn = function() return Movement.forward(true) end},
        {label = "turnRight", fn = Movement.turnRight},
        {label = "forward", fn = function() return Movement.forward(true) end},
        {label = "turnRight", fn = Movement.turnRight},
        {label = "forward", fn = function() return Movement.forward(true) end},
        {label = "turnRight", fn = Movement.turnRight},
        {label = "back", fn = Movement.back},
        {label = "turnLeft", fn = Movement.turnLeft},
        {label = "up", fn = function() return Movement.up(true) end},
        {label = "down", fn = function() return Movement.down(true) end},
    }

    for index, step in ipairs(actions) do
        local ok, message = step.fn()
        if ok then
            print(string.format("[movement] Step %d (%s) succeeded -> %s", index, step.label, formatPosition()))
        else
            print(string.format("[movement] Step %d (%s) failed: %s", index, step.label, tostring(message)))
            break
        end
        sleep(0.2)
    end

    if Movement.goTo(0, Movement.position.y, 0, true) then
        print("[movement] goTo demonstration -> " .. formatPosition())
    end

    if Movement.goHome(true) then
        print("[movement] Returned to home -> " .. formatPosition())
    else
        print("[movement] Could not return home, current -> " .. formatPosition())
    end

    print("[movement] Self-test complete")
end

local moduleName = ...
if moduleName == nil then
    Movement.runSelfTest()
end

return Movement
