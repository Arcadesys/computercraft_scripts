-- artillery.lua
-- A 2-player artillery game using Pine3D

-- Check if Pine3D is installed
if not fs.exists("Pine3D.lua") and not fs.exists("Pine3D") then
    print("Pine3D not found. Please install it using:")
    print("pastebin run qpJYiYs2")
    return
end

local Pine3D = require("Pine3D")

-- Initialize Frame
local frame = Pine3D.newFrame()
frame:setFoV(60)
frame:setCamera(0, 8, -15, 0.4, 0, 0) -- Positioned high and back, looking down slightly
frame:setBackgroundColor(colors.lightBlue)

-- Game Constants
local GRAVITY = 9.8
local DT = 0.1
local GROUND_Y = 0

-- Game State
local players = {
    {
        id = 1,
        x = -8, y = 0, z = 0,
        angle = 45,
        velocity = 15,
        color = colors.blue,
        model = nil -- Will be assigned
    },
    {
        id = 2,
        x = 8, y = 0, z = 0,
        angle = 135, -- Facing left
        velocity = 15,
        color = colors.red,
        model = nil -- Will be assigned
    }
}

local turn = 1
local projectile = {
    active = false,
    x = 0, y = 0, z = 0,
    vx = 0, vy = 0, vz = 0,
    model = nil
}

-- Load Models
-- We use the modelId "models/tank" assuming the file exists at models/tank.lua
players[1].model = frame:newObject("models/tank", players[1].x, players[1].y, players[1].z)
players[2].model = frame:newObject("models/tank", players[2].x, players[2].y, players[2].z)
projectile.model = frame:newObject("models/projectile", 0, -10, 0) -- Hide initially

-- Helper to draw text on top of 3D view
local function drawUI(text, line)
    term.setCursorPos(1, line)
    term.clearLine()
    term.write(text)
end

local function updateModels()
    -- Update player positions
    for _, p in ipairs(players) do
        if p.model then
             p.model.x = p.x
             p.model.y = p.y
             p.model.z = p.z
             -- Rotate player 2 to face left
             if p.id == 2 then
                 p.model.rotY = math.pi
             end
        end
    end
    
    if projectile.active then
        projectile.model.x = projectile.x
        projectile.model.y = projectile.y
        projectile.model.z = projectile.z
    else
        projectile.model.y = -100 -- Hide
    end
end

local function fire(player)
    projectile.active = true
    projectile.x = player.x
    projectile.y = player.y + 1 -- Start above tank
    projectile.z = player.z
    
    local rad = math.rad(player.angle)
    
    local vx = math.cos(rad) * player.velocity
    local vy = math.sin(rad) * player.velocity
    
    projectile.vx = vx
    projectile.vy = vy
    projectile.vz = 0
end

local function gameLoop()
    while true do
        -- Render
        updateModels()
        frame:drawObjects({players[1].model, players[2].model, projectile.model})
        frame:drawBuffer()
        
        -- UI
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        drawUI("Player " .. turn .. "'s Turn", 1)
        drawUI("Angle: " .. players[turn].angle, 2)
        drawUI("Velocity: " .. players[turn].velocity, 3)
        drawUI("Pos: " .. players[turn].x, 4)
        
        if projectile.active then
            -- Physics
            projectile.x = projectile.x + projectile.vx * DT
            projectile.y = projectile.y + projectile.vy * DT
            projectile.vy = projectile.vy - GRAVITY * DT
            
            -- Collision with ground
            if projectile.y <= GROUND_Y then
                projectile.active = false
                -- Check hit
                local hit = false
                for _, p in ipairs(players) do
                    if math.abs(projectile.x - p.x) < 1.5 then
                        drawUI("HIT Player " .. p.id .. "!", 5)
                        sleep(2)
                        hit = true
                        -- Reset positions? Or just end game?
                        -- For now, just print hit.
                    end
                end
                
                if not hit then
                    drawUI("Miss!", 5)
                    sleep(1)
                end
                
                -- Switch turn
                turn = (turn % 2) + 1
            end
            
            sleep(0.05)
        else
            -- Input
            drawUI("Action: (A)ngle, (V)elocity, (M)ove, (F)ire, (Q)uit", 6)
            
            local event, key = os.pullEvent("char")
            key = string.lower(key)
            
            if key == "a" then
                drawUI("Enter Angle: ", 7)
                term.setCursorPos(14, 7)
                local input = read()
                local num = tonumber(input)
                if num then players[turn].angle = num end
                drawUI("", 7) -- Clear line
            elseif key == "v" then
                drawUI("Enter Velocity: ", 7)
                term.setCursorPos(16, 7)
                local input = read()
                local num = tonumber(input)
                if num then players[turn].velocity = num end
                drawUI("", 7) -- Clear line
            elseif key == "m" then
                drawUI("Move (-1/1): ", 7)
                term.setCursorPos(14, 7)
                local input = read()
                local num = tonumber(input)
                if num then players[turn].x = players[turn].x + num end
                drawUI("", 7) -- Clear line
            elseif key == "f" then
                fire(players[turn])
            elseif key == "q" then
                term.clear()
                term.setCursorPos(1,1)
                break
            end
        end
    end
end

gameLoop()