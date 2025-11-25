-- ArcadeOS Installer
-- Auto-generated installer script
-- Run this file on a ComputerCraft computer to install the OS.

print("Initializing ArcadeOS Installer...")
local files = {}

files["arcade.lua"] = [[-- arcade.lua
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

function M.start(gameTable, configOverride)
        state.game = gameTable
        state.config = {}
        for k,v in pairs(DEFAULT) do state.config[k] = v end
        if configOverride then for k,v in pairs(configOverride) do state.config[k]=v end end
        state.logger = Log.new({ logFile = state.config.logFile, level = state.config.logLevel })
        log("info", "Starting arcade wrapper" .. (state.game and (" for " .. (state.game.name or "game")) or ""))
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
]]
files["arcade_shell.lua"] = [[---@diagnostic disable: undefined-global
-- arcade_shell.lua
-- Simple shell UI that lists arcade programs, lets players buy licenses,
-- and launches games once unlocked.

local LicenseStore = require("license_store")

-- ==========================
-- Persistence helpers
-- ==========================

local CREDIT_FILE = "credits.txt"
local DEFAULT_LICENSE_DIR = "licenses"
local SECRET_SALT = "arcade-license-v1"

local function detectDiskMount()
  local drive = peripheral.find and peripheral.find("drive") or nil
  if drive and drive.getMountPath then
    return drive.getMountPath()
  end
  return nil
end

local function combinePath(base, child)
  if base then
    return fs.combine(base, child)
  end
  return child
end

local function creditsPath()
  return combinePath(detectDiskMount(), CREDIT_FILE)
end

local function loadCredits()
  local path = creditsPath()
  if fs.exists(path) then
    local ok, value = pcall(function()
      local handle = fs.open(path, "r")
      local text = handle.readAll()
      handle.close()
      return tonumber(text)
    end)
    if ok and value then
      return math.max(0, value)
    end
  end
  return 0
end

local function saveCredits(amount)
  local path = creditsPath()
  local handle = fs.open(path, "w")
  handle.write(tostring(amount))
  handle.close()
end

-- ==========================
-- Program catalog
-- ==========================

local programs = {
  {
    id = "blackjack",
    name = "Blackjack",
    path = "blackjack.lua",
    price = 5,
    description = "Beat the dealer in a race to 21.",
    category = "games",
  },
  {
    id = "slots",
    name = "Slots",
    path = "slots.lua",
    price = 3,
    description = "Spin reels for quick wins.",
    category = "games",
  },
  {
    id = "cantstop",
    name = "Can't Stop",
    path = "cantstop.lua",
    price = 4,
    description = "Push your luck dice classic.",
    category = "games",
  },
  {
    id = "idlecraft",
    name = "IdleCraft",
    path = "idlecraft.lua",
    price = 6,
    description = "AFK-friendly cobble empire.",
    category = "games",
  },
  {
    id = "artillery",
    name = "Artillery",
    path = "artillery.lua",
    price = 5,
    description = "2-player tank battle.",
    category = "games",
  },
  {
    id = "factory_planner",
    name = "Factory Planner",
    path = "factory_planner.lua",
    price = 0,
    description = "Design factory layouts for turtles.",
    category = "actions",
  },
  -- Placeholder for Inventory Manager
  {
    id = "inv_manager",
    name = "Inventory Manager",
    path = "inv_manager.lua", -- Doesn't exist yet
    price = 0,
    description = "Manage inventory (Coming Soon).",
    category = "actions",
  },
}

-- ==========================
-- Shell state
-- ==========================

local state = {
  credits = 0,
  licenseStore = nil,
  theme = {
    text = colors.white,
    bg = colors.black,
    header = colors.blue,
    highlight = colors.yellow
  }
}

local THEME_FILE = "theme.settings"

local function loadTheme()
  if fs.exists(THEME_FILE) then
    local handle = fs.open(THEME_FILE, "r")
    if handle then
      local data = textutils.unserialize(handle.readAll())
      handle.close()
      if data then
        for k, v in pairs(data) do state.theme[k] = v end
      end
    end
  end
end

local function saveTheme()
  local handle = fs.open(THEME_FILE, "w")
  if handle then
    handle.write(textutils.serialize(state.theme))
    handle.close()
  end
end

local function initState()
  state.credits = loadCredits()
  local base = combinePath(detectDiskMount(), DEFAULT_LICENSE_DIR)
  state.licenseStore = LicenseStore.new(base, SECRET_SALT)
  loadTheme()
end

-- ==========================
-- DOS UI System
-- ==========================

local UI = {}

function UI.clear(color)
    term.setBackgroundColor(color)
    term.clear()
end

function UI.drawWindow(x, y, w, h, title)
    -- Shadow
    paintutils.drawFilledBox(x + 1, y + 1, x + w, y + h, colors.black)
    -- Body
    paintutils.drawFilledBox(x, y, x + w - 1, y + h - 1, colors.lightGray)
    -- Title Bar
    paintutils.drawFilledBox(x, y, x + w - 1, y, colors.blue)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.blue)
    term.setCursorPos(x + math.floor((w - #title) / 2), y)
    term.write(title)
    -- Close button
    term.setCursorPos(x + 2, y)
    term.write("[X]")
end

function UI.drawButton(x, y, w, text, active, hovered)
    local bg = active and colors.green or (hovered and colors.gray or colors.lightGray)
    local fg = active and colors.white or (hovered and colors.white or colors.black)
    
    -- If it's a button on a gray background, we might want it to pop
    if not active and not hovered then
        bg = colors.gray
        fg = colors.white
    end

    paintutils.drawFilledBox(x, y, x + w - 1, y, bg)
    term.setTextColor(fg)
    term.setBackgroundColor(bg)
    term.setCursorPos(x + math.floor((w - #text) / 2), y)
    term.write(text)
end

-- ==========================
-- License helpers
-- ==========================

local function ensureLicense(program)
  local owned = state.licenseStore:has(program.id)
  if owned then
    return true
  end

  term.setBackgroundColor(colors.blue)
  term.clear()
  local w, h = term.getSize()
  local msg = string.format("Purchase %s for %d credits?", program.name, program.price)
  
  UI.drawWindow(math.floor((w-30)/2), math.floor((h-10)/2), 30, 10, "Purchase Required")
  term.setCursorPos(math.floor((w-#msg)/2), math.floor((h-10)/2) + 3)
  term.setTextColor(colors.black)
  term.setBackgroundColor(colors.lightGray)
  term.write(msg)
  
  term.setCursorPos(math.floor((w-20)/2), math.floor((h-10)/2) + 5)
  term.write("Current Credits: " .. state.credits)
  
  term.setCursorPos(math.floor((w-20)/2), math.floor((h-10)/2) + 7)
  term.write("(Y)es   (N)o")
  
  while true do
      local event, key = os.pullEvent("char")
      key = string.lower(key)
      if key == "n" then return false end
      if key == "y" then
          if state.credits < program.price then
              term.setCursorPos(math.floor((w-20)/2), math.floor((h-10)/2) + 8)
              term.setTextColor(colors.red)
              term.write("Not enough credits!")
              os.sleep(1)
              return false
          end
          
          state.credits = state.credits - program.price
          saveCredits(state.credits)
          state.licenseStore:save(program.id, program.price, "purchased via shell")
          return true
      end
  end
end

-- ==========================
-- Package Manager
-- ==========================

local function downloadPackage(code, filename)
    if not http then
        print("Error: HTTP API not enabled.")
        return false
    end

    local url = "https://pastebin.com/raw/" .. textutils.urlEncode(code)
    print("Connecting to Pastebin...")
    local response = http.get(url)
    if response then
        print("Downloading...")
        local content = response.readAll()
        response.close()
        
        local file = fs.open(filename, "w")
        file.write(content)
        file.close()
        print("Saved to " .. filename)
        return true
    else
        print("Failed to download.")
        return false
    end
end

local function packageManagerScreen()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.white)
    print("Pastebin Package Manager")
    print("------------------------")
    print("Enter Pastebin Code:")
    write("> ")
    local code = read()
    if #code > 0 then
        print("Enter Filename (e.g. game.lua):")
        write("> ")
        local name = read()
        if #name > 0 then
            downloadPackage(code, name)
            os.sleep(2)
        end
    end
end

-- ==========================
-- Main Loop
-- ==========================

local function launchProgram(program)
  if not ensureLicense(program) then
    return
  end

  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1,1)
  print("Launching " .. program.name .. "...")
  
  local ok, err = pcall(function()
    shell.run(program.path)
  end)
  
  if not ok then
    print("Program error: " .. tostring(err))
    print("Press Enter to return...")
    read()
  end
end

local function main()
  initState()
  
  local w, h = term.getSize()
  local running = true
  local currentMenu = "main" -- main, games, actions, utils
  local mouseX, mouseY = 0, 0
  
  while running do
    -- Draw Desktop
    UI.clear(colors.cyan)
    
    -- Draw Window
    local winW, winH = 26, 14
    local winX = math.floor((w - winW) / 2) + 1
    local winY = math.floor((h - winH) / 2) + 1
    
    local title = "ArcadeOS"
    if currentMenu == "games" then title = "Games" end
    if currentMenu == "actions" then title = "Actions" end
    if currentMenu == "utils" then title = "Utilities" end
    
    UI.drawWindow(winX, winY, winW, winH, title)
    
    -- Define Buttons
    local buttons = {}
    local startY = winY + 2
    local btnW = winW - 8
    local btnX = winX + 4
    
    if currentMenu == "main" then
        table.insert(buttons, {text = "Games", y = startY, action = function() currentMenu = "games" end})
        table.insert(buttons, {text = "Actions", y = startY + 2, action = function() currentMenu = "actions" end})
        table.insert(buttons, {text = "Utilities", y = startY + 4, action = function() currentMenu = "utils" end})
        table.insert(buttons, {text = "Exit", y = startY + 8, action = function() running = false end})
    elseif currentMenu == "games" or currentMenu == "actions" then
        local list = {}
        for _, p in ipairs(programs) do
            if p.category == currentMenu then table.insert(list, p) end
        end
        
        for i, p in ipairs(list) do
            if i > 5 then break end
            table.insert(buttons, {
                text = p.name, 
                y = startY + (i-1)*2, 
                action = function() launchProgram(p) end
            })
        end
        table.insert(buttons, {text = "Back", y = winY + winH - 2, action = function() currentMenu = "main" end})
    elseif currentMenu == "utils" then
        table.insert(buttons, {text = "Package Manager", y = startY, action = packageManagerScreen})
        table.insert(buttons, {text = "Disk Info", y = startY + 2, action = function() 
            term.setBackgroundColor(colors.black)
            term.clear()
            term.setCursorPos(1,1)
            print("Free Space: " .. fs.getFreeSpace(detectDiskMount() or "/"))
            os.sleep(2)
        end})
        table.insert(buttons, {text = "Back", y = winY + winH - 2, action = function() currentMenu = "main" end})
    end
    
    -- Draw Buttons
    for _, btn in ipairs(buttons) do
        local isHovered = (mouseX >= btnX and mouseX <= btnX + btnW - 1 and mouseY == btn.y)
        UI.drawButton(btnX, btn.y, btnW, btn.text, false, isHovered)
    end
    
    -- Event Handling
    local event, p1, p2, p3 = os.pullEvent()
    
    if event == "mouse_click" or event == "mouse_drag" or event == "mouse_move" then
        mouseX, mouseY = p2, p3
        if event == "mouse_click" and p1 == 1 then
             for _, btn in ipairs(buttons) do
                if mouseX >= btnX and mouseX <= btnX + btnW - 1 and mouseY == btn.y then
                    UI.drawButton(btnX, btn.y, btnW, btn.text, true, true)
                    os.sleep(0.1)
                    btn.action()
                    mouseX, mouseY = -1, -1 -- Reset
                end
             end
        end
    elseif event == "key" then
        -- Basic keyboard nav could go here
    end
  end
  
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1,1)
end

main()
]]
files["artillery.lua"] = [[-- artillery.lua
-- A 2-player artillery game using Pine3D

-- Check if Pine3D is installed
if not fs.exists("Pine3D.lua") and not fs.exists("Pine3D") then
    print("Pine3D not found. Please install it using:")
    print("pastebin run qpJYiYs2")
    return
end

local Pine3D = require("Pine3D")

-- Debug: Try to load the model manually to check for syntax errors
local function testLoad(path)
    if not fs.exists(path) then
        print("File not found: " .. path)
        return false
    end
    local ok, err = loadfile(path)
    if not ok then
        printError("Syntax error in " .. path .. ": " .. tostring(err))
        return false
    end
    local ok2, res = pcall(ok)
    if not ok2 then
        printError("Runtime error loading " .. path .. ": " .. tostring(res))
        return false
    end
    -- print("Successfully loaded " .. path) -- Commented out to reduce noise if working
    return true
end

testLoad("models/tank.lua")
testLoad("models/projectile.lua")

-- Initialize Frame
local frame = Pine3D.newFrame()
frame:setFoV(60)
frame:setCamera(0, 8, -15, 0.4, 0, 0) -- Positioned high and back, looking down slightly
frame:setBackgroundColor(colors.lightBlue)

-- Game Constants
local GRAVITY = 9.8
local DT = 0.1
local GROUND_Y = 0

-- Game State
local players = {
    {
        id = 1,
        x = -8, y = 0, z = 0,
        angle = 45,
        velocity = 15,
        color = colors.blue,
        model = nil -- Will be assigned
    },
    {
        id = 2,
        x = 8, y = 0, z = 0,
        angle = 135, -- Facing left
        velocity = 15,
        color = colors.red,
        model = nil -- Will be assigned
    }
}

local turn = 1
local projectile = {
    active = false,
    x = 0, y = 0, z = 0,
    vx = 0, vy = 0, vz = 0,
    model = nil
}

-- Load Models
-- Using "tank" instead of "models/tank" assuming Pine3D searches in "models/" by default
players[1].model = frame:newObject("tank", players[1].x, players[1].y, players[1].z)
players[2].model = frame:newObject("tank", players[2].x, players[2].y, players[2].z)
projectile.model = frame:newObject("projectile", 0, -10, 0) -- Hide initially

-- Helper to draw text on top of 3D view
local function drawUI(text, line)
    term.setCursorPos(1, line)
    term.clearLine()
    term.write(text)
end

local function updateModels()
    -- Update player positions
    for _, p in ipairs(players) do
        if p.model then
             p.model.x = p.x
             p.model.y = p.y
             p.model.z = p.z
             -- Rotate player 2 to face left
             if p.id == 2 then
                 p.model.rotY = math.pi
             end
        end
    end
    
    if projectile.active then
        projectile.model.x = projectile.x
        projectile.model.y = projectile.y
        projectile.model.z = projectile.z
    else
        projectile.model.y = -100 -- Hide
    end
end

local function fire(player)
    projectile.active = true
    projectile.x = player.x
    projectile.y = player.y + 1 -- Start above tank
    projectile.z = player.z
    
    local rad = math.rad(player.angle)
    
    local vx = math.cos(rad) * player.velocity
    local vy = math.sin(rad) * player.velocity
    
    projectile.vx = vx
    projectile.vy = vy
    projectile.vz = 0
end

local function gameLoop()
    while true do
        -- Render
        updateModels()
        frame:drawObjects({players[1].model, players[2].model, projectile.model})
        frame:drawBuffer()
        
        -- UI
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        drawUI("Player " .. turn .. "'s Turn", 1)
        drawUI("Angle: " .. players[turn].angle, 2)
        drawUI("Velocity: " .. players[turn].velocity, 3)
        drawUI("Pos: " .. players[turn].x, 4)
        
        if projectile.active then
            -- Physics
            projectile.x = projectile.x + projectile.vx * DT
            projectile.y = projectile.y + projectile.vy * DT
            projectile.vy = projectile.vy - GRAVITY * DT
            
            -- Collision with ground
            if projectile.y <= GROUND_Y then
                projectile.active = false
                -- Check hit
                local hit = false
                for _, p in ipairs(players) do
                    if math.abs(projectile.x - p.x) < 1.5 then
                        drawUI("HIT Player " .. p.id .. "!", 5)
                        sleep(2)
                        hit = true
                        -- Reset positions? Or just end game?
                        -- For now, just print hit.
                    end
                end
                
                if not hit then
                    drawUI("Miss!", 5)
                    sleep(1)
                end
                
                -- Switch turn
                turn = (turn % 2) + 1
            end
            
            sleep(0.05)
        else
            -- Input
            drawUI("Action: (A)ngle, (V)elocity, (M)ove, (F)ire, (Q)uit", 6)
            
            local event, key = os.pullEvent("char")
            key = string.lower(key)
            
            if key == "a" then
                drawUI("Enter Angle: ", 7)
                term.setCursorPos(14, 7)
                local input = read()
                local num = tonumber(input)
                if num then players[turn].angle = num end
                drawUI("", 7) -- Clear line
            elseif key == "v" then
                drawUI("Enter Velocity: ", 7)
                term.setCursorPos(16, 7)
                local input = read()
                local num = tonumber(input)
                if num then players[turn].velocity = num end
                drawUI("", 7) -- Clear line
            elseif key == "m" then
                drawUI("Move (-1/1): ", 7)
                term.setCursorPos(14, 7)
                local input = read()
                local num = tonumber(input)
                if num then players[turn].x = players[turn].x + num end
                drawUI("", 7) -- Clear line
            elseif key == "f" then
                fire(players[turn])
            elseif key == "q" then
                term.clear()
                term.setCursorPos(1,1)
                break
            end
        end
    end
end

gameLoop()]]
files["blackjack.lua"] = [[---@diagnostic disable: undefined-global, undefined-field
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
]]
files["cantstop.lua"] = [[-- Can't Stop (Sid Sackson) on ComputerCraft
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
local _arcade_ok, _arcade = pcall(require, "games.arcade")
local Renderer = require("arcade.ui.renderer")

local function toBlit(color)
        if colors.toBlit then return colors.toBlit(color) end
        return string.format("%x", math.floor(math.log(color, 2)))
end

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
local rendererSkin = Renderer.mergeSkin(Renderer.defaultSkin(), {
        playfield = colors.black,
        buttonBar = { background = colors.black },
        buttons = {
                enabled = {
                        texture = { rows = {
                                { text = "::::", fg = string.rep(toBlit(colors.white), 4), bg = string.rep(toBlit(colors.orange), 4) },
                                { text = "++++", fg = string.rep(toBlit(colors.white), 4), bg = string.rep(toBlit(colors.red), 4) },
                                { text = "....", fg = string.rep(toBlit(colors.white), 4), bg = string.rep(toBlit(colors.brown), 4) },
                        }},
                        labelColor = colors.white,
                        shadowColor = colors.black,
                },
                disabled = {
                        texture = { rows = {
                                { text = "    ", fg = string.rep(toBlit(colors.gray), 4), bg = string.rep(toBlit(colors.black), 4) },
                                { text = "    ", fg = string.rep(toBlit(colors.gray), 4), bg = string.rep(toBlit(colors.black), 4) },
                        }},
                        labelColor = colors.lightGray,
                        shadowColor = colors.black,
                }
        },
})
local renderer = Renderer.new({ skin = rendererSkin })

local function initMonitor()
        -- Try to find an attached monitor; if none, we use the normal terminal.
        monitor = peripheral.find and peripheral.find("monitor") or nil
        if monitor then
                renderer:attachToMonitor(monitor, 0.5) -- smaller text for more info
        else
                renderer:attachToMonitor(nil)
        end
        screenW, screenH = renderer:getSize()
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
        screenW, screenH = renderer:getSize()
        -- Board takes everything above the bottom bar, minus top 2 lines (status & dice)
        local boardTop = 3
        local boardBottom = screenH - BUTTON_BAR_HEIGHT
        local pfH = math.max(1, screenH - BUTTON_BAR_HEIGHT)
        layout.board.x = 1
        layout.board.y = boardTop
        layout.board.w = screenW
        layout.board.h = pfH
        -- buttons horizontally divided
        local btnW = math.floor(screenW / 3)
        local leftover = screenW - (btnW * 3)
        local startY = screenH - BUTTON_BAR_HEIGHT + 1
        for i = 1, 3 do
                local extra = (i <= leftover) and 1 or 0
                local x = 1 + (i - 1) * btnW + math.min(i - 1, leftover)
                layout.buttons[i].x = x
                layout.buttons[i].y = startY
                layout.buttons[i].w = btnW + extra
                layout.buttons[i].h = BUTTON_BAR_HEIGHT
                renderer:registerHotspot("button" .. i, layout.buttons[i])
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
        -- The shared renderer tiles textures for us; fallback to color fill when no texture is provided.
        renderer:paintSurface({ x = x, y = y, w = w, h = h }, bg or rendererSkin.playfield)
        if fg then term.setTextColor(fg) end
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
        -- Paint a bar backdrop before stamping the individual buttons.
        renderer:paintSurface({ x = 1, y = layout.buttons[1].y, w = screenW, h = BUTTON_BAR_HEIGHT }, rendererSkin.buttonBar.background)
        for i = 1, 3 do
                local r = layout.buttons[i]
                renderer:drawButton(r, labels[i] or "", enabled[i] ~= false)
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
        computeLayout()
        renderer:paintSurface({ x = 1, y = 1, w = screenW, h = screenH }, rendererSkin.playfield)
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

local function waitForButtonPress()
	while true do
		local e = { os.pullEvent() }
		local ev = e[1]
                if ev == "monitor_touch" then
                        local _side, x, y = e[2], e[3], e[4]
                        for i = 1, 3 do if renderer:hitTest("button" .. i, x, y) then return i end end
                elseif ev == "mouse_click" then
                        -- If running on terminal, allow mouse clicks as well
                        local _btn, x, y = e[2], e[3], e[4]
                        for i = 1, 3 do if renderer:hitTest("button" .. i, x, y) then return i end end
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
        if renderer then renderer:restore() end
        print("Can't Stop crashed:\n" .. tostring(err))
        print("Press any key to exit...")
        os.pullEvent("key")
end

]]
files["factory_planner.lua"] = [[---@diagnostic disable: undefined-global
-- Factory Planner
-- A tool to design factory layouts and save them to disk for turtles.
-- Features: Mouse control, Palette, Copy/Paste, Schema saving.

local filename = "factory_schema.lua"
local diskPath = "disk/" .. filename

-- Configuration
local gridWidth = 20
local gridHeight = 15
local cellSize = 1 -- 1x1 char per cell? Or maybe 2x1 for square-ish look?
-- Terminals are usually 51x19. 20x15 fits easily.

local palette = {
    { id = "minecraft:air", char = " ", color = colors.black, label = "Air" },
    { id = "minecraft:stone", char = "#", color = colors.gray, label = "Stone" },
    { id = "minecraft:dirt", char = "#", color = colors.brown, label = "Dirt" },
    { id = "minecraft:planks", char = "=", color = colors.orange, label = "Planks" },
    { id = "minecraft:cobblestone", char = "%", color = colors.lightGray, label = "Cobble" },
    { id = "computercraft:turtle_advanced", char = "T", color = colors.yellow, label = "Turtle" },
    { id = "minecraft:chest", char = "C", color = colors.orange, label = "Chest" },
    { id = "minecraft:furnace", char = "F", color = colors.gray, label = "Furnace" },
}

-- State
local grid = {} -- 2D array [y][x] = paletteIndex
local selectedPaletteIndex = 2 -- Default to Stone
local clipboard = nil
local isRunning = true
local message = "Welcome to Factory Planner"
local messageTimer = 0

-- Initialize Grid
for y = 1, gridHeight do
    grid[y] = {}
    for x = 1, gridWidth do
        grid[y][x] = 1 -- Air
    end
end

-- Helper Functions
local function clear()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawRect(x, y, w, h, color)
    term.setBackgroundColor(color)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end
end

local function drawText(x, y, text, fg, bg)
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
    term.setCursorPos(x, y)
    term.write(text)
end

-- Drawing
local function draw()
    clear()

    -- Draw Grid
    local startX = 2
    local startY = 2
    
    -- Draw Border
    drawRect(startX - 1, startY - 1, gridWidth + 2, gridHeight + 2, colors.white)
    drawRect(startX, startY, gridWidth, gridHeight, colors.black)

    for y = 1, gridHeight do
        for x = 1, gridWidth do
            local itemIndex = grid[y][x]
            local item = palette[itemIndex]
            drawText(startX + x - 1, startY + y - 1, item.char, item.color, colors.black)
        end
    end

    -- Draw Palette
    local palX = startX + gridWidth + 3
    local palY = 2
    drawText(palX, palY - 1, "Palette:", colors.white, colors.black)
    
    for i, item in ipairs(palette) do
        local prefix = (i == selectedPaletteIndex) and "> " or "  "
        drawText(palX, palY + i - 1, prefix .. item.char .. " " .. item.label, item.color, colors.black)
    end

    -- Draw Controls / Help
    local helpX = palX
    local helpY = palY + #palette + 2
    drawText(helpX, helpY, "Controls:", colors.white, colors.black)
    drawText(helpX, helpY + 1, "L-Click: Paint", colors.lightGray, colors.black)
    drawText(helpX, helpY + 2, "R-Click: Erase", colors.lightGray, colors.black)
    drawText(helpX, helpY + 3, "C: Copy Grid", colors.lightGray, colors.black)
    drawText(helpX, helpY + 4, "V: Paste Grid", colors.lightGray, colors.black)
    drawText(helpX, helpY + 5, "S: Save to Disk", colors.lightGray, colors.black)
    drawText(helpX, helpY + 6, "Q: Quit", colors.lightGray, colors.black)

    -- Draw Message
    if messageTimer > 0 then
        drawText(2, gridHeight + 4, message, colors.yellow, colors.black)
    end
end

-- Logic
local function saveSchema()
    local data = {
        width = gridWidth,
        height = gridHeight,
        palette = palette,
        grid = grid
    }
    
    -- Try to save to disk first
    local path = filename
    if fs.exists("disk") then
        path = diskPath
    end

    local file = fs.open(path, "w")
    if file then
        file.write(textutils.serialize(data))
        file.close()
        message = "Saved to " .. path
    else
        message = "Error saving to " .. path
    end
    messageTimer = 50
end

local function copyGrid()
    clipboard = textutils.unserialize(textutils.serialize(grid)) -- Deep copy
    message = "Grid copied to clipboard"
    messageTimer = 30
end

local function pasteGrid()
    if clipboard then
        grid = textutils.unserialize(textutils.serialize(clipboard))
        message = "Grid pasted from clipboard"
    else
        message = "Clipboard empty"
    end
    messageTimer = 30
end

local function handleMouse(button, x, y)
    -- Grid Coordinates
    local startX = 2
    local startY = 2
    
    local gx = x - startX + 1
    local gy = y - startY + 1

    if gx >= 1 and gx <= gridWidth and gy >= 1 and gy <= gridHeight then
        if button == 1 then -- Left Click
            grid[gy][gx] = selectedPaletteIndex
        elseif button == 2 then -- Right Click
            grid[gy][gx] = 1 -- Air
        end
    else
        -- Check Palette Click
        local palX = startX + gridWidth + 3
        local palY = 2
        
        if x >= palX and x <= palX + 15 then -- Approximate width
            local py = y - palY + 1
            if py >= 1 and py <= #palette then
                selectedPaletteIndex = py
            end
        end
    end
end

local function handleKey(key)
    if key == keys.q then
        isRunning = false
    elseif key == keys.s then
        saveSchema()
    elseif key == keys.c then
        copyGrid()
    elseif key == keys.v then
        pasteGrid()
    end
end

-- Main Loop
while isRunning do
    draw()
    
    local event, p1, p2, p3 = os.pullEvent()
    
    if event == "mouse_click" or event == "mouse_drag" then
        handleMouse(p1, p2, p3)
    elseif event == "key" then
        handleKey(p1)
    elseif event == "timer" then
        if p1 == messageTimerId then
            -- Timer handled
        end
    end

    if messageTimer > 0 then
        messageTimer = messageTimer - 1
    end
end

clear()
print("Exited Factory Planner")
]]
files["games/arcade.lua"] = [[---@diagnostic disable: undefined-global
-- Shim so games written for `games/arcade.lua` can require the shared adapter
-- even when the files are placed at the repository root.
return require("arcade")
]]
files["idlecraft.lua"] = [[---@diagnostic disable: undefined-global, undefined-field
-- IdleCraft (Arcade wrapper version)
-- Refactored to run inside the generic three‑button arcade framework in `games/arcade.lua`.
-- The original standalone event / layout system has been removed. All rendering now
-- happens inside a single playfield using arcade's helper methods.
--
-- Button semantics (shown on bottom bar):
--  Left  : Mine (or Execute current selected upgrade action if a mode is active)
--  Center: Cycle action mode (None -> Upgrade -> Hire -> Mod -> None ...)
--  Right : Quit
-- When a mode (Upgrade/Hire/Mod) is selected the left button performs that action
-- instead of mining. Messages explain results. Passive cobble generation & random
-- events occur via onTick.
--
-- Lua Tips (search 'Lua Tip:') are sprinkled in for learning.

local arcade = require("games.arcade")

-- ==========================
-- Configuration
-- ==========================

local config = {
    tickSeconds = 1,          -- Arcade tick cadence drives passive income & events
    baseManualGain = 1,
    toolUpgradeScale = 1.45,
    baseToolCost = 25,
    toolCostGrowth = 1.85,
    baseSteveCost = 30,
    steveCostGrowth = 1.18,
    baseSteveRate = 1,
    baseModCost = 400,
    modCostGrowth = 1.35,
    baseModRate = 12,
    minimumModRate = 1,
    stageNames = {
        [1] = "Stage 1: Manual Labor",
        [2] = "Stage 2: Mod Madness",
    },
    stage2SteveRequirement = 100,
    stage2CobbleRequirement = 1000,
    modEventChance = 0.17,
    maxMessages = 6,
}

-- ==========================
-- Game State
-- ==========================

local state = {
    cobble = 0,
    steves = 0,
    mods = 0,
    toolLevel = 1,
    manualCobblePerClick = config.baseManualGain,
    toolUpgradeCost = config.baseToolCost,
    steveCost = config.baseSteveCost,
    modCost = config.baseModCost,
    stevePassiveRate = config.baseSteveRate,
    modPassiveRate = config.baseModRate,
    stage = 1,
    ops = 0,                  -- Ore per second (passive this tick)
    totalCobbleEarned = 0,
    elapsedSeconds = 0,
    flags = {
        firstMine = false,
        firstSteve = false,
        firstMod = false,
        stage2Announced = false,
    },
    mode = nil,               -- nil | 'upgrade' | 'hire' | 'mod'
    messages = {},
}

-- Lua Tip: Keeping formatting helpers local avoids re-computation / global pollution.
local function formatNumber(value)
    if value >= 1e9 then return string.format("%.2fB", value / 1e9)
    elseif value >= 1e6 then return string.format("%.2fM", value / 1e6)
    elseif value >= 1e3 then return string.format("%.1fk", value / 1e3)
    elseif value < 10 and value ~= math.floor(value) then return string.format("%.2f", value) end
    return tostring(math.floor(value + 0.5))
end

local function formatRate(rate)
    if rate >= 100 then return string.format("%.0f", rate)
    elseif rate >= 10 then return string.format("%.1f", rate) end
    return string.format("%.2f", rate)
end

local function addMessage(text)
    local msgs = state.messages
    if #msgs == config.maxMessages then table.remove(msgs, 1) end
    msgs[#msgs+1] = text
end

local function calculateManualGain(level)
    local gain = config.baseManualGain * (config.toolUpgradeScale ^ (level - 1))
    return math.max(1, math.floor(gain + 0.5))
end

-- ==========================
-- Core Actions
-- ==========================

local function mineBlock()
    local gain = state.manualCobblePerClick
    state.cobble = state.cobble + gain
    state.totalCobbleEarned = state.totalCobbleEarned + gain
    if not state.flags.firstMine then
        addMessage("You punch a tree. It feels nostalgic.")
        state.flags.firstMine = true
    end
end

local function upgradeTools()
    if state.cobble < state.toolUpgradeCost then
        addMessage("Not enough Cobble to craft better tools.")
        return
    end
    state.cobble = state.cobble - state.toolUpgradeCost
    state.toolLevel = state.toolLevel + 1
    state.manualCobblePerClick = calculateManualGain(state.toolLevel)
    state.toolUpgradeCost = math.ceil(state.toolUpgradeCost * config.toolCostGrowth)
    addMessage("Your tools shine brighter. Manual mining hits harder now.")
end

local function hireSteve()
    if state.cobble < state.steveCost then
        addMessage("You need more Cobble before another Steve signs up.")
        return
    end
    state.cobble = state.cobble - state.steveCost
    state.steves = state.steves + 1
    state.steveCost = math.ceil(state.steveCost * config.steveCostGrowth)
    if not state.flags.firstSteve then
        addMessage("Your first Steve joins. He mines when you're not looking.")
        state.flags.firstSteve = true
    else
        addMessage("Another Steve mans the cobble line. Passive OPS climbs.")
    end
end

local function installMod()
    if state.stage < 2 then
        addMessage("Mods still locked. Grow your workforce or cobble reserves first.")
        return
    end
    if state.cobble < state.modCost then
        addMessage("That mod pack costs more Cobble than you have right now.")
        return
    end
    state.cobble = state.cobble - state.modCost
    state.mods = state.mods + 1
    state.modCost = math.ceil(state.modCost * config.modCostGrowth)
    if not state.flags.firstMod then
        addMessage("You taught a turtle to mine. It never complains.")
        state.flags.firstMod = true
    else
        addMessage("A new mod hums to life, amplifying your automation stack.")
    end
end

-- Random event system (subset of original for brevity while preserving flavor)
local modEvents = {
    {
        weight = 3,
        condition = function() return state.mods > 0 end,
        resolve = function()
            state.modPassiveRate = state.modPassiveRate * 1.2
            return "+20% mod efficiency!"
        end,
    },
    {
        weight = 2,
        condition = function() return true end,
        resolve = function()
            local bonus = 2
            state.steves = state.steves + bonus
            return string.format("%d more Steves volunteer.", bonus)
        end,
    },
    {
        weight = 2,
        condition = function() return state.steves > 0 end,
        resolve = function()
            local loss = math.min(5, state.steves)
            state.steves = state.steves - loss
            return string.format("Update snafu costs %d Steves.", loss)
        end,
    },
}

local function pickWeightedEvent()
    local pool, total = {}, 0
    for _, ev in ipairs(modEvents) do
        if ev.condition() then
            total = total + ev.weight
            pool[#pool+1] = ev
        end
    end
    if total == 0 then return nil end
    local roll, acc = math.random() * total, 0
    for _, ev in ipairs(pool) do
        acc = acc + ev.weight
        if roll <= acc then return ev end
    end
    return pool[#pool]
end

local function maybeTriggerModEvent()
    if state.stage < 2 or state.mods == 0 then return end
    if math.random() > config.modEventChance then return end
    local ev = pickWeightedEvent(); if not ev then return end
    local msg = ev.resolve(); if msg then addMessage(msg) end
end

local function checkStageProgress()
    if state.stage == 1 then
        if state.steves >= config.stage2SteveRequirement or state.totalCobbleEarned >= config.stage2CobbleRequirement then
            state.stage = 2
            if not state.flags.stage2Announced then
                addMessage("Mods unlocked! Automation just got a lot stranger.")
                state.flags.stage2Announced = true
            end
        end
    end
end

local function passiveTick()
    local steveIncome = state.steves * state.stevePassiveRate
    local modIncome = state.mods * state.modPassiveRate
    local total = steveIncome + modIncome
    if total > 0 then
        state.cobble = state.cobble + total
        state.totalCobbleEarned = state.totalCobbleEarned + total
    end
    state.ops = total
    state.elapsedSeconds = state.elapsedSeconds + config.tickSeconds
    maybeTriggerModEvent()
    checkStageProgress()
end

-- ==========================
-- Mode Handling / Button Logic
-- ==========================

local modeCycle = { nil, "upgrade", "hire", "mod" } -- nil means plain mining

local function nextMode()
    -- Lua Tip: ipairs iterates sequential numeric keys 1..n; we use it to find current mode index.
    local idx
    for i, m in ipairs(modeCycle) do
        if m == state.mode then idx = i break end
    end
    idx = (idx or 1) + 1
    if idx > #modeCycle then idx = 1 end
    -- Skip 'mod' if stage not yet unlocked
    if modeCycle[idx] == "mod" and state.stage < 2 then idx = 1 end
    state.mode = modeCycle[idx]
end

local function performPrimary()
    if state.mode == "upgrade" then upgradeTools()
    elseif state.mode == "hire" then hireSteve()
    elseif state.mode == "mod" then installMod()
    else mineBlock() end
    -- Ensure stage transitions can happen immediately after manual actions
    checkStageProgress()
end

-- ==========================
-- Rendering (arcade draw callback)
-- ==========================

local function getStageName()
    return config.stageNames[state.stage] or ("Stage " .. tostring(state.stage))
end

local function currentModeLabel()
    if not state.mode then return "Mine" end
    if state.mode == "upgrade" then return "Upgrade" end
    if state.mode == "hire" then return "Hire" end
    if state.mode == "mod" then return "Mods" end
end

local function modeStatusLine()
    if not state.mode then
        return "Mode: Mine (Center cycles)"
    elseif state.mode == "upgrade" then
        return string.format("Upgrade cost %s (Next +%s)",
            formatNumber(state.toolUpgradeCost),
            formatNumber(calculateManualGain(state.toolLevel+1)))
    elseif state.mode == "hire" then
        return string.format("Hire Steve cost %s (+%s/sec)",
            formatNumber(state.steveCost), formatRate(state.stevePassiveRate))
    elseif state.mode == "mod" then
        return string.format("Install Mod cost %s (+%s/sec each)",
            formatNumber(state.modCost), formatRate(state.modPassiveRate))
    end
end

local function drawGame(a)
    a:clearPlayfield(colors.black, colors.white)
    -- Header
    a:centerPrint(1, string.format("IdleCraft — %s", getStageName()), colors.cyan)
    -- Resources
    a:centerPrint(2, string.format("Cobble %s  Steves %s  Mods %s  OPS %s", 
        formatNumber(state.cobble), formatNumber(state.steves), formatNumber(state.mods), formatRate(state.ops)), colors.white)
    -- Mode line
    a:centerPrint(3, modeStatusLine(), colors.lightGray)
    -- Messages
    local baseY = 5
    local msgs = state.messages
    local start = math.max(1, #msgs - (config.maxMessages) + 1)
    local line = 0
    for i = start, #msgs do
        line = line + 1
        a:centerPrint(baseY + line - 1, msgs[i], colors.white)
    end
    if #msgs == 0 then a:centerPrint(baseY, "(No messages yet. Mine something!)", colors.lightGray) end
end

-- ==========================
-- Game Table for arcade.start
-- ==========================

local game = {
    name = "IdleCraft",
    init = function(self, a)
        math.randomseed(os.epoch and os.epoch("utc") or os.clock()) -- Reseed per session
        -- Enable/disable left button if an action mode is selected but not affordable
        local enableLeft = true
        if state.mode == "upgrade" then enableLeft = state.cobble >= state.toolUpgradeCost
        elseif state.mode == "hire" then enableLeft = state.cobble >= state.steveCost
        elseif state.mode == "mod" then enableLeft = (state.stage >= 2) and (state.cobble >= state.modCost) end
        a:setButtons({currentModeLabel(), "Cycle", "Quit"}, {enableLeft, true, true})
        addMessage("Welcome to IdleCraft (Arcade edition). Press Center to pick an action mode.")
    end,
    draw = function(self, a)
        -- Update button labels each frame (mode can change between ticks)
        local enableLeft = true
        if state.mode == "upgrade" then enableLeft = state.cobble >= state.toolUpgradeCost
        elseif state.mode == "hire" then enableLeft = state.cobble >= state.steveCost
        elseif state.mode == "mod" then enableLeft = (state.stage >= 2) and (state.cobble >= state.modCost) end
        a:setButtons({currentModeLabel(), "Cycle", "Quit"}, {enableLeft, true, true})
        drawGame(a)
    end,
    onButton = function(self, a, which)
        if which == "left" then
            performPrimary()
        elseif which == "center" then
            nextMode()
        elseif which == "right" then
            a:requestQuit()
            return
        end
        self.draw(self, a)
    end,
    onTick = function(self, a, dt)
        passiveTick()
        self.draw(self, a)
    end,
}

-- Start via arcade wrapper. Provide custom tick interval from config.
arcade.start(game, { tickSeconds = config.tickSeconds })

-- END OF FILE]]
files["license_store.lua"] = [[---@diagnostic disable: undefined-global
-- license_store.lua
-- Simple disk-backed license manager for arcade programs.
-- Uses lightweight signatures to discourage casual tampering of license files.

local LicenseStore = {}
LicenseStore.__index = LicenseStore

-- Lua tip: small helper functions keep the public API easy to read.
local function ensureDirectory(path)
  if not fs.exists(path) then
    fs.makeDir(path)
  end
end

local function computeHash(input)
  if textutils.sha256 then
    return textutils.sha256(input)
  end
  -- Fallback checksum if sha256 is unavailable; keeps deterministic signature.
  local sum = 0
  for i = 1, #input do
    sum = (sum + string.byte(input, i)) % 0xFFFFFFFF
  end
  return string.format("%08x", sum)
end

local function signaturePayload(license)
  return table.concat({
    license.programId or "",
    tostring(license.purchasedAt or ""),
    tostring(license.pricePaid or ""),
    tostring(license.note or ""),
  }, "|")
end

local function signatureFor(license, secret)
  return computeHash(signaturePayload(license) .. "|" .. secret)
end

function LicenseStore.new(rootPath, secret)
  local store = setmetatable({}, LicenseStore)
  store.rootPath = rootPath or "licenses"
  store.secret = secret or "arcade-license-v1"
  ensureDirectory(store.rootPath)
  return store
end

function LicenseStore:licensePath(programId)
  return fs.combine(self.rootPath, programId .. ".lic")
end

function LicenseStore:load(programId)
  local path = self:licensePath(programId)
  if not fs.exists(path) then
    return nil, "missing"
  end

  local handle = fs.open(path, "r")
  local content = handle.readAll()
  handle.close()

  local data = textutils.unserialize(content)
  if type(data) ~= "table" then
    return nil, "corrupt"
  end

  local expected = signatureFor(data, self.secret)
  if data.signature ~= expected then
    return nil, "invalid_signature"
  end

  return data
end

function LicenseStore:has(programId)
  local license = self:load(programId)
  if license then
    return true, license
  end
  return false
end

function LicenseStore:save(programId, pricePaid, note)
  local license = {
    programId = programId,
    purchasedAt = os.epoch("utc"),
    pricePaid = pricePaid or 0,
    note = note,
  }
  license.signature = signatureFor(license, self.secret)

  local handle = fs.open(self:licensePath(programId), "w")
  handle.write(textutils.serialize(license))
  handle.close()

  return license
end

return LicenseStore
]]
files["log.lua"] = [[-- log.lua
-- Tiny logger tailored for ComputerCraft turtles/computers.
-- Provides leveled logging with safe file writes so crashes are easier
-- to diagnose. Defaults to `arcade.log` in the working directory.
-- Lua Tip: Returning a constructor function lets you keep state private
-- while still exposing an easy-to-use API.

local Log = {}
Log.__index = Log

local LEVELS = {
  error = 1,
  warn = 2,
  info = 3,
  debug = 4,
}

local function now()
  if os and os.date then
    return os.date("%Y-%m-%d %H:%M:%S")
  end
  return "unknown-time"
end

---Create a new logger.
---@param options table|nil {logFile:string, level:string}
function Log.new(options)
  options = options or {}
  local self = setmetatable({}, Log)
  self.logFile = options.logFile or "arcade.log"
  self.threshold = LEVELS[string.lower(options.level or "info")] or LEVELS.info
  return self
end

local function tryWrite(path, line)
  local ok, err = pcall(function()
    local handle = fs.open(path, "a")
    if handle then
      handle.writeLine(line)
      handle.close()
    end
  end)
  if not ok then
    return false, err
  end
  return true
end

---Internal helper used by all level-specific methods.
function Log:log(level, message)
  local numeric = LEVELS[level] or LEVELS.info
  if numeric > self.threshold then return end
  local safeMessage = tostring(message)
  local line = string.format("[%s] %-5s %s", now(), level:upper(), safeMessage)
  local success, err = tryWrite(self.logFile, line)
  if not success and term then
    -- Fallback to terminal output instead of crashing the program.
    term.setTextColor(colors.red)
    print("Log write failed: " .. tostring(err))
    term.setTextColor(colors.white)
  end
end

function Log:error(message) self:log("error", message) end
function Log:warn(message) self:log("warn", message) end
function Log:info(message) self:log("info", message) end
function Log:debug(message) self:log("debug", message) end

return Log
]]
files["models/projectile.lua"] = [[---@diagnostic disable: undefined-global
local function newPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
  return {
    x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3,
    c = c,
  }
end

local proj = {}
local color = colors.red

local function addBox(list, x, y, z, w, h, d, color)
    local x1, y1, z1 = x - w/2, y - h/2, z - d/2
    local x2, y2, z2 = x + w/2, y + h/2, z + d/2
    -- Front
    table.insert(list, newPoly(x1, y1, z1, x2, y1, z1, x2, y2, z1, color))
    table.insert(list, newPoly(x1, y1, z1, x2, y2, z1, x1, y2, z1, color))
    -- Back
    table.insert(list, newPoly(x1, y1, z2, x2, y2, z2, x2, y1, z2, color))
    table.insert(list, newPoly(x1, y1, z2, x2, y1, z2, x1, y2, z2, color))
    -- Top
    table.insert(list, newPoly(x1, y2, z1, x2, y2, z1, x2, y2, z2, color))
    table.insert(list, newPoly(x1, y2, z1, x2, y2, z2, x1, y2, z2, color))
    -- Bottom
    table.insert(list, newPoly(x1, y1, z1, x2, y1, z2, x2, y1, z1, color))
    table.insert(list, newPoly(x1, y1, z1, x1, y1, z2, x2, y1, z2, color))
    -- Left
    table.insert(list, newPoly(x1, y1, z1, x1, y2, z1, x1, y2, z2, color))
    table.insert(list, newPoly(x1, y1, z1, x1, y2, z2, x1, y1, z2, color))
    -- Right
    table.insert(list, newPoly(x2, y1, z1, x2, y2, z2, x2, y2, z1, color))
    table.insert(list, newPoly(x2, y1, z1, x2, y1, z2, x2, y2, z2, color))
end

addBox(proj, 0, 0, 0, 0.2, 0.2, 0.2, color)

return proj]]
files["models/tank.lua"] = [[---@diagnostic disable: undefined-global
local function newPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
  return {
    x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3,
    c = c,
  }
end

local tank = {}
local bodyColor = colors.green
local turretColor = colors.lime

-- Helper to add a box
local function addBox(list, x, y, z, w, h, d, color)
    local x1, y1, z1 = x - w/2, y - h/2, z - d/2
    local x2, y2, z2 = x + w/2, y + h/2, z + d/2
    
    -- Front
    table.insert(list, newPoly(x1, y1, z1, x2, y1, z1, x2, y2, z1, color))
    table.insert(list, newPoly(x1, y1, z1, x2, y2, z1, x1, y2, z1, color))
    -- Back
    table.insert(list, newPoly(x1, y1, z2, x2, y2, z2, x2, y1, z2, color))
    table.insert(list, newPoly(x1, y1, z2, x2, y1, z2, x1, y2, z2, color))
    -- Top
    table.insert(list, newPoly(x1, y2, z1, x2, y2, z1, x2, y2, z2, color))
    table.insert(list, newPoly(x1, y2, z1, x2, y2, z2, x1, y2, z2, color))
    -- Bottom
    table.insert(list, newPoly(x1, y1, z1, x2, y1, z2, x2, y1, z1, color))
    table.insert(list, newPoly(x1, y1, z1, x1, y1, z2, x2, y1, z2, color))
    -- Left
    table.insert(list, newPoly(x1, y1, z1, x1, y2, z1, x1, y2, z2, color))
    table.insert(list, newPoly(x1, y1, z1, x1, y2, z2, x1, y1, z2, color))
    -- Right
    table.insert(list, newPoly(x2, y1, z1, x2, y2, z2, x2, y2, z1, color))
    table.insert(list, newPoly(x2, y1, z1, x2, y1, z2, x2, y2, z2, color))
end

addBox(tank, 0, 0, 0, 1, 0.5, 1.5, bodyColor) -- Body
addBox(tank, 0, 0.5, 0, 0.6, 0.4, 0.8, turretColor) -- Turret

return tank]]
files["poker.lua"] = [[---@diagnostic disable: undefined-global, undefined-field

-- Video Poker (full game)
-- Implements a 52-card deck, Jacks-or-Better pay table, and three-button
-- controls via the shared arcade wrapper.
-- Lua Tip: keeping everything in one table or module helps avoid accidental
-- globals; here we keep state local to this file.

local arcade = require("games.arcade")

-- Card metadata for rendering and evaluation
local SUITS = {
        { name = "Spades",   glyph = "S", color = colors.lightGray },
        { name = "Hearts",   glyph = "H", color = colors.red },
        { name = "Clubs",    glyph = "C", color = colors.green },
        { name = "Diamonds", glyph = "D", color = colors.orange },
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
        if not card then return {"+-----+", "|     |", "+-----+"}, colors.lightGray end
        if not isRevealed then
                return {"+-----+", "|#####|", "+-----+"}, colors.lightGray
        end
        local face = string.format("|%-2s %s |", card.label, card.suit.glyph)
        return {"+-----+", face, "+-----+"}, card.suit.color
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
                statusMessage = string.format("Not enough credits!")
                resetFlash()
                refreshButtons(adapter)
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
]]
files["slots.lua"] = [[---@diagnostic disable: undefined-global, undefined-field
-- Slots with animated reels and weighted symbols
-- Uses the shared arcade wrapper (games/arcade.lua) for a monitor UI and credits.
-- Features: weighted virtual reels, animated spin frames in onTick, adjustable bet,
-- multi-line slot window with colored icons, and win flashes/sounds when possible.

local arcade = require("games.arcade")

-- Optional: play celebratory sounds if a speaker peripheral is attached.
local speaker = peripheral and peripheral.find and peripheral.find("speaker") or nil

local function playSound(note, vol)
        if speaker and speaker.playNote then
                speaker.playNote(note or "pling", vol or 1)
        end
end

-- Symbol definitions with weights and payouts (multipliers on the bet).
local symbolDefs = {
        { id = "cherry", icon = "@", color = colors.red,       weight = 8, pay3 = 6, pay2 = 1 },
        { id = "lemon",  icon = "O", color = colors.yellow,    weight = 7, pay3 = 5, pay2 = 1 },
        { id = "plum",   icon = "P", color = colors.magenta,  weight = 6, pay3 = 7, pay2 = 2 },
        { id = "bar",    icon = "#", color = colors.gray,     weight = 5, pay3 = 10, pay2 = 3 },
        { id = "diamond",icon = "*", color = colors.cyan,     weight = 3, pay3 = 14, pay2 = 4 },
        { id = "seven",  icon = "7", color = colors.orange,   weight = 2, pay3 = 20, pay2 = 5 },
}

local symbolLookup = {}
for _, def in ipairs(symbolDefs) do symbolLookup[def.id] = def end

-- Paylines to evaluate (row/col pairs). Three horizontal + two diagonals.
local paylines = {
        { {r=1,c=1}, {r=1,c=2}, {r=1,c=3} },
        { {r=2,c=1}, {r=2,c=2}, {r=2,c=3} },
        { {r=3,c=1}, {r=3,c=2}, {r=3,c=3} },
        { {r=1,c=1}, {r=2,c=2}, {r=3,c=3} },
        { {r=3,c=1}, {r=2,c=2}, {r=1,c=3} },
}

-- Game state table keeps timing and reel info together.
local state = {
        reels = {},
        reelPositions = {1,1,1},
        targetStops = {1,1,1},
        stopTimes = {0,0,0},
        spinning = false,
        reelLocked = {false,false,false},
        time = 0,
        betSteps = {1,2,5,10},
        betIndex = 1,
        message = "Spin to win!",
        lastWins = {},
        flashTimer = 0,
        flashVisible = false,
}

local function buildReel()
        local reel = {}
        for _, def in ipairs(symbolDefs) do
                for _ = 1, def.weight do table.insert(reel, def.id) end
        end
        -- Shuffle to avoid identical strips per reel.
        for i = #reel, 2, -1 do
                local j = math.random(i)
                reel[i], reel[j] = reel[j], reel[i]
        end
        return reel
end

local function wrapIndex(idx, len)
        local m = (idx - 1) % len
        return m + 1
end

local function currentWindow()
        -- Returns a 3x3 grid of symbols centered on reelPositions.
        local grid = {}
        for r = 1, 3 do grid[r] = {} end
        for col = 1, 3 do
                local reel = state.reels[col]
                local len = #reel
                local center = state.reelPositions[col]
                for rowOffset = -1, 1 do
                        local row = rowOffset + 2 -- map -1/0/1 to 1/2/3
                        grid[row][col] = reel[wrapIndex(center + rowOffset, len)]
                end
        end
        return grid
end

local function pickWeightedStop(reel)
        return math.random(#reel)
end

local function resetFlash()
        state.flashTimer = 0
        state.flashVisible = false
end

local function summarizeWins(totalWin)
        if totalWin <= 0 then return "No win" end
        local summary = {}
        for _, win in ipairs(state.lastWins) do
                table.insert(summary, string.format("Line %d %s x%d", win.line, win.symbol:upper(), win.amount))
        end
        return table.concat(summary, "  ")
end

local function scoreSpin(adapter)
        state.lastWins = {}
        local grid = currentWindow()
        local totalWin = 0
        for i, line in ipairs(paylines) do
                local a = grid[line[1].r][line[1].c]
                local b = grid[line[2].r][line[2].c]
                local c = grid[line[3].r][line[3].c]
                if a == b and b == c then
                        local def = symbolLookup[a]
                        local win = state.betSteps[state.betIndex] * def.pay3
                        totalWin = totalWin + win
                        table.insert(state.lastWins, { line = i, symbol = def.icon, amount = def.pay3 })
                elseif a == b or b == c or a == c then
                        -- Small consolation for pairs.
                        local pairId = a == b and a or b == c and b or a
                        local def = symbolLookup[pairId]
                        local win = state.betSteps[state.betIndex] * def.pay2
                        totalWin = totalWin + win
                        table.insert(state.lastWins, { line = i, symbol = def.icon, amount = def.pay2 })
                end
        end
        if totalWin > 0 then
                adapter:addCredits(totalWin)
                state.message = string.format("WIN! +%d credits (%s)", totalWin, summarizeWins(totalWin))
                state.flashTimer = 3
                playSound("bell", 1)
        else
                state.message = "Better luck next time"
        end
end

local function canSpin(adapter)
        return not state.spinning and adapter:getCredits() >= state.betSteps[state.betIndex]
end

local function refreshButtons(adapter)
        local leftLabel = state.spinning and "Spinning" or ("Spin (" .. state.betSteps[state.betIndex] .. ")")
        local centerLabel = state.spinning and "Bet+" or ("Bet+ -> " .. state.betSteps[state.betIndex])
        local rightLabel = state.spinning and "CashOut" or "CashOut"
        adapter:setButtons({ leftLabel, centerLabel, rightLabel }, { canSpin(adapter), not state.spinning, true })
end

local function startSpin(adapter)
        if state.spinning then return end
        local bet = state.betSteps[state.betIndex]
        if not adapter:consumeCredits(bet) then
                state.message = string.format("Need %d credits to spin", bet)
                resetFlash()
                refreshButtons(adapter)
                return
        end
        state.spinning = true
        state.reelLocked = {false,false,false}
        state.time = 0
        resetFlash()
        for i = 1, 3 do
                state.targetStops[i] = pickWeightedStop(state.reels[i])
                state.stopTimes[i] = (i * 0.6) -- staggered stops
        end
        state.message = "Reels spinning..."
        refreshButtons(adapter)
        playSound("pling", 0.8)
end

local function updateSpin(dt, adapter)
        if not state.spinning then
                if state.flashTimer > 0 then
                        state.flashTimer = math.max(0, state.flashTimer - dt)
                        if state.flashTimer > 0 then
                                state.flashVisible = not state.flashVisible
                        else
                                state.flashVisible = false
                        end
                end
                return
        end
        state.time = state.time + dt
        local allLocked = true
        for i = 1, 3 do
                local reel = state.reels[i]
                local len = #reel
                if not state.reelLocked[i] then
                        state.reelPositions[i] = wrapIndex(state.reelPositions[i] + 1, len)
                        if state.time >= state.stopTimes[i] then
                                state.reelPositions[i] = state.targetStops[i]
                                state.reelLocked[i] = true
                                playSound("pling", 0.5 + i * 0.1)
                        end
                end
                allLocked = allLocked and state.reelLocked[i]
        end
        if allLocked then
                                state.spinning = false
                                scoreSpin(adapter)
                                refreshButtons(adapter)
        end
end

local function drawPayoutTable()
        local _, screenH = term.getSize()
        local startY = math.max(8, screenH - 8)
        term.setTextColor(colors.lightGray)
        term.setCursorPos(2, startY)
        term.write("Payouts (xBet):")
        for idx, def in ipairs(symbolDefs) do
                term.setCursorPos(2, startY + idx)
                term.setTextColor(def.color)
                term.write(string.format(" %s%s 3=%d 2=%d", def.icon, def.id:sub(1,1), def.pay3, def.pay2))
        end
        term.setTextColor(colors.white)
end

local function drawWindow(grid)
        local w = term.getSize()
        local windowWidth = 3 * 4 + 1 -- columns plus separators
        local left = math.floor((w - windowWidth) / 2)
        local top = 3
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.setCursorPos(left, top)
        term.write("+---+---+---+")
        for row = 1, 3 do
                term.setCursorPos(left, top + (row * 1) + (row - 1))
                term.write("|   |   |   |")
                term.setCursorPos(left, top + row * 2)
                term.write("+---+---+---+")
        end
        -- Fill symbols (two lines inside each row block)
        for row = 1, 3 do
                for col = 1, 3 do
                        local symbolId = grid[row][col]
                        local def = symbolLookup[symbolId]
                        local x = left + 2 + (col - 1) * 4
                        local y = top + (row - 1) * 2 + 1
                        term.setCursorPos(x, y)
                        local highlight = false
                        for _, win in ipairs(state.lastWins) do
                                local line = paylines[win.line]
                                for _, cell in ipairs(line) do
                                        if cell.r == row and cell.c == col and state.flashVisible then
                                                highlight = true
                                        end
                                end
                        end
                        if highlight then
                                term.setBackgroundColor(colors.green)
                                term.setTextColor(colors.black)
                        else
                                term.setBackgroundColor(colors.black)
                                term.setTextColor(def and def.color or colors.white)
                        end
                        term.write(def and def.icon or "?")
                        term.setBackgroundColor(colors.black)
                end
        end
end

local function draw(a)
        a:clearPlayfield(colors.black, colors.white)
        local creditsText = string.format("Credits: %d", a:getCredits())
        local betText = string.format("Bet: %d", state.betSteps[state.betIndex])
        a:centerPrint(1, "Slots", colors.white)
        a:centerPrint(2, creditsText .. "  |  " .. betText, colors.lightGray)
        local grid = currentWindow()
        drawWindow(grid)
        local _, screenH = term.getSize()
        local playfieldBottom = screenH - 3
        local messageY = math.min(playfieldBottom, 11)
        a:centerPrint(messageY, state.message, colors.yellow)
        drawPayoutTable()
end

local game = {
        name = "Slots",
        init = function(a)
                math.randomseed(os.epoch and os.epoch("utc") or os.clock())
                state.reels = { buildReel(), buildReel(), buildReel() }
                state.reelPositions = { math.random(#state.reels[1]), math.random(#state.reels[2]), math.random(#state.reels[3]) }
                refreshButtons(a)
        end,
        draw = function(a)
                draw(a)
        end,
        onButton = function(a, which)
                if which == "left" then
                        startSpin(a)
                elseif which == "center" then
                        if not state.spinning then
                                state.betIndex = state.betIndex % #state.betSteps + 1
                                state.message = string.format("Bet set to %d", state.betSteps[state.betIndex])
                                refreshButtons(a)
                        end
                elseif which == "right" then
                        a:requestQuit()
                end
        end,
        onTick = function(a, dt)
                updateSpin(dt, a)
                refreshButtons(a)
                draw(a)
        end,
}

arcade.start(game, { tickSeconds = 0.15 })
]]
files["startup.lua"] = [[shell.run("arcade_shell.lua")
]]
files["ui/renderer.lua"] = [[-- ui/renderer.lua
-- Lightweight textured renderer for ComputerCraft monitors/terminals.
-- Provides sprite-style drawing helpers, hit-testing, and a pluggable skin
-- system so games can share visual assets while keeping logic minimal.
-- Lua Tip: Tables can act like objects when we set a metatable with __index.

---@diagnostic disable: undefined-global

local Renderer = {}
Renderer.__index = Renderer

-- Convert a colors.<name> entry into a blit hex digit.
local function toBlit(color)
    if colors.toBlit then return colors.toBlit(color) end
    -- Fallback: derive from bit position (useful when running outside CC tooling)
    local idx = math.floor(math.log(color, 2))
    return ("0123456789abcdef"):sub(idx + 1, idx + 1)
end

-- Repeat a pattern string to at least width characters, trimming if necessary.
local function repeatToWidth(pattern, desiredWidth)
    local out = ""
    while #out < desiredWidth do
        out = out .. pattern
    end
    if #out > desiredWidth then
        out = out:sub(1, desiredWidth)
    end
    return out
end

local function copyTable(tbl)
    local out = {}
    for k, v in pairs(tbl or {}) do
        if type(v) == "table" then
            out[k] = copyTable(v)
        else
            out[k] = v
        end
    end
    return out
end

local function deepMerge(base, override)
    local out = copyTable(base)
    for k, v in pairs(override or {}) do
        if type(v) == "table" and type(out[k]) == "table" then
            out[k] = deepMerge(out[k], v)
        else
            out[k] = v
        end
    end
    return out
end

local function normalizeTexture(texture)
    if not texture then return nil end
    if not texture.rows or #texture.rows == 0 then return nil end
    texture.width = texture.width or #texture.rows[1].text
    texture.height = texture.height or #texture.rows
    return texture
end

local function tryBuildPineTexture(width, height, baseColor, accentColor)
    -- We intentionally use pcall to avoid crashing when pine3d isn't present.
    local ok, pine3d = pcall(require, "pine3d")
    if not ok or type(pine3d) ~= "table" then return nil end

    local okTexture, texture = pcall(function()
        -- Lua Tip: feature detection keeps optional dependencies from breaking core logic.
        local canvasBuilder = pine3d.newCanvas or pine3d.canvas or pine3d.newRenderer
        if not canvasBuilder then return nil end
        local canvas = canvasBuilder(width, height)
        if canvas.clear then canvas:clear(baseColor) end
        -- Draw a pair of angular polygons for a "90s" tech-panel vibe.
        if canvas.polygon then
            canvas:polygon({0, 0}, {width - 1, 1}, {width - 2, height - 1}, {0, height - 2}, accentColor)
            canvas:polygon({2, 0}, {width - 1, 0}, {width - 1, height - 1}, {3, height - 2}, colors.black)
        end
        -- Exporters vary by pine3d version; try the common ones.
        if canvas.exportTexture then return normalizeTexture(canvas:exportTexture()) end
        if canvas.toTexture then return normalizeTexture(canvas:toTexture()) end
        if canvas.export then return normalizeTexture(canvas:export()) end
        return nil
    end)

    if okTexture then return texture end
    return nil
end

local function defaultButtonTexture(light, mid, dark)
    local pineTexture = tryBuildPineTexture(6, 3, dark, light)
    if pineTexture then return pineTexture end
    -- Two-tone diagonal stripes to give a bit of depth when pine3d is unavailable.
    local fgLight, fgDark = toBlit(colors.white), toBlit(colors.lightGray)
    return normalizeTexture({
        rows = {
            { text = "\\\\\\\\", fg = repeatToWidth(fgDark, 4), bg = repeatToWidth(toBlit(light), 4) },
            { text = "////", fg = repeatToWidth(fgLight, 4), bg = repeatToWidth(toBlit(mid), 4) },
            { text = "    ", fg = repeatToWidth(fgDark, 4), bg = repeatToWidth(toBlit(dark), 4) },
        }
    })
end

local function buildDefaultSkin()
    local base = colors.black
    local accent = colors.orange
    local accentDark = colors.brown
    return {
        background = base,
        playfield = base,
        buttonBar = { background = base },
        buttons = {
            enabled = {
                texture = defaultButtonTexture(accent, accentDark, base),
                labelColor = colors.orange,
                shadowColor = colors.gray,
            },
            disabled = {
                texture = defaultButtonTexture(colors.gray, colors.black, colors.black),
                labelColor = colors.lightGray,
                shadowColor = colors.black,
            }
        },
        titleColor = colors.orange,
    }
end

---Create a renderer instance.
---@param opts table|nil {skin=table, monitor=peripheral, textScale=number}
function Renderer.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Renderer)
    self.skin = deepMerge(buildDefaultSkin(), opts.skin or {})
    self.monitor = nil
    self.nativeTerm = term.current()
    self.w, self.h = term.getSize()
    self.hotspots = {}
    if opts.monitor then
        self:attachToMonitor(opts.monitor, opts.textScale)
    end
    return self
end

function Renderer:getSize()
    self.w, self.h = term.getSize()
    return self.w, self.h
end

function Renderer:attachToMonitor(monitor, textScale)
    self.monitor = monitor
    if not monitor then
        if self.nativeTerm then term.redirect(self.nativeTerm) end
        self.w, self.h = term.getSize()
        return
    end
    if textScale then monitor.setTextScale(textScale) end
    term.redirect(monitor)
    self.w, self.h = term.getSize()
end

function Renderer:restore()
    if self.nativeTerm then
        term.redirect(self.nativeTerm)
        self.monitor = nil
    end
end

function Renderer:setSkin(skin)
    self.skin = deepMerge(buildDefaultSkin(), skin or {})
end

function Renderer:registerHotspot(name, rect)
    self.hotspots[name] = copyTable(rect)
end

function Renderer:hitTest(name, x, y)
    local r = self.hotspots[name]
    if not r then return false end
    return x >= r.x and x <= r.x + r.w - 1 and y >= r.y and y <= r.y + r.h - 1
end

function Renderer:fillRect(x, y, w, h, bg, fg, ch)
    local bgBlit = repeatToWidth(toBlit(bg or colors.black), w)
    local fgBlit = repeatToWidth(toBlit(fg or bg or colors.black), w)
    local text = repeatToWidth(ch or " ", w)
    for yy = y, y + h - 1 do
        term.setCursorPos(x, yy)
        term.blit(text, fgBlit, bgBlit)
    end
end

function Renderer:drawTextureRect(texture, x, y, w, h)
    local tex = normalizeTexture(texture)
    if not tex then
        self:fillRect(x, y, w, h, colors.black, colors.black, " ")
        return
    end
    for row = 0, h - 1 do
        local src = tex.rows[(row % tex.height) + 1]
        local text = repeatToWidth(src.text, w)
        local fg = repeatToWidth(src.fg, w)
        local bg = repeatToWidth(src.bg, w)
        term.setCursorPos(x, y + row)
        term.blit(text, fg, bg)
    end
end

function Renderer.defaultSkin()
    return buildDefaultSkin()
end

function Renderer.mergeSkin(base, override)
    return deepMerge(base, override)
end

return Renderer
]]
print("Unpacking 16 files...")

for path, content in pairs(files) do
    print("  Installing: " .. path)
    
    -- Ensure directory exists
    local dir = fs.getDir(path)
    if dir ~= "" and dir ~= ".." and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local file = fs.open(path, "w")
    if file then
        file.write(content)
        file.close()
    else
        printError("  Failed to write: " .. path)
    end
end

print("Installation Complete!")

-- Install Pine3D
print("Installing Pine3D...")
if http then
    shell.run("pastebin run qpJYiYs2")
else
    printError("HTTP API not enabled! Cannot install Pine3D.")
end

print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
