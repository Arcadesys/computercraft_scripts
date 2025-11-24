---@diagnostic disable: undefined-global, undefined-field

-- Video Poker (full game)
-- Implements a 52-card deck, Jacks-or-Better pay table, and three-button
-- controls via the shared arcade wrapper.
-- Lua Tip: keeping everything in one table or module helps avoid accidental
-- globals; here we keep state local to this file.

local arcade = require("games.arcade")

-- Card metadata for rendering and evaluation
local SUITS = {
        { name = "Spades",   glyph = "\5", color = colors.lightGray },
        { name = "Hearts",   glyph = "\3", color = colors.red },
        { name = "Clubs",    glyph = "\6", color = colors.green },
        { name = "Diamonds", glyph = "\4", color = colors.orange },
}

local VALUES = {
        { value = 2,  label = "2" }, { value = 3,  label = "3" }, { value = 4,  label = "4" },
        { value = 5,  label = "5" }, { value = 6,  label = "6" }, { value = 7,  label = "7" },
        { value = 8,  label = "8" }, { value = 9,  label = "9" }, { value = 10, label = "10" },
        { value = 11, label = "J" }, { value = 12, label = "Q" }, { value = 13, label = "K" },
        { value = 14, label = "A" },
}

-- Configurable Jacks-or-Better pay table. The royal flush gets a dedicated
-- per-bet payout to capture the classic 4000-coin max-bet jackpot.
local PAY_TABLE = {
        ["Royal Flush"]     = { perBet = {250, 500, 750, 1000, 4000} },
        ["Straight Flush"]  = { multiplier = 50 },
        ["Four of a Kind"]  = { multiplier = 25 },
        ["Full House"]      = { multiplier = 9 },
        ["Flush"]           = { multiplier = 6 },
        ["Straight"]        = { multiplier = 4 },
        ["Three of a Kind"] = { multiplier = 3 },
        ["Two Pair"]        = { multiplier = 2 },
        ["Jacks or Better"] = { multiplier = 1 },
}

local MAX_BET = 5
local FLIP_DELAY = 0.12

-- Game state
local gameState = "betting" -- betting | dealing | holding | drawing | settled
local bet = 1
local handBet = 1
local deck = {}
local hand = {}
local holds = {}
local revealed = {}
local flipQueue = {}
local flipTimer = 0
local cursorIndex = 1
local statusMessage = "Insert coin and play!"
local lastRank = "—"
local lastPayout = 0
local arcadeAdapter = nil

local function clamp(v, lo, hi)
        if v < lo then return lo elseif v > hi then return hi else return v end
end

-- Deck helpers -----------------------------------------------------------

local function buildDeck()
        local d = {}
        for _, suit in ipairs(SUITS) do
                for _, val in ipairs(VALUES) do
                        table.insert(d, {
                                value = val.value,
                                label = val.label,
                                suit = suit,
                        })
                end
        end
        return d
end

local function shuffleDeck(d)
        for i = #d, 2, -1 do
                local j = math.random(i)
                d[i], d[j] = d[j], d[i]
        end
end

local function drawCardFromDeck()
        return table.remove(deck)
end

-- Evaluation -------------------------------------------------------------

local function isStraight(values)
        table.sort(values)
        local unique = {}
        for _, v in ipairs(values) do
                if unique[#unique] ~= v then table.insert(unique, v) end
        end
        if #unique ~= 5 then return false, unique[#unique] end
        local low, high = unique[1], unique[#unique]
        local sequential = true
        for i = 2, #unique do
                if unique[i] ~= unique[1] + (i - 1) then sequential = false break end
        end
        if sequential then return true, high end
        -- Wheel straight (A-2-3-4-5)
        if unique[1] == 2 and unique[2] == 3 and unique[3] == 4 and unique[4] == 5 and unique[5] == 14 then
                return true, 5
        end
        return false, high
end

local function evaluateHand()
        local countsByValue, countsBySuit, values = {}, {}, {}
        for _, card in ipairs(hand) do
                countsByValue[card.value] = (countsByValue[card.value] or 0) + 1
                countsBySuit[card.suit.name] = (countsBySuit[card.suit.name] or 0) + 1
                table.insert(values, card.value)
        end

        local isFlush = false
        for _, c in pairs(countsBySuit) do if c == 5 then isFlush = true break end end

        local straight, highStraight = isStraight(values)
        local pairsFound, hasThree, hasFour = {}, false, false
        for val, c in pairs(countsByValue) do
                if c == 4 then hasFour = true end
                if c == 3 then hasThree = true end
                if c == 2 then table.insert(pairsFound, val) end
        end

        local rank
        if straight and isFlush and highStraight == 14 and math.min(table.unpack(values)) == 10 then
                rank = "Royal Flush"
        elseif straight and isFlush then
                rank = "Straight Flush"
        elseif hasFour then
                rank = "Four of a Kind"
        elseif hasThree and #pairsFound == 1 then
                rank = "Full House"
        elseif isFlush then
                rank = "Flush"
        elseif straight then
                rank = "Straight"
        elseif hasThree then
                rank = "Three of a Kind"
        elseif #pairsFound == 2 then
                rank = "Two Pair"
        elseif #pairsFound == 1 and pairsFound[1] >= 11 then
                rank = "Jacks or Better"
        else
                rank = "No win"
        end
        return rank
end

local function payoutForRank(rank, wager)
        local rule = PAY_TABLE[rank]
        if not rule then return 0 end
        if rule.perBet then
                local idx = clamp(wager, 1, #rule.perBet)
                return rule.perBet[idx]
        end
        return (rule.multiplier or 0) * wager
end

-- Rendering --------------------------------------------------------------

local function cardArt(card, isRevealed)
        if not card then return {"┌─────┐", "│     │", "└─────┘"}, colors.lightGray end
        if not isRevealed then
                return {"┌─────┐", "│▒▒▒▒▒│", "└─────┘"}, colors.lightGray
        end
        local face = string.format("│%-2s %s │", card.label, card.suit.glyph)
        return {"┌─────┐", face, "└─────┘"}, card.suit.color
end

local function drawCardAt(x, y, card, isRevealed, isHeld, isCursor)
        local art, fg = cardArt(card, isRevealed)
        local bg = isHeld and colors.gray or colors.black
        if isCursor then bg = colors.blue end
        for row = 1, #art do
                term.setCursorPos(x, y + row - 1)
                term.setBackgroundColor(bg)
                term.setTextColor(fg)
                term.write(art[row])
        end
        term.setBackgroundColor(colors.black)
        if isHeld then
                term.setCursorPos(x + 1, y + 3)
                term.setTextColor(colors.yellow)
                term.write("HOLD")
        elseif isCursor and gameState == "holding" then
                term.setCursorPos(x + 2, y + 3)
                term.setTextColor(colors.lightBlue)
                term.write("^")
        end
end

local function renderCards()
        local screenW = ({term.getSize()})[1]
        local cardWidth, spacing = 7, 2
        local totalWidth = cardWidth * 5 + spacing * 4
        local startX = math.max(1, math.floor((screenW - totalWidth) / 2) + 1)
        local startY = 5
        for i = 1, 5 do
                local x = startX + (i - 1) * (cardWidth + spacing)
                drawCardAt(x, startY, hand[i], revealed[i], holds[i], cursorIndex == i)
        end
end

local function render(adapter)
        adapter:clearPlayfield()
        adapter:centerPrint(1, "Video Poker", colors.white)
        adapter:centerPrint(2, string.format("Credits: %d  Bet: %d", adapter:getCredits(), bet), colors.lightGray)
        adapter:centerPrint(3, statusMessage or " ", colors.yellow)
        renderCards()
        adapter:centerPrint(9, string.format("Last: %s (payout %d)", lastRank, lastPayout), colors.orange)
        adapter:centerPrint(10, "Use Prev/Hold/Next then Draw", colors.gray)
end

-- State helpers ----------------------------------------------------------

local function queueFlips(indices)
        for _, idx in ipairs(indices) do table.insert(flipQueue, idx) end
end

local function resetHand()
        deck = buildDeck()
        shuffleDeck(deck)
        hand, holds, revealed, flipQueue = {}, {}, {}, {}
        cursorIndex = 1
        flipTimer = 0
end

local function settleHand()
        local rank = evaluateHand()
        local payout = payoutForRank(rank, handBet)
        if payout > 0 then arcadeAdapter:addCredits(payout) end
        lastRank, lastPayout = rank, payout
        statusMessage = string.format("Result: %s (%s%d)", rank, payout > 0 and "+" or "", payout)
        gameState = "settled"
end

local function updateButtons()
        if not arcadeAdapter then return end
        if gameState == "betting" or gameState == "settled" then
                arcadeAdapter:setButtons({"Bet-", "Deal", "Bet+"}, {true, true, true})
        elseif gameState == "holding" then
                arcadeAdapter:setButtons({"Prev", "Hold", "Next/Draw"}, {true, true, true})
        else
                arcadeAdapter:setButtons({"...", "...", "..."}, {false, false, false})
        end
end

local function startDeal()
        if gameState ~= "betting" and gameState ~= "settled" then return end
        if not arcadeAdapter:consumeCredits(bet) then
                statusMessage = "Not enough credits!"
                return
        end
        handBet = bet
        resetHand()
        for i = 1, 5 do
                hand[i] = drawCardFromDeck()
                holds[i] = false
                revealed[i] = false
        end
        queueFlips({1,2,3,4,5})
        gameState = "dealing"
        statusMessage = "Dealing..."
        updateButtons()
end

local function startDrawPhase()
        if gameState ~= "holding" then return end
        local replacements = {}
        for idx = 1, 5 do
                if not holds[idx] then
                        hand[idx] = drawCardFromDeck()
                        revealed[idx] = false
                        table.insert(replacements, idx)
                end
        end
        if #replacements == 0 then
                settleHand()
                updateButtons()
                return
        end
        queueFlips(replacements)
        gameState = "drawing"
        statusMessage = "Drawing..."
        updateButtons()
end

local function processAnimations(dt)
        if #flipQueue > 0 then
                flipTimer = flipTimer + dt
                if flipTimer >= FLIP_DELAY then
                        flipTimer = 0
                        local idx = table.remove(flipQueue, 1)
                        revealed[idx] = true
                end
                return
        end
        if gameState == "dealing" then
                gameState = "holding"
                statusMessage = "Select holds, then draw"
                updateButtons()
        elseif gameState == "drawing" then
                settleHand()
                updateButtons()
        end
end

-- Input handlers ---------------------------------------------------------

local function adjustBet(delta)
        bet = clamp(bet + delta, 1, MAX_BET)
        statusMessage = "Bet set to " .. bet
end

local function handleButton(which)
        if gameState == "betting" or gameState == "settled" then
                if which == "left" then adjustBet(-1)
                elseif which == "center" then startDeal()
                elseif which == "right" then adjustBet(1) end
        elseif gameState == "holding" then
                if which == "left" then
                        cursorIndex = (cursorIndex == 1) and 5 or (cursorIndex - 1)
                elseif which == "center" then
                        holds[cursorIndex] = not holds[cursorIndex]
                        statusMessage = holds[cursorIndex] and "Holding card " .. cursorIndex or "Released card " .. cursorIndex
                elseif which == "right" then
                        if cursorIndex < 5 then
                                cursorIndex = cursorIndex + 1
                        else
                                startDrawPhase()
                        end
                end
        end
end

-- Game table -------------------------------------------------------------

local game = {
        name = "Video Poker",
        init = function(a)
                arcadeAdapter = a
                updateButtons()
        end,
        draw = function(a)
                render(a)
        end,
        onButton = function(_, which)
                handleButton(which)
        end,
        onTick = function(a, dt)
                processAnimations(dt)
                render(a)
        end,
}

arcade.start(game)
