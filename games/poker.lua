---@diagnostic disable: undefined-global, undefined-field

-- Video Poker (scaffold)
-- Uses the shared arcade wrapper for UI and credit handling.
-- This is a minimal playable stub to validate the wrapper. Real hand evaluation
-- and pay table will be added next.

local arcade = require("games.arcade")

local bet = 1
local message = "Insert coin and play!"

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end

local function dealStub()
	-- Placeholder payout: 10% chance to double, else lose the bet
	if math.random() < 0.10 then
		return bet * 2, "Win! +" .. tostring(bet * 2)
	else
		return -bet, "No pair. -" .. tostring(bet)
	end
end

local game = {
	name = "Video Poker",
	init = function(a)
		a:setButtons({"Bet-","Deal","CashOut"}, {true, true, true})
	end,
	draw = function(a)
		a:clearPlayfield()
		a:centerPrint(1, "Video Poker", colors.white)
		a:centerPrint(3, "Credits: " .. a:getCredits(), colors.lightGray)
		a:centerPrint(4, "Bet: " .. tostring(bet), colors.lightGray)
		a:centerPrint(6, message or " ", colors.yellow)
	end,
	onButton = function(a, which)
		if which == "left" then
			bet = clamp(bet - 1, 1, 99)
			message = "Bet set to " .. bet
		elseif which == "center" then
			if a:consumeCredits(bet) then
				local delta, msg = dealStub()
				if delta > 0 then a:addCredits(delta) end
				message = msg
			else
				message = "Not enough credits!"
			end
		elseif which == "right" then
			a:requestQuit()
		end
	end,
}

arcade.start(game)
