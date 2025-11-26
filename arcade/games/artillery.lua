---@diagnostic disable: undefined-global, undefined-field

local function setupPaths()
    local dir = fs.getDir(shell.getRunningProgram())
    local boot = fs.combine(fs.getDir(dir), "boot.lua")
    if fs.exists(boot) then dofile(boot) end
end

setupPaths()

-- A 2-player artillery game using Pine3D

if not fs.exists("Pine3D.lua") and not fs.exists("Pine3D") then
    print("Pine3D not found. Please install it using:")
    print("pastebin run qpJYiYs2")
    return
end

local Pine3D = require("Pine3D")

local function testLoad(path)
    if not fs.exists(path) then
        print("File not found: " .. path)
        return false
    end
    local ok, err = loadfile(path)
    if not ok then
        printError("Syntax error in " .. path .. ": " .. tostring(err))
        return false
    end
    local ok2, res = pcall(ok)
    if not ok2 then
        printError("Runtime error loading " .. path .. ": " .. tostring(res))
        return false
    end
    return true
end

testLoad("models/tank.lua")
testLoad("models/projectile.lua")

local frame = Pine3D.newFrame()
frame:setFoV(60)
frame:setCamera(0, 8, -15, 0.4, 0, 0)
frame:setBackgroundColor(colors.lightBlue)

local GRAVITY = 9.8
local DT = 0.1
local GROUND_Y = 0

local players = {
    { id = 1, x = -8, y = 0, z = 0, angle = 45, velocity = 15, color = colors.blue, model = nil },
    { id = 2, x = 8, y = 0, z = 0, angle = 135, velocity = 15, color = colors.red, model = nil }
}

local turn = 1
local projectile = {
    active = false,
    x = 0, y = 0, z = 0,
    vx = 0, vy = 0, vz = 0,
    model = nil
}

players[1].model = frame:newObject("tank", players[1].x, players[1].y, players[1].z)
players[2].model = frame:newObject("tank", players[2].x, players[2].y, players[2].z)
projectile.model = frame:newObject("projectile", 0, -10, 0)

local function drawUI(text, line)
    term.setCursorPos(1, line)
    term.clearLine()
    term.write(text)
end

local function updateModels()
    for _, p in ipairs(players) do
        if p.model then
            p.model.x = p.x
            p.model.y = p.y
            p.model.z = p.z
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
        projectile.model.y = -100
    end
end

local function fire(player)
    projectile.active = true
    projectile.x = player.x
    projectile.y = player.y + 1
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
        updateModels()
        frame:drawObjects({players[1].model, players[2].model, projectile.model})
        frame:drawBuffer()

        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        drawUI("Player " .. turn .. "'s Turn", 1)
        drawUI("Angle: " .. players[turn].angle, 2)
        drawUI("Velocity: " .. players[turn].velocity, 3)
        drawUI("Pos: " .. players[turn].x, 4)

        if projectile.active then
            projectile.x = projectile.x + projectile.vx * DT
            projectile.y = projectile.y + projectile.vy * DT
            projectile.vy = projectile.vy - GRAVITY * DT

            if projectile.y <= GROUND_Y then
                projectile.active = false
                local hit = false
                for _, p in ipairs(players) do
                    if math.abs(projectile.x - p.x) < 1.5 then
                        drawUI("HIT Player " .. p.id .. "!", 5)
                        sleep(2)
                        hit = true
                    end
                end

                if not hit then
                    drawUI("Miss!", 5)
                    sleep(1)
                end

                turn = (turn == 1) and 2 or 1
                projectile.vx = 0
                projectile.vy = 0
                projectile.vz = 0
            end
        end

        local event, key = os.pullEvent()
        if event == "key" then
            if key == keys.left then
                players[turn].angle = players[turn].angle - 1
            elseif key == keys.right then
                players[turn].angle = players[turn].angle + 1
            elseif key == keys.up then
                players[turn].velocity = math.min(50, players[turn].velocity + 1)
            elseif key == keys.down then
                players[turn].velocity = math.max(5, players[turn].velocity - 1)
            elseif key == keys.a then
                players[turn].x = players[turn].x - 0.5
            elseif key == keys.d then
                players[turn].x = players[turn].x + 0.5
            elseif key == keys.space then
                fire(players[turn])
            elseif key == keys.q then
                term.clear()
                term.setCursorPos(1, 1)
                break
            end
        end
    end
end

gameLoop()
