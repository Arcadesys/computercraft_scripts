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
 local Renderer = require("arcade.ui.renderer")
 local Log = require("log")

-- ==========================
-- Configuration defaults
-- ==========================

local DEFAULT = {
        textScale = 0.5,         -- Monitor text scale for readability
        buttonBarHeight = 3,     -- Height in rows of bottom bar
        creditsFile = "credits.txt", -- File stored on disk drive media
        tickSeconds = 0.25,      -- Passive tick interval (can drive animations)
        skin = Renderer.defaultSkin(), -- Shared skin/theme for buttons and backgrounds
        logFile = "arcade.log",  -- Where to write diagnostic information
        logLevel = "info",       -- error < warn < info < debug
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
        logger = nil,
}

-- ==========================
-- Utility helpers
-- ==========================

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end

local function log(level, message)
        if not state.logger or not state.logger[level] then return end
        state.logger[level](state.logger, message)
end

local function safeCall(label, fn, ...)
        if type(fn) ~= "function" then return end
        local ok, err = pcall(fn, ...)
        if not ok then
                log("warn", label .. " failed: " .. tostring(err))
                -- Emergency print to screen
                local w,h = term.getSize()
                term.setCursorPos(1, h)
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.red)
                term.write("ERR: " .. label .. " " .. tostring(err))
        end
end

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
                if ok and val then
                        state.credits = clamp(val, 0, 10^12)
                        log("info", "Credits loaded from " .. path .. ": " .. state.credits)
                else
                        log("warn", "Failed to read credits file, resetting balance.")
                        state.credits = 0
                end
        else
                state.credits = 0
                log("info", "No credits file found; starting at 0")
        end
end

local function saveCredits()
        local path = creditsFilePath()
        local ok, err = pcall(function()
                local h = fs.open(path, "w"); h.write(tostring(state.credits)); h.close() end)
        if not ok then
                -- Non-fatal; games can choose to display warning
                log("warn", "Failed to persist credits: " .. tostring(err))
                return false, err
        end
        log("debug", "Credits saved to " .. path .. ": " .. state.credits)
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
        if not state.renderer then return end
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
        if not state.renderer then return end
        local barRect = { x = 1, y = state.screenH - state.config.buttonBarHeight + 1, w = state.screenW, h = state.config.buttonBarHeight }
        state.renderer:paintSurface(barRect, state.skin.buttonBar.background or colors.black)
end

local function drawButtons()
        if not state.renderer then return end
        drawButtonBar()
        for i=1,3 do
                local r = state.layout.buttonRects[i]
                local enabled = state.buttonEnabled[i]
                local label = state.buttons[i]
                state.renderer:drawButton(r, label, enabled)
        end
end

function M:clearPlayfield(surface)
        if not state.renderer then return end
        local pf = state.layout.playfield
        state.renderer:paintSurface(pf, surface or state.skin.playfield)
end

function M:centerPrint(relY, text, fg, bg)
        if not state.renderer then return end
        local pf = state.layout.playfield
        local y = pf.y + relY - 1
        if y < pf.y or y > pf.y + pf.h - 1 then return end
	if bg then term.setBackgroundColor(bg) end
	if fg then term.setTextColor(fg) end
	local x = pf.x + math.floor((pf.w - #text)/2)
	term.setCursorPos(x, y)
	term.write(text)
    -- Debug: ensure text is written
    -- term.setCursorPos(1,1); term.write("CP: " .. text)
end

function M:setButtons(labels, enabled)
        if not state.renderer then return end
        for i=1,3 do
                state.buttons[i] = labels[i] or ""
                state.buttonEnabled[i] = (not enabled) and true or (enabled[i] ~= false)
        end
        drawButtons()
end

function M:enableButton(index, value)
        if not state.renderer then return end
        state.buttonEnabled[index] = not not value
        drawButtons()
end

-- ==========================
-- Credits API
-- ==========================

function M:getCredits() return state.credits end
function M:addCredits(delta)
        local before = state.credits
        state.credits = math.max(0, state.credits + delta)
        log("info", string.format("Credits updated %d -> %d (delta %+d)", before, state.credits, delta))
        saveCredits()
end
function M:consumeCredits(amount)
        if state.credits >= amount then
                log("debug", "Consuming credits: " .. amount)
                state.credits = state.credits - amount
                saveCredits(); return true
        end
	return false
end

function M:setSkin(skin)
    applySkin(skin)
    redrawAll()
end

-- ==========================
-- Quit control
-- ==========================

function M:getRenderer()
    return state.renderer
end

function M:getMonitor()
    return state.monitor
end

function M:requestQuit()
        log("info", "Quit requested")
        state.quitRequested = true
end

-- ==========================
-- Event processing
-- ==========================

local function detectMonitor()
        state.monitor = peripheral.find and peripheral.find("monitor") or nil
        if state.monitor then
                state.renderer:attachToMonitor(state.monitor, state.config.textScale)
                log("info", "Monitor detected: " .. (peripheral.getName and peripheral.getName(state.monitor) or "unknown"))
        else
                state.renderer:attachToMonitor(nil)
                log("warn", "No monitor detected; falling back to terminal display")
        end
end

local function detectDiskDrive()
        state.drive = peripheral.find and peripheral.find("drive") or nil
        -- If a disk is inserted we will persist credits there; else local file.
        if state.drive then
                log("info", "Disk drive detected: " .. (peripheral.getName and peripheral.getName(state.drive) or "unknown"))
        else
                log("debug", "No disk drive; credits stored locally")
        end
end

local function redrawAll()
        computeLayout()
        M:clearPlayfield()
        drawButtons()
        if state.game and state.game.draw then safeCall("game.draw", state.game.draw, state.game, M) end
end

local function handleButtonPress(idx)
        local names = {"left","center","right"}
        if not state.buttonEnabled[idx] then return end
        if state.game and state.game.onButton then
                log("debug", "Button pressed: " .. names[idx])
                safeCall("game.onButton", state.game.onButton, state.game, M, names[idx])
        end
end

local function waitEvent()
	return { os.pullEvent() }
end

local function processEvent(e)
        if not state.renderer then return end
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
                                safeCall("game.onTick", state.game.onTick, state.game, M, state.config.tickSeconds)
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

local SKIN_FILE = "arcade_skin.settings"

local function loadSkin()
    if fs.exists(SKIN_FILE) then
        local f = fs.open(SKIN_FILE, "r")
        if f then
            local data = textutils.unserialize(f.readAll())
            f.close()
            if data then
                state.config.skin = Renderer.mergeSkin(Renderer.defaultSkin(), data)
            end
        end
    end
end

function M.start(gameTable, configOverride)
        state.game = gameTable
        state.quitRequested = false
        state.config = {}
        for k,v in pairs(DEFAULT) do state.config[k] = v end
        if configOverride then for k,v in pairs(configOverride) do state.config[k]=v end end
        state.logger = Log.new({ logFile = state.config.logFile, level = state.config.logLevel })
        log("info", "Starting arcade wrapper" .. (state.game and (" for " .. (state.game.name or "game")) or ""))
        
        loadSkin()
        applySkin(state.config.skin)
        
        local okRenderer, rendererOrErr = pcall(Renderer.new, { skin = state.skin })
        if not okRenderer or not rendererOrErr then
                log("error", "Renderer initialization failed: " .. tostring(rendererOrErr))
                return
        end
        state.renderer = rendererOrErr
        detectMonitor()
        detectDiskDrive()
        loadCredits()
        computeLayout()
        if state.game and state.game.init then safeCall("game.init", state.game.init, state.game, M) end
        redrawAll()
        state._tickTimer = os.startTimer(state.config.tickSeconds)
        while not state.quitRequested do
                local e = waitEvent()
                local ok, err = pcall(processEvent, e)
                if not ok then
                        log("error", "Event loop error: " .. tostring(err))
                        M:clearPlayfield(colors.black)
                        M:centerPrint(1, "Arcade error - see log", colors.red)
                        break
                end
        end
        -- Clean up terminal redirection
        if state.renderer then state.renderer:restore() end
        -- Persist credits one last time
        saveCredits()
        log("info", "Arcade wrapper stopped")
end

-- Return module table for require()
return M
