-- Can't Stop (Sid Sackson) on ComputerCraft
-- Author: You + Copilot
-- 
-- This script implements a playable version of "Can't Stop" with:
-- - A monitor UI using a persistent three-button bar at the bottom
-- - Touch input on the monitor (optional: redstone buttons can be wired in later)
-- - Core game rules: roll 4 dice, pick one pairing, move up to three neutral markers, stop/commit, bust, claim columns
-- - Save/Load of game state
--
-- Lua tips sprinkled throughout as comments. Search for "Lua Tip:" in this file.
--
-- Assumptions and scope:
-- - Focused on a single set of three buttons (Left, Center, Right) on the monitor.
-- - LOBBY uses Left to add players with auto names/colors, Center to start (needs >=2), Right to load/reset.
-- - During a turn: Left=Roll, Center=Stop (commit), Right=Menu (Save/Rules).
-- - When choosing a pair: Left/Center/Right map to the available pairings.
-- - A chosen pairing must be fully placeable (both sums) to be considered valid.

-- ==========================
-- Configuration and constants
-- ==========================

-- Arcade wrapper note: we require the wrapper for consistency with other games,
-- but Can't Stop currently uses its own bespoke UI/event loop.
local _arcade_ok, _arcade = pcall(require, "lib.arcade")

---@diagnostic disable: undefined-global, undefined-field
-- Above directive silences static analysis complaints about ComputerCraft globals
-- like `term`, `colors`, `paintutils`, `fs`, `textutils`, `peripheral`, `os`, etc.

local SAVE_FILE = "cantstop.save" -- (Arcade wrapper note: this game predates arcade.lua and runs standalone.)

-- Board heights for columns 2..12 per classic rules
local BOARD_HEIGHTS = {
	[2] = 3, [3] = 5, [4] = 7, [5] = 9, [6] = 11,
	[7] = 13, [8] = 11, [9] = 9, [10] = 7, [11] = 5, [12] = 3
}

-- Simple palette for players (background colors). Adjust as desired.
local PLAYER_COLORS = {
	colors.red, colors.lime, colors.blue, colors.orange,
	colors.purple, colors.cyan, colors.yellow, colors.magenta, colors.brown
}

-- UI: how many lines reserved for the bottom button bar
local BUTTON_BAR_HEIGHT = 3

-- Game phases
local PHASE = {
	LOBBY = "LOBBY",
	TURN = "TURN",           -- Player may Roll or Stop
	CHOOSE = "CHOOSE",       -- Player chooses among valid pairings
	GAME_OVER = "GAME_OVER"
}

-- Button identifiers
local BTN = { LEFT = 1, CENTER = 2, RIGHT = 3 }

-- ==========================
-- Utilities
-- ==========================

-- Lua Tip: Prefer local functions to avoid polluting the global environment.

local function deepcopy(tbl)
	if type(tbl) ~= "table" then return tbl end
	local out = {}
	for k, v in pairs(tbl) do out[k] = deepcopy(v) end
	return out
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function countKeys(t)
	local c = 0
	for _ in pairs(t) do c = c + 1 end
	return c
end

-- ==========================
-- Peripheral detection and screen setup
-- ==========================

local monitor = nil
local termNative = term.current()
local screenW, screenH = term.getSize()

local function initMonitor()
	-- Try to find an attached monitor; if none, we use the normal terminal.
	monitor = peripheral.find and peripheral.find("monitor") or nil
	if monitor then
		monitor.setTextScale(0.5) -- smaller text for more info
		term.redirect(monitor)
	end
	screenW, screenH = term.getSize()
end

-- ==========================
-- Layout helpers
-- ==========================

local layout = {
	board = { x = 1, y = 3, w = 0, h = 0 },  -- main board area
	statusY = 1,                              -- top status line
	diceY = 2,                                -- dice/detail line below status
	buttons = {                               -- three buttons at bottom
		{ x = 1, y = 1, w = 1, h = BUTTON_BAR_HEIGHT },
		{ x = 1, y = 1, w = 1, h = BUTTON_BAR_HEIGHT },
		{ x = 1, y = 1, w = 1, h = BUTTON_BAR_HEIGHT },
	}
}

local function computeLayout()
	screenW, screenH = term.getSize()
	-- Board takes everything above the bottom bar, minus top 2 lines (status & dice)
	local boardTop = 3
	local boardBottom = screenH - BUTTON_BAR_HEIGHT
	if boardBottom < boardTop + 4 then
		-- If monitor is tiny, collapse dice into status and shrink board
		layout.statusY = 1
		layout.diceY = 1
		boardTop = 2
		boardBottom = math.max(2, screenH - BUTTON_BAR_HEIGHT)
	else
		layout.statusY = 1
		layout.diceY = 2
	end
	layout.board.x = 1
	layout.board.y = boardTop
	layout.board.w = screenW
	layout.board.h = boardBottom - boardTop + 1

	-- Buttons split width into 3 equal parts at the bottom
	local btnW = math.floor(screenW / 3)
	local leftover = screenW - (btnW * 3)
	local startY = screenH - BUTTON_BAR_HEIGHT + 1
	for i = 1, 3 do
		local extra = (i <= leftover) and 1 or 0 -- distribute leftover pixels
		local x = 1 + (i - 1) * btnW + math.min(i - 1, leftover)
		layout.buttons[i].x = x
		layout.buttons[i].y = startY
		layout.buttons[i].w = btnW + extra
		layout.buttons[i].h = BUTTON_BAR_HEIGHT
	end
end

-- ==========================
-- Game state
-- ==========================

local state = {
	phase = PHASE.LOBBY,
	players = {},                 -- array: { {name, color}, ... }
	currentPlayer = 1,
	claimedColumns = {},          -- [col] = playerIndex
	permanentProgress = {},       -- [playerIndex] = { [col] = height }
	neutralMarkers = {},          -- in-turn markers: [col] = height this turn
	lastRoll = nil,               -- {d1,d2,d3,d4}
	validPairings = nil,          -- array of pairings {{s1,s2}, ...}
	statusText = "Welcome to Can't Stop!",
}

-- ==========================
-- Rendering helpers
-- ==========================

local function clearArea(x, y, w, h, bg, fg)
	bg = bg or colors.black
	fg = fg or colors.white
	term.setBackgroundColor(bg)
	term.setTextColor(fg)
	for yy = y, y + h - 1 do
		term.setCursorPos(x, yy)
		term.write(string.rep(" ", w))
	end
end

local function centerText(x, y, w, text)
	local tx = x + math.floor((w - #text) / 2)
	term.setCursorPos(tx, y)
	term.write(text)
end

local function drawStatus()
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.white)
	term.setCursorPos(1, layout.statusY)
	term.clearLine()
	term.write(state.statusText or "")
end

local function drawDice()
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.lightGray)
	term.setCursorPos(1, layout.diceY)
	term.clearLine()
	if state.lastRoll then
		term.write(string.format("Dice: %d %d %d %d", state.lastRoll[1], state.lastRoll[2], state.lastRoll[3], state.lastRoll[4]))
	else
		term.write("Dice: -- -- -- --")
	end
end

local function drawButtons(labels, enabled)
	enabled = enabled or { true, true, true }
	for i = 1, 3 do
		local r = layout.buttons[i]
		local bg = enabled[i] and colors.gray or colors.black
		local fg = enabled[i] and colors.white or colors.lightGray
		clearArea(r.x, r.y, r.w, r.h, bg, fg)
		centerText(r.x, r.y + math.floor(r.h / 2), r.w, labels[i] or "")
	end
end

-- Count how many columns a player has claimed (helper for progress UI)
local function countClaimedColumnsForPlayer(playerIndex)
	local claimed = 0
	for _, owner in pairs(state.claimedColumns) do
		if owner == playerIndex then claimed = claimed + 1 end
	end
	return claimed
end

-- Build a compact progress summary string for a player.
-- Format example: *P1(1): 6@5 9@3 10@2
-- Where * indicates current player, (1) is claimed columns count, then up to a few active progress entries.
local function buildPlayerProgressString(playerIndex)
	local player = state.players[playerIndex]
	if not player then return "" end
	local marker = (playerIndex == state.currentPlayer) and "*" or " "
	local name = player.name or ("P" .. playerIndex)
	local claimed = countClaimedColumnsForPlayer(playerIndex)

	-- Gather permanent progress entries
	local entries = {}
	local perm = state.permanentProgress[playerIndex] or {}
	for col, h in pairs(perm) do
		local colHeight = BOARD_HEIGHTS[col]
		if colHeight then
			table.insert(entries, {col = col, h = h, remaining = colHeight - h})
		end
	end
	-- Sort by proximity to the top (fewest remaining first)
	table.sort(entries, function(a,b)
		if a.remaining == b.remaining then return a.col < b.col end
		return a.remaining < b.remaining
	end)
	-- Limit number shown for brevity
	local parts = {}
	local shown = 0
	for _, e in ipairs(entries) do
		shown = shown + 1
		if shown > 4 then break end -- show at most 4 columns per player
		-- If this is the current player and there is a neutral marker further than perm progress, show that temp height instead for tension
		local displayH = e.h
		if playerIndex == state.currentPlayer and state.neutralMarkers[e.col] and state.neutralMarkers[e.col] > e.h then
			displayH = state.neutralMarkers[e.col]
		end
		table.insert(parts, string.format("%d@%d", e.col, displayH))
	end
	return string.format("%s%s(%d): %s", marker, name, claimed, table.concat(parts, " "))
end

-- Enhanced players summary showing progress for ALL players at once.
-- This replaces the earlier minimalist name list and adds tension by revealing everyone else's climb.
local function drawPlayersSummary()
	-- Render a compact, right-aligned single-line summary on the dice line to avoid overlapping the board.
	-- We compress multiple player strings and trim from the left if it overflows screen width.
	local parts = {}
	for i = 1, #state.players do
		table.insert(parts, buildPlayerProgressString(i))
	end
	local summary = table.concat(parts, "  |  ")
	local y = layout.diceY
	term.setTextColor(colors.white)
	-- If too long, trim from the left so the rightmost portion (often current player) remains visible.
	if #summary > screenW then
		summary = string.sub(summary, #summary - screenW + 1)
	end
	term.setCursorPos(math.max(1, screenW - #summary + 1), y)
	term.write(summary)
end

local function drawBoard()
	local r = layout.board
	clearArea(r.x, r.y, r.w, r.h, colors.black, colors.white)

	-- Determine vertical scaling based on max board height (13)
	local maxH = BOARD_HEIGHTS[7] or 13
	local usableH = math.max(3, r.h - 2) -- leave a small header/footer inside board area

	-- Compute per-column width
	local columns = {}
	for c = 2, 12 do table.insert(columns, c) end
	local colCount = #columns -- 11
	local padding = 1
	local minColW = 3 -- at least 3 characters per column
	local totalPad = padding * (colCount + 1)
	local availableW = math.max(1, r.w - totalPad)
	local colW = math.max(minColW, math.floor(availableW / colCount))
	local leftover = availableW - (colW * colCount)

	-- Header: column numbers
	local x = r.x + padding
	local headerY = r.y
	term.setTextColor(colors.orange)
	for idx, col in ipairs(columns) do
		local w = colW + (idx <= leftover and 1 or 0)
		local label = tostring(col)
		local cx = x + math.floor((w - #label) / 2)
		term.setCursorPos(cx, headerY)
		term.write(label)
		x = x + w + padding
	end

	-- Draw columns
	local baseY = r.y + 1
	local heightArea = usableH

	x = r.x + padding
	for idx, col in ipairs(columns) do
		local w = colW + (idx <= leftover and 1 or 0)
		local colHeight = BOARD_HEIGHTS[col]

		-- Column background box
		paintutils.drawFilledBox(x, baseY, x + w - 1, baseY + heightArea - 1, colors.gray)

		-- Claimed?
		if state.claimedColumns[col] then
			local owner = state.claimedColumns[col]
			local ownerColor = state.players[owner] and state.players[owner].color or colors.white
			paintutils.drawFilledBox(x, baseY, x + w - 1, baseY + heightArea - 1, ownerColor)
		end

		-- Scale: map progress 0..colHeight to visual 0..(heightArea-1)
		local function toYFromHeight(h)
			-- h: 1 means first step; h == colHeight at the top
			local t = (h / colHeight)
			local rel = heightArea - math.max(1, math.floor(t * (heightArea - 1)))
			return baseY + rel - 1
		end


		-- Draw permanent progress ticks for ALL players.
		-- Lua Tip: nested loops are fine; cost here is tiny compared to screen draw time.
		for pIndex, p in ipairs(state.players) do
			local perm = (state.permanentProgress[pIndex] and state.permanentProgress[pIndex][col]) or 0
			if perm > 0 then
				local yy = toYFromHeight(perm)
				-- Use player's assigned color for their progress; if column is claimed by someone else, still show (historical) but it will be under fill.
				local color = p.color or colors.white
				paintutils.drawLine(x, yy, x + w - 1, yy, color)
			end
		end

		-- Draw neutral marker for this turn
		local temp = state.neutralMarkers[col]
		if temp and temp > 0 then
			local yy = toYFromHeight(temp)
			paintutils.drawLine(x, yy, x + w - 1, yy, colors.lime)
		end

		-- Draw top cap (visual limit)
		local topY = toYFromHeight(colHeight)
		paintutils.drawLine(x, topY, x + w - 1, topY, colors.white)

		x = x + w + padding
	end
end

local function drawAll(labels, enabled)
	term.setBackgroundColor(colors.black)
	term.clear()
	computeLayout()
	drawStatus()
	drawDice()
	drawPlayersSummary()
	drawBoard()
	drawButtons(labels, enabled)
end

-- ==========================
-- Dice and pairing logic
-- ==========================

local function seedRandom()
	-- Lua Tip: Seed once at program start. Discard a few initial values.
	math.randomseed(os.epoch("utc"))
	for _ = 1, 5 do math.random() end
end

local function roll4Dice()
	return { math.random(1, 6), math.random(1, 6), math.random(1, 6), math.random(1, 6) }
end

local function computePairings(d)
	-- Three possible pairings for 4 dice
	local pairsList = {
		{ d[1] + d[2], d[3] + d[4] },
		{ d[1] + d[3], d[2] + d[4] },
		{ d[1] + d[4], d[2] + d[3] },
	}
	-- Deduplicate: order of sums in a pairing does not matter
	local unique = {}
	local out = {}
	for _, pr in ipairs(pairsList) do
		local a, b = pr[1], pr[2]
		local k = (a < b) and (a .. "-" .. b) or (b .. "-" .. a)
		if not unique[k] then
			unique[k] = true
			table.insert(out, { a, b })
		end
	end
	return out
end

local function activeColumnsCount(neutral)
	local c = 0
	for _ in pairs(neutral) do c = c + 1 end
	return c
end

local function canPlaceSumForCurrentPlayer(sum)
	-- Cannot place on a claimed column
	if state.claimedColumns[sum] then return false end

	local curP = state.currentPlayer
	local perm = (state.permanentProgress[curP] and state.permanentProgress[curP][sum]) or 0
	local temp = state.neutralMarkers[sum] or perm
	local nextStep = temp + 1
	if nextStep > BOARD_HEIGHTS[sum] then return false end

	-- If starting a new column this turn, ensure we don't exceed 3 active columns
	if state.neutralMarkers[sum] == nil then
		if activeColumnsCount(state.neutralMarkers) >= 3 then return false end
	end
	return true
end

local function filterValidPairings(pairings)
	local valid = {}
	for _, pr in ipairs(pairings) do
		local s1, s2 = pr[1], pr[2]
		if canPlaceSumForCurrentPlayer(s1) and canPlaceSumForCurrentPlayer(s2) then
			table.insert(valid, { s1, s2 })
		end
	end
	return valid
end

local function placePairing(pairing)
	-- Place both sums, assuming already validated
	local s1, s2 = pairing[1], pairing[2]
	local curP = state.currentPlayer
	local perm1 = (state.permanentProgress[curP] and state.permanentProgress[curP][s1]) or 0
	local perm2 = (state.permanentProgress[curP] and state.permanentProgress[curP][s2]) or 0

	state.neutralMarkers[s1] = (state.neutralMarkers[s1] or perm1) + 1
	state.neutralMarkers[s2] = (state.neutralMarkers[s2] or perm2) + 1
end

-- ==========================
-- Turn flow helpers
-- ==========================

local function bustTurn()
	state.neutralMarkers = {}
	state.statusText = "Busted! No valid pairings."
end

local function commitTurn()
	local curP = state.currentPlayer
	if not state.permanentProgress[curP] then state.permanentProgress[curP] = {} end
	for col, h in pairs(state.neutralMarkers) do
		state.permanentProgress[curP][col] = h
		if h == BOARD_HEIGHTS[col] then
			state.claimedColumns[col] = curP
		end
	end
	state.neutralMarkers = {}

	-- Check win condition (3 columns claimed by this player)
	local claimedByCur = 0
	for _, owner in pairs(state.claimedColumns) do
		if owner == curP then claimedByCur = claimedByCur + 1 end
	end
	if claimedByCur >= 3 then
		state.phase = PHASE.GAME_OVER
		state.statusText = (state.players[curP].name or ("Player " .. curP)) .. " wins!"
	else
		state.statusText = "Progress saved."
	end
end

local function nextPlayer()
	state.currentPlayer = ((state.currentPlayer) % #state.players) + 1
	state.neutralMarkers = {}
	state.lastRoll = nil
	state.validPairings = nil
	state.phase = PHASE.TURN
	state.statusText = (state.players[state.currentPlayer].name or ("Player " .. state.currentPlayer)) .. ": Roll or Stop"
end

local function newGame(keepPlayers)
	local savedPlayers = keepPlayers and deepcopy(state.players) or {}
	state.phase = (#savedPlayers >= 2) and PHASE.TURN or PHASE.LOBBY
	state.players = savedPlayers
	state.currentPlayer = 1
	state.claimedColumns = {}
	state.permanentProgress = {}
	state.neutralMarkers = {}
	state.lastRoll = nil
	state.validPairings = nil
	if #state.players >= 2 then
		state.statusText = (state.players[1].name or "Player 1") .. ": Roll or Stop"
	else
		state.statusText = "Add at least 2 players."
	end
end

-- ==========================
-- Save/Load
-- ==========================

local function saveGame()
	local data = {
		phase = state.phase,
		players = state.players,
		currentPlayer = state.currentPlayer,
		claimedColumns = state.claimedColumns,
		permanentProgress = state.permanentProgress,
	}
	local ok, err = pcall(function()
		local fh = fs.open(SAVE_FILE, "w")
		fh.write(textutils.serialize(data))
		fh.close()
	end)
	if ok then
		state.statusText = "Game saved."
	else
		state.statusText = "Save failed: " .. tostring(err)
	end
end

local function loadGame()
	if not fs.exists(SAVE_FILE) then
		state.statusText = "No save file found."
		return false
	end
	local ok, res = pcall(function()
		local fh = fs.open(SAVE_FILE, "r")
		local txt = fh.readAll()
		fh.close()
		return textutils.unserialize(txt)
	end)
	if ok and type(res) == "table" then
		state.phase = res.phase or PHASE.LOBBY
		state.players = res.players or {}
		state.currentPlayer = clamp(tonumber(res.currentPlayer) or 1, 1, math.max(1, #state.players))
		state.claimedColumns = res.claimedColumns or {}
		state.permanentProgress = res.permanentProgress or {}
		state.neutralMarkers = {}
		state.lastRoll = nil
		state.validPairings = nil
		state.statusText = "Save loaded."
		return true
	else
		state.statusText = "Load failed."
		return false
	end
end

-- ==========================
-- Input handling
-- ==========================

local function pointInRect(px, py, rx, ry, rw, rh)
	return px >= rx and px <= rx + rw - 1 and py >= ry and py <= ry + rh - 1
end

local function waitForButtonPress()
	while true do
		local e = { os.pullEvent() }
		local ev = e[1]
		if ev == "monitor_touch" then
			local _side, x, y = e[2], e[3], e[4]
			for i = 1, 3 do
				local r = layout.buttons[i]
				if pointInRect(x, y, r.x, r.y, r.w, r.h) then
					return i -- BTN.LEFT/CENTER/RIGHT
				end
			end
		elseif ev == "mouse_click" then
			-- If running on terminal, allow mouse clicks as well
			local _btn, x, y = e[2], e[3], e[4]
			for i = 1, 3 do
				local r = layout.buttons[i]
				if pointInRect(x, y, r.x, r.y, r.w, r.h) then
					return i
				end
			end
		elseif ev == "term_resize" or ev == "monitor_resize" then
			drawAll({"","",""}, {false,false,false})
		end
	end
end

-- ==========================
-- LOBBY helpers
-- ==========================

local function addAutoPlayer()
	local idx = #state.players + 1
	local name = "Player " .. idx
	local color = PLAYER_COLORS[((idx - 1) % #PLAYER_COLORS) + 1]
	table.insert(state.players, { name = name, color = color })
	state.statusText = string.format("Added %s. Players: %d", name, #state.players)
end

-- ==========================
-- Menus (simple)
-- ==========================

local function showMenuDuringTurn()
	-- Minimal menu: Center to Save, Left to Rules (help), Right to Close
	state.statusText = "Menu: Left=Rules, Center=Save, Right=Close"
	drawAll({"Rules","Save","Close"})
	while true do
		local b = waitForButtonPress()
		if b == BTN.LEFT then
			state.statusText = "Rules: Roll 4 dice, pick a pairing, use <=3 columns, Stop to save."
			drawAll({"Rules","Save","Close"})
		elseif b == BTN.CENTER then
			saveGame()
			drawAll({"Rules","Save","Close"})
		elseif b == BTN.RIGHT then
			state.statusText = (state.players[state.currentPlayer].name or "Player") .. ": Roll or Stop"
			return
		end
	end
end

-- ==========================
-- Main game loop
-- ==========================

local function runLobby()
	while state.phase == PHASE.LOBBY do
		drawAll({"Add Player","Start","Load/Reset"})
		local b = waitForButtonPress()
		if b == BTN.LEFT then
			addAutoPlayer()
		elseif b == BTN.CENTER then
			if #state.players >= 2 then
				newGame(true) -- keep players, move to TURN
			else
				state.statusText = "Need at least 2 players to start."
			end
		elseif b == BTN.RIGHT then
			-- Toggle: if save exists, load it; otherwise reset players
			if fs.exists(SAVE_FILE) then
				loadGame()
				if #state.players >= 2 then
					state.phase = PHASE.TURN
				else
					state.phase = PHASE.LOBBY
				end
			else
				state.players = {}
				state.statusText = "Reset lobby."
			end
		end
	end
end

local function runTurns()
	while state.phase == PHASE.TURN or state.phase == PHASE.CHOOSE do
		if state.phase == PHASE.TURN then
			-- Buttons: Roll, Stop, Menu
			drawAll({"Roll","Stop","Menu"})
			local b = waitForButtonPress()
			if b == BTN.LEFT then
				-- Roll
				state.lastRoll = roll4Dice()
				local pairsList = computePairings(state.lastRoll)
				state.validPairings = filterValidPairings(pairsList)
				if #state.validPairings == 0 then
					bustTurn()
					drawAll({"","",""}, {false,false,false})
					sleep(0.8)
					nextPlayer()
				else
					state.phase = PHASE.CHOOSE
					state.statusText = "Choose a pairing"
				end
			elseif b == BTN.CENTER then
				-- Stop/Commit
				commitTurn()
				drawAll({"","",""}, {false,false,false})
				if state.phase ~= PHASE.GAME_OVER then
					sleep(0.5)
					nextPlayer()
				end
			elseif b == BTN.RIGHT then
				-- Menu
				showMenuDuringTurn()
			end
		elseif state.phase == PHASE.CHOOSE then
			-- Map available pairings to buttons
			local labels = {"","",""}
			local enabled = {false,false,false}
			for i = 1, math.min(3, #state.validPairings) do
				local pr = state.validPairings[i]
				labels[i] = string.format("%d + %d", pr[1], pr[2])
				enabled[i] = true
			end
			drawAll(labels, enabled)
			local b = waitForButtonPress()
			local choice = nil
			if b >= 1 and b <= 3 and enabled[b] then
				choice = state.validPairings[b]
			end
			if choice then
				placePairing(choice)
				state.phase = PHASE.TURN
				state.statusText = "Placed. Roll or Stop."
			else
				-- ignore clicks on disabled slots
			end
		end
	end
end

local function runGameOver()
	while state.phase == PHASE.GAME_OVER do
		drawAll({"New Game","Save","Exit"})
		local b = waitForButtonPress()
		if b == BTN.LEFT then
			newGame(true)
		elseif b == BTN.CENTER then
			saveGame()
		elseif b == BTN.RIGHT then
			-- Return to lobby
			newGame(false)
		end
	end
end

-- ==========================
-- Entry point
-- ==========================

local function main()
	-- Arcade integration placeholder:
	-- You can later wrap this logic inside arcade.start({...}) if desired.
	-- For now we keep Can't Stop independent due to its bespoke UI.
	seedRandom()
	initMonitor()
	computeLayout()
	-- Start in lobby with no players
	state.phase = PHASE.LOBBY
	state.statusText = "Add players, then Start."

	while true do
		if state.phase == PHASE.LOBBY then
			runLobby()
		elseif state.phase == PHASE.TURN or state.phase == PHASE.CHOOSE then
			runTurns()
		elseif state.phase == PHASE.GAME_OVER then
			runGameOver()
		else
			state.phase = PHASE.LOBBY
		end
	end
end

-- Lua Tip: wrap main in pcall to catch runtime errors and show them on-screen.
local ok, err = pcall(main)
if not ok then
	if monitor then term.redirect(termNative) end
	print("Can't Stop crashed:\n" .. tostring(err))
	print("Press any key to exit...")
	os.pullEvent("key")
end

