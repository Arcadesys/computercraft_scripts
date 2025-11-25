---@diagnostic disable: undefined-global, undefined-field
package.loaded["arcade"] = nil

local function setupPaths()
    local program = shell.getRunningProgram()
    local dir = fs.getDir(program)
    local gamesDir = fs.getDir(program)
    local arcadeDir = fs.getDir(gamesDir)
    local root = fs.getDir(arcadeDir)
    
    local function add(path)
        local part = fs.combine(root, path)
        local pattern = "/" .. fs.combine(part, "?.lua")
        if not string.find(package.path, pattern, 1, true) then
            package.path = package.path .. ";" .. pattern
        end
    end
    
    add("lib")
    add("arcade")
    if not string.find(package.path, ";/?.lua", 1, true) then
        package.path = package.path .. ";/?.lua"
    end
end

setupPaths()

local arcade = require("arcade")

-- ==========================================
-- Card Logic
-- ==========================================

local SUITS = {"S", "H", "D", "C"}
local RANKS = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}
local SUIT_COLORS = {S=colors.gray, H=colors.red, D=colors.red, C=colors.gray}
local SUIT_SYMBOLS = {S="\6", H="\3", D="\4", C="\5"} -- ComputerCraft chars if available, else letters

local function createDeck()
    local deck = {}
    for s=1,4 do
        for r=1,13 do
            table.insert(deck, {suit=SUITS[s], rank=r, rankStr=RANKS[r]})
        end
    end
    return deck
end

local function shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

local function getCardString(card)
    return card.rankStr .. SUIT_SYMBOLS[card.suit]
end

-- ==========================================
-- Hand Evaluation
-- ==========================================

local function evaluateHand(hand)
    -- Sort by rank
    local sorted = {}
    for _, c in ipairs(hand) do table.insert(sorted, c) end
    table.sort(sorted, function(a,b) return a.rank < b.rank end)

    local flush = true
    local suit = sorted[1].suit
    for i=2,5 do
        if sorted[i].suit ~= suit then flush = false break end
    end

    local straight = true
    for i=1,4 do
        if sorted[i+1].rank ~= sorted[i].rank + 1 then
            straight = false
            break
        end
    end
    -- Special case: A, 2, 3, 4, 5 (A is 13)
    -- Sorted would be 2,3,4,5,A (ranks 1,2,3,4,13)
    if not straight and sorted[5].rank == 13 and sorted[1].rank == 1 and sorted[2].rank == 2 and sorted[3].rank == 3 and sorted[4].rank == 4 then
        straight = true
    end

    local counts = {}
    for _, c in ipairs(sorted) do
        counts[c.rank] = (counts[c.rank] or 0) + 1
    end
    local countsArr = {}
    for r, c in pairs(counts) do table.insert(countsArr, {rank=r, count=c}) end
    table.sort(countsArr, function(a,b) return a.count > b.count end)

    local royal = straight and flush and sorted[1].rank == 9 -- 10,J,Q,K,A (ranks 9,10,11,12,13)
    -- Wait, my ranks are 1=2... 9=10, 13=A.
    -- 10 is rank 9.
    -- If straight and flush and lowest is 9 (10), then Royal.
    if straight and flush and sorted[1].rank == 9 then return "ROYAL_FLUSH", 250 end
    if straight and flush then return "STRAIGHT_FLUSH", 50 end
    if countsArr[1].count == 4 then return "FOUR_OF_A_KIND", 25 end
    if countsArr[1].count == 3 and countsArr[2].count == 2 then return "FULL_HOUSE", 9 end
    if flush then return "FLUSH", 6 end
    if straight then return "STRAIGHT", 4 end
    if countsArr[1].count == 3 then return "THREE_OF_A_KIND", 3 end
    if countsArr[1].count == 2 and countsArr[2].count == 2 then return "TWO_PAIR", 2 end
    if countsArr[1].count == 2 and (countsArr[1].rank >= 10 or countsArr[1].rank == 13) then -- J, Q, K, A (10,11,12,13)
        -- Wait, rank 10 is J.
        -- Ranks: 1=2, 2=3, 3=4, 4=5, 5=6, 6=7, 7=8, 8=9, 9=10, 10=J, 11=Q, 12=K, 13=A
        -- Jacks or Better means rank >= 10.
        return "JACKS_OR_BETTER", 1
    end
    
    return "NONE", 0
end

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
        deck = createDeck()
        shuffle(deck)
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
                local col = SUIT_COLORS[card.suit]
                local txt = card.rankStr .. SUIT_SYMBOLS[card.suit]
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
                    deck = createDeck()
                    shuffle(deck)
                    hand = {}
                    held = {false, false, false, false, false}
                    for i=1,5 do table.insert(hand, table.remove(deck)) end
                    
                    local name, payout = evaluateHand(hand)
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
                
                local name, payout = evaluateHand(hand)
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
