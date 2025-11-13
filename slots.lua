---@diagnostic disable: undefined-global, undefined-field
-- Slots (placeholder)
-- Minimal demo using arcade wrapper: spin costs 1 credit, 5% chance triple payout.

local arcade = require("lib.arcade")
local lastResult = "---"
local message = "Spin to win!"

local symbols = {"A","B","C","7","*"}

local function spin()
	local r = {symbols[math.random(#symbols)], symbols[math.random(#symbols)], symbols[math.random(#symbols)]}
	local text = table.concat(r)
	local payout = 0
	if r[1]==r[2] and r[2]==r[3] then
		payout = 5
		message = "TRIPLE! +5"
	elseif r[1]==r[2] or r[2]==r[3] then
		payout = 2
		message = "Pair! +2"
	else
		message = "No match"
	end
	lastResult = text
	return payout
end

local game = {
	name = "Slots",
	init = function(a)
		a:setButtons({"Spin","+1","Quit"})
	end,
	draw = function(a)
		a:clearPlayfield()
		a:centerPrint(1, "Slots", colors.white)
		a:centerPrint(3, lastResult, colors.yellow)
		a:centerPrint(5, message, colors.lightGray)
		a:centerPrint(7, "Credits: " .. a:getCredits(), colors.gray)
	end,
	onButton = function(a, which)
		if which == "left" then
			if a:consumeCredits(1) then
				local payout = spin()
				if payout>0 then a:addCredits(payout) end
			else
				message = "Need credit"
			end
		elseif which == "center" then
			a:addCredits(1)
			message = "+1 credit added"
		elseif which == "right" then
			a:requestQuit()
		end
	end,
	onTick = function(a, dt)
		-- Periodically redraw to reflect any changes
		a:setButtons({"Spin","+1","Quit"})
	end,
}

arcade.start(game)
