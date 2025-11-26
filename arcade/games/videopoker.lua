---@diagnostic disable: undefined-global, undefined-field
package.loaded["arcade"] = nil

local function setupPaths()
    local dir = fs.getDir(shell.getRunningProgram())
    local boot = fs.combine(fs.getDir(dir), "boot.lua")
    if fs.exists(boot) then dofile(boot) end
end

setupPaths()

local arcade = require("arcade")
local cards = require("lib_cards")

-- ==========================================
-- Game State
-- ==========================================

local STATE_BETTING = "BETTING"
local STATE_DEAL = "DEAL" -- Cards dealt, waiting for hold
local STATE_RESULT = "RESULT" -- Show win/loss

local currentState = STATE_BETTING
local deck = {}
local hand = {}
local held = {false, false, false, false, false}
local bet = 1
local message = "BET 1-5 & DEAL"
local lastWin = 0
local lastHandName = ""

local CARD_W = 7
local CARD_H = 5
local CARD_SPACING = 2

local game = {
    name = "Video Poker",
    
    init = function(self, a)
        a:setButtons({"Bet One", "Deal", "Quit"})
        deck = cards.createDeck()
        cards.shuffle(deck)
    end,

    draw = function(self, a)
        a:clearPlayfield(colors.blue)
        local r = a:getRenderer()
        if not r then return end
        
        local w, h = r:getSize()
        local cx = math.floor(w / 2)
        
        -- Title
        a:centerPrint(2, "--- VIDEO POKER ---", colors.yellow, colors.blue)
        
        -- Cards
        local totalW = (CARD_W * 5) + (CARD_SPACING * 4)
        local startX = cx - math.floor(totalW / 2)
        local startY = 6
        
        for i=1,5 do
            local x = startX + (i-1)*(CARD_W+CARD_SPACING)
            local card = hand[i]
            
            -- Draw Card Background
            local bg = colors.white
            if currentState == STATE_DEAL and held[i] then bg = colors.lightGray end
            r:fillRect(x, startY, CARD_W, CARD_H, bg, colors.black, " ")
            
            if card then
                local col = cards.SUIT_COLORS[card.suit]
                local txt = card.rankStr .. cards.SUIT_SYMBOLS[card.suit]
                r:drawLabelCentered(x, startY + 2, CARD_W, txt, col, bg)
                
                if currentState == STATE_DEAL and held[i] then
                    r:drawLabelCentered(x, startY + CARD_H + 1, CARD_W, "HELD", colors.yellow, colors.blue)
                end
            else
                -- Card back
                r:fillRect(x, startY, CARD_W, CARD_H, colors.red, colors.white, "#")
            end
        end
        
        -- Info
        a:centerPrint(startY + CARD_H + 3, message, colors.white, colors.blue)
        if lastWin > 0 then
            a:centerPrint(startY + CARD_H + 4, "WON " .. lastWin .. " CREDITS (" .. lastHandName .. ")", colors.lime, colors.blue)
        end
        
        a:centerPrint(h - 4, "Bet: " .. bet .. "   Credits: " .. a:getCredits(), colors.orange, colors.blue)
    end,

    onButton = function(self, a, button)
        if button == "left" then -- Bet One
            if currentState == STATE_BETTING or currentState == STATE_RESULT then
                bet = bet + 1
                if bet > 5 then bet = 1 end
                currentState = STATE_BETTING
                message = "BET " .. bet .. " & DEAL"
                lastWin = 0
                hand = {} -- Clear hand
            end
        elseif button == "center" then -- Deal / Draw
            if currentState == STATE_BETTING or currentState == STATE_RESULT then
                -- Deal
                if a:consumeCredits(bet) then
                    deck = cards.createDeck()
                    cards.shuffle(deck)
                    hand = {}
                    held = {false, false, false, false, false}
                    for i=1,5 do table.insert(hand, table.remove(deck)) end
                    
                    local name, payout = cards.evaluateHand(hand)
                    if payout > 0 then
                        message = "Hand: " .. name .. ". HOLD cards & DRAW."
                    else
                        message = "Select cards to HOLD then DRAW."
                    end
                    
                    currentState = STATE_DEAL
                    lastWin = 0
                    a:setButtons({"Bet One", "Draw", "Quit"})
                else
                    message = "INSERT COIN"
                end
            elseif currentState == STATE_DEAL then
                -- Draw
                for i=1,5 do
                    if not held[i] then
                        hand[i] = table.remove(deck)
                    end
                end
                
                local name, payout = cards.evaluateHand(hand)
                local win = payout * bet
                if name == "ROYAL_FLUSH" and bet == 5 then win = 800 end -- Bonus for max bet
                
                if win > 0 then
                    a:addCredits(win)
                    lastWin = win
                    lastHandName = name
                    message = "WINNER!"
                else
                    message = "GAME OVER"
                    lastWin = 0
                end
                
                currentState = STATE_RESULT
                a:setButtons({"Bet One", "Deal", "Quit"})
            end
        elseif button == "right" then
            a:requestQuit()
        end
    end,
    
    handleEvent = function(self, a, e)
        if currentState == STATE_DEAL and (e[1] == "monitor_touch" or e[1] == "mouse_click") then
            local x, y = e[3], e[4]
            local r = a:getRenderer()
            if not r then return end
            local w, h = r:getSize()
            local cx = math.floor(w / 2)
            local totalW = (CARD_W * 5) + (CARD_SPACING * 4)
            local startX = cx - math.floor(totalW / 2)
            local startY = 6
            
            if y >= startY and y < startY + CARD_H then
                -- Check which card
                for i=1,5 do
                    local cx = startX + (i-1)*(CARD_W+CARD_SPACING)
                    if x >= cx and x < cx + CARD_W then
                        held[i] = not held[i]
                        self:draw(a)
                        return
                    end
                end
            end
        end
    end
}

arcade.start(game)
