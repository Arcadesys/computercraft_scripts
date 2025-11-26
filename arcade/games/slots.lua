---@diagnostic disable: undefined-global, undefined-field
-- Clear potentially failed loads
package.loaded["arcade"] = nil
package.loaded["log"] = nil

local function setupPaths()
    local dir = fs.getDir(shell.getRunningProgram())
    local boot = fs.combine(fs.getDir(dir), "boot.lua")
    if fs.exists(boot) then dofile(boot) end
end

setupPaths()

local arcade = require("arcade")
local ui = require("lib_ui")

-- Helper to create simple block textures
local toBlit = ui.toBlit

local function solidTex(char, fg, bg, w, h)
    local f = string.rep(toBlit(fg), w)
    local b = string.rep(toBlit(bg), w)
    local t = string.rep(char, w)
    local rows = {}
    for i=1,h do table.insert(rows, {text=t, fg=f, bg=b}) end
    return { rows = rows }
end

local SYMBOLS = {
    ["Cherry"] = solidTex("@", colors.red, colors.white, 4, 3),
    ["Lemon"] = solidTex("O", colors.yellow, colors.white, 4, 3),
    ["Orange"] = solidTex("O", colors.orange, colors.white, 4, 3),
    ["Plum"] = solidTex("%", colors.purple, colors.white, 4, 3),
    ["Bell"] = solidTex("A", colors.gold or colors.yellow, colors.white, 4, 3),
    ["Bar"] = solidTex("=", colors.black, colors.white, 4, 3),
    ["7"] = solidTex("7", colors.red, colors.white, 4, 3)
}

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
    
    init = function(self, a)
        a:setButtons({"Info", "Spin", "Quit"})
    end,

    draw = function(self, a)
        a:clearPlayfield(colors.green)
        local r = a:getRenderer()
        if not r then return end
        
        local w, h = r:getSize()
        local cx = math.floor(w / 2)
        local cy = math.floor(h / 2)
        
        -- Draw Title
        a:centerPrint(2, "--- SLOTS ---", colors.yellow, colors.green)
        
        -- Draw Reels
        local reelW = 6
        local reelH = 5
        local spacing = 2
        local totalW = (reelW * 3) + (spacing * 2)
        local startX = cx - math.floor(totalW / 2)
        local startY = 4
        
        for i=1,3 do
            local symName = result[i]
            local tex = SYMBOLS[symName]
            local x = startX + (i-1)*(reelW+spacing)
            
            -- Draw reel background/frame
            r:fillRect(x, startY, reelW, reelH, colors.white, colors.black, " ")
            
            if tex then
                -- Center texture in reel
                local tx = x + 1
                local ty = startY + 1
                r:drawTextureRect(tex, tx, ty, 4, 3)
            else
                -- Draw placeholder
                r:drawLabelCentered(x, startY + 2, reelW, "?", colors.black)
            end
        end
        
        -- Draw Info
        if winAmount > 0 then
            a:centerPrint(startY + reelH + 2, "WINNER! " .. winAmount, colors.lime, colors.green)
        else
            a:centerPrint(startY + reelH + 2, message, colors.white, colors.green)
        end
        
        a:centerPrint(startY + reelH + 4, "Credits: " .. a:getCredits(), colors.orange, colors.green)
    end,

    onButton = function(self, a, button)
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
