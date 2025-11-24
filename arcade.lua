-- arcade.lua
-- Shared wrapper library for three-button arcade games in this folder.
-- Provides: monitor setup, 3-button UI bar, credit persistence via disk drive,
-- event loop abstraction, and helper APIs so each game only implements its
-- own state & drawing logic.
--
-- HOW TO USE (minimal):
-- local arcade = require("arcade")
-- local game = {
--   name = "Demo",
--   init = function(a) a:setButtons({"Play","Add","Quit"}) end,
--   draw = function(a) a:clearPlayfield(); a:centerPrint(1, game.name .. " Credits:" .. a:getCredits()) end,
--   onButton = function(a, button)
--       if button == "left" then a:addCredits(-1) end
--       if button == "center" then a:addCredits(1) end
--       if button == "right" then a:requestQuit() end
--   end
-- }
-- arcade.start(game)
--
-- See README_ARCADE.md for expanded documentation.
--
-- Lua Tips sprinkled in comments for learning. Search "Lua Tip:".

---@diagnostic disable: undefined-global, undefined-field

local M = {}
local Renderer = require("ui.renderer")

-- ==========================
-- Configuration defaults
-- ==========================

local DEFAULT = {
        textScale = 0.5,         -- Monitor text scale for readability
        buttonBarHeight = 3,     -- Height in rows of bottom bar
        creditsFile = "credits.txt", -- File stored on disk drive media
        tickSeconds = 0.25,      -- Passive tick interval (can drive animations)
        skin = Renderer.defaultSkin(), -- Shared skin/theme for buttons and backgrounds
}

-- ==========================
-- Internal state
-- ==========================

local state = {
        monitor = nil,
        termNative = term and term.current(),
        screenW = 0, screenH = 0,
	buttons = {"", "", ""},
	buttonEnabled = {true, true, true},
	quitRequested = false,
	game = nil,              -- game table passed to start()
	lastTickTime = 0,
	layout = {
		playfield = {x=1,y=1,w=0,h=0},
		buttonRects = { -- will be filled by computeLayout
			{x=1,y=1,w=1,h=1}, {x=1,y=1,w=1,h=1}, {x=1,y=1,w=1,h=1}
		}
	},
        credits = 0,
        drive = nil,             -- peripheral for disk drive
        config = DEFAULT,
        renderer = nil,
        skin = Renderer.defaultSkin(),
}

-- ==========================
-- Utility helpers
-- ==========================

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end

local function pointInRect(px,py,r)
	return px >= r.x and px <= r.x + r.w - 1 and py >= r.y and py <= r.y + r.h - 1
end

-- Safe FS helpers on disk. We call through to the disk drive's mount path if present.
local function diskPath()
	if not state.drive then return nil end
	local mount = peripheral.getName(state.drive)
	-- Lua Tip: peripheral.getName returns the attached side/name; the disk's mount path is available via disk.getMountPath().
	if state.drive.getMountPath then return state.drive.getMountPath() end
	-- Fallback: older CC may not have getMountPath; we simply return nil to use local folder.
	return nil
end

local function creditsFilePath()
	local mp = diskPath()
	if mp then return mp .. "/" .. state.config.creditsFile end
	return state.config.creditsFile -- local fallback
end

local function loadCredits()
	local path = creditsFilePath()
	if fs.exists(path) then
		local ok, val = pcall(function()
			local h = fs.open(path, "r"); local txt = h.readAll(); h.close(); return tonumber(txt) end)
		if ok and val then state.credits = clamp(val, 0, 10^12) end
	else
		state.credits = 0
	end
end

local function saveCredits()
	local path = creditsFilePath()
	local ok, err = pcall(function()
		local h = fs.open(path, "w"); h.write(tostring(state.credits)); h.close() end)
	if not ok then
		-- Non-fatal; games can choose to display warning
		return false, err
	end
	return true
end

-- ==========================
-- Layout & rendering
-- ==========================

local function applySkin(skinOverride)
        state.skin = Renderer.mergeSkin(Renderer.defaultSkin(), skinOverride or {})
        if state.renderer then state.renderer:setSkin(state.skin) end
end

local function computeLayout()
        state.screenW, state.screenH = state.renderer:getSize()
        local barH = state.config.buttonBarHeight
        local pfH = math.max(1, state.screenH - barH)
        state.layout.playfield.x = 1
        state.layout.playfield.y = 1
        state.layout.playfield.w = state.screenW
        state.layout.playfield.h = pfH
        -- buttons horizontally divided
        local btnW = math.floor(state.screenW / 3)
        local leftover = state.screenW - btnW * 3
        local startY = state.screenH - barH + 1
        for i=1,3 do
                local extra = (i <= leftover) and 1 or 0
                local x = 1 + (i-1)*btnW + math.min(i-1, leftover)
                local r = state.layout.buttonRects[i]
                r.x, r.y, r.w, r.h = x, startY, btnW+extra, barH
                state.renderer:registerHotspot("button"..i, r)
        end
end

local function drawButtonBar()
        local barRect = { x = 1, y = state.screenH - state.config.buttonBarHeight + 1, w = state.screenW, h = state.config.buttonBarHeight }
        state.renderer:paintSurface(barRect, state.skin.buttonBar.background or colors.black)
end

local function drawButtons()
        drawButtonBar()
        for i=1,3 do
                local r = state.layout.buttonRects[i]
                local enabled = state.buttonEnabled[i]
                local label = state.buttons[i]
                state.renderer:drawButton(r, label, enabled)
        end
end

function M:clearPlayfield(surface)
        local pf = state.layout.playfield
        state.renderer:paintSurface(pf, surface or state.skin.playfield)
end

function M:centerPrint(relY, text, fg, bg)
	local pf = state.layout.playfield
	local y = pf.y + relY - 1
	if y < pf.y or y > pf.y + pf.h - 1 then return end
	if bg then term.setBackgroundColor(bg) end
	if fg then term.setTextColor(fg) end
	local x = pf.x + math.floor((pf.w - #text)/2)
	term.setCursorPos(x, y)
	term.write(text)
end

function M:setButtons(labels, enabled)
	for i=1,3 do
		state.buttons[i] = labels[i] or ""
		state.buttonEnabled[i] = (not enabled) and true or (enabled[i] ~= false)
	end
	drawButtons()
end

function M:enableButton(index, value)
	state.buttonEnabled[index] = not not value
	drawButtons()
end

-- ==========================
-- Credits API
-- ==========================

function M:getCredits() return state.credits end
function M:addCredits(delta)
	state.credits = math.max(0, state.credits + delta)
	saveCredits()
end
function M:consumeCredits(amount)
	if state.credits >= amount then
		state.credits = state.credits - amount
		saveCredits(); return true
	end
	return false
end

-- ==========================
-- Quit control
-- ==========================

function M:requestQuit()
	state.quitRequested = true
end

-- ==========================
-- Event processing
-- ==========================

local function detectMonitor()
        state.monitor = peripheral.find and peripheral.find("monitor") or nil
        if state.monitor then
                state.renderer:attachToMonitor(state.monitor, state.config.textScale)
        else
                state.renderer:attachToMonitor(nil)
        end
end

local function detectDiskDrive()
	state.drive = peripheral.find and peripheral.find("drive") or nil
	-- If a disk is inserted we will persist credits there; else local file.
end

local function redrawAll()
        computeLayout()
        M:clearPlayfield()
        drawButtons()
        if state.game and state.game.draw then state.game.draw(M) end
end

local function handleButtonPress(idx)
	local names = {"left","center","right"}
	if not state.buttonEnabled[idx] then return end
	if state.game and state.game.onButton then
		state.game.onButton(M, names[idx])
	end
end

local function waitEvent()
	return { os.pullEvent() }
end

local function processEvent(e)
        local ev = e[1]
        if ev == "term_resize" or ev == "monitor_resize" then
                redrawAll(); return
        elseif ev == "monitor_touch" then
                local x,y = e[3], e[4]
                for i=1,3 do if state.renderer:hitTest("button"..i, x, y) then handleButtonPress(i); return end end
        elseif ev == "mouse_click" then
                local x,y = e[3], e[4]
                for i=1,3 do if state.renderer:hitTest("button"..i, x, y) then handleButtonPress(i); return end end
        elseif ev == "timer" then
                local id = e[2]
                if id == state._tickTimer then
			if state.game and state.game.onTick then
				state.game.onTick(M, state.config.tickSeconds)
			end
			if state.quitRequested then return end
			state._tickTimer = os.startTimer(state.config.tickSeconds)
		end
	elseif ev == "key" then
		local keyCode = e[2]
		-- Lua Tip: key codes vary; we map space & q common actions.
		if keyCode == keys.q then M:requestQuit() end
		if keyCode == keys.space then handleButtonPress(1) end
	elseif ev == "char" then
		local ch = e[2]
		if ch == "q" then M:requestQuit() end
		if ch == "1" then handleButtonPress(1) elseif ch == "2" then handleButtonPress(2) elseif ch == "3" then handleButtonPress(3) end
	end
end

-- ==========================
-- Public start API
-- ==========================

function M.start(gameTable, configOverride)
        state.game = gameTable
        state.config = {}
        for k,v in pairs(DEFAULT) do state.config[k] = v end
        if configOverride then for k,v in pairs(configOverride) do state.config[k]=v end end
        applySkin(state.config.skin)
        state.renderer = Renderer.new({ skin = state.skin })
        detectMonitor()
        detectDiskDrive()
        loadCredits()
	computeLayout()
	if state.game and state.game.init then state.game.init(M) end
	redrawAll()
	state._tickTimer = os.startTimer(state.config.tickSeconds)
        while not state.quitRequested do
                local e = waitEvent()
                processEvent(e)
        end
        -- Clean up terminal redirection
        if state.renderer then state.renderer:restore() end
        -- Persist credits one last time
        saveCredits()
end

-- Return module table for require()
return M
