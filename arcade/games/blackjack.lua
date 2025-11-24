---@diagnostic disable: undefined-global, undefined-field
-- Blackjack arcade game
-- Uses the shared three-button arcade wrapper. Implements a multi-deck shoe,
-- betting controls, and the usual hit/stand/double play flow.
-- Lua tip: using small helper functions (like card builders and draw helpers)
-- keeps the main game loop easier to read and tweak.

local arcade = require("games.arcade")

local suits = {"S", "H", "C", "D"} -- spade, heart, club, diamond
local ranks = {
        {label = "A", value = 11},
        {label = "2", value = 2}, {label = "3", value = 3}, {label = "4", value = 4}, {label = "5", value = 5},
        {label = "6", value = 6}, {label = "7", value = 7}, {label = "8", value = 8}, {label = "9", value = 9},
        {label = "10", value = 10}, {label = "J", value = 10}, {label = "Q", value = 10}, {label = "K", value = 10}
}

local shoe = {}
local shoeDecks = 4
local playerHand, dealerHand = {}, {}
local baseBet = 1
local activeWager = 0
local phase = "betting" -- betting, dealing, player, dealer, roundEnd
local statusMessage = "Adjust bet then deal"
local adapter = nil
local revealTimer = 0
local revealDelay = 0.35
local dealQueue = {}
local dealerHoleRevealed = false
local playerHasActed = false
local screenDirty = true

local function shuffle(list)
        for i = #list, 2, -1 do
                local j = math.random(i)
                list[i], list[j] = list[j], list[i]
        end
end

local function buildShoe()
        shoe = {}
        for _ = 1, shoeDecks do
                for _, suit in ipairs(suits) do
                        for _, rank in ipairs(ranks) do
                                table.insert(shoe, {label = rank.label, value = rank.value, suit = suit})
                        end
                end
        end
        shuffle(shoe)
end

local function drawCard()
        if #shoe == 0 then buildShoe() end
        return table.remove(shoe)
end

local function handTotal(hand)
        local total, aces = 0, 0
        for _, card in ipairs(hand) do
                        total = total + card.value
                        if card.label == "A" then aces = aces + 1 end
        end
        while total > 21 and aces > 0 do
                total = total - 10
                aces = aces - 1
        end
        return total
end

local function visibleDealerTotal(hand)
        local total, aces = 0, 0
        for _, card in ipairs(hand) do
                if not card.hidden then
                        total = total + card.value
                        if card.label == "A" then aces = aces + 1 end
                end
        end
        while total > 21 and aces > 0 do
                total = total - 10
                aces = aces - 1
        end
        return total
end

local function formatCard(card, hide)
        if hide then return "[??]" end
        return string.format("[%s%s]", card.label, card.suit)
end

local function cardLine(hand, reveal)
        local bits = {}
        for i, card in ipairs(hand) do
                local hide = card.hidden and not reveal
                bits[i] = formatCard(card, hide)
        end
        return table.concat(bits, " ")
end

local function setButtonsForPhase()
        if not adapter then return end
        if phase == "betting" then
                adapter:setButtons({"Bet -", "Deal", "Bet +"})
        elseif phase == "player" then
                local canDouble = (not playerHasActed) and adapter:getCredits() >= activeWager
                adapter:setButtons({"Hit", "Stand", "Double"}, {true, true, canDouble})
        elseif phase == "roundEnd" then
                adapter:setButtons({"Bet -", "New", "Bet +"})
        else
                adapter:setButtons({"", "...", ""}, {false, false, false})
        end
end

local function resetRoundState()
        playerHand, dealerHand = {}, {}
        activeWager = 0
        dealQueue = {}
        phase = "betting"
        statusMessage = "Adjust bet then deal"
        dealerHoleRevealed = false
        playerHasActed = false
        revealTimer = 0
        screenDirty = true
        setButtonsForPhase()
end

local function isBlackjack(hand)
        return #hand == 2 and handTotal(hand) == 21
end

local function setPhase(newPhase)
        phase = newPhase
        setButtonsForPhase()
        screenDirty = true
end

local function payout(amount)
        if amount > 0 and adapter then adapter:addCredits(amount) end
end

local function endRound(outcome)
        local totalPlayer = handTotal(playerHand)
        local totalDealer = handTotal(dealerHand)
        local label = outcome
        if outcome == "playerBlackjack" then
                local award = math.floor(activeWager * 2.5)
                payout(award)
                label = string.format("Blackjack! Paid %d", award)
        elseif outcome == "playerWin" or outcome == "dealerBust" then
                payout(activeWager * 2)
                label = string.format("You win! Paid %d", activeWager * 2)
        elseif outcome == "push" then
                payout(activeWager)
                label = string.format("Push. Returned %d", activeWager)
        else
                label = "Dealer wins"
        end
        statusMessage = string.format("%s (You %d / Dealer %d)", label, totalPlayer, totalDealer)
        setPhase("roundEnd")
end

local function evaluateAfterPlayerStands()
        local playerTotal = handTotal(playerHand)
        local dealerTotal = handTotal(dealerHand)
        if dealerTotal > 21 then endRound("dealerBust")
        elseif dealerTotal < playerTotal then endRound("playerWin")
        elseif dealerTotal > playerTotal then endRound("dealerWin")
        else endRound("push") end
end

local function revealDealerHole()
        for _, card in ipairs(dealerHand) do
                if card.hidden then card.hidden = false end
        end
        dealerHoleRevealed = true
        screenDirty = true
end

local function startDealerTurn()
        revealDealerHole()
        setPhase("dealer")
        statusMessage = "Dealer drawing..."
        revealTimer = 0
end

local function resolveForBlackjack()
        local playerBJ = isBlackjack(playerHand)
        local dealerBJ = isBlackjack(dealerHand)
        if playerBJ or dealerBJ then
                revealDealerHole()
                if playerBJ and dealerBJ then
                        endRound("push")
                elseif playerBJ then
                        endRound("playerBlackjack")
                else
                        endRound("dealerWin")
                end
                return true
        end
        return false
end

local function queueInitialDeal()
        dealQueue = {"player", "dealer", "player", "dealer"}
        setPhase("dealing")
        statusMessage = "Dealing..."
        revealTimer = 0
end

local function dealTo(target)
        local card = drawCard()
        if target == "dealer" and #dealerHand == 1 then
                card.hidden = true
        end
        if target == "player" then table.insert(playerHand, card) else table.insert(dealerHand, card) end
        screenDirty = true
end

local function drawHud(a)
        a:clearPlayfield(colors.green, colors.white)
        local credits = a:getCredits()
        a:centerPrint(1, "Blackjack", colors.white, colors.green)
        a:centerPrint(2, string.format("Credits: %d   Bet: %d   Shoe: %d", credits, baseBet, #shoe))
        local wagerLine = activeWager > 0 and ("Wager in play: " .. activeWager) or "Waiting for next hand"
        a:centerPrint(3, wagerLine, colors.lightGray)
        a:centerPrint(5, "Dealer", colors.white)
        a:centerPrint(6, cardLine(dealerHand, dealerHoleRevealed or (phase ~= "dealing" and phase ~= "player")), colors.white)
        local dealerTotalText = "Total: "
        if dealerHoleRevealed or phase == "roundEnd" or phase == "dealer" then
                dealerTotalText = dealerTotalText .. tostring(handTotal(dealerHand))
        else
                dealerTotalText = dealerTotalText .. tostring(visibleDealerTotal(dealerHand)) .. " + ?"
        end
        a:centerPrint(7, dealerTotalText, colors.lightGray)

        a:centerPrint(9, "Player", colors.white)
        a:centerPrint(10, cardLine(playerHand, true), colors.white)
        a:centerPrint(11, "Total: " .. tostring(handTotal(playerHand)), colors.lightGray)

        a:centerPrint(13, statusMessage or " ", colors.yellow)
        a:centerPrint(15, "Keys: 1/2/3 or buttons. Q to quit.", colors.gray)
end

local function redraw()
        if adapter then drawHud(adapter); screenDirty = false end
end

local function startRound()
        if not adapter then return end
        if adapter:consumeCredits(baseBet) then
                resetRoundState()
                activeWager = baseBet
                queueInitialDeal()
        else
                statusMessage = "Not enough credits for that bet"
                setPhase("betting")
        end
end

local function playerHit()
        dealTo("player")
        local total = handTotal(playerHand)
        playerHasActed = true
        if total > 21 then
                statusMessage = "Bust!"
                revealDealerHole()
                endRound("dealerWin")
        else
                statusMessage = "Hit or stand"
                setPhase("player")
        end
end

local function playerStand()
        playerHasActed = true
        startDealerTurn()
end

local function playerDouble()
        if adapter:consumeCredits(activeWager) then
                activeWager = activeWager * 2
                dealTo("player")
                playerHasActed = true
                if handTotal(playerHand) > 21 then
                        statusMessage = "Double bust"
                        revealDealerHole()
                        endRound("dealerWin")
                else
                        startDealerTurn()
                end
        else
                statusMessage = "Need more credits to double"
        end
end

local function adjustBet(delta)
        baseBet = math.max(1, math.min(100, baseBet + delta))
        statusMessage = "Bet set to " .. baseBet
        screenDirty = true
end

local function advanceDealing(dt)
        if #dealQueue == 0 then return end
        revealTimer = revealTimer + dt
        if revealTimer >= revealDelay then
                revealTimer = 0
                local target = table.remove(dealQueue, 1)
                dealTo(target)
                if #dealQueue == 0 then
                        if not resolveForBlackjack() then
                                setPhase("player")
                                statusMessage = "Hit or stand"
                        end
                end
        end
end

local function advanceDealer(dt)
        revealTimer = revealTimer + dt
        if not dealerHoleRevealed and revealTimer >= revealDelay then
                revealTimer = 0
                revealDealerHole()
                screenDirty = true
                return
        end
        if revealTimer < revealDelay then return end
        local total = handTotal(dealerHand)
        if total < 17 then
                revealTimer = 0
                dealTo("dealer")
        else
                revealTimer = 0
                evaluateAfterPlayerStands()
        end
end

local function onButton(a, which)
        adapter = a
        if phase == "betting" then
                if which == "left" then adjustBet(-1)
                elseif which == "center" then startRound()
                elseif which == "right" then adjustBet(1) end
        elseif phase == "player" then
                if which == "left" then playerHit()
                elseif which == "center" then playerStand()
                elseif which == "right" then playerDouble() end
        elseif phase == "roundEnd" then
                if which == "left" then adjustBet(-1)
                elseif which == "center" then resetRoundState()
                elseif which == "right" then adjustBet(1) end
        end
        redraw()
end

local game = {
        name = "Blackjack",
        init = function(a)
                math.randomseed(os.time())
                adapter = a
                buildShoe()
                resetRoundState()
                setButtonsForPhase()
                redraw()
        end,
        draw = function(a)
                adapter = a
                redraw()
        end,
        onButton = function(a, which)
                onButton(a, which)
        end,
        onTick = function(a, dt)
                adapter = a
                if phase == "dealing" then
                        advanceDealing(dt)
                elseif phase == "dealer" then
                        advanceDealer(dt)
                end
                if screenDirty then redraw() end
        end,
}

arcade.start(game)
