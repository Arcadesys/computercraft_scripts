---@diagnostic disable: undefined-global, undefined-field
-- Blackjack (placeholder)
-- This file currently uses the shared arcade wrapper and shows a coming-soon UI.
-- Later, we'll implement full blackjack logic using the same three-button controls.

local arcade = require("lib.arcade")

local game = {
	name = "Blackjack",
	init = function(a)
		a:setButtons({"Bet","Hit/Stay","Quit"})
	end,
	draw = function(a)
		a:clearPlayfield()
		a:centerPrint(1, "Blackjack — Coming soon", colors.white, colors.black)
		a:centerPrint(3, "Credits: " .. a:getCredits(), colors.lightGray)
		a:centerPrint(5, "Use Left to bet -1, Center to add +1, Right to quit", colors.gray)
	end,
	onButton = function(a, which)
		if which == "left" then a:consumeCredits(1) end
		if which == "center" then a:addCredits(1) end
		if which == "right" then a:requestQuit() end
	end,
}

arcade.start(game)
