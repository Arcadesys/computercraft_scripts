-- Clear potentially failed loads
package.loaded["arcade"] = nil
package.loaded["log"] = nil

local function setupPaths()
    local program = shell.getRunningProgram()
    local dir = fs.getDir(program)
    -- slots is in arcade/games/slots.lua
    -- dir is arcade/games
    -- root is arcade
    -- parent of root is installation root
    local gamesDir = fs.getDir(program)
    local arcadeDir = fs.getDir(gamesDir)
    local root = fs.getDir(arcadeDir)
    
    local function add(path)
        local part = fs.combine(root, path)
        -- fs.combine strips leading slashes, so we force absolute path
        local pattern = "/" .. fs.combine(part, "?.lua")
        
        if not string.find(package.path, pattern, 1, true) then
            package.path = package.path .. ";" .. pattern
        end
    end
    
    add("lib")
    add("arcade")
end

setupPaths()

local arcade = require("arcade")

local REELS = {
    {"Cherry", "Lemon", "Orange", "Plum", "Bell", "Bar", "7"},
    {"Cherry", "Lemon", "Orange", "Plum", "Bell", "Bar", "7"},
    {"Cherry", "Lemon", "Orange", "Plum", "Bell", "Bar", "7"}
}

local PAYOUTS = {
    ["Cherry"] = 2,
    ["Lemon"] = 3,
    ["Orange"] = 5,
    ["Plum"] = 10,
    ["Bell"] = 20,
    ["Bar"] = 50,
    ["7"] = 100
}

local COST = 1
local result = {"-", "-", "-"}
local message = "Press Spin!"
local winAmount = 0

local game = {
    name = "Slots",
    
    init = function(a)
        a:setButtons({"Info", "Spin", "Quit"})
    end,

    draw = function(a)
        a:clearPlayfield()
        a:centerPrint(2, "--- SLOTS ---", colors.yellow)
        
        local s = string.format("[%s] [%s] [%s]", result[1], result[2], result[3])
        a:centerPrint(5, s, colors.white)
        
        if winAmount > 0 then
            a:centerPrint(7, "WINNER! " .. winAmount, colors.lime)
        else
            a:centerPrint(7, message, colors.lightGray)
        end
        
        a:centerPrint(9, "Credits: " .. a:getCredits(), colors.orange)
    end,

    onButton = function(a, button)
        if button == "left" then
            message = "Cost: " .. COST .. " Credit"
            winAmount = 0
        elseif button == "center" then
            if a:consumeCredits(COST) then
                winAmount = 0
                -- Spin
                for i=1,3 do
                    result[i] = REELS[i][math.random(1, #REELS[i])]
                end
                
                -- Check win
                if result[1] == result[2] and result[2] == result[3] then
                    local sym = result[1]
                    winAmount = (PAYOUTS[sym] or 0) * COST
                    a:addCredits(winAmount)
                    message = "JACKPOT!"
                elseif result[1] == result[2] or result[2] == result[3] or result[1] == result[3] then
                     -- No prize for 2 in this simple version
                     message = "Spin again!"
                else
                    message = "Try again!"
                end
            else
                message = "Insert Coin"
            end
        elseif button == "right" then
            a:requestQuit()
        end
    end
}

arcade.start(game)
