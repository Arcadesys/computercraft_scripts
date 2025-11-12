-- starfield.lua
-- Generates an artificial night sky starfield without destroying blocks.
-- Turtle wanders a 3D region and places 'stars' with safe spacing.
-- Fill slot 1 with your star material (shroomlight, glowstone, tinted glass, etc).

local t = turtle

------------------------------
-- EDIT ME
------------------------------
local X_MIN, X_MAX = 0, 30   -- bounds on X
local Z_MIN, Z_MAX = 0, 30   -- bounds on Z
local Y_MIN, Y_MAX = 30, 60  -- sky height band
local STAR_DENSITY = 0.08    -- probability per step to attempt a star
------------------------------

-- Movement bookkeeping -----------------------------------------------
local function forward()
    for _=1,10 do
        if t.forward() then return true end
        sleep(0.2)
    end
    return false
end

local function up()
    for _=1,10 do
        if t.up() then return true end
        sleep(0.2)
    end
    return false
end

local function down()
    for _=1,10 do
        if t.down() then return true end
        sleep(0.2)
    end
    return false
end

local function turn_random()
    local r = math.random(4)
    for _=1,r do t.turnLeft() end
end

-- Sensing --------------------------------------------------------------
local function isAir(fn)
    local ok, data = fn()
    return ok and data.name == "minecraft:air"
end

-- Check that all six adjacent spaces are air
local function clearForStar()
    -- Current block
    if not isAir(t.inspect) then return false end

    -- Up
    if not isAir(t.inspectUp) then return false end

    -- Down
    if not isAir(t.inspectDown) then return false end

    -- North/East/South/West from turtle’s facing
    t.turnLeft()
    if not isAir(t.inspect) then t.turnRight() return false end
    t.turnRight()

    if not isAir(t.inspect) then t.turnRight() return false end
    t.turnRight()

    if not isAir(t.inspect) then t.turnRight() return false end
    t.turnRight()

    if not isAir(t.inspect) then return false end

    return true
end

-- Place a star
local function placeStar()
    if t.getItemCount(1) == 0 then
        print("Out of star blocks!")
        return false
    end
    t.select(1)
    return t.place()
end

-- Wandering logic -------------------------------------------------------
local function randomStep()
    local axis = math.random(3)
    if axis == 1 then
        -- wander north/south
        turn_random()
        forward()
    elseif axis == 2 then
        -- wander east/west
        turn_random()
        forward()
    else
        -- wander up/down inside band
        if math.random() < 0.5 then
            if posY < Y_MAX then up() end
        else
            if posY > Y_MIN then down() end
        end
    end
end

-- Position tracking (simple local coords)
local posX, posY, posZ = 0, 0, 0
local facing = 0 -- 0=N, 1=E, 2=S, 3=W

local function trackForward()
    if facing == 0 then posZ = posZ - 1
    elseif facing == 1 then posX = posX + 1
    elseif facing == 2 then posZ = posZ + 1
    elseif facing == 3 then posX = posX - 1 end
end

local function trackTurnLeft() facing = (facing + 3) % 4 end
local function trackTurnRight() facing = (facing + 1) % 4 end

-- Monkey-patch tracking
local oldForward = t.forward
t.forward = function()
    if oldForward() then
        trackForward()
        return true
    end
    return false
end

local oldUp = t.up
t.up = function()
    if oldUp() then
        posY = posY + 1
        return true
    end
    return false
end

local oldDown = t.down
t.down = function()
    if oldDown() then
        posY = posY - 1
        return true
    end
    return false
end

local oldLeft = t.turnLeft
t.turnLeft = function()
    oldLeft()
    trackTurnLeft()
end

local oldRight = t.turnRight
t.turnRight = function()
    oldRight()
    trackTurnRight()
end

-- MAIN ------------------------------------------------------------------
print("Rising to sky band…")
while posY < Y_MIN do up() end

print("Painting stars… Ctrl+T to stop.")

while true do
    -- Boundaries: if drifting outside bounds, turn around
    if posX < X_MIN or posX > X_MAX or posZ < Z_MIN or posZ > Z_MAX then
        t.turnLeft()
        t.turnLeft()
        forward()
    else
        randomStep()
    end

    -- Try placing a star randomly
    if math.random() < STAR_DENSITY then
        if clearForStar() then
            placeStar()
        end
    end

    sleep(0.1)
end
