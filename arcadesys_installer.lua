-- Arcadesys Unified Installer
-- Auto-generated at 2025-11-26T16:20:43.548Z
print("Starting Arcadesys install v2.1.1 (build 40)...")
local files = {}

files["arcade/arcade_shell.lua"] = [[package.loaded["arcade"] = nil
package.loaded["log"] = nil
package.loaded["data.programs"] = nil
local function setupPaths()
local program = shell.getRunningProgram()
local dir = fs.getDir(program)
local root = fs.getDir(dir)
local function add(path)
local part = fs.combine(root, path)
local pattern = "/" .. fs.combine(part, "?.lua")
if not string.find(package.path, pattern, 1, true) then
package.path = package.path .. ";" .. pattern
end
end
add("lib")
add("arcade")
add("factory")
add("") -- Add root for games.arcade shim
end
setupPaths()
local LicenseStore = require("license_store")
local version = require("version")
local BASE_DIR = fs.getDir(shell and shell.getRunningProgram and shell.getRunningProgram() or "") or ""
if BASE_DIR == "" then BASE_DIR = "." end
local function resolvePath(rel)
if type(rel) ~= "string" or rel == "" then
return rel
end
if rel:sub(1, 1) == "/" then
return rel
end
if BASE_DIR == "." then
return rel
end
return fs.combine(BASE_DIR, rel)
end
local CREDIT_FILE = "credits.txt"
local DEFAULT_LICENSE_DIR = "licenses"
local SECRET_SALT = "arcade-license-v1"
local ENVIRONMENT_FILE = "environment.settings"
local DEFAULT_ENVIRONMENT = {
mode = "development",
}
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
package.loaded["data.programs"] = nil -- Force reload
local programs = require("data.programs")
local function installProgram(program)
term.setBackgroundColor(colors.blue)
term.clear()
local w, h = term.getSize()
local function center(y, text)
term.setCursorPos(math.floor((w - #text) / 2), y)
term.write(text)
end
UI.drawWindow(math.floor((w-30)/2), math.floor((h-10)/2), 30, 10, "Installing...")
center(math.floor((h-10)/2) + 3, "Downloading " .. program.name)
local url = program.url
if not url then
center(math.floor((h-10)/2) + 5, "Error: No URL")
os.sleep(2)
return false
end
local targetPath = resolvePath(program.path)
local ok, err = downloadFile(url, targetPath)
if ok then
center(math.floor((h-10)/2) + 5, "Success!")
os.sleep(1)
return true
else
center(math.floor((h-10)/2) + 5, "Error: " .. (err or "Unknown"))
os.sleep(2)
return false
end
end
local state = {
credits = 0,
licenseStore = nil,
theme = {
text = colors.white,
bg = colors.cyan,
header = colors.blue,
highlight = colors.yellow,
windowBg = colors.lightGray,
buttonBg = colors.lightGray,
buttonFg = colors.black
},
environment = DEFAULT_ENVIRONMENT.mode,
}
local THEME_FILE = "arcade_skin.settings"
local function loadTheme()
if fs.exists(THEME_FILE) then
local handle = fs.open(THEME_FILE, "r")
if handle then
local data = textutils.unserialize(handle.readAll())
handle.close()
if data then
state.theme.bg = data.background or state.theme.bg
state.theme.windowBg = data.playfield or state.theme.windowBg
state.theme.header = data.titleColor or state.theme.header
if data.buttons and data.buttons.enabled then
state.theme.buttonBg = data.buttons.enabled.shadowColor or state.theme.buttonBg
state.theme.buttonFg = data.buttons.enabled.labelColor or state.theme.buttonFg
end
end
end
end
end
local function loadEnvironment()
state.environment = DEFAULT_ENVIRONMENT.mode
if fs.exists(ENVIRONMENT_FILE) then
local handle = fs.open(ENVIRONMENT_FILE, "r")
if handle then
local data = textutils.unserialize(handle.readAll())
handle.close()
if data and type(data.mode) == "string" then
state.environment = data.mode
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
loadEnvironment()
end
local UI = {}
function UI.clear(color)
term.setBackgroundColor(color)
term.clear()
end
function UI.drawWindow(x, y, w, h, title)
paintutils.drawFilledBox(x + 1, y + 1, x + w, y + h, colors.black)
paintutils.drawFilledBox(x, y, x + w - 1, y + h - 1, state.theme.windowBg)
paintutils.drawFilledBox(x, y, x + w - 1, y, state.theme.header)
term.setTextColor(colors.white)
term.setBackgroundColor(state.theme.header)
term.setCursorPos(x + math.floor((w - #title) / 2), y)
term.write(title)
term.setCursorPos(x + 2, y)
term.write("[X]")
end
function UI.drawButton(x, y, w, text, active, hovered)
local bg = active and colors.green or (hovered and colors.gray or state.theme.buttonBg)
local fg = active and colors.white or (hovered and colors.white or state.theme.buttonFg)
paintutils.drawFilledBox(x, y, x + w - 1, y, bg)
term.setTextColor(fg)
term.setBackgroundColor(bg)
term.setCursorPos(x + math.floor((w - #text) / 2), y)
term.write(text)
end
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
local function shouldShowProgram(program, currentMenu)
if program.category ~= currentMenu then
return false
end
if state.environment == "production" and program.prodReady == false then
return false
end
return true
end
local REPO_BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/"
local function downloadFile(url, path)
if not http then
return false, "HTTP API disabled"
end
local response = http.get(url)
if not response then
return false, "Failed to connect"
end
local content = response.readAll()
response.close()
local dir = fs.getDir(path)
if dir ~= "" and not fs.exists(dir) then
fs.makeDir(dir)
end
local file = fs.open(path, "w")
if file then
file.write(content)
file.close()
return true
else
return false, "Write failed"
end
end
local function installProgram(program)
term.setBackgroundColor(colors.blue)
term.clear()
local w, h = term.getSize()
local function center(y, text)
term.setCursorPos(math.floor((w - #text) / 2), y)
term.write(text)
end
UI.drawWindow(math.floor((w-30)/2), math.floor((h-10)/2), 30, 10, "Installing...")
center(math.floor((h-10)/2) + 3, "Downloading " .. program.name)
local url = program.url
if not url then
center(math.floor((h-10)/2) + 5, "Error: No URL")
os.sleep(2)
return false
end
local targetPath = resolvePath(program.path)
local ok, err = downloadFile(url, targetPath)
if ok then
center(math.floor((h-10)/2) + 5, "Success!")
os.sleep(1)
return true
else
center(math.floor((h-10)/2) + 5, "Error: " .. (err or "Unknown"))
os.sleep(2)
return false
end
end
local function launchProgram(program)
local fullPath = resolvePath(program.path)
if not fs.exists(fullPath) then
if not installProgram(program) then
return
end
end
if not ensureLicense(program) then
return
end
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("Launching " .. program.name .. "...")
local ok, err = pcall(function()
shell.run(fullPath)
end)
if not ok then
print("Program error: " .. tostring(err))
print("Press Enter to return...")
read()
else
print("Program finished cleanly.")
os.sleep(2)
end
end
local function main()
initState()
if not term.isColor() then
local menu = require("lib_menu")
while true do
local options = {
{text = "Store", action = function()
for _, p in ipairs(programs) do
if p.id == "store" then launchProgram(p) return end
end
end},
{text = "My Apps", action = function()
local gameOptions = {}
for _, p in ipairs(programs) do
if p.id ~= "store" and state.licenseStore:has(p.id) then
table.insert(gameOptions, {text = p.name, action = function() launchProgram(p) end})
end
end
table.insert(gameOptions, {text = "Back", action = function() end})
local idx, choice = menu.run("My Apps", gameOptions)
if choice and choice.action then choice.action() end
end},
{text = "System", action = function()
local sysOptions = {
{text = "Themes", action = function()
for _, p in ipairs(programs) do
if p.id == "themes" then launchProgram(p) return end
end
end},
{text = "Disk Info", action = function()
term.clear()
term.setCursorPos(1,1)
print("Free Space: " .. fs.getFreeSpace(detectDiskMount() or "/"))
os.sleep(2)
end},
{text = "Back", action = function() end}
}
local idx, choice = menu.run("System", sysOptions)
if choice and choice.action then choice.action() end
end},
{text = "Exit", action = function()
term.clear()
term.setCursorPos(1,1)
return
end}
}
local idx, choice = menu.run("ArcadeOS (Mono)", options)
if choice and choice.action then choice.action() end
end
return
end
local w, h = term.getSize()
local running = true
local currentMenu = "main" -- main, library, system
local lastMenu = currentMenu
local selectedButtonIndex = 1
local mouseX, mouseY = 0, 0
local LIBRARY_VISIBLE_LIMIT = 5
local libraryScrollOffset = 0
local libraryScrollMax = 0
local libraryVisibleCount = 0
local libraryTotalCount = 0
local function adjustLibraryScroll(delta)
if delta == 0 or libraryScrollMax <= 0 then
return
end
local nextOffset = math.max(0, math.min(libraryScrollOffset + delta, libraryScrollMax))
if nextOffset ~= libraryScrollOffset then
libraryScrollOffset = nextOffset
end
end
while running do
if currentMenu ~= lastMenu then
selectedButtonIndex = 1
if currentMenu == "library" then
libraryScrollOffset = 0
end
lastMenu = currentMenu
end
UI.clear(state.theme.bg)
local winW, winH = 26, 14
local winX = math.floor((w - winW) / 2) + 1
local winY = math.floor((h - winH) / 2) + 1
if winY < 1 then winY = 1 end
local title = "ArcadeOS"
if currentMenu == "main" and version then
title = title .. " v" .. version.MAJOR .. "." .. version.MINOR .. "." .. version.PATCH
end
if currentMenu == "library" then title = "My Apps" end
if currentMenu == "system" then title = "System" end
UI.drawWindow(winX, winY, winW, winH, title)
local buttons = {}
local startY = winY + 2
local btnW = winW - 8
local btnX = winX + 4
if currentMenu == "main" then
table.insert(buttons, {text = "Store", y = startY, action = function()
for _, p in ipairs(programs) do
if p.id == "store" then launchProgram(p) return end
end
end})
table.insert(buttons, {text = "My Apps", y = startY + 2, action = function() currentMenu = "library" end})
table.insert(buttons, {text = "System", y = startY + 4, action = function() currentMenu = "system" end})
table.insert(buttons, {text = "Exit", y = startY + 8, action = function() running = false end})
elseif currentMenu == "library" then
local list = {}
for _, p in ipairs(programs) do
if p.id ~= "store" and state.licenseStore:has(p.id) then
table.insert(list, p)
end
end
libraryTotalCount = #list
libraryScrollMax = math.max(libraryTotalCount - LIBRARY_VISIBLE_LIMIT, 0)
if libraryTotalCount == 0 then
libraryScrollOffset = 0
libraryVisibleCount = 0
table.insert(buttons, {text = "(No Apps)", y = startY, action = function() end})
else
if libraryScrollOffset > libraryScrollMax then
libraryScrollOffset = libraryScrollMax
end
libraryVisibleCount = 0
for i = 1, LIBRARY_VISIBLE_LIMIT do
local idx = libraryScrollOffset + i
local p = list[idx]
if not p then break end
libraryVisibleCount = libraryVisibleCount + 1
table.insert(buttons, {
text = p.name,
y = startY + (i-1)*2,
action = function() launchProgram(p) end
})
end
if libraryScrollMax > 0 then
local infoStart = libraryScrollOffset + 1
local infoEnd = libraryScrollOffset + libraryVisibleCount
local info = string.format("Apps %d-%d/%d", infoStart, infoEnd, libraryTotalCount)
local infoY = winY + winH - 3
local innerWidth = winW - 4
term.setBackgroundColor(state.theme.windowBg or colors.lightGray)
term.setTextColor(state.theme.buttonFg or colors.black)
term.setCursorPos(winX + 2, infoY)
term.write(string.rep(" ", innerWidth))
term.setCursorPos(winX + 2, infoY)
term.write(info:sub(1, innerWidth))
end
end
table.insert(buttons, {text = "Back", y = winY + winH - 2, action = function()
currentMenu = "main"
libraryScrollOffset = 0
end})
elseif currentMenu == "system" then
table.insert(buttons, {text = "Themes", y = startY, action = function()
local found = false
for _, p in ipairs(programs) do
if p.id == "themes" then
launchProgram(p)
found = true
return
end
end
if not found then
term.setCursorPos(1,1)
print("Theme app not found")
os.sleep(1)
end
end})
table.insert(buttons, {text = "Disk Info", y = startY + 2, action = function()
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("Free Space: " .. fs.getFreeSpace(detectDiskMount() or "/"))
os.sleep(2)
end})
table.insert(buttons, {text = "Back", y = startY + 4, action = function() currentMenu = "main" end})
end
if selectedButtonIndex > #buttons then selectedButtonIndex = #buttons end
if selectedButtonIndex < 1 and #buttons > 0 then selectedButtonIndex = 1 end
for i, btn in ipairs(buttons) do
local isHovered = (mouseX >= btnX and mouseX <= btnX + btnW - 1 and mouseY == btn.y)
local isSelected = (i == selectedButtonIndex)
UI.drawButton(btnX, btn.y, btnW, btn.text, false, isHovered or isSelected)
end
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
elseif event == "mouse_scroll" then
if currentMenu == "library" then
adjustLibraryScroll(p1)
end
elseif event == "key" then
local key = p1
if key == keys.up then
if currentMenu == "library" and libraryScrollOffset > 0 and selectedButtonIndex == 1 then
libraryScrollOffset = libraryScrollOffset - 1
else
selectedButtonIndex = selectedButtonIndex - 1
if selectedButtonIndex < 1 then selectedButtonIndex = #buttons end
end
elseif key == keys.down then
if currentMenu == "library" and libraryScrollOffset < libraryScrollMax and selectedButtonIndex == libraryVisibleCount and libraryVisibleCount > 0 then
libraryScrollOffset = libraryScrollOffset + 1
else
selectedButtonIndex = selectedButtonIndex + 1
if selectedButtonIndex > #buttons then selectedButtonIndex = 1 end
end
elseif key == keys.pageUp then
if currentMenu == "library" then
adjustLibraryScroll(-LIBRARY_VISIBLE_LIMIT)
end
elseif key == keys.pageDown then
if currentMenu == "library" then
adjustLibraryScroll(LIBRARY_VISIBLE_LIMIT)
end
elseif key == keys.enter then
local btn = buttons[selectedButtonIndex]
if btn then
UI.drawButton(btnX, btn.y, btnW, btn.text, true, true)
os.sleep(0.1)
btn.action()
end
end
end
end
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
end
main()]]
files["arcade/arcade.lua"] = [[local M = {}
local Renderer = require("arcade.ui.renderer")
local Log = require("log")
local DEFAULT = {
textScale = 0.5,         -- Monitor text scale for readability
buttonBarHeight = 3,     -- Height in rows of bottom bar
creditsFile = "credits.txt", -- File stored on disk drive media
tickSeconds = 0.25,      -- Passive tick interval (can drive animations)
skin = Renderer.defaultSkin(), -- Shared skin/theme for buttons and backgrounds
logFile = "arcade.log",  -- Where to write diagnostic information
logLevel = "info",       -- error < warn < info < debug
}
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
local function diskPath()
if not state.drive then return nil end
local mount = peripheral.getName(state.drive)
if state.drive.getMountPath then return state.drive.getMountPath() end
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
log("warn", "Failed to persist credits: " .. tostring(err))
return false, err
end
log("debug", "Credits saved to " .. path .. ": " .. state.credits)
return true
end
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
if keyCode == keys.q then M:requestQuit() end
if keyCode == keys.space then handleButtonPress(1) end
elseif ev == "char" then
local ch = e[2]
if ch == "q" then M:requestQuit() end
if ch == "1" then handleButtonPress(1) elseif ch == "2" then handleButtonPress(2) elseif ch == "3" then handleButtonPress(3) end
end
if state.game and state.game.handleEvent then
safeCall("game.handleEvent", state.game.handleEvent, state.game, M, e)
end
end
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
if state.renderer then state.renderer:restore() end
saveCredits()
log("info", "Arcade wrapper stopped")
end
return M]]
files["arcade/boot.lua"] = [[local program = shell.getRunningProgram()
local dir = fs.getDir(program)
local function findRoot(startDir)
local current = startDir
while true do
if fs.exists(fs.combine(current, "lib")) then
return current
end
if current == "" or current == ".." then break end
current = fs.getDir(current)
end
return nil
end
local root = findRoot(dir)
if root then
local function add(path)
local part = fs.combine(root, path)
local pattern = "/" .. fs.combine(part, "?.lua")
if not string.find(package.path, pattern, 1, true) then
package.path = package.path .. ";" .. pattern
end
end
add("lib")
add("arcade")
add("arcade/ui")
if not string.find(package.path, ";/?.lua", 1, true) then
package.path = package.path .. ";/?.lua"
end
end]]
files["arcade/data/programs.lua"] = [[local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/arcade/"
local PRICING = {
blackjack = 0,
slots = 0,
videopoker = 0,
cantstop = 0,
idlecraft = 0,
artillery = 0,
factory_planner = 0,
inv_manager = 0,
store = 0,
themes = 0
}
local programs = {
{
id = "blackjack",
name = "Blackjack",
path = "games/blackjack.lua",
price = PRICING.blackjack,
description = "Beat the dealer in a race to 21.",
category = "games",
url = BASE_URL .. "games/blackjack.lua"
},
{
id = "slots",
name = "Slots",
path = "games/slots.lua",
price = PRICING.slots,
description = "Spin reels for quick wins.",
category = "games",
url = BASE_URL .. "games/slots.lua"
},
{
id = "videopoker",
name = "Video Poker",
path = "games/videopoker.lua",
price = PRICING.videopoker,
description = "Jacks or Better poker.",
category = "games",
url = BASE_URL .. "games/videopoker.lua"
},
{
id = "cantstop",
name = "Can't Stop",
path = "games/cantstop.lua",
price = PRICING.cantstop,
description = "Push your luck dice classic.",
category = "games",
url = BASE_URL .. "games/cantstop.lua"
},
{
id = "idlecraft",
name = "IdleCraft",
path = "games/idlecraft.lua",
price = PRICING.idlecraft,
description = "AFK-friendly cobble empire.",
category = "games",
url = BASE_URL .. "games/idlecraft.lua"
},
{
id = "artillery",
name = "Artillery",
path = "games/artillery.lua",
price = PRICING.artillery,
description = "2-player tank battle.",
category = "games",
url = BASE_URL .. "games/artillery.lua"
},
{
id = "factory_planner",
name = "Factory Planner",
path = "factory_planner.lua",
price = PRICING.factory_planner,
description = "Design factory layouts for turtles.",
category = "actions",
url = BASE_URL .. "factory_planner.lua"
},
{
id = "inv_manager",
name = "Inventory Manager",
path = "inv_manager.lua",
price = PRICING.inv_manager,
description = "Manage inventory (Coming Soon).",
category = "actions",
prodReady = false,
url = BASE_URL .. "inv_manager.lua"
},
{
id = "store",
name = "App Store",
path = "store.lua",
price = PRICING.store,
description = "Download new games.",
category = "system",
url = BASE_URL .. "store.lua"
},
{
id = "themes",
name = "Themes",
path = "games/themes.lua",
price = PRICING.themes,
description = "Change system theme.",
category = "system",
url = BASE_URL .. "games/themes.lua"
},
}
return programs]]
files["arcade/data/valhelsia_blocks.lua"] = [[return {
{ id = "minecraft:stone", label = "Stone" },
{ id = "minecraft:dirt", label = "Dirt" },
{ id = "minecraft:cobblestone", label = "Cobblestone" },
{ id = "minecraft:planks", label = "Planks" },
{ id = "minecraft:sand", label = "Sand" },
{ id = "minecraft:gravel", label = "Gravel" },
{ id = "minecraft:log", label = "Log" },
{ id = "minecraft:glass", label = "Glass" },
{ id = "minecraft:chest", label = "Chest" },
{ id = "minecraft:furnace", label = "Furnace" },
{ id = "minecraft:crafting_table", label = "Crafting Table" },
{ id = "minecraft:iron_block", label = "Iron Block" },
{ id = "minecraft:gold_block", label = "Gold Block" },
{ id = "minecraft:diamond_block", label = "Diamond Block" },
{ id = "minecraft:torch", label = "Torch" },
{ id = "minecraft:hopper", label = "Hopper" },
{ id = "minecraft:dropper", label = "Dropper" },
{ id = "minecraft:dispenser", label = "Dispenser" },
{ id = "minecraft:observer", label = "Observer" },
{ id = "minecraft:piston", label = "Piston" },
{ id = "minecraft:sticky_piston", label = "Sticky Piston" },
{ id = "minecraft:lever", label = "Lever" },
{ id = "minecraft:redstone_block", label = "Redstone Block" },
{ id = "storagedrawers:controller", label = "Drawer Controller" },
{ id = "storagedrawers:oak_full_drawers_1", label = "Oak Drawer" },
{ id = "storagedrawers:compacting_drawers_3", label = "Compacting Drawer" },
{ id = "create:andesite_casing", label = "Andesite Casing" },
{ id = "create:brass_casing", label = "Brass Casing" },
{ id = "create:copper_casing", label = "Copper Casing" },
{ id = "create:shaft", label = "Shaft" },
{ id = "create:cogwheel", label = "Cogwheel" },
{ id = "create:large_cogwheel", label = "Large Cogwheel" },
{ id = "create:gearbox", label = "Gearbox" },
{ id = "create:clutch", label = "Clutch" },
{ id = "create:gearshift", label = "Gearshift" },
{ id = "create:encased_chain_drive", label = "Chain Drive" },
{ id = "create:belt", label = "Mechanical Belt" },
{ id = "create:chute", label = "Chute" },
{ id = "create:smart_chute", label = "Smart Chute" },
{ id = "create:fluid_pipe", label = "Fluid Pipe" },
{ id = "create:mechanical_pump", label = "Mech Pump" },
{ id = "create:fluid_tank", label = "Fluid Tank" },
{ id = "create:mechanical_press", label = "Mech Press" },
{ id = "create:mechanical_mixer", label = "Mech Mixer" },
{ id = "create:basin", label = "Basin" },
{ id = "create:blaze_burner", label = "Blaze Burner" },
{ id = "create:millstone", label = "Millstone" },
{ id = "create:crushing_wheel", label = "Crushing Wheel" },
{ id = "create:mechanical_drill", label = "Mech Drill" },
{ id = "create:mechanical_saw", label = "Mech Saw" },
{ id = "create:deployer", label = "Deployer" },
{ id = "create:portable_storage_interface", label = "Portable Storage" },
{ id = "create:redstone_link", label = "Redstone Link" },
{ id = "mekanism:steel_casing", label = "Steel Casing" },
{ id = "mekanism:metallurgic_infuser", label = "Met. Infuser" },
{ id = "mekanism:enrichment_chamber", label = "Enrich. Chamber" },
{ id = "mekanism:crusher", label = "Crusher" },
{ id = "mekanism:osmium_compressor", label = "Osmium Comp." },
{ id = "mekanism:combiner", label = "Combiner" },
{ id = "mekanism:purification_chamber", label = "Purif. Chamber" },
{ id = "mekanism:pressurized_reaction_chamber", label = "PRC" },
{ id = "mekanism:chemical_injection_chamber", label = "Chem. Inj." },
{ id = "mekanism:chemical_crystallizer", label = "Crystallizer" },
{ id = "mekanism:chemical_dissolution_chamber", label = "Dissolution" },
{ id = "mekanism:chemical_washer", label = "Washer" },
{ id = "mekanism:digital_miner", label = "Digital Miner" },
{ id = "mekanism:basic_universal_cable", label = "Univ. Cable" },
{ id = "mekanism:basic_mechanical_pipe", label = "Mech. Pipe" },
{ id = "mekanism:basic_pressurized_tube", label = "Press. Tube" },
{ id = "mekanism:basic_logistical_transporter", label = "Log. Transp." },
{ id = "immersiveengineering:coke_oven", label = "Coke Oven" },
{ id = "immersiveengineering:blast_furnace", label = "Blast Furnace" },
{ id = "immersiveengineering:windmill", label = "Windmill" },
{ id = "immersiveengineering:watermill", label = "Watermill" },
{ id = "immersiveengineering:dynamo", label = "Dynamo" },
{ id = "immersiveengineering:hv_capacitor", label = "HV Capacitor" },
{ id = "immersiveengineering:mv_capacitor", label = "MV Capacitor" },
{ id = "immersiveengineering:lv_capacitor", label = "LV Capacitor" },
{ id = "immersiveengineering:conveyor_basic", label = "Conveyor" },
{ id = "ae2:controller", label = "ME Controller" },
{ id = "ae2:drive", label = "ME Drive" },
{ id = "ae2:terminal", label = "ME Terminal" },
{ id = "ae2:crafting_terminal", label = "Crafting Term" },
{ id = "ae2:pattern_terminal", label = "Pattern Term" },
{ id = "ae2:interface", label = "ME Interface" },
{ id = "ae2:molecular_assembler", label = "Mol. Assembler" },
{ id = "ae2:cable_glass", label = "Glass Cable" },
{ id = "ae2:cable_smart", label = "Smart Cable" },
{ id = "computercraft:computer_normal", label = "Computer" },
{ id = "computercraft:computer_advanced", label = "Adv Computer" },
{ id = "computercraft:turtle_normal", label = "Turtle" },
{ id = "computercraft:turtle_advanced", label = "Adv Turtle" },
{ id = "computercraft:monitor_normal", label = "Monitor" },
{ id = "computercraft:monitor_advanced", label = "Adv Monitor" },
{ id = "computercraft:disk_drive", label = "Disk Drive" },
{ id = "computercraft:printer", label = "Printer" },
{ id = "computercraft:speaker", label = "Speaker" },
{ id = "computercraft:wired_modem", label = "Wired Modem" },
{ id = "computercraft:wireless_modem_normal", label = "Wireless Modem" },
}]]
files["arcade/games/cantstop.lua"] = [[package.loaded["arcade"] = nil
package.loaded["log"] = nil
local function setupPaths()
local dir = fs.getDir(shell.getRunningProgram())
local boot = fs.combine(fs.getDir(dir), "boot.lua")
if fs.exists(boot) then dofile(boot) end
end
setupPaths()
local _arcade_ok, _arcade = pcall(require, "arcade")
local Renderer = require("arcade.ui.renderer")
local ui = require("lib_ui")
local toBlit = ui.toBlit
local SAVE_FILE = "cantstop.save" -- (Arcade wrapper note: this game predates arcade.lua and runs standalone.)
local BOARD_HEIGHTS = {
[2] = 3, [3] = 5, [4] = 7, [5] = 9, [6] = 11,
[7] = 13, [8] = 11, [9] = 9, [10] = 7, [11] = 5, [12] = 3
}
local PLAYER_COLORS = {
colors.red, colors.lime, colors.blue, colors.orange,
colors.purple, colors.cyan, colors.yellow, colors.magenta, colors.brown
}
local BUTTON_BAR_HEIGHT = 3
local PHASE = {
LOBBY = "LOBBY",
TURN = "TURN",           -- Player may Roll or Stop
CHOOSE = "CHOOSE",       -- Player chooses among valid pairings
GAME_OVER = "GAME_OVER"
}
local BTN = { LEFT = 1, CENTER = 2, RIGHT = 3 }
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
monitor = peripheral.find and peripheral.find("monitor") or nil
if monitor then
renderer:attachToMonitor(monitor, 0.5) -- smaller text for more info
else
renderer:attachToMonitor(nil)
end
screenW, screenH = renderer:getSize()
end
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
local boardTop = 3
local boardBottom = screenH - BUTTON_BAR_HEIGHT
if boardBottom < boardTop + 4 then
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
renderer:registerHotspot("button" .. i, layout.buttons[i])
end
end
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
local function clearArea(x, y, w, h, bg, fg)
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
renderer:paintSurface({ x = 1, y = layout.buttons[1].y, w = screenW, h = BUTTON_BAR_HEIGHT }, rendererSkin.buttonBar.background)
for i = 1, 3 do
local r = layout.buttons[i]
renderer:drawButton(r, labels[i] or "", enabled[i] ~= false)
end
end
local function countClaimedColumnsForPlayer(playerIndex)
local claimed = 0
for _, owner in pairs(state.claimedColumns) do
if owner == playerIndex then claimed = claimed + 1 end
end
return claimed
end
local function buildPlayerProgressString(playerIndex)
local player = state.players[playerIndex]
if not player then return "" end
local marker = (playerIndex == state.currentPlayer) and "*" or " "
local name = player.name or ("P" .. playerIndex)
local claimed = countClaimedColumnsForPlayer(playerIndex)
local entries = {}
local perm = state.permanentProgress[playerIndex] or {}
for col, h in pairs(perm) do
local colHeight = BOARD_HEIGHTS[col]
if colHeight then
table.insert(entries, {col = col, h = h, remaining = colHeight - h})
end
end
table.sort(entries, function(a,b)
if a.remaining == b.remaining then return a.col < b.col end
return a.remaining < b.remaining
end)
local parts = {}
local shown = 0
for _, e in ipairs(entries) do
shown = shown + 1
if shown > 4 then break end -- show at most 4 columns per player
local displayH = e.h
if playerIndex == state.currentPlayer and state.neutralMarkers[e.col] and state.neutralMarkers[e.col] > e.h then
displayH = state.neutralMarkers[e.col]
end
table.insert(parts, string.format("%d@%d", e.col, displayH))
end
return string.format("%s%s(%d): %s", marker, name, claimed, table.concat(parts, " "))
end
local function drawPlayersSummary()
local parts = {}
for i = 1, #state.players do
table.insert(parts, buildPlayerProgressString(i))
end
local summary = table.concat(parts, "  |  ")
local y = layout.diceY
term.setTextColor(colors.white)
if #summary > screenW then
summary = string.sub(summary, #summary - screenW + 1)
end
term.setCursorPos(math.max(1, screenW - #summary + 1), y)
term.write(summary)
end
local function drawBoard()
local r = layout.board
clearArea(r.x, r.y, r.w, r.h, colors.black, colors.white)
local maxH = BOARD_HEIGHTS[7] or 13
local usableH = math.max(3, r.h - 2) -- leave a small header/footer inside board area
local columns = {}
for c = 2, 12 do table.insert(columns, c) end
local colCount = #columns -- 11
local padding = 1
local minColW = 3 -- at least 3 characters per column
local totalPad = padding * (colCount + 1)
local availableW = math.max(1, r.w - totalPad)
local colW = math.max(minColW, math.floor(availableW / colCount))
local leftover = availableW - (colW * colCount)
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
local baseY = r.y + 1
local heightArea = usableH
x = r.x + padding
for idx, col in ipairs(columns) do
local w = colW + (idx <= leftover and 1 or 0)
local colHeight = BOARD_HEIGHTS[col]
paintutils.drawFilledBox(x, baseY, x + w - 1, baseY + heightArea - 1, colors.gray)
if state.claimedColumns[col] then
local owner = state.claimedColumns[col]
local ownerColor = state.players[owner] and state.players[owner].color or colors.white
paintutils.drawFilledBox(x, baseY, x + w - 1, baseY + heightArea - 1, ownerColor)
end
local function toYFromHeight(h)
local t = (h / colHeight)
local rel = heightArea - math.max(1, math.floor(t * (heightArea - 1)))
return baseY + rel - 1
end
for pIndex, p in ipairs(state.players) do
local perm = (state.permanentProgress[pIndex] and state.permanentProgress[pIndex][col]) or 0
if perm > 0 then
local yy = toYFromHeight(perm)
local color = p.color or colors.white
paintutils.drawLine(x, yy, x + w - 1, yy, color)
end
end
local temp = state.neutralMarkers[col]
if temp and temp > 0 then
local yy = toYFromHeight(temp)
paintutils.drawLine(x, yy, x + w - 1, yy, colors.lime)
end
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
local function seedRandom()
math.randomseed(os.epoch("utc"))
for _ = 1, 5 do math.random() end
end
local function roll4Dice()
return { math.random(1, 6), math.random(1, 6), math.random(1, 6), math.random(1, 6) }
end
local function computePairings(d)
local pairsList = {
{ d[1] + d[2], d[3] + d[4] },
{ d[1] + d[3], d[2] + d[4] },
{ d[1] + d[4], d[2] + d[3] },
}
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
if state.claimedColumns[sum] then return false end
local curP = state.currentPlayer
local perm = (state.permanentProgress[curP] and state.permanentProgress[curP][sum]) or 0
local temp = state.neutralMarkers[sum] or perm
local nextStep = temp + 1
if nextStep > BOARD_HEIGHTS[sum] then return false end
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
local s1, s2 = pairing[1], pairing[2]
local curP = state.currentPlayer
local perm1 = (state.permanentProgress[curP] and state.permanentProgress[curP][s1]) or 0
local perm2 = (state.permanentProgress[curP] and state.permanentProgress[curP][s2]) or 0
state.neutralMarkers[s1] = (state.neutralMarkers[s1] or perm1) + 1
state.neutralMarkers[s2] = (state.neutralMarkers[s2] or perm2) + 1
end
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
local function waitForButtonPress()
while true do
local e = { os.pullEvent() }
local ev = e[1]
if ev == "monitor_touch" then
local _side, x, y = e[2], e[3], e[4]
for i = 1, 3 do if renderer:hitTest("button" .. i, x, y) then return i end end
elseif ev == "mouse_click" then
local _btn, x, y = e[2], e[3], e[4]
for i = 1, 3 do if renderer:hitTest("button" .. i, x, y) then return i end end
elseif ev == "term_resize" or ev == "monitor_resize" then
drawAll({"","",""}, {false,false,false})
end
end
end
local function addAutoPlayer()
local idx = #state.players + 1
local name = "Player " .. idx
local color = PLAYER_COLORS[((idx - 1) % #PLAYER_COLORS) + 1]
table.insert(state.players, { name = name, color = color })
state.statusText = string.format("Added %s. Players: %d", name, #state.players)
end
local function showMenuDuringTurn()
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
drawAll({"Roll","Stop","Menu"})
local b = waitForButtonPress()
if b == BTN.LEFT then
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
commitTurn()
drawAll({"","",""}, {false,false,false})
if state.phase ~= PHASE.GAME_OVER then
sleep(0.5)
nextPlayer()
end
elseif b == BTN.RIGHT then
showMenuDuringTurn()
end
elseif state.phase == PHASE.CHOOSE then
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
newGame(false)
end
end
end
local function main()
seedRandom()
initMonitor()
computeLayout()
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
local ok, err = pcall(main)
if not ok then
if renderer then renderer:restore() end
print("Can't Stop crashed:\n" .. tostring(err))
print("Press any key to exit...")
os.pullEvent("key")
end]]
files["arcade/games/idlecraft.lua"] = [[package.loaded["arcade"] = nil
package.loaded["log"] = nil
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
add("arcade/ui")
if not string.find(package.path, ";/?.lua", 1, true) then
package.path = package.path .. ";/?.lua"
end
end
setupPaths()
local arcade = require("arcade")
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
menuOpen = false,
menuSelection = 1,
messages = {},
}
local function formatNumber(value)
if not value then return "0" end
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
local savePath = "arcade/data/idlecraft_save.txt"
local lastSaveRealTime = os.clock()
local function saveGame()
local file = fs.open(savePath, "w")
if file then
file.write(textutils.serialize(state))
file.close()
end
end
local function loadGame()
if fs.exists(savePath) then
local file = fs.open(savePath, "r")
if file then
local content = file.readAll()
file.close()
local loaded = textutils.unserialize(content)
if loaded and type(loaded) == "table" then
for k, v in pairs(loaded) do
state[k] = v
end
end
end
end
end
local function getMenuItems()
local items = {}
table.insert(items, {
label = "Upgrade Tools (" .. formatNumber(state.toolUpgradeCost) .. ")",
action = function() upgradeTools() end,
enabled = state.cobble >= state.toolUpgradeCost
})
if state.stage >= 2 then
table.insert(items, {
label = "MODS (" .. formatNumber(state.modCost) .. ")",
action = function() installMod() end,
enabled = state.cobble >= state.modCost
})
end
table.insert(items, {
label = "Resume",
action = function() state.menuOpen = false end,
enabled = true
})
table.insert(items, {
label = "EXIT",
action = function(a) a:requestQuit() end,
enabled = true
})
return items
end
local function getStageName()
return config.stageNames[state.stage] or ("Stage " .. tostring(state.stage))
end
local function drawGame(a)
local r = a:getRenderer()
if not r then return end
a:clearPlayfield(colors.black)
local w, h = r:getSize()
r:fillRect(1, 1, w, 1, colors.blue, colors.white, " ")
r:drawLabelCentered(1, 1, w, "IdleCraft - " .. getStageName(), colors.white)
r:fillRect(1, 2, w, 3, colors.gray, colors.white, " ")
r:drawLabelCentered(1, 2, math.floor(w/2), "Cobble: " .. formatNumber(state.cobble), colors.white)
r:drawLabelCentered(math.floor(w/2)+1, 2, math.floor(w/2), "OPS: " .. formatRate(state.ops), colors.white)
r:drawLabelCentered(1, 3, math.floor(w/2), "Steves: " .. formatNumber(state.steves), colors.lightGray)
r:drawLabelCentered(math.floor(w/2)+1, 3, math.floor(w/2), "Mods: " .. formatNumber(state.mods), colors.lightGray)
local msgY = 5
local msgs = state.messages
local start = math.max(1, #msgs - 7)
for i = start, #msgs do
r:drawLabelCentered(1, msgY, w, msgs[i], colors.white)
msgY = msgY + 1
end
if state.menuOpen then
local menuWidth = 30
local menuX = w - menuWidth + 1
local menuH = h - 1
r:fillRect(menuX, 2, menuWidth, menuH, colors.lightGray, colors.black, " ")
r:drawLabelCentered(menuX, 2, menuWidth, "--- MENU ---", colors.black)
local items = getMenuItems()
for i, item in ipairs(items) do
local y = 4 + (i-1)*2
local fg = colors.black
local bg = colors.lightGray
local prefix = "  "
if i == state.menuSelection then
fg = colors.white
bg = colors.blue
prefix = "> "
end
if i == state.menuSelection then
r:fillRect(menuX + 1, y, menuWidth - 2, 1, bg, fg, " ")
end
r:drawLabel(menuX + 2, y, prefix .. item.label, fg, bg)
end
end
end
local game = {
name = "IdleCraft",
init = function(self, a)
math.randomseed(os.epoch and os.epoch("utc") or os.clock()) -- Reseed per session
loadGame()
addMessage("Welcome to IdleCraft. Mine, Hire Steves, and Automate!")
self.draw(self, a)
end,
draw = function(self, a)
if state.menuOpen then
a:setButtons({"Up", "Select", "Down"}, {true, true, true})
else
local steveLabel = "Steve (" .. formatNumber(state.steveCost) .. ")"
local canAffordSteve = state.cobble >= state.steveCost
a:setButtons({"Mine", steveLabel, "Menu"}, {true, canAffordSteve, true})
end
drawGame(a)
end,
onButton = function(self, a, which)
if state.menuOpen then
local items = getMenuItems()
if which == "left" then
state.menuSelection = state.menuSelection - 1
if state.menuSelection < 1 then state.menuSelection = #items end
elseif which == "right" then
state.menuSelection = state.menuSelection + 1
if state.menuSelection > #items then state.menuSelection = 1 end
elseif which == "center" then
local item = items[state.menuSelection]
if item and item.enabled then
item.action(a)
end
end
else
if which == "left" then
mineBlock()
elseif which == "center" then
hireSteve()
elseif which == "right" then
state.menuOpen = true
state.menuSelection = 1
end
end
self.draw(self, a)
end,
onTick = function(self, a, dt)
passiveTick()
if os.clock() - lastSaveRealTime >= 10 then
saveGame()
lastSaveRealTime = os.clock()
end
self.draw(self, a)
end,
}
arcade.start(game, { tickSeconds = config.tickSeconds })]]
files["arcade/games/slots.lua"] = [[package.loaded["arcade"] = nil
package.loaded["log"] = nil
local function setupPaths()
local dir = fs.getDir(shell.getRunningProgram())
local boot = fs.combine(fs.getDir(dir), "boot.lua")
if fs.exists(boot) then dofile(boot) end
end
setupPaths()
local arcade = require("arcade")
local ui = require("lib_ui")
local toBlit = ui.toBlit
local function solidTex(char, fg, bg, w, h)
local f = string.rep(toBlit(fg), w)
local b = string.rep(toBlit(bg), w)
local t = string.rep(char, w)
local rows = {}
for i=1,h do table.insert(rows, {text=t, fg=f, bg=b}) end
return { rows = rows }
end
local SYMBOLS = {
["Cherry"] = solidTex("@", colors.red, colors.white, 4, 3),
["Lemon"] = solidTex("O", colors.yellow, colors.white, 4, 3),
["Orange"] = solidTex("O", colors.orange, colors.white, 4, 3),
["Plum"] = solidTex("%", colors.purple, colors.white, 4, 3),
["Bell"] = solidTex("A", colors.gold or colors.yellow, colors.white, 4, 3),
["Bar"] = solidTex("=", colors.black, colors.white, 4, 3),
["7"] = solidTex("7", colors.red, colors.white, 4, 3)
}
local REELS = {
{"Cherry", "Lemon", "Orange", "Plum", "Bell", "Bar", "7"},
{"Cherry", "Lemon", "Orange", "Plum", "Bell", "Bar", "7"},
{"Cherry", "Lemon", "Orange", "Plum", "Bell", "Bar", "7"}
}
local PAYOUTS = {
["Cherry"] = 2,
["Lemon"] = 3,
["Orange"] = 5,
["Plum"] = 10,
["Bell"] = 20,
["Bar"] = 50,
["7"] = 100
}
local COST = 1
local result = {"-", "-", "-"}
local message = "Press Spin!"
local winAmount = 0
local game = {
name = "Slots",
init = function(self, a)
a:setButtons({"Info", "Spin", "Quit"})
end,
draw = function(self, a)
a:clearPlayfield(colors.green)
local r = a:getRenderer()
if not r then return end
local w, h = r:getSize()
local cx = math.floor(w / 2)
local cy = math.floor(h / 2)
a:centerPrint(2, "--- SLOTS ---", colors.yellow, colors.green)
local reelW = 6
local reelH = 5
local spacing = 2
local totalW = (reelW * 3) + (spacing * 2)
local startX = cx - math.floor(totalW / 2)
local startY = 4
for i=1,3 do
local symName = result[i]
local tex = SYMBOLS[symName]
local x = startX + (i-1)*(reelW+spacing)
r:fillRect(x, startY, reelW, reelH, colors.white, colors.black, " ")
if tex then
local tx = x + 1
local ty = startY + 1
r:drawTextureRect(tex, tx, ty, 4, 3)
else
r:drawLabelCentered(x, startY + 2, reelW, "?", colors.black)
end
end
if winAmount > 0 then
a:centerPrint(startY + reelH + 2, "WINNER! " .. winAmount, colors.lime, colors.green)
else
a:centerPrint(startY + reelH + 2, message, colors.white, colors.green)
end
a:centerPrint(startY + reelH + 4, "Credits: " .. a:getCredits(), colors.orange, colors.green)
end,
onButton = function(self, a, button)
if button == "left" then
message = "Cost: " .. COST .. " Credit"
winAmount = 0
elseif button == "center" then
if a:consumeCredits(COST) then
winAmount = 0
for i=1,3 do
result[i] = REELS[i][math.random(1, #REELS[i])]
end
if result[1] == result[2] and result[2] == result[3] then
local sym = result[1]
winAmount = (PAYOUTS[sym] or 0) * COST
a:addCredits(winAmount)
message = "JACKPOT!"
elseif result[1] == result[2] or result[2] == result[3] or result[1] == result[3] then
message = "Spin again!"
else
message = "Try again!"
end
else
message = "Insert Coin"
end
elseif button == "right" then
a:requestQuit()
end
end
}
arcade.start(game)]]
files["arcade/games/themes.lua"] = [[package.loaded["arcade"] = nil
package.loaded["log"] = nil
local function setupPaths()
local program = shell.getRunningProgram()
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
local themes = {
{
name = "Default",
skin = {
background = colors.black,
playfield = colors.black,
buttonBar = { background = colors.black },
titleColor = colors.orange,
buttons = {
enabled = { labelColor = colors.orange, shadowColor = colors.gray },
disabled = { labelColor = colors.lightGray, shadowColor = colors.black }
}
}
},
{
name = "Ocean",
skin = {
background = colors.blue,
playfield = colors.lightBlue,
buttonBar = { background = colors.blue },
titleColor = colors.cyan,
buttons = {
enabled = { labelColor = colors.white, shadowColor = colors.blue },
disabled = { labelColor = colors.gray, shadowColor = colors.blue }
}
}
},
{
name = "Forest",
skin = {
background = colors.green,
playfield = colors.lime,
buttonBar = { background = colors.green },
titleColor = colors.yellow,
buttons = {
enabled = { labelColor = colors.white, shadowColor = colors.green },
disabled = { labelColor = colors.gray, shadowColor = colors.green }
}
}
},
{
name = "Retro",
skin = {
background = colors.gray,
playfield = colors.lightGray,
buttonBar = { background = colors.gray },
titleColor = colors.black,
buttons = {
enabled = { labelColor = colors.black, shadowColor = colors.white },
disabled = { labelColor = colors.gray, shadowColor = colors.white }
}
}
}
}
local currentIndex = 1
local SKIN_FILE = "arcade_skin.settings"
local function saveSkin(skin)
local f = fs.open(SKIN_FILE, "w")
if f then
f.write(textutils.serialize(skin))
f.close()
end
end
local function loadSkin()
if fs.exists(SKIN_FILE) then
local f = fs.open(SKIN_FILE, "r")
if f then
local content = f.readAll()
f.close()
return textutils.unserialize(content)
end
end
return nil
end
local w, h = term.getSize()
local currentSkin = loadSkin()
local function draw()
term.setCursorPos(1, 1)
term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
term.clearLine()
term.write(" Theme Switcher")
term.setCursorPos(1, h)
term.setBackgroundColor(colors.gray)
term.setTextColor(colors.white)
term.clearLine()
term.write(" Enter: Apply  Q: Quit")
for i, theme in ipairs(themes) do
local y = i + 2
term.setCursorPos(1, y)
term.clearLine()
if i == currentIndex then
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
else
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
end
term.write(" " .. theme.name)
if currentSkin and currentSkin.background == theme.skin.background and currentSkin.titleColor == theme.skin.titleColor then
term.setCursorPos(w - 8, y)
term.setTextColor(colors.green)
term.write("(Active)")
end
end
end
while true do
draw()
local ev, p1 = os.pullEvent()
if ev == "key" then
if p1 == keys.up then
currentIndex = currentIndex - 1
if currentIndex < 1 then currentIndex = #themes end
elseif p1 == keys.down then
currentIndex = currentIndex + 1
if currentIndex > #themes then currentIndex = 1 end
elseif p1 == keys.enter then
local theme = themes[currentIndex]
saveSkin(theme.skin)
currentSkin = theme.skin
term.setCursorPos(1, h-1)
term.setBackgroundColor(colors.green)
term.setTextColor(colors.white)
term.clearLine()
term.write(" Theme Applied! ")
os.sleep(1)
elseif p1 == keys.q then
break
end
end
end
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)]]
files["arcade/games/videopoker.lua"] = [[package.loaded["arcade"] = nil
local function setupPaths()
local dir = fs.getDir(shell.getRunningProgram())
local boot = fs.combine(fs.getDir(dir), "boot.lua")
if fs.exists(boot) then dofile(boot) end
end
setupPaths()
local arcade = require("arcade")
local cards = require("lib_cards")
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
deck = cards.createDeck()
cards.shuffle(deck)
end,
draw = function(self, a)
a:clearPlayfield(colors.blue)
local r = a:getRenderer()
if not r then return end
local w, h = r:getSize()
local cx = math.floor(w / 2)
a:centerPrint(2, "--- VIDEO POKER ---", colors.yellow, colors.blue)
local totalW = (CARD_W * 5) + (CARD_SPACING * 4)
local startX = cx - math.floor(totalW / 2)
local startY = 6
for i=1,5 do
local x = startX + (i-1)*(CARD_W+CARD_SPACING)
local card = hand[i]
local bg = colors.white
if currentState == STATE_DEAL and held[i] then bg = colors.lightGray end
r:fillRect(x, startY, CARD_W, CARD_H, bg, colors.black, " ")
if card then
local col = cards.SUIT_COLORS[card.suit]
local txt = card.rankStr .. cards.SUIT_SYMBOLS[card.suit]
r:drawLabelCentered(x, startY + 2, CARD_W, txt, col, bg)
if currentState == STATE_DEAL and held[i] then
r:drawLabelCentered(x, startY + CARD_H + 1, CARD_W, "HELD", colors.yellow, colors.blue)
end
else
r:fillRect(x, startY, CARD_W, CARD_H, colors.red, colors.white, "#")
end
end
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
if a:consumeCredits(bet) then
deck = cards.createDeck()
cards.shuffle(deck)
hand = {}
held = {false, false, false, false, false}
for i=1,5 do table.insert(hand, table.remove(deck)) end
local name, payout = cards.evaluateHand(hand)
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
for i=1,5 do
if not held[i] then
hand[i] = table.remove(deck)
end
end
local name, payout = cards.evaluateHand(hand)
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
arcade.start(game)]]
files["arcade/games/warlords.lua"] = [[local arcade = require("arcade")
local INPUT_SIDES = {"left", "right", "back", "bottom"}
local PADDLE_SIZE = 6
local BALL_SPEED_START = 0.8
local MAX_SCORE = 10
local COLORS = {
P1 = colors.red,    -- Bottom
P2 = colors.blue,   -- Top
P3 = colors.green,  -- Left
P4 = colors.yellow, -- Right
BALL = colors.white,
BG = colors.black,
TEXT = colors.white
}
local mon = nil
local W, H = 0, 0
local running = false
local winner = nil
local players = {}
local ball = {x=0, y=0, vx=0, vy=0}
local function createPlayer(id, side, color, isVertical, axisPos)
return {
id = id,
side = side,
color = color,
vertical = isVertical,
axisPos = axisPos, -- The fixed coordinate (Y for horiz, X for vert)
pos = 1, -- The moving coordinate
score = MAX_SCORE,
alive = true
}
end
local game = {
name = "Warlords 4-Way",
init = function(self, a)
mon = peripheral.find("monitor")
if not mon then
mon = term.current()
end
if mon.setTextScale then mon.setTextScale(0.5) end
W, H = mon.getSize()
H = H - 3 -- Reserve button space
players = {
createPlayer(1, INPUT_SIDES[1], COLORS.P1, false, H), -- Bottom
createPlayer(2, INPUT_SIDES[2], COLORS.P2, false, 1), -- Top
createPlayer(3, INPUT_SIDES[3], COLORS.P3, true, 1),  -- Left
createPlayer(4, INPUT_SIDES[4], COLORS.P4, true, W)   -- Right
}
players[1].pos = W/2 - PADDLE_SIZE/2
players[2].pos = W/2 - PADDLE_SIZE/2
players[3].pos = H/2 - PADDLE_SIZE/2
players[4].pos = H/2 - PADDLE_SIZE/2
a:setButtons({"Start", "Reset", "Quit"})
self:resetBall()
end,
resetBall = function(self)
ball.x = W/2
ball.y = H/2
local angle = math.random() * math.pi * 2
ball.vx = math.cos(angle) * BALL_SPEED_START
ball.vy = math.sin(angle) * BALL_SPEED_START
if math.abs(ball.vx) < 0.3 then ball.vx = (ball.vx < 0 and -0.5 or 0.5) end
if math.abs(ball.vy) < 0.3 then ball.vy = (ball.vy < 0 and -0.5 or 0.5) end
end,
onTick = function(self, a, dt)
if not running then
self:drawDirect()
return
end
for _, p in ipairs(players) do
if p.alive then
local input = rs.getInput(p.side)
local dir = input and 1 or -1
local limit = p.vertical and H or W
p.pos = p.pos + (dir * 1.5) -- Speed multiplier
if p.pos < 1 then p.pos = 1 end
if p.pos > limit - PADDLE_SIZE + 1 then p.pos = limit - PADDLE_SIZE + 1 end
end
end
local nextX = ball.x + ball.vx
local nextY = ball.y + ball.vy
local hit = false
if nextX <= 1 then
if self:checkPaddle(players[3], nextY) then
ball.vx = math.abs(ball.vx) * 1.05
hit = true
else
self:damage(players[3])
ball.vx = math.abs(ball.vx) -- Bounce anyway
end
elseif nextX >= W then
if self:checkPaddle(players[4], nextY) then
ball.vx = -math.abs(ball.vx) * 1.05
hit = true
else
self:damage(players[4])
ball.vx = -math.abs(ball.vx)
end
end
if nextY <= 1 then
if self:checkPaddle(players[2], nextX) then
ball.vy = math.abs(ball.vy) * 1.05
hit = true
else
self:damage(players[2])
ball.vy = math.abs(ball.vy)
end
elseif nextY >= H then
if self:checkPaddle(players[1], nextX) then
ball.vy = -math.abs(ball.vy) * 1.05
hit = true
else
self:damage(players[1])
ball.vy = -math.abs(ball.vy)
end
end
if not hit then
ball.x = ball.x + ball.vx
ball.y = ball.y + ball.vy
else
ball.x = ball.x + ball.vx
ball.y = ball.y + ball.vy
end
if ball.x < 1 then ball.x = 1 end
if ball.x > W then ball.x = W end
if ball.y < 1 then ball.y = 1 end
if ball.y > H then ball.y = H end
self:drawDirect()
end,
checkPaddle = function(self, p, ballPos)
return ballPos >= p.pos - 1 and ballPos <= p.pos + PADDLE_SIZE
end,
damage = function(self, p)
if not p.alive then return end
p.score = p.score - 1
if p.score <= 0 then
p.alive = false
p.color = colors.gray
self:checkWin()
end
end,
checkWin = function(self)
local alive = 0
local last = nil
for _, p in ipairs(players) do
if p.alive then
alive = alive + 1
last = p
end
end
if alive <= 1 then
running = false
winner = last
end
end,
drawDirect = function(self)
if not mon then return end
mon.setBackgroundColor(COLORS.BG)
for y=1, H do
mon.setCursorPos(1, y)
mon.write(string.rep(" ", W))
end
for _, p in ipairs(players) do
mon.setBackgroundColor(p.color)
if p.vertical then
for i=0, PADDLE_SIZE-1 do
local y = math.floor(p.pos + i)
if y >= 1 and y <= H then
mon.setCursorPos(p.axisPos, y)
mon.write(" ")
end
end
else
for i=0, PADDLE_SIZE-1 do
local x = math.floor(p.pos + i)
if x >= 1 and x <= W then
mon.setCursorPos(x, p.axisPos)
mon.write(" ")
end
end
end
mon.setTextColor(p.color)
mon.setBackgroundColor(COLORS.BG)
if p.id == 1 then mon.setCursorPos(W/2, H-1) -- Bottom
elseif p.id == 2 then mon.setCursorPos(W/2, 2) -- Top
elseif p.id == 3 then mon.setCursorPos(2, H/2) -- Left
elseif p.id == 4 then mon.setCursorPos(W-2, H/2) -- Right
end
mon.write(tostring(p.score))
end
mon.setBackgroundColor(COLORS.BALL)
mon.setCursorPos(math.floor(ball.x), math.floor(ball.y))
mon.write(" ")
if winner then
mon.setBackgroundColor(COLORS.BG)
mon.setTextColor(winner.color)
local msg = "WINNER: P" .. winner.id
mon.setCursorPos(W/2 - #msg/2, H/2)
mon.write(msg)
end
end,
onButton = function(self, a, btn)
if btn == "left" then running = true end
if btn == "center" then
self:resetBall()
for _, p in ipairs(players) do
p.score = MAX_SCORE
p.alive = true
p.color = (p.id==1 and COLORS.P1) or (p.id==2 and COLORS.P2) or (p.id==3 and COLORS.P3) or (p.id==4 and COLORS.P4)
end
winner = nil
running = false
end
if btn == "right" then a:requestQuit() end
end,
draw = function(self, a)
self:drawDirect()
end
}
arcade.start(game, {tickSeconds = 0.05})]]
files["arcade/license_store.lua"] = [[local LicenseStore = {}
LicenseStore.__index = LicenseStore
local function ensureDirectory(path)
if not fs.exists(path) then
fs.makeDir(path)
end
end
local function computeHash(input)
if textutils.sha256 then
return textutils.sha256(input)
end
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
return LicenseStore]]
files["arcade/store.lua"] = [[package.loaded["arcade"] = nil
package.loaded["log"] = nil
local function setupPaths()
local program = shell.getRunningProgram()
local dir = fs.getDir(program)
local root = fs.getDir(dir)
local function add(path)
local part = fs.combine(root, path)
local pattern = "/" .. fs.combine(part, "?.lua")
if not string.find(package.path, pattern, 1, true) then
package.path = package.path .. ";" .. pattern
end
end
add("lib")
add("arcade")
end
setupPaths()
local programs = require("data.programs")
local LicenseStore = require("license_store")
local CREDITS_FILE = "credits.txt"
local LICENSE_DIR = "licenses"
local function getDiskPath()
local drive = peripheral.find("drive")
if drive and drive.getMountPath then
return drive.getMountPath()
end
return nil
end
local function getCreditsPath()
local disk = getDiskPath()
if disk then return fs.combine(disk, CREDITS_FILE) end
return CREDITS_FILE
end
local function loadCredits()
local path = getCreditsPath()
if fs.exists(path) then
local f = fs.open(path, "r")
if f then
local n = tonumber(f.readAll())
f.close()
return n or 0
end
end
return 0
end
local function saveCredits(amount)
local path = getCreditsPath()
local f = fs.open(path, "w")
if f then
f.write(tostring(amount))
f.close()
end
end
local function getLicenseStore()
local disk = getDiskPath()
local root = disk or ""
local path = fs.combine(root, LICENSE_DIR)
return LicenseStore.new(path)
end
local function isInstalled(item)
local path = fs.combine("arcade", item.path)
return fs.exists(path)
end
local function downloadItem(item)
if not http then return false, "HTTP API disabled" end
if not item.url then return false, "No URL" end
local response = http.get(item.url)
if not response then return false, "Connection failed" end
local content = response.readAll()
response.close()
local path = fs.combine("arcade", item.path)
local dir = fs.getDir(path)
if not fs.exists(dir) then fs.makeDir(dir) end
local f = fs.open(path, "w")
if f then
f.write(content)
f.close()
return true
end
return false, "Write failed"
end
local w, h = term.getSize()
local selectedIndex = 1
local scrollOffset = 0
local credits = loadCredits()
local licenseStore = getLicenseStore()
local function drawHeader()
term.setCursorPos(1, 1)
term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
term.clearLine()
term.write(" App Store")
local cStr = "Credits: " .. credits
term.setCursorPos(w - #cStr, 1)
term.write(cStr)
end
local function drawList(items)
local listH = h - 2 -- Header and footer
for i = 1, listH do
local idx = i + scrollOffset
local item = items[idx]
local y = i + 1
term.setCursorPos(1, y)
term.setBackgroundColor(colors.black)
term.clearLine()
if item then
if idx == selectedIndex then
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
else
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
end
local status = ""
if isInstalled(item) then
status = "Installed"
elseif licenseStore:has(item.id) then
status = "Owned"
else
status = item.price .. " C"
end
local label = " " .. item.name
term.write(label)
term.setCursorPos(w - #status - 1, y)
term.write(status)
end
end
end
local function drawFooter()
term.setCursorPos(1, h)
term.setBackgroundColor(colors.gray)
term.setTextColor(colors.white)
term.clearLine()
term.write(" Enter: Details/Buy  Q: Quit")
end
local function showDetails(item)
term.setBackgroundColor(colors.blue)
term.clear()
local function center(y, text, bg, fg)
term.setCursorPos(math.floor((w - #text) / 2) + 1, y)
if bg then term.setBackgroundColor(bg) end
if fg then term.setTextColor(fg) end
term.write(text)
end
local bw, bh = 26, 12
local bx = math.floor((w - bw) / 2) + 1
local by = math.floor((h - bh) / 2) + 1
paintutils.drawFilledBox(bx, by, bx + bw - 1, by + bh - 1, colors.lightGray)
paintutils.drawFilledBox(bx, by, bx + bw - 1, by, colors.cyan)
term.setCursorPos(bx + 1, by)
term.setTextColor(colors.black)
term.setBackgroundColor(colors.cyan)
term.write(item.name)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
local desc = item.description or "No description."
local lines = {}
local line = ""
for word in desc:gmatch("%S+") do
if #line + #word + 1 > bw - 2 then
table.insert(lines, line)
line = word
else
if #line > 0 then line = line .. " " .. word else line = word end
end
end
table.insert(lines, line)
for i, l in ipairs(lines) do
if i > 5 then break end
term.setCursorPos(bx + 1, by + 1 + i)
term.write(l)
end
local owned = licenseStore:has(item.id)
local installed = isInstalled(item)
local price = item.price or 0
local action = ""
if installed then
action = "Re-download"
elseif owned then
action = "Download"
else
action = "Buy (" .. price .. ")"
end
term.setCursorPos(bx + 1, by + bh - 3)
term.write("Status: " .. (installed and "Installed" or (owned and "Owned" or "Available")))
term.setCursorPos(bx + 2, by + bh - 2)
term.setBackgroundColor(colors.green)
term.setTextColor(colors.white)
term.write(" " .. action .. " ")
term.setBackgroundColor(colors.blue)
while true do
local ev, p1 = os.pullEvent()
if ev == "key" then
if p1 == keys.enter or p1 == keys.space then
if not owned and not installed then
if credits >= price then
credits = credits - price
saveCredits(credits)
licenseStore:save(item.id, price, "store purchase")
owned = true
else
term.setCursorPos(bx + 2, by + bh - 1)
term.setBackgroundColor(colors.red)
term.write(" Not enough credits! ")
os.sleep(1)
return
end
end
term.setCursorPos(bx + 2, by + bh - 1)
term.setBackgroundColor(colors.yellow)
term.setTextColor(colors.black)
term.write(" Downloading... ")
local ok, err = downloadItem(item)
if ok then
term.setCursorPos(bx + 2, by + bh - 1)
term.setBackgroundColor(colors.green)
term.write(" Success! ")
else
term.setCursorPos(bx + 2, by + bh - 1)
term.setBackgroundColor(colors.red)
term.write(" Error: " .. (err or "?") .. " ")
end
os.sleep(1)
return
elseif p1 == keys.q or p1 == keys.backspace then
return
end
end
end
end
local function main()
local items = {}
for _, p in ipairs(programs) do
if p.id ~= "store" then
table.insert(items, p)
end
end
while true do
drawHeader()
drawList(items)
drawFooter()
local ev, p1, p2, p3 = os.pullEvent()
if ev == "key" then
if p1 == keys.up then
selectedIndex = selectedIndex - 1
if selectedIndex < 1 then selectedIndex = 1 end
if selectedIndex <= scrollOffset then scrollOffset = selectedIndex - 1 end
elseif p1 == keys.down then
selectedIndex = selectedIndex + 1
if selectedIndex > #items then selectedIndex = #items end
if selectedIndex > scrollOffset + (h - 2) then scrollOffset = selectedIndex - (h - 2) end
elseif p1 == keys.enter then
showDetails(items[selectedIndex])
credits = loadCredits()
licenseStore = getLicenseStore()
term.setBackgroundColor(colors.black)
term.clear()
elseif p1 == keys.q then
break
end
elseif ev == "mouse_scroll" then
if p1 > 0 then
selectedIndex = selectedIndex + 1
if selectedIndex > #items then selectedIndex = #items end
if selectedIndex > scrollOffset + (h - 2) then scrollOffset = selectedIndex - (h - 2) end
elseif p1 < 0 then
selectedIndex = selectedIndex - 1
if selectedIndex < 1 then selectedIndex = 1 end
if selectedIndex <= scrollOffset then scrollOffset = selectedIndex - 1 end
end
end
end
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
end
main()]]
files["arcade/ui/renderer.lua"] = [[local Renderer = {}
Renderer.__index = Renderer
local function toBlit(color)
if colors.toBlit then return colors.toBlit(color) end
local idx = math.floor(math.log(color, 2))
return ("0123456789abcdef"):sub(idx + 1, idx + 1)
end
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
local ok, pine3d = pcall(require, "pine3d")
if not ok or type(pine3d) ~= "table" then return nil end
local okTexture, texture = pcall(function()
local canvasBuilder = pine3d.newCanvas or pine3d.canvas or pine3d.newRenderer
if not canvasBuilder then return nil end
local canvas = canvasBuilder(width, height)
if canvas.clear then canvas:clear(baseColor) end
if canvas.polygon then
canvas:polygon({0, 0}, {width - 1, 1}, {width - 2, height - 1}, {0, height - 2}, accentColor)
canvas:polygon({2, 0}, {width - 1, 0}, {width - 1, height - 1}, {3, height - 2}, colors.black)
end
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
function Renderer:drawLabelCentered(x, y, w, text, color, shadowColor)
if not text or text == "" then return end
local tx = x + math.floor((w - #text) / 2)
if shadowColor then
term.setTextColor(shadowColor)
term.setCursorPos(tx + 1, y + 1)
term.write(text)
end
term.setTextColor(color or colors.white)
term.setCursorPos(tx, y)
term.write(text)
end
function Renderer:drawButton(rect, label, enabled)
local skin = enabled and self.skin.buttons.enabled or self.skin.buttons.disabled
self:drawTextureRect(skin.texture, rect.x, rect.y, rect.w, rect.h)
self:drawLabelCentered(rect.x, rect.y + math.floor(rect.h / 2), rect.w, label, skin.labelColor, skin.shadowColor)
end
function Renderer:paintSurface(rect, surface)
if type(surface) == "table" then
self:drawTextureRect(surface, rect.x, rect.y, rect.w, rect.h)
else
self:fillRect(rect.x, rect.y, rect.w, rect.h, surface or colors.black)
end
end
function Renderer.defaultSkin()
return buildDefaultSkin()
end
function Renderer.mergeSkin(base, override)
return deepMerge(base, override)
end
return Renderer]]
files["factory_planner.lua"] = [[local filename = "factory_schema.lua"
local diskPath = "disk/" .. filename
local gridWidth = 20
local gridHeight = 15
local cellSize = 1 -- 1x1 char per cell? Or maybe 2x1 for square-ish look?
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
local grid = {} -- 2D array [y][x] = paletteIndex
local selectedPaletteIndex = 2 -- Default to Stone
local clipboard = nil
local isRunning = true
local message = "Welcome to Factory Planner"
local messageTimer = 0
for y = 1, gridHeight do
grid[y] = {}
for x = 1, gridWidth do
grid[y][x] = 1 -- Air
end
end
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
local function draw()
clear()
local startX = 2
local startY = 2
drawRect(startX - 1, startY - 1, gridWidth + 2, gridHeight + 2, colors.white)
drawRect(startX, startY, gridWidth, gridHeight, colors.black)
for y = 1, gridHeight do
for x = 1, gridWidth do
local itemIndex = grid[y][x]
local item = palette[itemIndex]
drawText(startX + x - 1, startY + y - 1, item.char, item.color, colors.black)
end
end
local palX = startX + gridWidth + 3
local palY = 2
drawText(palX, palY - 1, "Palette:", colors.white, colors.black)
for i, item in ipairs(palette) do
local prefix = (i == selectedPaletteIndex) and "> " or "  "
drawText(palX, palY + i - 1, prefix .. item.char .. " " .. item.label, item.color, colors.black)
end
local helpX = palX
local helpY = palY + #palette + 2
drawText(helpX, helpY, "Controls:", colors.white, colors.black)
drawText(helpX, helpY + 1, "L-Click: Paint", colors.lightGray, colors.black)
drawText(helpX, helpY + 2, "R-Click: Erase", colors.lightGray, colors.black)
drawText(helpX, helpY + 3, "C: Copy Grid", colors.lightGray, colors.black)
drawText(helpX, helpY + 4, "V: Paste Grid", colors.lightGray, colors.black)
drawText(helpX, helpY + 5, "S: Save to Disk", colors.lightGray, colors.black)
drawText(helpX, helpY + 6, "Q: Quit", colors.lightGray, colors.black)
if messageTimer > 0 then
drawText(2, gridHeight + 4, message, colors.yellow, colors.black)
end
end
local function saveSchema()
local data = {
width = gridWidth,
height = gridHeight,
palette = palette,
grid = grid
}
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
while isRunning do
draw()
local event, p1, p2, p3 = os.pullEvent()
if event == "mouse_click" or event == "mouse_drag" then
handleMouse(p1, p2, p3)
elseif event == "key" then
handleKey(p1)
elseif event == "timer" then
if p1 == messageTimerId then
end
end
if messageTimer > 0 then
messageTimer = messageTimer - 1
end
end
clear()
print("Exited Factory Planner")]]
files["factory/factory.lua"] = [[local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")
local debug = debug
local function requireForce(name)
package.loaded[name] = nil
return require(name)
end
local states = {
INITIALIZE = requireForce("state_initialize"),
CHECK_REQUIREMENTS = requireForce("state_check_requirements"),
BUILD = requireForce("state_build"),
MINE = requireForce("state_mine"),
TREEFARM = requireForce("state_treefarm"),
POTATOFARM = requireForce("state_potatofarm"),
RESTOCK = requireForce("state_restock"),
REFUEL = requireForce("state_refuel"),
BLOCKED = requireForce("state_blocked"),
ERROR = requireForce("state_error"),
DONE = requireForce("state_done"),
}
local function mergeTables(base, extra)
if type(base) ~= "table" then
base = {}
end
if type(extra) == "table" then
for key, value in pairs(extra) do
base[key] = value
end
end
return base
end
local function buildPayload(ctx, extra)
local payload = { context = diagnostics.snapshot(ctx) }
if extra then
mergeTables(payload, extra)
end
return payload
end
local function run(args)
local ctx = {
state = "INITIALIZE",
config = {
verbose = false,
schemaPath = nil,
},
origin = { x = 0, y = 0, z = 0, facing = "north" },
pointer = 1,
schema = nil,
strategy = nil,
inventoryState = {},
fuelState = {},
retries = 0,
}
local index = 1
while index <= #args do
local value = args[index]
if value == "--verbose" then
ctx.config.verbose = true
elseif value == "mine" then
ctx.config.mode = "mine"
elseif value == "tunnel" then
ctx.config.mode = "tunnel"
elseif value == "excavate" then
ctx.config.mode = "excavate"
elseif value == "treefarm" then
ctx.config.mode = "treefarm"
elseif value == "potatofarm" then
ctx.config.mode = "potatofarm"
elseif value == "farm" then
ctx.config.mode = "farm"
elseif value == "--farm-type" then
index = index + 1
ctx.config.farmType = args[index]
elseif value == "--width" then
index = index + 1
ctx.config.width = tonumber(args[index])
elseif value == "--height" then
index = index + 1
ctx.config.height = tonumber(args[index])
elseif value == "--depth" then
index = index + 1
ctx.config.depth = tonumber(args[index])
elseif value == "--length" then
index = index + 1
ctx.config.length = tonumber(args[index])
elseif value == "--branch-interval" then
index = index + 1
ctx.config.branchInterval = tonumber(args[index])
elseif value == "--branch-length" then
index = index + 1
ctx.config.branchLength = tonumber(args[index])
elseif value == "--torch-interval" then
index = index + 1
ctx.config.torchInterval = tonumber(args[index])
elseif not value:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
ctx.config.schemaPath = value
end
index = index + 1
end
if not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
ctx.config.schemaPath = "schema.json"
end
local logOpts = {
level = ctx.config.verbose and "debug" or "info",
timestamps = true
}
logger.attach(ctx, logOpts)
ctx.logger:info("Agent starting...")
if turtle and turtle.getFuelLevel then
local level = turtle.getFuelLevel()
local limit = turtle.getFuelLimit()
ctx.logger:info(string.format("Fuel: %s / %s", tostring(level), tostring(limit)))
if level ~= "unlimited" and type(level) == "number" and level < 100 then
ctx.logger:warn("Fuel is very low on startup!")
local fuelLib = require("lib_fuel")
fuelLib.refuel(ctx, { target = 2000 })
end
end
while ctx.state ~= "EXIT" do
local stateHandler = states[ctx.state]
if not stateHandler then
ctx.logger:error("Unknown state: " .. tostring(ctx.state), buildPayload(ctx))
break
end
ctx.logger:debug("Entering state: " .. ctx.state)
local ok, nextStateOrErr = pcall(stateHandler, ctx)
if not ok then
local trace = debug and debug.traceback and debug.traceback() or nil
ctx.logger:error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr),
buildPayload(ctx, { error = tostring(nextStateOrErr), traceback = trace }))
ctx.lastError = nextStateOrErr
ctx.state = "ERROR"
else
if type(nextStateOrErr) ~= "string" or nextStateOrErr == "" then
ctx.logger:error("State returned invalid transition", buildPayload(ctx, { result = tostring(nextStateOrErr) }))
ctx.lastError = nextStateOrErr
ctx.state = "ERROR"
elseif not states[nextStateOrErr] and nextStateOrErr ~= "EXIT" then
ctx.logger:error("Transitioned to unknown state: " .. tostring(nextStateOrErr), buildPayload(ctx))
ctx.state = "ERROR"
else
ctx.state = nextStateOrErr
end
end
sleep(0)
end
ctx.logger:info("Agent finished.")
end
local module = { run = run }
if not _G.__FACTORY_EMBED__ then
local argv = { ... }
run(argv)
end
return module]]
files["factory/main.lua"] = [[if not string.find(package.path, "/lib/?.lua") then
package.path = package.path .. ";/?.lua;/lib/?.lua;/arcade/?.lua;/factory/?.lua"
end
local logger = require("lib_logger")
local movement = require("lib_movement")
local ui = require("lib_ui")
local trash_config = require("ui.trash_config")
local function interactiveSetup(ctx)
local mode = "treefarm"
local width = 9
local height = 9
local length = 60
local branchInterval = 3
local branchLength = 16
local torchInterval = 6
local selected = 1
while true do
ui.clear()
ui.drawFrame(2, 2, 30, 16, "Factory Setup")
ui.label(4, 4, "Mode: ")
local modeLabel = "Tree"
if mode == "potatofarm" then modeLabel = "Potato" end
if mode == "mine" then modeLabel = "Mine" end
if selected == 1 then
if term.isColor() then term.setTextColor(colors.yellow) end
term.write("< " .. modeLabel .. " >")
else
if term.isColor() then term.setTextColor(colors.white) end
term.write("  " .. modeLabel .. "  ")
end
local startIdx = 4
if mode == "treefarm" or mode == "potatofarm" then
startIdx = 4
ui.label(4, 6, "Width: ")
if selected == 2 then
if term.isColor() then term.setTextColor(colors.yellow) end
term.write("< " .. width .. " >")
else
if term.isColor() then term.setTextColor(colors.white) end
term.write("  " .. width .. "  ")
end
ui.label(4, 8, "Height:")
if selected == 3 then
if term.isColor() then term.setTextColor(colors.yellow) end
term.write("< " .. height .. " >")
else
if term.isColor() then term.setTextColor(colors.white) end
term.write("  " .. height .. "  ")
end
elseif mode == "mine" then
startIdx = 7
ui.label(4, 6, "Length: ")
if selected == 2 then
if term.isColor() then term.setTextColor(colors.yellow) end
term.write("< " .. length .. " >")
else
if term.isColor() then term.setTextColor(colors.white) end
term.write("  " .. length .. "  ")
end
ui.label(4, 7, "Br. Int:")
if selected == 3 then
if term.isColor() then term.setTextColor(colors.yellow) end
term.write("< " .. branchInterval .. " >")
else
if term.isColor() then term.setTextColor(colors.white) end
term.write("  " .. branchInterval .. "  ")
end
ui.label(4, 8, "Br. Len:")
if selected == 4 then
if term.isColor() then term.setTextColor(colors.yellow) end
term.write("< " .. branchLength .. " >")
else
if term.isColor() then term.setTextColor(colors.white) end
term.write("  " .. branchLength .. "  ")
end
ui.label(4, 9, "Torch Int:")
if selected == 5 then
if term.isColor() then term.setTextColor(colors.yellow) end
term.write("< " .. torchInterval .. " >")
else
if term.isColor() then term.setTextColor(colors.white) end
term.write("  " .. torchInterval .. "  ")
end
ui.label(4, 10, "Trash:")
if selected == 6 then
if term.isColor() then term.setTextColor(colors.yellow) end
term.write(" < EDIT > ")
else
if term.isColor() then term.setTextColor(colors.white) end
term.write("   EDIT   ")
end
end
ui.button(8, 12, "START", selected == startIdx)
local event, key = os.pullEvent("key")
if key == keys.up then
selected = selected - 1
if selected < 1 then selected = startIdx end
elseif key == keys.down then
selected = selected + 1
if selected > startIdx then selected = 1 end
elseif key == keys.left then
if selected == 1 then
if mode == "treefarm" then mode = "potatofarm"
elseif mode == "potatofarm" then mode = "mine"
else mode = "treefarm" end
selected = 1
end
if mode == "treefarm" or mode == "potatofarm" then
if selected == 2 then width = math.max(1, width - 1) end
if selected == 3 then height = math.max(1, height - 1) end
elseif mode == "mine" then
if selected == 2 then length = math.max(10, length - 10) end
if selected == 3 then branchInterval = math.max(1, branchInterval - 1) end
if selected == 4 then branchLength = math.max(1, branchLength - 1) end
if selected == 5 then torchInterval = math.max(1, torchInterval - 1) end
end
elseif key == keys.right then
if selected == 1 then
if mode == "treefarm" then mode = "mine"
elseif mode == "mine" then mode = "potatofarm"
else mode = "treefarm" end
selected = 1
end
if mode == "treefarm" or mode == "potatofarm" then
if selected == 2 then width = width + 1 end
if selected == 3 then height = height + 1 end
elseif mode == "mine" then
if selected == 2 then length = length + 10 end
if selected == 3 then branchInterval = branchInterval + 1 end
if selected == 4 then branchLength = branchLength + 1 end
if selected == 5 then torchInterval = torchInterval + 1 end
end
elseif key == keys.enter then
if selected == startIdx then
return {
mode = mode,
width = width,
height = height,
length = length,
branchInterval = branchInterval,
branchLength = branchLength,
torchInterval = torchInterval
}
elseif mode == "mine" and selected == 6 then
trash_config.run()
end
end
end
end
local states = {
INITIALIZE = require("state_initialize"),
BUILD = require("state_build"),
MINE = require("state_mine"),
RESTOCK = require("state_restock"),
REFUEL = require("state_refuel"),
BLOCKED = require("state_blocked"),
ERROR = require("state_error"),
DONE = require("state_done"),
CHECK_REQUIREMENTS = require("state_check_requirements"),
TREEFARM = require("state_treefarm"),
POTATOFARM = require("state_potatofarm"),
BRANCHMINE = require("state_branchmine")
}
local function main(args)
local ctx = {
state = "INITIALIZE",
config = {
verbose = false,
schemaPath = nil
},
origin = { x=0, y=0, z=0, facing="north" }, -- Default home
pointer = 1, -- Current step in the build path
schema = nil, -- Will be loaded by INITIALIZE
strategy = nil, -- Will be computed by INITIALIZE
inventoryState = {},
fuelState = {},
retries = 0
}
local i = 1
while i <= #args do
local arg = args[i]
if arg == "--verbose" then
ctx.config.verbose = true
elseif arg == "mine" then
ctx.config.mode = "mine"
elseif arg == "treefarm" then
ctx.config.mode = "treefarm"
elseif arg == "potatofarm" then
ctx.config.mode = "potatofarm"
elseif arg == "--length" then
i = i + 1
ctx.config.length = tonumber(args[i])
elseif arg == "--width" then
i = i + 1
ctx.config.width = tonumber(args[i])
elseif arg == "--height" then
i = i + 1
ctx.config.height = tonumber(args[i])
elseif arg == "--branch-interval" then
i = i + 1
ctx.config.branchInterval = tonumber(args[i])
elseif arg == "--branch-length" then
i = i + 1
ctx.config.branchLength = tonumber(args[i])
elseif arg == "--torch-interval" then
i = i + 1
ctx.config.torchInterval = tonumber(args[i])
elseif not arg:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
ctx.config.schemaPath = arg
end
i = i + 1
end
if #args == 0 then
local setupConfig = interactiveSetup(ctx)
for k, v in pairs(setupConfig) do
ctx.config[k] = v
end
end
if not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
ctx.config.schemaPath = "schema.json"
end
ctx.logger = logger.new({
level = ctx.config.verbose and "debug" or "info"
})
ctx.logger:info("Agent starting...")
while ctx.state ~= "EXIT" do
local currentStateFunc = states[ctx.state]
if not currentStateFunc then
ctx.logger:error("Unknown state: " .. tostring(ctx.state))
break
end
ctx.logger:debug("Entering state: " .. ctx.state)
local ok, nextStateOrErr = pcall(currentStateFunc, ctx)
if not ok then
ctx.logger:error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr))
ctx.lastError = nextStateOrErr
ctx.state = "ERROR"
else
ctx.state = nextStateOrErr
end
sleep(0) -- Yield to avoid "Too long without yielding"
end
ctx.logger:info("Agent finished.")
if ctx.lastError then
print("Agent finished: " .. tostring(ctx.lastError))
else
print("Agent finished: success!")
end
end
local args = { ... }
main(args)]]
files["factory/state_blocked.lua"] = [[local logger = require("lib_logger")
local function BLOCKED(ctx)
local resume = ctx.resumeState or "BUILD"
logger.log(ctx, "warn", string.format("Movement blocked while executing %s. Retrying in 5 seconds...", resume))
sleep(5)
ctx.retries = (ctx.retries or 0) + 1
if ctx.retries > 5 then
local message = string.format("Too many retries while resuming %s", resume)
logger.log(ctx, "error", message)
ctx.lastError = message
ctx.resumeState = nil
return "ERROR"
end
ctx.resumeState = nil
return resume
end
return BLOCKED]]
files["factory/state_branchmine.lua"] = [[local movement = require("lib_movement")
local inventory = require("lib_inventory")
local mining = require("lib_mining")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local startup = require("lib_startup")
local OPPOSITE = {
north = "south",
south = "north",
east = "west",
west = "east"
}
local function ensureSpineAnchor(ctx, bm)
if not bm then
return
end
if not bm.spineInitialized then
local pos = movement.getPosition(ctx)
bm.spineY = bm.spineY or pos.y
bm.spineFacing = bm.spineFacing or movement.getFacing(ctx)
bm.spineInitialized = true
end
end
local function verifyOutputChest(ctx, bm)
if not bm or bm.chestVerified then
return true
end
local dir = bm.chests and bm.chests.output
if not dir then
logger.log(ctx, "warn", "Output chest direction missing; skipping verification.")
bm.chestVerified = true
return true
end
local spineFacing = bm.spineFacing or movement.getFacing(ctx)
local ok, err = movement.face(ctx, dir)
if not ok then
return false, "Unable to face output chest (" .. tostring(err) .. ")"
end
sleep(0.1)
local hasBlock, data = turtle.inspect()
local restoreFacing = spineFacing or movement.getFacing(ctx) or "north"
local restored, restoreErr = movement.face(ctx, restoreFacing)
if not restored then
logger.log(ctx, "error", "Failed to restore facing after chest verification: " .. tostring(restoreErr))
return false, "Failed to restore facing: " .. tostring(restoreErr)
end
if not hasBlock then
return false, "Missing output chest on " .. dir
end
local name = data and data.name or "unknown block"
if not name:find("chest") and not name:find("barrel") then
return false, string.format("Expected chest on %s but found %s", dir, name)
end
bm.chestVerified = true
return true
end
local function selectTorch(ctx)
local torchItem = ctx.config.torchItem or "minecraft:torch"
local ok = inventory.selectMaterial(ctx, torchItem)
if ok then
return true, torchItem
end
ctx.missingMaterial = torchItem
return false, torchItem
end
local function placeTorch(ctx)
local ok, item = selectTorch(ctx)
if not ok then
logger.log(ctx, "warn", "No torches to place (missing " .. tostring(item) .. ")")
return false
end
if turtle.placeDown() then return true end
if turtle.placeUp() then return true end
if turtle.digDown() then
if turtle.placeDown() then
return true
end
end
movement.turnRight(ctx)
if turtle.detect() then
turtle.dig()
end
if turtle.place() then
movement.turnLeft(ctx)
return true
end
movement.turnLeft(ctx) -- Restore facing
movement.turnLeft(ctx)
if turtle.detect() then
turtle.dig()
end
if turtle.place() then
movement.turnRight(ctx)
return true
end
movement.turnRight(ctx) -- Restore facing
movement.turnRight(ctx)
movement.turnRight(ctx)
if turtle.place() then
movement.turnRight(ctx)
movement.turnRight(ctx)
return true
end
movement.turnRight(ctx)
movement.turnRight(ctx)
logger.log(ctx, "warn", "Failed to place torch (all strategies failed).")
return false
end
local function dumpTrash(ctx)
inventory.condense(ctx)
inventory.scan(ctx)
local state = ctx.inventory
if not state or not state.slots then return end
for slot, item in pairs(state.slots) do
if mining.TRASH_BLOCKS[item.name] and not item.name:find("torch") and not item.name:find("chest") then
turtle.select(slot)
turtle.drop()
end
end
end
local function orientByChests(ctx, chests)
if not chests then return false end
logger.log(ctx, "info", "Auto-orienting based on chests...")
local surroundings = {}
for i = 0, 3 do
local hasBlock, data = turtle.inspect()
if hasBlock and (data.name:find("chest") or data.name:find("barrel")) then
surroundings[i] = true
else
surroundings[i] = false
end
turtle.turnRight()
end
local CARDINALS = {"north", "east", "south", "west"}
local bestScore = -1
local bestFacing = nil
for i, candidate in ipairs(CARDINALS) do
local score = 0
for name, dir in pairs(chests) do
local dirIdx = -1
for k, v in ipairs(CARDINALS) do if v == dir then dirIdx = k break end end
local candIdx = i
if dirIdx ~= -1 then
local offset = (dirIdx - candIdx) % 4
if surroundings[offset] then
score = score + 1
end
end
end
if score > bestScore then
bestScore = score
bestFacing = candidate
end
end
if bestFacing and bestScore > 0 then
logger.log(ctx, "info", "Oriented to " .. bestFacing .. " (Score: " .. bestScore .. ")")
ctx.movement = ctx.movement or {}
ctx.movement.facing = bestFacing
ctx.origin = ctx.origin or {}
ctx.origin.facing = bestFacing
return true
else
logger.log(ctx, "warn", "Could not determine orientation from chests.")
return false
end
end
local function BRANCHMINE(ctx)
local bm = ctx.branchmine
if not bm then return "INITIALIZE" end
if bm.state == "SPINE" and bm.currentDist == 0 then
if not bm.oriented then
orientByChests(ctx, bm.chests)
bm.oriented = true
bm.spineInitialized = false
end
if bm.chests and bm.chests.output then
local outDir = bm.chests.output
local mineDir = OPPOSITE[outDir]
if mineDir then
local current = movement.getFacing(ctx)
if current ~= mineDir then
logger.log(ctx, "info", "Aligning to mine shaft: " .. mineDir)
movement.faceDirection(ctx, mineDir)
bm.spineInitialized = false
end
end
end
end
ensureSpineAnchor(ctx, bm)
if not startup.runFuelCheck(ctx, bm.chests, 100, 1000) then
return "BRANCHMINE"
end
if bm.state == "SPINE" then
if bm.currentDist >= bm.length then
bm.state = "RETURN"
return "BRANCHMINE"
end
if not bm.chestVerified then
local ok, err = verifyOutputChest(ctx, bm)
if not ok then
local message = err or "Output chest verification failed"
logger.log(ctx, "error", message)
ctx.lastError = message
return "ERROR"
end
end
local isNewGround = turtle.detect()
if not movement.forward(ctx, { dig = true }) then
logger.log(ctx, "warn", "Blocked on spine.")
return "BRANCHMINE" -- Retry
end
while turtle.detectUp() do
if turtle.digUp() then
turtle.suckUp()
else
break
end
sleep(0.5)
end
bm.currentDist = bm.currentDist + 1
if isNewGround then
mining.scanAndMineNeighbors(ctx)
end
if bm.currentDist % bm.torchInterval == 0 then
placeTorch(ctx)
end
if bm.currentDist % 5 == 0 then
dumpTrash(ctx)
end
if bm.currentDist % bm.branchInterval == 0 then
bm.state = "BRANCH_LEFT_INIT"
end
return "BRANCHMINE"
elseif bm.state == "BRANCH_LEFT_INIT" then
movement.turnLeft(ctx)
bm.branchDist = 0
bm.state = "BRANCH_LEFT_OUT"
return "BRANCHMINE"
elseif bm.state == "BRANCH_LEFT_OUT" then
if bm.branchDist >= bm.branchLength then
bm.state = "BRANCH_LEFT_UP"
return "BRANCHMINE"
end
local isNewGround = turtle.detect()
if not movement.forward(ctx, { dig = true }) then
logger.log(ctx, "warn", "Branch blocked. Returning.")
bm.state = "BRANCH_LEFT_RETURN"
return "BRANCHMINE"
end
bm.branchDist = bm.branchDist + 1
mining.scanAndMineNeighbors(ctx)
return "BRANCHMINE"
elseif bm.state == "BRANCH_LEFT_UP" then
local moved = movement.up(ctx)
if not moved then
turtle.digUp()
moved = movement.up(ctx)
end
if moved then
mining.scanAndMineNeighbors(ctx)
end
bm.state = "BRANCH_LEFT_RETURN"
return "BRANCHMINE"
elseif bm.state == "BRANCH_LEFT_RETURN" then
if not bm.returning then
movement.turnAround(ctx)
bm.returning = true
bm.returnDist = 0
end
if bm.returnDist >= bm.branchDist then
bm.returning = false
local downRetries = 0
while movement.getPosition(ctx).y > bm.spineY do
if not movement.down(ctx) then
turtle.digDown()
end
downRetries = downRetries + 1
if downRetries > 20 then
logger.log(ctx, "warn", "Failed to descend to spine level. Aborting return.")
break
end
end
movement.turnLeft(ctx)
bm.state = "BRANCH_RIGHT_INIT"
return "BRANCHMINE"
end
if not movement.forward(ctx) then
turtle.dig()
movement.forward(ctx)
end
if movement.getPosition(ctx).y > bm.spineY then
mining.scanAndMineNeighbors(ctx)
end
bm.returnDist = bm.returnDist + 1
return "BRANCHMINE"
elseif bm.state == "BRANCH_RIGHT_INIT" then
movement.turnRight(ctx)
bm.branchDist = 0
bm.state = "BRANCH_RIGHT_OUT"
return "BRANCHMINE"
elseif bm.state == "BRANCH_RIGHT_OUT" then
if bm.branchDist >= bm.branchLength then
bm.state = "BRANCH_RIGHT_UP"
return "BRANCHMINE"
end
local isNewGround = turtle.detect()
if not movement.forward(ctx, { dig = true }) then
logger.log(ctx, "warn", "Branch blocked. Returning.")
bm.state = "BRANCH_RIGHT_RETURN"
return "BRANCHMINE"
end
bm.branchDist = bm.branchDist + 1
mining.scanAndMineNeighbors(ctx)
return "BRANCHMINE"
elseif bm.state == "BRANCH_RIGHT_UP" then
local moved = movement.up(ctx)
if not moved then
turtle.digUp()
moved = movement.up(ctx)
end
if moved then
mining.scanAndMineNeighbors(ctx)
end
bm.state = "BRANCH_RIGHT_RETURN"
return "BRANCHMINE"
elseif bm.state == "BRANCH_RIGHT_RETURN" then
if not bm.returning then
movement.turnAround(ctx)
bm.returning = true
bm.returnDist = 0
end
if bm.returnDist >= bm.branchDist then
bm.returning = false
local downRetries = 0
while movement.getPosition(ctx).y > bm.spineY do
if not movement.down(ctx) then
turtle.digDown()
end
downRetries = downRetries + 1
if downRetries > 20 then
logger.log(ctx, "warn", "Failed to descend to spine level. Aborting return.")
break
end
end
movement.turnRight(ctx)
bm.state = "SPINE"
return "BRANCHMINE"
end
if not movement.forward(ctx) then
turtle.dig()
movement.forward(ctx)
end
if movement.getPosition(ctx).y > bm.spineY then
mining.scanAndMineNeighbors(ctx)
end
bm.returnDist = bm.returnDist + 1
return "BRANCHMINE"
elseif bm.state == "RETURN" then
logger.log(ctx, "info", "Mining done. Returning home.")
movement.goTo(ctx, {x=0, y=0, z=0})
return "DONE"
end
return "BRANCHMINE"
end
return BRANCHMINE]]
files["factory/state_build.lua"] = [[local movement = require("lib_movement")
local placement = require("lib_placement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local orientation = require("lib_orientation")
local diagnostics = require("lib_diagnostics")
local world = require("lib_world")
local startup = require("lib_startup")
local function BUILD(ctx)
local strategy, errMsg = diagnostics.requireStrategy(ctx)
if not strategy then
return "ERROR"
end
if ctx.pointer > #strategy then
return "DONE"
end
local step = strategy[ctx.pointer]
local material = step.block.material
if not startup.runFuelCheck(ctx, ctx.chests, 100, 1000) then
return "BUILD"
end
local count = inventory.countMaterial(ctx, material)
if count == 0 then
logger.log(ctx, "warn", "Out of material: " .. material)
ctx.missingMaterial = material
ctx.resumeState = "BUILD"
return "RESTOCK"
end
local targetPos = world.localToWorldRelative(ctx.origin, step.approachLocal)
local ok, err = movement.goTo(ctx, targetPos)
if not ok then
logger.log(ctx, "warn", "Movement blocked: " .. tostring(err))
ctx.resumeState = "BUILD"
return "BLOCKED"
end
local placed, placeErr = placement.placeMaterial(ctx, material, {
side = step.side,
block = step.block,
dig = true, -- Clear obstacles
attack = true
})
if not placed then
if placeErr == "already_present" then
else
local failureMsg = "Placement failed: " .. tostring(placeErr)
logger.log(ctx, "warn", failureMsg)
ctx.lastError = failureMsg
return "ERROR" -- For now, fail hard so we can debug.
end
end
ctx.pointer = ctx.pointer + 1
ctx.retries = 0
return "BUILD"
end
return BUILD]]
files["factory/state_check_requirements.lua"] = [[local inventory = require("lib_inventory")
local logger = require("lib_logger")
local fuel = require("lib_fuel")
local diagnostics = require("lib_diagnostics")
local movement = require("lib_movement")
local function calculateRequirements(ctx, strategy)
local reqs = {
fuel = 0,
materials = {}
}
if strategy then
reqs.fuel = #strategy
end
reqs.fuel = math.ceil(reqs.fuel * 1.1) + 100
if ctx.config.mode == "mine" then
for _, step in ipairs(strategy) do
if step.type == "place_torch" then
reqs.materials["minecraft:torch"] = (reqs.materials["minecraft:torch"] or 0) + 1
elseif step.type == "place_chest" then
reqs.materials["minecraft:chest"] = (reqs.materials["minecraft:chest"] or 0) + 1
end
end
else
for _, step in ipairs(strategy) do
if step.block and step.block.material then
local mat = step.block.material
reqs.materials[mat] = (reqs.materials[mat] or 0) + 1
end
end
end
return reqs
end
local function calculateBranchmineRequirements(ctx)
local bm = ctx.branchmine or {}
local length = tonumber(bm.length or ctx.config.length) or 60
local branchInterval = tonumber(bm.branchInterval or ctx.config.branchInterval) or 3
local branchLength = tonumber(bm.branchLength or ctx.config.branchLength) or 16
local torchInterval = tonumber(bm.torchInterval or ctx.config.torchInterval) or 6
branchInterval = math.max(branchInterval, 1)
torchInterval = math.max(torchInterval, 1)
branchLength = math.max(branchLength, 1)
local branchPairs = math.floor(length / branchInterval)
local branchTravel = branchPairs * (4 * branchLength + 4)
local totalTravel = length + branchTravel
local reqs = {
fuel = math.ceil(totalTravel * 1.1) + 100,
materials = {}
}
local torchItem = ctx.config.torchItem or "minecraft:torch"
local torchCount = math.max(1, math.floor(length / torchInterval))
reqs.materials[torchItem] = torchCount
return reqs
end
local function CHECK_REQUIREMENTS(ctx)
logger.log(ctx, "info", "Checking requirements...")
local reqs
if ctx.branchmine then
reqs = calculateBranchmineRequirements(ctx)
else
if ctx.config.mode == "mine" then
logger.log(ctx, "warn", "Branchmine context missing, re-initializing...")
ctx.branchmine = {
length = tonumber(ctx.config.length) or 60,
branchInterval = tonumber(ctx.config.branchInterval) or 3,
branchLength = tonumber(ctx.config.branchLength) or 16,
torchInterval = tonumber(ctx.config.torchInterval) or 6,
currentDist = 0,
state = "SPINE",
spineY = 0,
chests = ctx.chests
}
ctx.nextState = "BRANCHMINE"
reqs = calculateBranchmineRequirements(ctx)
else
local strategy, errMsg = diagnostics.requireStrategy(ctx)
if not strategy then
ctx.lastError = errMsg or "Strategy missing"
return "ERROR"
end
reqs = calculateRequirements(ctx, strategy)
end
end
local invCounts = inventory.getCounts(ctx)
local currentFuel = turtle.getFuelLevel()
if currentFuel == "unlimited" then currentFuel = 999999 end
if type(currentFuel) ~= "number" then currentFuel = 0 end
local missing = {
fuel = 0,
materials = {}
}
local hasMissing = false
if currentFuel < reqs.fuel then
print("Attempting to refuel to meet requirements...")
logger.log(ctx, "info", "Attempting to refuel to meet requirements...")
fuel.refuel(ctx, { target = reqs.fuel, excludeItems = { "minecraft:torch" } })
currentFuel = turtle.getFuelLevel()
if currentFuel == "unlimited" then currentFuel = 999999 end
if type(currentFuel) ~= "number" then currentFuel = 0 end
end
if currentFuel < reqs.fuel then
missing.fuel = reqs.fuel - currentFuel
hasMissing = true
end
for mat, count in pairs(reqs.materials) do
local have = invCounts[mat] or 0
if mat == "minecraft:chest" and have < count then
local totalChests = 0
for invMat, invCount in pairs(invCounts) do
if invMat:find("chest") or invMat:find("barrel") or invMat:find("shulker") then
totalChests = totalChests + invCount
end
end
if totalChests >= count then
have = count -- Satisfied
end
end
if have < count then
missing.materials[mat] = count - have
hasMissing = true
end
end
if hasMissing then
print("Checking nearby chests for missing items...")
if inventory.retrieveFromNearby(ctx, missing.materials) then
invCounts = inventory.getCounts(ctx)
hasMissing = false
missing.materials = {}
for mat, count in pairs(reqs.materials) do
local have = invCounts[mat] or 0
if have < count then
missing.materials[mat] = count - have
hasMissing = true
end
end
end
end
if not hasMissing then
logger.log(ctx, "info", "All requirements met.")
return ctx.nextState or "DONE"
end
print("\n=== MISSING REQUIREMENTS ===")
if missing.fuel > 0 then
print(string.format("- Fuel: %d (Have %d, Need %d)", missing.fuel, currentFuel, reqs.fuel))
end
for mat, count in pairs(missing.materials) do
print(string.format("- %s: %d", mat, count))
end
local nearby = inventory.checkNearby(ctx, missing.materials)
local foundNearby = false
for mat, count in pairs(nearby) do
if not foundNearby then
print("\n=== FOUND IN NEARBY CHESTS ===")
foundNearby = true
end
print(string.format("- %s: %d", mat, count))
end
print("\nPress Enter to re-check, or type 'q' then Enter to quit.")
local input = read()
if input == "q" or input == "Q" then
return "DONE"
end
return "CHECK_REQUIREMENTS"
end
return CHECK_REQUIREMENTS]]
files["factory/state_done.lua"] = [[local movement = require("lib_movement")
local logger = require("lib_logger")
local function DONE(ctx)
logger.log(ctx, "info", "Build complete!")
movement.goTo(ctx, ctx.origin)
return "EXIT"
end
return DONE]]
files["factory/state_error.lua"] = [[local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")
local function ERROR(ctx)
local message = tostring(ctx.lastError or "Unknown fatal error")
if ctx.logger then
ctx.logger:error("Fatal Error: " .. message)
else
logger.log(ctx, "error", "Fatal Error: " .. message)
end
local crashOk, crashResult = logger.writeCrashFile(ctx, message)
if crashOk and crashResult then
print("Crash details saved to " .. crashResult)
elseif not crashOk and crashResult then
logger.log(ctx, "warn", "Failed to write crash file: " .. tostring(crashResult))
end
print("Press Enter to exit...")
read()
return "EXIT"
end
return ERROR]]
files["factory/state_initialize.lua"] = [[local parser = require("lib_parser")
local orientation = require("lib_orientation")
local logger = require("lib_logger")
local strategyTunnel = require("lib_strategy_tunnel")
local strategyExcavate = require("lib_strategy_excavate")
local strategyFarm = require("lib_strategy_farm")
local ui = require("lib_ui")
local startup = require("lib_startup")
local inventory = require("lib_inventory")
local function validateSchema(schema)
if type(schema) ~= "table" then return false, "Schema is not a table" end
local count = 0
for _ in pairs(schema) do count = count + 1 end
if count == 0 then return false, "Schema is empty" end
return true
end
local function getBlock(schema, x, y, z)
local xLayer = schema[x] or schema[tostring(x)]
if not xLayer then return nil end
local yLayer = xLayer[y] or xLayer[tostring(y)]
if not yLayer then return nil end
return yLayer[z] or yLayer[tostring(z)]
end
local function isPlaceable(block)
if not block then return false end
local name = block.material
if not name or name == "" then return false end
if name == "minecraft:air" or name == "air" then return false end
return true
end
local function computeApproachLocal(localPos, side)
side = side or "down"
if side == "up" then
return { x = localPos.x, y = localPos.y - 1, z = localPos.z }, side
elseif side == "down" then
return { x = localPos.x, y = localPos.y + 1, z = localPos.z }, side
else
return { x = localPos.x, y = localPos.y, z = localPos.z }, side
end
end
local function computeLocalXZ(bounds, x, z, orientationKey)
local orient = orientation.resolveOrientationKey(orientationKey)
local relativeX = x - bounds.minX
local relativeZ = z - bounds.minZ
local localZ = - (relativeZ + 1)
local localX
if orient == "forward_right" then
localX = relativeX + 1
else
localX = - (relativeX + 1)
end
return localX, localZ
end
local function normaliseBounds(info)
if not info or not info.bounds then return nil, "missing_bounds" end
local minB = info.bounds.min
local maxB = info.bounds.max
if not (minB and maxB) then return nil, "missing_bounds" end
local function norm(t, k) return tonumber(t[k]) end
return {
minX = norm(minB, "x") or 0,
minY = norm(minB, "y") or 0,
minZ = norm(minB, "z") or 0,
maxX = norm(maxB, "x") or 0,
maxY = norm(maxB, "y") or 0,
maxZ = norm(maxB, "z") or 0,
}
end
local function buildOrder(schema, info, opts)
local bounds, err = normaliseBounds(info)
if not bounds then return nil, err or "missing_bounds" end
opts = opts or {}
local offsetLocal = opts.offsetLocal or { x = 0, y = 0, z = 0 }
local offsetXLocal = offsetLocal.x or 0
local offsetYLocal = offsetLocal.y or 0
local offsetZLocal = offsetLocal.z or 0
local orientKey = opts.orientation or "forward_left"
local order = {}
for y = bounds.minY, bounds.maxY do
for row = 0, bounds.maxZ - bounds.minZ do
local z = bounds.minZ + row
local forward = (row % 2) == 0
local xStart = forward and bounds.minX or bounds.maxX
local xEnd = forward and bounds.maxX or bounds.minX
local step = forward and 1 or -1
local x = xStart
while true do
local block = getBlock(schema, x, y, z)
if isPlaceable(block) then
local baseX, baseZ = computeLocalXZ(bounds, x, z, orientKey)
local localPos = {
x = baseX + offsetXLocal,
y = y + offsetYLocal,
z = baseZ + offsetZLocal,
}
local meta = (block and type(block.meta) == "table") and block.meta or nil
local side = (meta and meta.side) or "down"
local approach, resolvedSide = computeApproachLocal(localPos, side)
order[#order + 1] = {
schemaPos = { x = x, y = y, z = z },
localPos = localPos,
approachLocal = approach,
block = block,
side = resolvedSide,
}
end
if x == xEnd then break end
x = x + step
end
end
end
return order, bounds
end
local function INITIALIZE(ctx)
logger.log(ctx, "info", "Initializing...")
if not ctx.chests then
ctx.chests = startup.runChestSetup(ctx)
end
if not startup.runFuelCheck(ctx, ctx.chests) then
return "INITIALIZE"
end
if ctx.config.mode == "mine" then
logger.log(ctx, "info", "Starting Branch Mine mode...")
ctx.branchmine = {
length = tonumber(ctx.config.length) or 60,
branchInterval = tonumber(ctx.config.branchInterval) or 3,
branchLength = tonumber(ctx.config.branchLength) or 16,
torchInterval = tonumber(ctx.config.torchInterval) or 6,
currentDist = 0,
state = "SPINE",
spineY = 0, -- Assuming we start at 0 relative to start
chests = ctx.chests
}
ctx.nextState = "BRANCHMINE"
return "CHECK_REQUIREMENTS"
end
if ctx.config.mode == "tunnel" then
logger.log(ctx, "info", "Generating tunnel strategy...")
local length = tonumber(ctx.config.length) or 16
local width = tonumber(ctx.config.width) or 1
local height = tonumber(ctx.config.height) or 2
local torchInterval = tonumber(ctx.config.torchInterval) or 6
ctx.strategy = strategyTunnel.generate(length, width, height, torchInterval)
ctx.pointer = 1
logger.log(ctx, "info", string.format("Tunnel Plan: %d steps.", #ctx.strategy))
ctx.nextState = "MINE"
return "CHECK_REQUIREMENTS"
end
if ctx.config.mode == "excavate" then
logger.log(ctx, "info", "Generating excavation strategy...")
local length = tonumber(ctx.config.length) or 8
local width = tonumber(ctx.config.width) or 8
local depth = tonumber(ctx.config.depth) or 3
ctx.strategy = strategyExcavate.generate(length, width, depth)
ctx.pointer = 1
logger.log(ctx, "info", string.format("Excavation Plan: %d steps.", #ctx.strategy))
ctx.nextState = "MINE"
return "CHECK_REQUIREMENTS"
end
if ctx.config.mode == "treefarm" then
logger.log(ctx, "info", "Starting Tree Farm mode...")
ctx.treefarm = {
width = tonumber(ctx.config.width) or 9,
height = tonumber(ctx.config.height) or 9,
currentX = 0,
currentZ = 0, -- Using Z for the second dimension to match Minecraft coordinates usually
state = "SCAN",
chests = ctx.chests
}
return "TREEFARM"
end
if ctx.config.mode == "potatofarm" then
logger.log(ctx, "info", "Starting Potato Farm mode...")
ctx.potatofarm = {
width = tonumber(ctx.config.width) or 9,
height = tonumber(ctx.config.height) or 9,
currentX = 0,
currentZ = 0,
nextX = 0,
nextZ = 0,
state = "SCAN",
chests = ctx.chests
}
return "POTATOFARM"
end
if ctx.config.mode == "farm" then
logger.log(ctx, "info", "Generating farm strategy...")
local farmType = ctx.config.farmType or "tree"
local width = tonumber(ctx.config.width) or 9
local length = tonumber(ctx.config.length) or 9
local schema = strategyFarm.generate(farmType, width, length)
local valid, err = validateSchema(schema)
if not valid then
ctx.lastError = "Generated schema invalid: " .. tostring(err)
return "ERROR"
end
ui.clear()
ui.drawPreview(schema, 2, 2, 30, 15)
term.setCursorPos(1, 18)
print("Previewing " .. farmType .. " farm.")
print("Press Enter to confirm, 'q' to quit.")
local input = read()
if input == "q" or input == "Q" then
return "DONE"
end
local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
local minY, maxY = 0, 1 -- Assuming 2 layers for now
for sx, row in pairs(schema) do
local nx = tonumber(sx)
if nx then
if nx < minX then minX = nx end
if nx > maxX then maxX = nx end
for sy, col in pairs(row) do
for sz, block in pairs(col) do
local nz = tonumber(sz)
if nz then
if nz < minZ then minZ = nz end
if nz > maxZ then maxZ = nz end
end
end
end
end
end
ctx.schema = schema
ctx.schemaInfo = {
bounds = {
min = { x = minX, y = minY, z = minZ },
max = { x = maxX, y = maxY, z = maxZ }
}
}
logger.log(ctx, "info", "Computing build strategy...")
local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
if not order then
ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
return "ERROR"
end
ctx.strategy = order
ctx.pointer = 1
logger.log(ctx, "info", string.format("Plan: %d steps.", #order))
ctx.nextState = "BUILD"
return "CHECK_REQUIREMENTS"
end
if not ctx.config.schemaPath then
ctx.lastError = "No schema path provided"
return "ERROR"
end
logger.log(ctx, "info", "Loading schema: " .. ctx.config.schemaPath)
local ok, schemaOrErr, info = parser.parseFile(ctx, ctx.config.schemaPath, { formatHint = nil })
if not ok then
ctx.lastError = "Failed to parse schema: " .. tostring(schemaOrErr)
return "ERROR"
end
ctx.schema = schemaOrErr
ctx.schemaInfo = info
local valid, err = validateSchema(ctx.schema)
if not valid then
ctx.lastError = "Loaded schema invalid: " .. tostring(err)
return "ERROR"
end
logger.log(ctx, "info", "Computing build strategy...")
local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
if not order then
ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
return "ERROR"
end
ctx.strategy = order
ctx.pointer = 1
logger.log(ctx, "info", string.format("Plan: %d steps.", #order))
ctx.nextState = "BUILD"
return "CHECK_REQUIREMENTS"
end
return INITIALIZE]]
files["factory/state_mine.lua"] = [[local movement = require("lib_movement")
local inventory = require("lib_inventory")
local mining = require("lib_mining")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")
local world = require("lib_world")
local startup = require("lib_startup")
local function localToWorld(ctx, localPos)
return world.localToWorldRelative(ctx.origin, localPos)
end
local function selectTorch(ctx)
local torchItem = ctx.config.torchItem or "minecraft:torch"
local ok = inventory.selectMaterial(ctx, torchItem)
if ok then
return true, torchItem
end
ctx.missingMaterial = torchItem
return false, torchItem
end
local function MINE(ctx)
logger.log(ctx, "info", "State: MINE")
if not startup.runFuelCheck(ctx, ctx.chests, 100, 1000) then
return "MINE"
end
local stepIndex = ctx.pointer or 1
local strategy, errMsg = diagnostics.requireStrategy(ctx)
if not strategy then
return "ERROR"
end
if stepIndex > #strategy then
return "DONE"
end
local step = strategy[stepIndex]
if step.type == "move" then
local dest = localToWorld(ctx, step)
local ok, err = movement.goTo(ctx, dest, { dig = true, attack = true })
if not ok then
logger.log(ctx, "warn", "Mining movement blocked: " .. tostring(err))
ctx.resumeState = "MINE"
if err == "blocked" then
return "BLOCKED"
end
ctx.lastError = "Mining movement failed: " .. tostring(err)
return "ERROR"
end
elseif step.type == "turn" then
if step.data == "left" then
movement.turnLeft(ctx)
elseif step.data == "right" then
movement.turnRight(ctx)
end
elseif step.type == "mine_neighbors" then
mining.scanAndMineNeighbors(ctx)
elseif step.type == "place_torch" then
local ok = selectTorch(ctx)
if not ok then
logger.log(ctx, "warn", "No torches to place. Skipping.")
else
if turtle.placeDown() then
elseif turtle.placeUp() then
else
movement.turnRight(ctx)
movement.turnRight(ctx)
if turtle.detect() then
turtle.dig()
end
if turtle.place() then
else
movement.turnLeft(ctx)
if turtle.detect() then
turtle.dig()
end
if turtle.place() then
movement.turnRight(ctx) -- Restore to facing behind
else
movement.turnRight(ctx) -- Restore to facing behind
if turtle.digDown() then
turtle.placeDown()
else
logger.log(ctx, "warn", "Failed to place torch")
end
end
end
movement.turnRight(ctx)
movement.turnRight(ctx)
end
end
elseif step.type == "dump_trash" then
local dumped = inventory.dumpTrash(ctx)
if not dumped then
logger.log(ctx, "debug", "dumpTrash failed (probably empty inventory)")
end
elseif step.type == "done" then
return "DONE"
elseif step.type == "place_chest" then
local chestItem = ctx.config.chestItem or "minecraft:chest"
local ok = inventory.selectMaterial(ctx, chestItem)
if not ok then
inventory.scan(ctx)
local state = inventory.ensureState(ctx)
for slot, item in pairs(state.slots) do
if item.name:find("chest") or item.name:find("barrel") or item.name:find("shulker") then
turtle.select(slot)
ok = true
break
end
end
end
if not ok then
local msg = "Pre-flight check failed: Missing chest"
logger.log(ctx, "error", msg)
ctx.lastError = msg
return "ERROR"
end
if not turtle.placeDown() then
if turtle.detectDown() then
turtle.digDown()
if not turtle.placeDown() then
local msg = "Pre-flight check failed: Could not place chest"
logger.log(ctx, "error", msg)
ctx.lastError = msg
return "ERROR"
end
else
local msg = "Pre-flight check failed: Could not place chest"
logger.log(ctx, "error", msg)
ctx.lastError = msg
return "ERROR"
end
end
end
ctx.pointer = stepIndex + 1
ctx.retries = 0
return "MINE"
end
return MINE]]
files["factory/state_potatofarm.lua"] = [[local movement = require("lib_movement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local wizard = require("lib_wizard")
local startup = require("lib_startup")
local farming = require("lib_farming")
local function POTATOFARM(ctx)
local pf = ctx.potatofarm
if not pf then return "INITIALIZE" end
if not startup.runFuelCheck(ctx, pf.chests) then
return "POTATOFARM"
end
if pf.state == "SCAN" then
local width = tonumber(pf.width) or 9
local height = tonumber(pf.height) or 9
if width < 3 then width = 3 end
if height < 3 then height = 3 end
logger.log(ctx, "info", "PotatoFarm SCAN: " .. width .. "x" .. height)
local w, h = width - 2, height - 2
pf.nextX = tonumber(pf.nextX) or 0
pf.nextZ = tonumber(pf.nextZ) or 0
if pf.nextZ >= h then
pf.state = "DEPOSIT"
return "POTATOFARM"
end
local x = pf.nextX
local z = pf.nextZ
local hoverHeight = 1
local target = { x = x + 1, y = hoverHeight, z = -(z + 1) }
if not movement.goTo(ctx, target, { axisOrder = { "y", "x", "z" } }) then
logger.log(ctx, "warn", "Path blocked to " .. target.x .. "," .. target.z)
if not movement.up(ctx) then
return "POTATOFARM" -- Stuck
end
else
local hasDown, dataDown = turtle.inspectDown()
if hasDown and dataDown.name == "minecraft:potatoes" then
local age = dataDown.state and dataDown.state.age or 0
if age >= 7 then
inventory.scan(ctx)
if not inventory.findEmptySlot(ctx) then
logger.log(ctx, "warn", "Inventory full. Depositing...")
pf.state = "DEPOSIT"
return "POTATOFARM"
end
logger.log(ctx, "info", "Harvesting potato at " .. x .. "," .. z)
local harvested = false
if inventory.selectMaterial(ctx, "minecraft:potato") then
turtle.placeDown()
else
local emptySlot = inventory.findEmptySlot(ctx)
if emptySlot then
turtle.select(emptySlot)
turtle.placeDown()
end
end
local hCheck, dCheck = turtle.inspectDown()
if hCheck and dCheck.name == "minecraft:potatoes" then
local newAge = dCheck.state and dCheck.state.age or 0
if newAge < 7 then
harvested = true
end
end
if not harvested then
turtle.digDown()
end
sleep(0.2) -- Wait for drops
while turtle.suckDown() do
sleep(0.1)
end
local hPost, dPost = turtle.inspectDown()
if not hPost or dPost.name == "minecraft:air" then
if inventory.selectMaterial(ctx, "minecraft:potato") then
turtle.placeDown()
end
end
end
elseif not hasDown or dataDown.name == "minecraft:air" then
if inventory.selectMaterial(ctx, "minecraft:potato") then
turtle.placeDown()
end
end
end
pf.nextX = pf.nextX + 1
if pf.nextX >= w then
pf.nextX = 0
pf.nextZ = pf.nextZ + 1
end
return "POTATOFARM"
elseif pf.state == "DEPOSIT" then
if not pf.chests or not pf.chests.output then
logger.log(ctx, "error", "Missing output chest configuration.")
return "ERROR"
end
local ok, err = farming.deposit(ctx, {
safeHeight = 2,
chests = pf.chests,
keepItems = { ["minecraft:potato"] = 64 },
trashItems = { "minecraft:poisonous_potato" },
refuel = true
})
if not ok then
logger.log(ctx, "error", "Deposit failed: " .. tostring(err))
return "ERROR"
end
pf.state = "WAIT"
return "POTATOFARM"
elseif pf.state == "WAIT" then
logger.log(ctx, "info", "Waiting for growth...")
sleep(60)
pf.state = "SCAN"
pf.nextX = 0
pf.nextZ = 0
return "POTATOFARM"
end
return "POTATOFARM"
end
return POTATOFARM]]
files["factory/state_refuel.lua"] = [[local movement = require("lib_movement")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local function REFUEL(ctx)
logger.log(ctx, "info", "Refueling...")
local ok, err = movement.goTo(ctx, ctx.origin)
if not ok then
ctx.resumeState = ctx.resumeState or "BUILD"
return "BLOCKED"
end
local limit = turtle.getFuelLimit()
local target = (type(limit) == "number" and limit < 20000) and limit or 20000
fuelLib.refuel(ctx, { target = target, excludeItems = { "minecraft:torch" } })
local level = turtle.getFuelLevel()
if level == "unlimited" then level = math.huge end
if type(level) ~= "number" then level = 0 end
if level > 1000 then
local resume = ctx.resumeState or "BUILD"
ctx.resumeState = nil
return resume
end
logger.log(ctx, "error", "Out of fuel and no fuel items found.")
ctx.lastError = "Out of fuel and no fuel items found."
return "ERROR"
end
return REFUEL]]
files["factory/state_restock.lua"] = [[local movement = require("lib_movement")
local inventory = require("lib_inventory")
local logger = require("lib_logger")
local function RESTOCK(ctx)
logger.log(ctx, "info", "Restocking " .. tostring(ctx.missingMaterial))
local ok, err = movement.goTo(ctx, ctx.origin)
if not ok then
ctx.resumeState = ctx.resumeState or "BUILD"
return "BLOCKED"
end
local material = ctx.missingMaterial
if not material then
local resume = ctx.resumeState or "BUILD"
ctx.resumeState = nil
return resume
end
local pulled = false
for _, side in ipairs({"front", "up", "down", "left", "right", "back"}) do
local okPull, pullErr = inventory.pullMaterial(ctx, material, 64, { side = side })
if okPull then
pulled = true
break
end
end
if not pulled then
logger.log(ctx, "error", "Could not find " .. material .. " in nearby inventories.")
print("Please supply " .. material .. " in the chest and press Enter to retry...")
read()
return "RESTOCK"
end
ctx.missingMaterial = nil
local resume = ctx.resumeState or "BUILD"
ctx.resumeState = nil
return resume
end
return RESTOCK]]
files["factory/state_treefarm.lua"] = [[local movement = require("lib_movement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local wizard = require("lib_wizard")
local startup = require("lib_startup")
local farming = require("lib_farming")
local function selectSapling(ctx)
inventory.scan(ctx)
local state = ctx.inventory
if not state or not state.slots then return false end
for slot, info in pairs(state.slots) do
if info.name and info.name:find("sapling") then
if turtle.select(slot) then
return true
end
end
end
return false
end
local function TREEFARM(ctx)
logger.log(ctx, "info", "TREEFARM State (Fix Applied)")
local tf = ctx.treefarm
if not tf then return "INITIALIZE" end
if not startup.runFuelCheck(ctx, tf.chests) then
return "TREEFARM"
end
if tf.state == "SCAN" then
local treeW = tonumber(tf.width) or 8
local treeH = tonumber(tf.height) or 8
local limitX = (treeW * 2) - 1
local limitZ = (treeH * 2) - 1
if type(tf.nextX) ~= "number" then tf.nextX = 0 end
if type(tf.nextZ) ~= "number" then tf.nextZ = 0 end
if tf.nextX == 0 and tf.nextZ == 0 then
logger.log(ctx, "info", "Starting patrol run. Grid: " .. treeW .. "x" .. treeH .. " trees.")
local totalSpots = (limitX + 1) * (limitZ + 1)
local fuelPerSpot = 16 -- Descent/Ascent + Travel
local needed = (totalSpots * fuelPerSpot) + 200
if type(needed) ~= "number" then needed = 1000 end
local function getFuel()
local l = turtle.getFuelLevel()
if l == "unlimited" then return math.huge end
if type(l) ~= "number" then return 0 end
return l
end
local current = getFuel()
if current < needed then
logger.log(ctx, "warn", string.format("Pre-run fuel check: Have %s, Need %s", tostring(current), tostring(needed)))
fuelLib.refuel(ctx, { target = needed, excludeItems = { "sapling", "log" } })
current = getFuel()
logger.log(ctx, "debug", string.format("Fuel check: current=%s needed=%s", tostring(current), tostring(needed)))
if current < needed and tf.chests and tf.chests.fuel then
logger.log(ctx, "info", "Insufficient fuel. Visiting fuel depot.")
movement.goTo(ctx, { x=0, y=0, z=0 })
movement.face(ctx, tf.chests.fuel)
local attempts = 0
while current < needed and attempts < 16 do
if not turtle.suck() then
logger.log(ctx, "warn", "Fuel chest empty or inventory full!")
break
end
fuelLib.refuel(ctx, { target = needed, excludeItems = { "sapling", "log" } })
current = getFuel()
attempts = attempts + 1
end
end
end
end
if tf.nextZ > limitZ then
tf.state = "DEPOSIT"
return "TREEFARM"
end
local x = tf.nextX
local z = tf.nextZ
logger.log(ctx, "debug", "Checking sector " .. x .. "," .. z)
local hoverHeight = 6
local xOffset = 2
local zOffset = 2
local target = { x = x + xOffset, y = hoverHeight, z = -(z + zOffset) }
if not movement.goTo(ctx, target, { axisOrder = { "y", "x", "z" } }) then
logger.log(ctx, "warn", "Path blocked to " .. x .. "," .. z)
else
while movement.getPosition(ctx).y > 1 do
local hasDown, dataDown = turtle.inspectDown()
if hasDown and (dataDown.name:find("log") or dataDown.name:find("leaves")) then
turtle.digDown()
sleep(0.2)
while turtle.suckDown() do sleep(0.1) end
elseif hasDown and not dataDown.name:find("air") then
turtle.digDown()
sleep(0.2)
while turtle.suckDown() do sleep(0.1) end
end
if not movement.down(ctx) then
turtle.digDown() -- Try again
sleep(0.2)
while turtle.suckDown() do sleep(0.1) end
end
end
local hasDown, dataDown = turtle.inspectDown()
if hasDown and dataDown.name:find("log") then
logger.log(ctx, "info", "Timber! Found a tree at " .. x .. "," .. z .. ". Chopping it down.")
turtle.digDown()
sleep(0.2)
while turtle.suckDown() do sleep(0.1) end
hasDown = false
end
local isGridSpot = (x % 2 == 0) and (z % 2 == 0)
if isGridSpot and (not hasDown or dataDown.name:find("air") or dataDown.name:find("sapling")) then
if selectSapling(ctx) then
logger.log(ctx, "info", "Replanting sapling at " .. x .. "," .. z .. ".")
turtle.placeDown()
end
end
end
tf.nextX = tf.nextX + 1
if tf.nextX > limitX then
tf.nextX = 0
tf.nextZ = tf.nextZ + 1
end
return "TREEFARM"
elseif tf.state == "DEPOSIT" then
local ok, err = farming.deposit(ctx, {
safeHeight = 6,
chests = tf.chests,
keepItems = { ["sapling"] = 16 },
refuel = true
})
if not ok then
logger.log(ctx, "error", "Deposit failed: " .. tostring(err))
return "ERROR"
end
tf.state = "WAIT"
return "TREEFARM"
elseif tf.state == "WAIT" then
logger.log(ctx, "info", "All done for now. Taking a nap while trees grow.")
sleep(30)
tf.state = "SCAN"
tf.nextX = 0
tf.nextZ = 0
return "TREEFARM"
end
return "TREEFARM"
end
return TREEFARM]]
files["games/arcade.lua"] = [[local ok, mod = pcall(require, "arcade")
if ok and mod then
return mod
end
error("Unable to load arcade library via either 'games.arcade' shim or 'arcade'")]]
files["installer.lua"] = [=[local function clear()
term.clear()
term.setCursorPos(1,1)
end
local function printHeader()
clear()
print("========================================")
print("       ARCADESYS UNIFIED INSTALLER      ")
print("========================================")
print("")
end
local function detectPlatform()
if turtle then
return "turtle"
else
return "computer"
end
end
local function install()
printHeader()
local platform = detectPlatform()
print("Detected Platform: " .. string.upper(platform))
print("")
print("This installer would normally download files from a server.")
print("Since you are running from a local repo, the files are already here.")
print("NOTE: This script DOES NOT update files. Use 'arcadesys_installer' for that.")
print("")
print("Verifying structure...")
local missing = false
if not fs.exists("lib") then print("! Missing /lib"); missing = true end
if not fs.exists("arcade") then print("! Missing /arcade"); missing = true end
if not fs.exists("factory") then print("! Missing /factory"); missing = true end
if missing then
print("")
print("Error: Repository structure is incomplete.")
return
end
print("Structure OK.")
print("")
local startupTargets = {
turtle = "/factory/turtle_os.lua",
computer = "/arcade/arcade_shell.lua",
}
print("Validating startup targets...")
local missingTargets = {}
for platformName, path in pairs(startupTargets) do
if not fs.exists(path) then
table.insert(missingTargets, string.format("%s (%s)", platformName, path))
end
end
if #missingTargets > 0 then
print("! Missing startup targets: " .. table.concat(missingTargets, ", "))
print("Cannot create startup.lua until required files are present.")
return
end
print("Creating startup.lua...")
local startupContent = [[
local platform = turtle and "turtle" or "computer"
package.path = package.path .. ";/?.lua;/lib/?.lua;/arcade/?.lua;/factory/?.lua"
if platform == "turtle" then
shell.run("/factory/turtle_os.lua")
else
shell.run("/arcade/arcade_shell.lua")
end
]]
local h = fs.open("startup.lua", "w")
h.write(startupContent)
h.close()
print("startup.lua created.")
print("")
print("Installation Complete!")
print("Rebooting in 3 seconds...")
os.sleep(3)
os.reboot()
end
install()]=]
files["lib/lib_cards.lua"] = [[local cards = {}
cards.SUITS = {"S", "H", "D", "C"}
cards.RANKS = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}
cards.SUIT_COLORS = {S=colors.gray, H=colors.red, D=colors.red, C=colors.gray}
cards.SUIT_SYMBOLS = {S="\6", H="\3", D="\4", C="\5"}
function cards.createDeck()
local deck = {}
for s=1,4 do
for r=1,13 do
table.insert(deck, {suit=cards.SUITS[s], rank=r, rankStr=cards.RANKS[r]})
end
end
return deck
end
function cards.shuffle(deck)
for i = #deck, 2, -1 do
local j = math.random(i)
deck[i], deck[j] = deck[j], deck[i]
end
end
function cards.getCardString(card)
return card.rankStr .. cards.SUIT_SYMBOLS[card.suit]
end
function cards.evaluateHand(hand)
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
if straight and flush and sorted[1].rank == 9 then return "ROYAL_FLUSH", 250 end
if straight and flush then return "STRAIGHT_FLUSH", 50 end
if countsArr[1].count == 4 then return "FOUR_OF_A_KIND", 25 end
if countsArr[1].count == 3 and countsArr[2].count == 2 then return "FULL_HOUSE", 9 end
if flush then return "FLUSH", 6 end
if straight then return "STRAIGHT", 4 end
if countsArr[1].count == 3 then return "THREE_OF_A_KIND", 3 end
if countsArr[1].count == 2 and countsArr[2].count == 2 then return "TWO_PAIR", 2 end
if countsArr[1].count == 2 and (countsArr[1].rank >= 10 or countsArr[1].rank == 13) then -- J, Q, K, A (10,11,12,13)
return "JACKS_OR_BETTER", 1
end
return "NONE", 0
end
return cards]]
files["lib/lib_designer.lua"] = [[local ui = require("lib_ui")
local json = require("lib_json")
local items = require("lib_items")
local schema_utils = require("lib_schema")
local parser = require("lib_parser")
local version = require("version")
local designer = {}
local COLORS = {
bg = colors.gray,
canvas_bg = colors.black,
grid = colors.lightGray,
text = colors.white,
btn_active = colors.blue,
btn_inactive = colors.lightGray,
btn_text = colors.black,
}
local DEFAULT_MATERIALS = {
{ id = "minecraft:stone", color = colors.lightGray, sym = "#" },
{ id = "minecraft:dirt", color = colors.brown, sym = "d" },
{ id = "minecraft:cobblestone", color = colors.gray, sym = "c" },
{ id = "minecraft:planks", color = colors.orange, sym = "p" },
{ id = "minecraft:glass", color = colors.lightBlue, sym = "g" },
{ id = "minecraft:log", color = colors.brown, sym = "L" },
{ id = "minecraft:torch", color = colors.yellow, sym = "i" },
{ id = "minecraft:iron_block", color = colors.white, sym = "I" },
{ id = "minecraft:gold_block", color = colors.yellow, sym = "G" },
{ id = "minecraft:diamond_block", color = colors.cyan, sym = "D" },
}
local TOOLS = {
PENCIL = "Pencil",
LINE = "Line",
RECT = "Rect",
RECT_FILL = "FillRect",
CIRCLE = "Circle",
CIRCLE_FILL = "FillCircle",
BUCKET = "Bucket",
PICKER = "Picker"
}
local state = {}
local function resetState()
state.running = true
state.w = 14
state.h = 14
state.d = 5
state.data = {} -- [x][y][z] = material_index (0 or nil for air)
state.meta = {} -- [x][y][z] = meta table
state.palette = {}
state.paletteEditMode = false
state.offset = { x = 0, y = 0, z = 0 }
state.view = {
layer = 0, -- Current Y level
offsetX = 4, -- Screen X offset of canvas
offsetY = 3, -- Screen Y offset of canvas
scrollX = 0,
scrollY = 0,
cursorX = 0,
cursorY = 0,
}
state.menuOpen = false
state.inventoryOpen = false
state.searchOpen = false
state.searchQuery = ""
state.searchResults = {}
state.searchScroll = 0
state.dragItem = nil -- { id, sym, color }
state.tool = TOOLS.PENCIL
state.primaryColor = 1 -- Index in palette
state.secondaryColor = 0 -- 0 = Air/Eraser
state.mouse = {
down = false,
drag = false,
startX = 0, startY = 0, -- Canvas coords
currX = 0, currY = 0,   -- Canvas coords
btn = 1
}
state.status = "Ready"
for i, m in ipairs(DEFAULT_MATERIALS) do
state.palette[i] = { id = m.id, color = m.color, sym = m.sym }
end
end
resetState()
local function getMaterial(idx)
if idx == 0 or not idx then return nil end
return state.palette[idx]
end
local function getBlock(x, y, z)
if not state.data[x] then return 0 end
if not state.data[x][y] then return 0 end
return state.data[x][y][z] or 0
end
local function setBlock(x, y, z, matIdx, meta)
if x < 0 or x >= state.w or z < 0 or z >= state.h or y < 0 or y >= state.d then return end
if not state.data[x] then state.data[x] = {} end
if not state.data[x][y] then state.data[x][y] = {} end
if not state.meta[x] then state.meta[x] = {} end
if not state.meta[x][y] then state.meta[x][y] = {} end
if matIdx == 0 then
state.data[x][y][z] = nil
if state.meta[x] and state.meta[x][y] then
state.meta[x][y][z] = nil
end
else
state.data[x][y][z] = matIdx
state.meta[x][y][z] = meta or {}
end
end
local function getBlockMeta(x, y, z)
if not state.meta[x] or not state.meta[x][y] then return {} end
return schema_utils.cloneMeta(state.meta[x][y][z])
end
local function findItemDef(id)
for _, item in ipairs(items) do
if item.id == id then
return item
end
end
return nil
end
local function ensurePaletteMaterial(material)
for idx, mat in ipairs(state.palette) do
if mat.id == material then
return idx
end
end
local fallback = findItemDef(material)
local entry = {
id = material,
color = fallback and fallback.color or colors.white,
sym = fallback and fallback.sym or "?",
}
table.insert(state.palette, entry)
return #state.palette
end
local function clearCanvas()
state.data = {}
state.meta = {}
end
local function loadCanonical(schema, metadata)
if type(schema) ~= "table" then
return false, "invalid_schema"
end
clearCanvas()
local bounds = schema_utils.newBounds()
local blockCount = 0
for xKey, xColumn in pairs(schema) do
if type(xColumn) == "table" then
local x = tonumber(xKey) or xKey
if type(x) ~= "number" then return false, "invalid_coordinate" end
for yKey, yColumn in pairs(xColumn) do
if type(yColumn) == "table" then
local y = tonumber(yKey) or yKey
if type(y) ~= "number" then return false, "invalid_coordinate" end
for zKey, block in pairs(yColumn) do
if type(block) == "table" and block.material then
local z = tonumber(zKey) or zKey
if type(z) ~= "number" then return false, "invalid_coordinate" end
schema_utils.updateBounds(bounds, x, y, z)
blockCount = blockCount + 1
end
end
end
end
end
end
if blockCount == 0 then
state.status = "Loaded empty schema"
return true
end
state.offset = {
x = bounds.min.x,
y = bounds.min.y,
z = bounds.min.z,
}
state.w = math.max(1, (bounds.max.x - bounds.min.x) + 1)
state.d = math.max(1, (bounds.max.y - bounds.min.y) + 1)
state.h = math.max(1, (bounds.max.z - bounds.min.z) + 1)
for xKey, xColumn in pairs(schema) do
if type(xColumn) == "table" then
local x = tonumber(xKey) or xKey
if type(x) ~= "number" then return false, "invalid_coordinate" end
for yKey, yColumn in pairs(xColumn) do
if type(yColumn) == "table" then
local y = tonumber(yKey) or yKey
if type(y) ~= "number" then return false, "invalid_coordinate" end
for zKey, block in pairs(yColumn) do
if type(block) == "table" and block.material then
local z = tonumber(zKey) or zKey
if type(z) ~= "number" then return false, "invalid_coordinate" end
local matIdx = ensurePaletteMaterial(block.material)
local localX = x - state.offset.x
local localY = y - state.offset.y
local localZ = z - state.offset.z
setBlock(localX, localY, localZ, matIdx, schema_utils.cloneMeta(block.meta))
end
end
end
end
end
end
state.status = string.format("Loaded %d blocks", blockCount)
if metadata and metadata.path then
state.status = state.status .. " from " .. metadata.path
end
return true
end
local function exportCanonical()
local schema = {}
local bounds = schema_utils.newBounds()
local total = 0
for x, xColumn in pairs(state.data) do
for y, yColumn in pairs(xColumn) do
for z, matIdx in pairs(yColumn) do
local mat = getMaterial(matIdx)
if mat then
local worldX = x + state.offset.x
local worldY = y + state.offset.y
local worldZ = z + state.offset.z
schema[worldX] = schema[worldX] or {}
schema[worldX][worldY] = schema[worldX][worldY] or {}
schema[worldX][worldY][worldZ] = {
material = mat.id,
meta = getBlockMeta(x, y, z),
}
schema_utils.updateBounds(bounds, worldX, worldY, worldZ)
total = total + 1
end
end
end
end
local info = { totalBlocks = total }
if total > 0 then
info.bounds = bounds
end
return schema, info
end
local function exportVoxelDefinition()
local canonical, info = exportCanonical()
return schema_utils.canonicalToVoxelDefinition(canonical), info
end
local function drawLine(x0, y0, x1, y1, callback)
local dx = math.abs(x1 - x0)
local dy = math.abs(y1 - y0)
local sx = x0 < x1 and 1 or -1
local sy = y0 < y1 and 1 or -1
local err = dx - dy
while true do
callback(x0, y0)
if x0 == x1 and y0 == y1 then break end
local e2 = 2 * err
if e2 > -dy then
err = err - dy
x0 = x0 + sx
end
if e2 < dx then
err = err + dx
y0 = y0 + sy
end
end
end
local function drawRect(x0, y0, x1, y1, filled, callback)
local minX, maxX = math.min(x0, x1), math.max(x0, x1)
local minY, maxY = math.min(y0, y1), math.max(y0, y1)
for x = minX, maxX do
for y = minY, maxY do
if filled or (x == minX or x == maxX or y == minY or y == maxY) then
callback(x, y)
end
end
end
end
local function drawCircle(x0, y0, x1, y1, filled, callback)
local r = math.floor(math.min(math.abs(x1 - x0), math.abs(y1 - y0)) / 2)
local cx = math.floor((x0 + x1) / 2)
local cy = math.floor((y0 + y1) / 2)
local x = r
local y = 0
local err = 0
while x >= y do
if filled then
for i = cx - x, cx + x do callback(i, cy + y); callback(i, cy - y) end
for i = cx - y, cx + y do callback(i, cy + x); callback(i, cy - x) end
else
callback(cx + x, cy + y)
callback(cx + y, cy + x)
callback(cx - y, cy + x)
callback(cx - x, cy + y)
callback(cx - x, cy - y)
callback(cx - y, cy - x)
callback(cx + y, cy - x)
callback(cx + x, cy - y)
end
if err <= 0 then
y = y + 1
err = err + 2 * y + 1
end
if err > 0 then
x = x - 1
err = err - 2 * x + 1
end
end
end
local function floodFill(startX, startY, targetColor, replaceColor)
if targetColor == replaceColor then return end
local queue = { {x = startX, y = startY} }
local visited = {}
local function key(x, y) return x .. "," .. y end
while #queue > 0 do
local p = table.remove(queue, 1)
local k = key(p.x, p.y)
if not visited[k] then
visited[k] = true
local curr = getBlock(p.x, state.view.layer, p.y)
if curr == targetColor then
setBlock(p.x, state.view.layer, p.y, replaceColor)
local neighbors = {
{x = p.x + 1, y = p.y},
{x = p.x - 1, y = p.y},
{x = p.x, y = p.y + 1},
{x = p.x, y = p.y - 1}
}
for _, n in ipairs(neighbors) do
if n.x >= 0 and n.x < state.w and n.y >= 0 and n.y < state.h then
table.insert(queue, n)
end
end
end
end
end
end
local drawSearch
local function drawMenu()
if not state.menuOpen then return end
local w, h = term.getSize()
local mx, my = w - 12, 2
local mw, mh = 12, 8
ui.drawFrame(mx, my, mw, mh, "Menu")
local options = { "Resize", "Save", "Load", "Clear", "Inventory", "Quit" }
for i, opt in ipairs(options) do
term.setCursorPos(mx + 1, my + i)
term.setBackgroundColor(COLORS.bg)
term.setTextColor(COLORS.text)
if opt == "Inventory" and state.inventoryOpen then
term.setTextColor(colors.yellow)
end
term.write(opt)
end
end
local function drawInventory()
if not state.inventoryOpen then return end
local w, h = term.getSize()
local iw, ih = 18, 6 -- 4x4 grid + border
local ix, iy = math.floor((w - iw)/2), math.floor((h - ih)/2)
ui.drawFrame(ix, iy, iw, ih, "Inventory")
for row = 0, 3 do
for col = 0, 3 do
local slot = row * 4 + col + 1
local item = turtle.getItemDetail(slot)
term.setCursorPos(ix + 1 + (col * 4), iy + 1 + row)
local sym = "."
local color = colors.gray
if item then
sym = item.name:sub(11, 11):upper() -- First char of name after minecraft:
color = colors.white
end
term.setBackgroundColor(colors.black)
term.setTextColor(color)
term.write(" " .. sym .. " ")
end
end
term.setCursorPos(ix + 1, iy + ih)
term.setBackgroundColor(COLORS.bg)
term.setTextColor(COLORS.text)
term.write("Drag to Palette")
end
local function drawDragItem()
if state.dragItem and state.mouse.screenX then
term.setCursorPos(state.mouse.screenX, state.mouse.screenY)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.write(state.dragItem.sym)
end
end
local function drawUI()
ui.clear()
term.setBackgroundColor(COLORS.bg)
term.setCursorPos(1, 1)
term.clearLine()
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
term.write(" M ")
term.setBackgroundColor(COLORS.bg)
term.setTextColor(COLORS.text)
term.write(string.format(" Designer [%d,%d,%d] Layer: %d/%d", state.w, state.h, state.d, state.view.layer, state.d - 1))
local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
for i, t in ipairs(toolsList) do
term.setCursorPos(1, 2 + i)
if state.tool == t then
term.setBackgroundColor(COLORS.btn_active)
term.setTextColor(colors.white)
term.write(" " .. t:sub(1,1) .. " ")
else
term.setBackgroundColor(COLORS.btn_inactive)
term.setTextColor(COLORS.btn_text)
term.write(" " .. t:sub(1,1) .. " ")
end
end
local palX = 2 + state.w + 2
term.setCursorPos(palX, 2)
term.setBackgroundColor(COLORS.bg)
term.setTextColor(COLORS.text)
local editLabel = state.paletteEditMode and "[EDITING]" or "[Edit]"
if state.paletteEditMode then term.setTextColor(colors.red) end
term.write("Pal " .. editLabel)
term.setCursorPos(palX + 14, 2)
term.setBackgroundColor(COLORS.btn_inactive)
term.setTextColor(COLORS.btn_text)
term.write("Find")
for i, mat in ipairs(state.palette) do
term.setCursorPos(palX, 3 + i)
local indicator = " "
if state.primaryColor == i then indicator = "L" end
if state.secondaryColor == i then indicator = "R" end
if state.primaryColor == i and state.secondaryColor == i then indicator = "B" end
term.setBackgroundColor(COLORS.bg)
term.setTextColor(COLORS.text)
term.write(indicator)
term.setBackgroundColor(mat.color)
term.setTextColor(colors.black)
term.write(" " .. mat.sym .. " ")
term.setBackgroundColor(COLORS.bg)
term.setTextColor(COLORS.text)
local name = mat.id:match(":(.+)") or mat.id
term.write(" " .. name)
end
local w, h = term.getSize()
term.setCursorPos(1, h)
term.setBackgroundColor(COLORS.bg)
term.clearLine()
term.write(state.status)
local versionText = version.display()
term.setCursorPos(w - #versionText + 1, h)
term.setTextColor(colors.lightGray)
term.write(versionText)
term.setTextColor(COLORS.text)
term.setCursorPos(1, h-1)
term.write("S:Save L:Load F:Find R:Resize C:Clear Q:Quit PgUp/Dn:Layer")
drawMenu()
drawInventory()
drawSearch()
drawDragItem()
end
local function drawCanvas()
local ox, oy = state.view.offsetX, state.view.offsetY
local sx, sy = state.view.scrollX, state.view.scrollY
term.setBackgroundColor(COLORS.bg)
term.setTextColor(colors.white)
ui.drawBox(ox - 1, oy - 1, state.w + 2, state.h + 2, COLORS.bg, colors.white)
for x = 0, state.w - 1 do
for z = 0, state.h - 1 do
local screenX = ox + x - sx
local screenY = oy + z - sy
local w, h = term.getSize()
if screenX >= ox and screenX < w and screenY >= oy and screenY < h - 2 then
local matIdx = getBlock(x, state.view.layer, z)
local mat = getMaterial(matIdx)
local bg = COLORS.canvas_bg
local char = "."
local fg = COLORS.grid
if mat then
bg = mat.color
char = mat.sym
fg = colors.black
if bg == colors.black then fg = colors.white end
end
if state.mouse.down and state.mouse.drag then
local isGhost = false
local ghostColor = (state.mouse.btn == 1) and state.primaryColor or state.secondaryColor
local function checkGhost(gx, gy)
if gx == x and gy == z then isGhost = true end
end
if state.tool == TOOLS.PENCIL then
checkGhost(state.mouse.currX, state.mouse.currY)
elseif state.tool == TOOLS.LINE then
drawLine(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, checkGhost)
elseif state.tool == TOOLS.RECT then
drawRect(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, false, checkGhost)
elseif state.tool == TOOLS.RECT_FILL then
drawRect(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, true, checkGhost)
elseif state.tool == TOOLS.CIRCLE then
drawCircle(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, false, checkGhost)
elseif state.tool == TOOLS.CIRCLE_FILL then
drawCircle(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, true, checkGhost)
end
if isGhost then
local gMat = getMaterial(ghostColor)
if gMat then
bg = gMat.color
char = gMat.sym
fg = colors.black
else
bg = COLORS.canvas_bg
char = "x"
fg = colors.red
end
end
end
term.setCursorPos(screenX, screenY)
term.setBackgroundColor(bg)
term.setTextColor(fg)
term.write(char)
end
end
end
local cx, cy = state.view.cursorX, state.view.cursorY
local screenX = ox + cx - sx
local screenY = oy + cy - sy
local w, h = term.getSize()
if screenX >= ox and screenX < w and screenY >= oy and screenY < h - 2 then
term.setCursorPos(screenX, screenY)
if os.clock() % 0.8 < 0.4 then
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
else
local matIdx = getBlock(cx, state.view.layer, cy)
local mat = getMaterial(matIdx)
if mat then
term.setBackgroundColor(mat.color == colors.white and colors.black or colors.white)
term.setTextColor(mat.color)
else
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
end
end
local matIdx = getBlock(cx, state.view.layer, cy)
local mat = getMaterial(matIdx)
term.write(mat and mat.sym or "+")
end
end
local function applyTool(x, y, btn)
local color = (btn == 1) and state.primaryColor or state.secondaryColor
if state.tool == TOOLS.PENCIL then
setBlock(x, state.view.layer, y, color)
elseif state.tool == TOOLS.BUCKET then
local target = getBlock(x, state.view.layer, y)
floodFill(x, y, target, color)
elseif state.tool == TOOLS.PICKER then
local picked = getBlock(x, state.view.layer, y)
if btn == 1 then state.primaryColor = picked else state.secondaryColor = picked end
state.tool = TOOLS.PENCIL -- Auto switch back
end
end
local function applyShape(x0, y0, x1, y1, btn)
local color = (btn == 1) and state.primaryColor or state.secondaryColor
local function plot(x, y)
setBlock(x, state.view.layer, y, color)
end
if state.tool == TOOLS.LINE then
drawLine(x0, y0, x1, y1, plot)
elseif state.tool == TOOLS.RECT then
drawRect(x0, y0, x1, y1, false, plot)
elseif state.tool == TOOLS.RECT_FILL then
drawRect(x0, y0, x1, y1, true, plot)
elseif state.tool == TOOLS.CIRCLE then
drawCircle(x0, y0, x1, y1, false, plot)
elseif state.tool == TOOLS.CIRCLE_FILL then
drawCircle(x0, y0, x1, y1, true, plot)
end
end
local function loadSchema()
ui.clear()
term.setCursorPos(1, 1)
print("Load Schema")
term.write("Filename: ")
local name = read()
if name == "" then return end
if not fs.exists(name) then
if fs.exists(name .. ".json") then name = name .. ".json"
elseif fs.exists(name .. ".txt") then name = name .. ".txt"
else
state.status = "File not found"
return
end
end
local ok, schema, meta = parser.parseFile(nil, name)
if ok then
local ok2, err = loadCanonical(schema, meta)
if ok2 then
state.status = "Loaded " .. name
else
state.status = "Error loading: " .. err
end
else
state.status = "Parse error: " .. schema
end
end
local function saveSchema()
ui.clear()
term.setCursorPos(1, 1)
print("Save Schema")
term.write("Filename: ")
local name = read()
if name == "" then return end
if not name:find("%.json$") then name = name .. ".json" end
local exportDef = exportVoxelDefinition()
local f = fs.open(name, "w")
f.write(json.encode(exportDef))
f.close()
state.status = "Saved to " .. name
end
local function resizeCanvas()
ui.clear()
print("Resize Canvas")
term.write("Width (" .. state.w .. "): ")
local w = tonumber(read()) or state.w
term.write("Height/Depth (" .. state.h .. "): ")
local h = tonumber(read()) or state.h
term.write("Layers (" .. state.d .. "): ")
local d = tonumber(read()) or state.d
state.w = w
state.h = h
state.d = d
end
local function editPaletteItem(idx)
ui.clear()
term.setCursorPos(1, 1)
print("Edit Palette Item #" .. idx)
local current = state.palette[idx]
term.write("ID (" .. current.id .. "): ")
local newId = read()
if newId == "" then newId = current.id end
term.write("Symbol (" .. current.sym .. "): ")
local newSym = read()
if newSym == "" then newSym = current.sym end
newSym = newSym:sub(1, 1)
state.palette[idx].id = newId
state.palette[idx].sym = newSym
state.status = "Updated Item #" .. idx
end
local function updateSearchResults()
state.searchResults = {}
local query = state.searchQuery:lower()
for _, item in ipairs(items) do
if item.name:lower():find(query, 1, true) or item.id:lower():find(query, 1, true) then
table.insert(state.searchResults, item)
end
end
state.searchScroll = 0
end
drawSearch = function()
if not state.searchOpen then return end
local w, h = term.getSize()
local sw, sh = 24, 14
local sx, sy = math.floor((w - sw)/2), math.floor((h - sh)/2)
ui.drawFrame(sx, sy, sw, sh, "Item Search")
term.setCursorPos(sx + 1, sy + 1)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.write(state.searchQuery .. "_")
local padding = sw - 2 - #state.searchQuery - 1
if padding > 0 then term.write(string.rep(" ", padding)) end
local maxLines = sh - 3
for i = 1, maxLines do
local idx = state.searchScroll + i
local item = state.searchResults[idx]
term.setCursorPos(sx + 1, sy + 2 + i)
if item then
term.setBackgroundColor(colors.black)
term.setTextColor(item.color or colors.white)
local label = item.name or item.id
if #label > sw - 4 then label = label:sub(1, sw - 4) end
term.write(" " .. item.sym .. " " .. label)
local pad = sw - 2 - 3 - #label
if pad > 0 then term.write(string.rep(" ", pad)) end
else
term.setBackgroundColor(COLORS.bg)
term.write(string.rep(" ", sw - 2))
end
end
end
function designer.run(opts)
opts = opts or {}
resetState()
if opts.schema then
local ok, err = loadCanonical(opts.schema, opts.metadata)
if not ok then
return false, err
end
end
state.running = true
while state.running do
drawUI()
drawCanvas()
drawMenu()
drawInventory()
drawSearch()
drawDragItem()
local event, p1, p2, p3 = os.pullEvent()
if event == "char" and state.searchOpen then
state.searchQuery = state.searchQuery .. p1
updateSearchResults()
elseif event == "mouse_scroll" and state.searchOpen then
local dir = p1
state.searchScroll = math.max(0, state.searchScroll + dir)
elseif event == "mouse_click" then
local btn, mx, my = p1, p2, p3
state.mouse.screenX = mx
state.mouse.screenY = my
local handled = false
if state.searchOpen then
local w, h = term.getSize()
local sw, sh = 24, 14
local sx, sy = math.floor((w - sw)/2), math.floor((h - sh)/2)
if mx >= sx and mx < sx + sw and my >= sy and my < sy + sh then
if my >= sy + 3 then
local idx = state.searchScroll + (my - (sy + 2))
local item = state.searchResults[idx]
if item then
state.dragItem = { id = item.id, sym = item.sym, color = item.color }
state.searchOpen = false
end
end
handled = true
else
state.searchOpen = false
handled = true
end
end
if not handled and state.menuOpen then
local w, h = term.getSize()
local menuX, menuY = w - 12, 2
if mx >= menuX and mx < menuX + 12 and my >= menuY and my < menuY + 8 then
local idx = my - menuY
local options = { "Resize", "Save", "Load", "Clear", "Inventory", "Quit" }
if options[idx] then
if options[idx] == "Quit" then state.running = false
elseif options[idx] == "Inventory" then state.inventoryOpen = not state.inventoryOpen
elseif options[idx] == "Resize" then resizeCanvas()
elseif options[idx] == "Save" then saveSchema()
elseif options[idx] == "Clear" then clearCanvas()
elseif options[idx] == "Load" then loadSchema()
end
if options[idx] ~= "Inventory" then state.menuOpen = false end
end
handled = true
else
state.menuOpen = false
handled = true -- Consume click
end
end
if not handled and state.inventoryOpen then
local w, h = term.getSize()
local iw, ih = 18, 6
local ix, iy = math.floor((w - iw)/2), math.floor((h - ih)/2)
if mx >= ix and mx < ix + iw and my >= iy and my < iy + ih then
local relX, relY = mx - ix - 1, my - iy - 1
if relX >= 0 and relY >= 0 then
local col = math.floor(relX / 4)
local row = relY
if col >= 0 and col <= 3 and row >= 0 and row <= 3 then
local slot = row * 4 + col + 1
local item = turtle.getItemDetail(slot)
if item then
state.dragItem = {
id = item.name,
sym = item.name:sub(11, 11):upper(),
color = colors.white
}
end
end
end
handled = true
end
end
if not handled and mx >= 1 and mx <= 3 and my == 1 then
state.menuOpen = not state.menuOpen
handled = true
end
local palX = 2 + state.w + 2
if not handled and mx >= palX and mx <= palX + 18 then -- Expanded for Search button
if my == 2 then
if mx >= palX + 14 and mx <= palX + 17 then
state.searchOpen = not state.searchOpen
if state.searchOpen then
state.searchQuery = ""
updateSearchResults()
end
elseif mx <= palX + 13 then
state.paletteEditMode = not state.paletteEditMode
end
handled = true
elseif my >= 4 and my < 4 + #state.palette then
local idx = my - 3
if state.paletteEditMode then
editPaletteItem(idx)
else
if btn == 1 then state.primaryColor = idx
elseif btn == 2 then state.secondaryColor = idx end
end
handled = true
end
end
if not handled and mx >= 1 and mx <= 3 and my >= 3 and my < 3 + 8 then
local idx = my - 2
local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
if toolsList[idx] then state.tool = toolsList[idx] end
handled = true
end
if not handled then
local cx = mx - state.view.offsetX
local cy = my - state.view.offsetY
if cx >= 0 and cx < state.w and cy >= 0 and cy < state.h then
state.mouse.down = true
state.mouse.btn = btn
state.mouse.startX = cx
state.mouse.startY = cy
state.mouse.currX = cx
state.mouse.currY = cy
if state.tool == TOOLS.PENCIL or state.tool == TOOLS.BUCKET or state.tool == TOOLS.PICKER then
applyTool(cx, cy, btn)
end
end
end
elseif event == "mouse_drag" then
local btn, mx, my = p1, p2, p3
state.mouse.screenX = mx
state.mouse.screenY = my
local cx = mx - state.view.offsetX
local cy = my - state.view.offsetY
if state.mouse.down then
cx = math.max(0, math.min(state.w - 1, cx))
cy = math.max(0, math.min(state.h - 1, cy))
state.mouse.currX = cx
state.mouse.currY = cy
state.mouse.drag = true
if state.tool == TOOLS.PENCIL then
applyTool(cx, cy, state.mouse.btn)
end
end
elseif event == "mouse_up" then
local btn, mx, my = p1, p2, p3
if state.dragItem then
local palX = 2 + state.w + 2
if mx >= palX and mx <= palX + 15 and my >= 4 and my < 4 + #state.palette then
local idx = my - 3
state.palette[idx].id = state.dragItem.id
state.palette[idx].sym = state.dragItem.sym
state.status = "Assigned " .. state.dragItem.id .. " to slot " .. idx
end
state.dragItem = nil
end
if state.mouse.down and state.mouse.drag then
if state.tool == TOOLS.LINE or state.tool == TOOLS.RECT or state.tool == TOOLS.RECT_FILL or state.tool == TOOLS.CIRCLE then
applyShape(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, state.mouse.btn)
end
end
state.mouse.down = false
state.mouse.drag = false
elseif event == "key" then
local key = p1
if state.searchOpen then
if key == keys.backspace then
state.searchQuery = state.searchQuery:sub(1, -2)
updateSearchResults()
elseif key == keys.enter then
if #state.searchResults > 0 then
local item = state.searchResults[1]
state.dragItem = { id = item.id, sym = item.sym, color = item.color }
state.searchOpen = false
end
elseif key == keys.up then
state.searchScroll = math.max(0, state.searchScroll - 1)
elseif key == keys.down then
state.searchScroll = state.searchScroll + 1
end
else
if key == keys.up then
state.view.cursorY = math.max(0, state.view.cursorY - 1)
if state.view.cursorY < state.view.scrollY then state.view.scrollY = state.view.cursorY end
if state.mouse.drag then state.mouse.currY = state.view.cursorY end
elseif key == keys.down then
state.view.cursorY = math.min(state.h - 1, state.view.cursorY + 1)
local h = term.getSize()
local viewH = h - 2 - state.view.offsetY
if state.view.cursorY >= state.view.scrollY + viewH then state.view.scrollY = state.view.cursorY - viewH + 1 end
if state.mouse.drag then state.mouse.currY = state.view.cursorY end
elseif key == keys.left then
state.view.cursorX = math.max(0, state.view.cursorX - 1)
if state.view.cursorX < state.view.scrollX then state.view.scrollX = state.view.cursorX end
if state.mouse.drag then state.mouse.currX = state.view.cursorX end
elseif key == keys.right then
state.view.cursorX = math.min(state.w - 1, state.view.cursorX + 1)
local w = term.getSize()
local viewW = w - state.view.offsetX
if state.view.cursorX >= state.view.scrollX + viewW then state.view.scrollX = state.view.cursorX - viewW + 1 end
if state.mouse.drag then state.mouse.currX = state.view.cursorX end
elseif key == keys.space or key == keys.enter then
if state.tool == TOOLS.PENCIL or state.tool == TOOLS.BUCKET or state.tool == TOOLS.PICKER then
applyTool(state.view.cursorX, state.view.cursorY, 1)
else
if not state.mouse.drag then
state.mouse.startX = state.view.cursorX
state.mouse.startY = state.view.cursorY
state.mouse.currX = state.view.cursorX
state.mouse.currY = state.view.cursorY
state.mouse.drag = true
state.mouse.down = true
state.mouse.btn = 1
else
state.mouse.currX = state.view.cursorX
state.mouse.currY = state.view.cursorY
applyShape(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, 1)
state.mouse.drag = false
state.mouse.down = false
end
end
elseif key == keys.leftBracket then
state.primaryColor = math.max(1, state.primaryColor - 1)
elseif key == keys.rightBracket then
state.primaryColor = math.min(#state.palette, state.primaryColor + 1)
elseif key >= keys.one and key <= keys.eight then
local idx = key - keys.one + 1
local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
if toolsList[idx] then state.tool = toolsList[idx] end
end
if key == keys.q then state.running = false end
if key == keys.f then
state.searchOpen = not state.searchOpen
if state.searchOpen then
state.searchQuery = ""
updateSearchResults()
end
end
if key == keys.s then saveSchema() end
if key == keys.r then resizeCanvas() end
if key == keys.c then clearCanvas() end -- Clear all
if key == keys.pageUp then state.view.layer = math.min(state.d - 1, state.view.layer + 1) end
if key == keys.pageDown then state.view.layer = math.max(0, state.view.layer - 1) end
end
end
end
if opts.returnSchema then
return exportCanonical()
end
end
designer.loadCanonical = loadCanonical
designer.exportCanonical = exportCanonical
designer.exportVoxelDefinition = exportVoxelDefinition
return designer]]
files["lib/lib_diagnostics.lua"] = [[local diagnostics = {}
local function safeOrigin(origin)
if type(origin) ~= "table" then
return nil
end
return {
x = origin.x,
y = origin.y,
z = origin.z,
facing = origin.facing
}
end
local function normalizeStrategy(strategy)
if type(strategy) == "table" then
return strategy
end
return nil
end
local function snapshot(ctx)
if type(ctx) ~= "table" then
return { error = "missing context" }
end
local config = type(ctx.config) == "table" and ctx.config or {}
local origin = safeOrigin(ctx.origin)
local strategyLen = 0
if type(ctx.strategy) == "table" then
strategyLen = #ctx.strategy
end
local stamp
if os and type(os.time) == "function" then
stamp = os.time()
end
return {
state = ctx.state,
mode = config.mode,
pointer = ctx.pointer,
strategySize = strategyLen,
retries = ctx.retries,
missingMaterial = ctx.missingMaterial,
lastError = ctx.lastError,
origin = origin,
timestamp = stamp
}
end
local function requireStrategy(ctx)
local strategy = normalizeStrategy(ctx.strategy)
if strategy then
return strategy
end
local message = "Build strategy unavailable"
if ctx and ctx.logger then
ctx.logger:error(message, { context = snapshot(ctx) })
end
ctx.lastError = ctx.lastError or message
return nil, message
end
diagnostics.snapshot = snapshot
diagnostics.requireStrategy = requireStrategy
return diagnostics]]
files["lib/lib_farming.lua"] = [[local movement = require("lib_movement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local farming = {}
function farming.deposit(ctx, config)
local chests = config.chests or ctx.chests
if not chests then
logger.log(ctx, "error", "No chests defined for deposit.")
return false
end
logger.log(ctx, "info", "Heading home to deposit items...")
local safeHeight = config.safeHeight or 6
if not movement.goTo(ctx, { x=0, y=safeHeight, z=0 }) then
return false, "Failed to go home"
end
local descendRetries = 0
while movement.getPosition(ctx).y > 0 do
local hasDown, dataDown = turtle.inspectDown()
if hasDown and not dataDown.name:find("air") and not dataDown.name:find("chest") then
turtle.digDown()
end
if not movement.down(ctx) then
turtle.digDown()
end
descendRetries = descendRetries + 1
if descendRetries > 50 then
logger.log(ctx, "error", "Failed to descend to home level.")
return false, "Failed to descend"
end
end
if chests.output then
movement.face(ctx, chests.output)
logger.log(ctx, "info", "Dropping items...")
for i=1, 16 do
local item = turtle.getItemDetail(i)
if item then
local keepCount = 0
if config.keepItems then
for k, v in pairs(config.keepItems) do
if item.name == k or item.name:find(k) then
keepCount = v
break
end
end
end
if keepCount > 0 then
if item.count > keepCount then
turtle.select(i)
turtle.drop(item.count - keepCount)
end
else
local isFuel = turtle.refuel(0)
local isTrash = false
if config.trashItems then
for _, t in ipairs(config.trashItems) do
if item.name == t then isTrash = true break end
end
end
if not isFuel and not isTrash then
turtle.select(i)
turtle.drop()
end
end
end
end
end
if config.refuel and chests.fuel then
movement.face(ctx, chests.fuel)
logger.log(ctx, "info", "Refueling...")
turtle.suck()
fuelLib.refuel(ctx, { target = 1000 })
local item = turtle.getItemDetail()
if item and turtle.refuel(0) then
turtle.drop()
end
end
if chests.trash then
movement.face(ctx, chests.trash)
logger.log(ctx, "info", "Trashing junk...")
for i=1, 16 do
local item = turtle.getItemDetail(i)
if item then
local isTrash = false
if config.trashItems then
for _, t in ipairs(config.trashItems) do
if item.name == t then isTrash = true break end
end
end
local keepCount = 0
if config.keepItems then
for k, v in pairs(config.keepItems) do
if item.name == k or item.name:find(k) then
keepCount = v
break
end
end
end
local isFuel = turtle.refuel(0)
if isTrash or (keepCount == 0 and not isFuel) then
turtle.select(i)
turtle.drop()
end
end
end
end
return true
end
return farming]]
files["lib/lib_fs.lua"] = [[local fs_utils = {}
local createdArtifacts = {}
function fs_utils.stageArtifact(path)
for _, existing in ipairs(createdArtifacts) do
if existing == path then
return
end
end
createdArtifacts[#createdArtifacts + 1] = path
end
function fs_utils.writeFile(path, contents)
if type(path) ~= "string" or path == "" then
return false, "invalid_path"
end
if fs and fs.open then
local handle = fs.open(path, "w")
if not handle then
return false, "open_failed"
end
handle.write(contents)
handle.close()
return true
end
if io and io.open then
local handle, err = io.open(path, "w")
if not handle then
return false, err or "open_failed"
end
handle:write(contents)
handle:close()
return true
end
return false, "fs_unavailable"
end
function fs_utils.deleteFile(path)
if fs and fs.delete and fs.exists then
local ok, exists = pcall(fs.exists, path)
if ok and exists then
fs.delete(path)
end
return true
end
if os and os.remove then
os.remove(path)
return true
end
return false
end
function fs_utils.readFile(path)
if type(path) ~= "string" or path == "" then
return nil, "invalid_path"
end
if fs and fs.open then
local handle = fs.open(path, "r")
if not handle then
return nil, "open_failed"
end
local ok, contents = pcall(handle.readAll)
handle.close()
if not ok then
return nil, "read_failed"
end
return contents
end
if io and io.open then
local handle, err = io.open(path, "r")
if not handle then
return nil, err or "open_failed"
end
local contents = handle:read("*a")
handle:close()
return contents
end
return nil, "fs_unavailable"
end
function fs_utils.cleanupArtifacts()
for index = #createdArtifacts, 1, -1 do
local path = createdArtifacts[index]
fs_utils.deleteFile(path)
createdArtifacts[index] = nil
end
end
return fs_utils]]
files["lib/lib_fuel.lua"] = [[local movement = require("lib_movement")
local inventory = require("lib_inventory")
local table_utils = require("lib_table")
local logger = require("lib_logger")
local fuel = {}
local DEFAULT_THRESHOLD = 80
local DEFAULT_RESERVE = 160
local DEFAULT_SIDES = { "forward", "down", "up" }
local DEFAULT_FUEL_ITEMS = {
"minecraft:coal",
"minecraft:charcoal",
"minecraft:coal_block",
"minecraft:lava_bucket",
"minecraft:blaze_rod",
"minecraft:dried_kelp_block",
}
local function ensureFuelState(ctx)
if type(ctx) ~= "table" then
error("fuel library requires a context table", 2)
end
ctx.fuelState = ctx.fuelState or {}
local state = ctx.fuelState
local cfg = ctx.config or {}
state.threshold = state.threshold or cfg.fuelThreshold or cfg.minFuel or DEFAULT_THRESHOLD
state.reserve = state.reserve or cfg.fuelReserve or math.max(DEFAULT_RESERVE, state.threshold * 2)
state.fuelItems = state.fuelItems or (cfg.fuelItems and #cfg.fuelItems > 0 and table_utils.copyArray(cfg.fuelItems)) or table_utils.copyArray(DEFAULT_FUEL_ITEMS)
state.sides = state.sides or (cfg.fuelChestSides and #cfg.fuelChestSides > 0 and table_utils.copyArray(cfg.fuelChestSides)) or table_utils.copyArray(DEFAULT_SIDES)
state.cycleLimit = state.cycleLimit or cfg.fuelCycleLimit or cfg.inventoryCycleLimit or 192
state.history = state.history or {}
state.serviceActive = state.serviceActive or false
state.lastLevel = state.lastLevel or nil
return state
end
function fuel.ensureState(ctx)
return ensureFuelState(ctx)
end
local function readFuel()
if not turtle or not turtle.getFuelLevel then
return nil, nil, false
end
local level = turtle.getFuelLevel()
local limit = turtle.getFuelLimit and turtle.getFuelLimit() or nil
if level == "unlimited" or limit == "unlimited" then
return nil, nil, true
end
if level == math.huge or limit == math.huge then
return nil, nil, true
end
if type(level) ~= "number" then
return nil, nil, false
end
if type(limit) ~= "number" then
limit = nil
end
return level, limit, false
end
local function resolveTarget(state, opts)
opts = opts or {}
local target = opts.target or 0
if type(target) ~= "number" or target <= 0 then
target = 0
end
local threshold = opts.threshold or state.threshold or 0
local reserve = opts.reserve or state.reserve or 0
if threshold > target then
target = threshold
end
if reserve > target then
target = reserve
end
if target <= 0 then
target = threshold > 0 and threshold or DEFAULT_THRESHOLD
end
return target
end
local function resolveSides(state, opts)
opts = opts or {}
if type(opts.sides) == "table" and #opts.sides > 0 then
return table_utils.copyArray(opts.sides)
end
return table_utils.copyArray(state.sides)
end
local function resolveFuelItems(state, opts)
opts = opts or {}
if type(opts.fuelItems) == "table" and #opts.fuelItems > 0 then
return table_utils.copyArray(opts.fuelItems)
end
return table_utils.copyArray(state.fuelItems)
end
local function recordHistory(state, entry)
state.history = state.history or {}
state.history[#state.history + 1] = entry
local limit = 20
while #state.history > limit do
table.remove(state.history, 1)
end
end
local function consumeFromInventory(ctx, target, opts)
if not turtle or type(turtle.refuel) ~= "function" then
return false, { error = "turtle API unavailable" }
end
local before = select(1, readFuel())
if before == nil then
return false, { error = "fuel unreadable" }
end
target = target or 0
if target <= 0 then
return false, {
consumed = {},
startLevel = before,
endLevel = before,
note = "no_target",
}
end
local level = before
local consumed = {}
for slot = 1, 16 do
if target > 0 and level >= target then
break
end
local item = turtle.getItemDetail(slot)
local shouldSkip = false
if item and opts and opts.excludeItems then
for _, pattern in ipairs(opts.excludeItems) do
if item.name:find(pattern) then
shouldSkip = true
break
end
end
end
if not shouldSkip then
turtle.select(slot)
local count = turtle.getItemCount(slot)
local canRefuel = count and count > 0 and turtle.refuel(0)
if canRefuel then
while (target <= 0 or level < target) and turtle.getItemCount(slot) > 0 do
if not turtle.refuel(1) then
break
end
consumed[slot] = (consumed[slot] or 0) + 1
level = select(1, readFuel()) or level
if target > 0 and level >= target then
break
end
end
end
end
end
local after = select(1, readFuel()) or level
if inventory.invalidate then
inventory.invalidate(ctx)
end
return (after > before), {
consumed = consumed,
startLevel = before,
endLevel = after,
}
end
local function pullFromSources(ctx, state, opts)
if not turtle then
return false, { error = "turtle API unavailable" }
end
inventory.ensureState(ctx)
local sides = resolveSides(state, opts)
local items = resolveFuelItems(state, opts)
local pulled = {}
local errors = {}
local attempts = 0
local maxAttempts = opts and opts.maxPullAttempts or (#sides * #items)
if maxAttempts < 1 then
maxAttempts = #sides * #items
end
local cycleLimit = (opts and opts.inventoryCycleLimit) or state.cycleLimit or 192
for _, side in ipairs(sides) do
for _, material in ipairs(items) do
if attempts >= maxAttempts then
break
end
attempts = attempts + 1
local ok, err = inventory.pullMaterial(ctx, material, nil, {
side = side,
deferScan = true,
cycleLimit = cycleLimit,
})
if ok then
pulled[#pulled + 1] = { side = side, material = material }
logger.log(ctx, "debug", string.format("Pulled %s from %s", material, side))
elseif err ~= "missing_material" then
errors[#errors + 1] = { side = side, material = material, error = err }
logger.log(ctx, "warn", string.format("Pull %s from %s failed: %s", material, side, tostring(err)))
end
end
if attempts >= maxAttempts then
break
end
end
if #pulled > 0 then
inventory.invalidate(ctx)
end
return #pulled > 0, { pulled = pulled, errors = errors }
end
local function refuelRound(ctx, state, opts, target, report)
local consumed, info = consumeFromInventory(ctx, target, opts)
report.steps[#report.steps + 1] = {
type = "inventory",
round = report.round,
success = consumed,
info = info,
}
if consumed then
logger.log(ctx, "debug", string.format("Consumed %d fuel items from inventory", table_utils.sumValues(info and info.consumed)))
end
local level = select(1, readFuel())
if level and level >= target and target > 0 then
report.finalLevel = level
report.reachedTarget = true
return true, report
end
local pulled, pullInfo = pullFromSources(ctx, state, opts)
report.steps[#report.steps + 1] = {
type = "pull",
round = report.round,
success = pulled,
info = pullInfo,
}
if pulled then
local consumedAfterPull, postInfo = consumeFromInventory(ctx, target, opts)
report.steps[#report.steps + 1] = {
type = "inventory",
stage = "post_pull",
round = report.round,
success = consumedAfterPull,
info = postInfo,
}
if consumedAfterPull then
logger.log(ctx, "debug", string.format("Post-pull consumption used %d fuel items", table_utils.sumValues(postInfo and postInfo.consumed)))
local postLevel = select(1, readFuel())
if postLevel and postLevel >= target and target > 0 then
report.finalLevel = postLevel
report.reachedTarget = true
return true, report
end
end
end
return (pulled or consumed), report
end
local function refuelInternal(ctx, state, opts)
local startLevel, limit, unlimited = readFuel()
if unlimited then
return true, {
startLevel = startLevel,
limit = limit,
finalLevel = startLevel,
unlimited = true,
}
end
if not startLevel then
return true, {
startLevel = nil,
limit = limit,
finalLevel = nil,
message = "fuel level unavailable",
}
end
local target = resolveTarget(state, opts)
local report = {
startLevel = startLevel,
limit = limit,
target = target,
steps = {},
}
local rounds = opts and opts.rounds or 3
if rounds < 1 then
rounds = 1
end
for i = 1, rounds do
report.round = i
local ok, roundReport = refuelRound(ctx, state, opts, target, report)
report = roundReport
if report.reachedTarget then
return true, report
end
if not ok then
break
end
end
report.finalLevel = select(1, readFuel()) or startLevel
if report.finalLevel and report.finalLevel >= target and target > 0 then
report.reachedTarget = true
return true, report
end
report.reachedTarget = target <= 0
return report.reachedTarget, report
end
function fuel.check(ctx, opts)
local state = ensureFuelState(ctx)
local level, limit, unlimited = readFuel()
state.lastLevel = level or state.lastLevel
local report = {
level = level,
limit = limit,
unlimited = unlimited,
threshold = state.threshold,
reserve = state.reserve,
history = state.history,
}
if unlimited then
report.ok = true
return true, report
end
if not level then
report.ok = true
report.note = "fuel level unavailable"
return true, report
end
local threshold = opts and opts.threshold or state.threshold or 0
report.threshold = threshold
report.reserve = opts and opts.reserve or state.reserve
report.ok = level >= threshold
report.needsService = not report.ok
report.depleted = level <= 0
return report.ok, report
end
function fuel.refuel(ctx, opts)
local state = ensureFuelState(ctx)
local ok, report = refuelInternal(ctx, state, opts)
recordHistory(state, {
type = "refuel",
timestamp = os and os.time and os.time() or nil,
success = ok,
report = report,
})
if ok then
logger.log(ctx, "info", string.format("Refuel complete (fuel=%s)", tostring(report.finalLevel or "unknown")))
else
logger.log(ctx, "warn", "Refuel attempt did not reach target level")
end
return ok, report
end
function fuel.ensure(ctx, opts)
local state = ensureFuelState(ctx)
local ok, report = fuel.check(ctx, opts)
if ok then
return true, report
end
if opts and opts.nonInteractive then
return false, report
end
local serviceOk, serviceReport = fuel.service(ctx, opts)
if not serviceOk then
report.service = serviceReport
return false, report
end
return fuel.check(ctx, opts)
end
local function bootstrapFuel(ctx, state, opts, report)
logger.log(ctx, "warn", "Fuel depleted; attempting to consume onboard fuel before navigating")
local minimumMove = opts and opts.minimumMoveFuel or math.max(10, state.threshold or 0)
if minimumMove <= 0 then
minimumMove = 10
end
local consumed, info = consumeFromInventory(ctx, minimumMove, opts)
report.steps[#report.steps + 1] = {
type = "inventory",
stage = "bootstrap",
success = consumed,
info = info,
}
local level = select(1, readFuel()) or (info and info.endLevel) or report.startLevel
report.bootstrapLevel = level
if level <= 0 then
logger.log(ctx, "error", "Fuel depleted; cannot move to origin")
report.error = "out_of_fuel"
report.finalLevel = level
return false, report
end
return true, report
end
local function runService(ctx, state, opts, report)
state.serviceActive = true
logger.log(ctx, "info", "Entering SERVICE mode: returning to origin for refuel")
local ok, err = movement.returnToOrigin(ctx, opts and opts.navigation)
if not ok then
state.serviceActive = false
logger.log(ctx, "error", "SERVICE return failed: " .. tostring(err))
report.returnError = err
return false, report
end
report.steps[#report.steps + 1] = { type = "return", success = true }
local refuelOk, refuelReport = refuelInternal(ctx, state, opts)
report.steps[#report.steps + 1] = {
type = "refuel",
success = refuelOk,
report = refuelReport,
}
state.serviceActive = false
recordHistory(state, {
type = "service",
timestamp = os and os.time and os.time() or nil,
success = refuelOk,
report = report,
})
if not refuelOk then
logger.log(ctx, "warn", "SERVICE refuel did not reach target level")
report.finalLevel = select(1, readFuel()) or (refuelReport and refuelReport.finalLevel) or report.startLevel
return false, report
end
local finalLevel = select(1, readFuel()) or refuelReport.finalLevel
report.finalLevel = finalLevel
logger.log(ctx, "info", string.format("SERVICE complete (fuel=%s)", tostring(finalLevel or "unknown")))
return true, report
end
function fuel.service(ctx, opts)
local state = ensureFuelState(ctx)
if state.serviceActive then
return false, { error = "service_already_active" }
end
inventory.ensureState(ctx)
movement.ensureState(ctx)
local level, limit, unlimited = readFuel()
local report = {
startLevel = level,
limit = limit,
steps = {},
}
if unlimited then
report.note = "fuel is unlimited"
return true, report
end
if not level then
logger.log(ctx, "warn", "Fuel level unavailable; skipping service")
report.error = "fuel_unreadable"
return false, report
end
if level <= 0 then
local ok, bootstrapReport = bootstrapFuel(ctx, state, opts, report)
if not ok then
return false, bootstrapReport
end
report = bootstrapReport
end
return runService(ctx, state, opts, report)
end
function fuel.resolveFuelThreshold(ctx)
local threshold = 0
local function consider(value)
if type(value) == "number" and value > threshold then
threshold = value
end
end
if type(ctx.fuelState) == "table" then
local fuel = ctx.fuelState
consider(fuel.threshold)
consider(fuel.reserve)
consider(fuel.min)
consider(fuel.minFuel)
consider(fuel.low)
end
if type(ctx.config) == "table" then
local cfg = ctx.config
consider(cfg.fuelThreshold)
consider(cfg.fuelReserve)
consider(cfg.minFuel)
end
return threshold
end
function fuel.isFuelLow(ctx)
if not turtle or not turtle.getFuelLevel then
return false
end
local level = turtle.getFuelLevel()
if level == "unlimited" then
return false
end
if type(level) ~= "number" then
return false
end
local threshold = fuel.resolveFuelThreshold(ctx)
if threshold <= 0 then
return false
end
return level <= threshold
end
function fuel.describeFuel(io, report)
if not io.print then
return
end
if report.unlimited then
io.print("Fuel: unlimited")
return
end
local levelText = report.level and tostring(report.level) or "unknown"
local limitText = report.limit and ("/" .. tostring(report.limit)) or ""
io.print(string.format("Fuel level: %s%s", levelText, limitText))
if report.threshold then
io.print(string.format("Threshold: %d", report.threshold))
end
if report.reserve then
io.print(string.format("Reserve target: %d", report.reserve))
end
if report.needsService then
io.print("Status: below threshold (service required)")
else
io.print("Status: sufficient for now")
end
end
function fuel.describeService(io, report)
if not io.print then
return
end
if not report then
io.print("No service report available.")
return
end
if report.returnError then
io.print("Return-to-origin failed: " .. tostring(report.returnError))
end
if report.steps then
for _, step in ipairs(report.steps) do
if step.type == "return" then
io.print("Return to origin: " .. (step.success and "OK" or "FAIL"))
elseif step.type == "refuel" then
local info = step.report or {}
local final = info.finalLevel ~= nil and info.finalLevel or (info.endLevel or "unknown")
io.print(string.format("Refuel step: %s (final=%s)", step.success and "OK" or "FAIL", tostring(final)))
end
end
end
if report.finalLevel then
io.print("Service final fuel level: " .. tostring(report.finalLevel))
end
end
return fuel]]
files["lib/lib_games.lua"] = [=[local ui = require("lib_ui")
local games = {}
local function createDeck()
local suits = {"H", "D", "C", "S"}
local ranks = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}
local deck = {}
for _, s in ipairs(suits) do
for _, r in ipairs(ranks) do
table.insert(deck, { suit = s, rank = r, faceUp = false })
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
local function drawCard(x, y, card, selected)
local color = (card.suit == "H" or card.suit == "D") and colors.red or colors.black
local bg = selected and colors.yellow or colors.white
if not card.faceUp then
term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
term.setCursorPos(x, y)
term.write("##")
return
end
term.setBackgroundColor(bg)
term.setTextColor(color)
term.setCursorPos(x, y)
local r = card.rank
if #r == 1 then r = r .. " " end
term.write(r)
term.setCursorPos(x, y+1)
term.write(card.suit .. " ")
end
function games.minesweeper()
local w, h = 16, 16
local mines = 40
local grid = {}
local revealed = {}
local flagged = {}
local gameOver = false
local win = false
for x = 1, w do
grid[x] = {}
revealed[x] = {}
flagged[x] = {}
for y = 1, h do
grid[x][y] = 0
revealed[x][y] = false
flagged[x][y] = false
end
end
local placed = 0
while placed < mines do
local x, y = math.random(w), math.random(h)
if grid[x][y] ~= -1 then
grid[x][y] = -1
placed = placed + 1
for dx = -1, 1 do
for dy = -1, 1 do
local nx, ny = x + dx, y + dy
if nx >= 1 and nx <= w and ny >= 1 and ny <= h and grid[nx][ny] ~= -1 then
grid[nx][ny] = grid[nx][ny] + 1
end
end
end
end
end
local function draw()
ui.clear()
ui.drawFrame(1, 1, w + 2, h + 2, "Minesweeper")
for x = 1, w do
for y = 1, h do
term.setCursorPos(x + 1, y + 1)
if revealed[x][y] then
if grid[x][y] == -1 then
term.setBackgroundColor(colors.red)
term.setTextColor(colors.black)
term.write("*")
elseif grid[x][y] == 0 then
term.setBackgroundColor(colors.lightGray)
term.write(" ")
else
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
term.write(tostring(grid[x][y]))
end
elseif flagged[x][y] then
term.setBackgroundColor(colors.gray)
term.setTextColor(colors.red)
term.write("F")
else
term.setBackgroundColor(colors.gray)
term.write(" ")
end
end
end
if gameOver then
ui.drawBox(5, 8, 12, 3, colors.red, colors.white)
ui.label(6, 9, win and "YOU WIN!" or "GAME OVER")
ui.button(6, 10, "Click to exit", true)
end
end
local function reveal(x, y)
if x < 1 or x > w or y < 1 or y > h or revealed[x][y] or flagged[x][y] then return end
revealed[x][y] = true
if grid[x][y] == -1 then
gameOver = true
win = false
elseif grid[x][y] == 0 then
for dx = -1, 1 do
for dy = -1, 1 do
reveal(x + dx, y + dy)
end
end
end
end
while true do
draw()
local event, p1, p2, p3 = os.pullEvent("mouse_click")
local btn, mx, my = p1, p2, p3
if gameOver then return end
local gx, gy = mx - 1, my - 1
if gx >= 1 and gx <= w and gy >= 1 and gy <= h then
if btn == 1 then -- Left click
reveal(gx, gy)
elseif btn == 2 then -- Right click
if not revealed[gx][gy] then
flagged[gx][gy] = not flagged[gx][gy]
end
end
end
local covered = 0
for x = 1, w do
for y = 1, h do
if not revealed[x][y] then covered = covered + 1 end
end
end
if covered == mines then
gameOver = true
win = true
end
end
end
function games.solitaire()
local deck = createDeck()
shuffle(deck)
local piles = {} -- 7 tableau piles
local foundations = {{}, {}, {}, {}} -- 4 foundations
local stock = {}
local waste = {}
for i = 1, 7 do
piles[i] = {}
for j = 1, i do
local card = table.remove(deck)
if j == i then card.faceUp = true end
table.insert(piles[i], card)
end
end
stock = deck
local selected = nil -- { type="pile"|"waste", index=1, cardIndex=1 }
local function draw()
ui.clear()
ui.drawFrame(1, 1, 50, 19, "Solitaire")
if #stock > 0 then
drawCard(2, 2, {suit="?", rank="?", faceUp=false}, false)
else
ui.label(2, 2, "[]")
end
if #waste > 0 then
local card = waste[#waste]
card.faceUp = true
drawCard(6, 2, card, selected and selected.type == "waste")
end
for i = 1, 4 do
local x = 15 + (i-1)*4
if #foundations[i] > 0 then
drawCard(x, 2, foundations[i][#foundations[i]], false)
else
ui.label(x, 2, "[]")
end
end
for i = 1, 7 do
local x = 2 + (i-1)*5
if #piles[i] == 0 then
ui.label(x, 5, "[]")
else
for j, card in ipairs(piles[i]) do
local y = 5 + (j-1)
if y < 18 then
local isSel = selected and selected.type == "pile" and selected.index == i and selected.cardIndex == j
drawCard(x, y, card, isSel)
end
end
end
end
end
local function canStack(bottom, top)
if not bottom then return top.rank == "K" end -- Empty pile needs King
local ranks = {A=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, J=11, Q=12, K=13}
local red = {H=true, D=true}
local bottomRed = red[bottom.suit]
local topRed = red[top.suit]
return (bottomRed ~= topRed) and (ranks[bottom.rank] == ranks[top.rank] + 1)
end
local function canFoundation(foundation, card)
local ranks = {A=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, J=11, Q=12, K=13}
if #foundation == 0 then return card.rank == "A" end
local top = foundation[#foundation]
return top.suit == card.suit and ranks[card.rank] == ranks[top.rank] + 1
end
while true do
draw()
local event, p1, p2, p3 = os.pullEvent()
if event == "key" and p1 == keys.q then return end
if event == "mouse_click" then
local btn, mx, my = p1, p2, p3
if my >= 2 and my <= 3 and mx >= 2 and mx <= 4 then
if #stock > 0 then
table.insert(waste, table.remove(stock))
else
while #waste > 0 do
local c = table.remove(waste)
c.faceUp = false
table.insert(stock, c)
end
end
selected = nil
elseif my >= 2 and my <= 3 and mx >= 6 and mx <= 8 and #waste > 0 then
if selected and selected.type == "waste" then
selected = nil
else
selected = { type = "waste" }
end
elseif my >= 2 and my <= 3 and mx >= 15 and mx <= 30 then
local fIdx = math.floor((mx - 15) / 4) + 1
if fIdx >= 1 and fIdx <= 4 then
if selected then
local card
if selected.type == "waste" then card = waste[#waste]
elseif selected.type == "pile" then
local p = piles[selected.index]
if selected.cardIndex == #p then card = p[#p] end
end
if card and canFoundation(foundations[fIdx], card) then
table.insert(foundations[fIdx], card)
if selected.type == "waste" then table.remove(waste)
else table.remove(piles[selected.index]) end
if selected.type == "pile" then
local p = piles[selected.index]
if #p > 0 then p[#p].faceUp = true end
end
selected = nil
end
end
end
elseif my >= 5 then
local pIdx = math.floor((mx - 2) / 5) + 1
if pIdx >= 1 and pIdx <= 7 then
local p = piles[pIdx]
local cIdx = my - 4
if cIdx <= #p and cIdx > 0 then
local card = p[cIdx]
if card.faceUp then
if selected then
if selected.type == "pile" and selected.index == pIdx then
selected = nil -- Deselect self
else
local srcCard
if selected.type == "waste" then srcCard = waste[#waste]
elseif selected.type == "pile" then srcCard = piles[selected.index][selected.cardIndex] end
if srcCard and canStack(card, srcCard) then
if selected.type == "waste" then
table.insert(p, table.remove(waste))
else
local srcPile = piles[selected.index]
local moving = {}
for k = selected.cardIndex, #srcPile do
table.insert(moving, srcPile[k])
end
for k = #srcPile, selected.cardIndex, -1 do
table.remove(srcPile)
end
for _, m in ipairs(moving) do table.insert(p, m) end
if #srcPile > 0 then srcPile[#srcPile].faceUp = true end
end
selected = nil
else
selected = { type = "pile", index = pIdx, cardIndex = cIdx }
end
end
else
selected = { type = "pile", index = pIdx, cardIndex = cIdx }
end
end
elseif #p == 0 and cIdx == 1 then
if selected then
local srcCard
if selected.type == "waste" then srcCard = waste[#waste]
elseif selected.type == "pile" then srcCard = piles[selected.index][selected.cardIndex] end
if srcCard and canStack(nil, srcCard) then
if selected.type == "waste" then
table.insert(p, table.remove(waste))
else
local srcPile = piles[selected.index]
local moving = {}
for k = selected.cardIndex, #srcPile do
table.insert(moving, srcPile[k])
end
for k = #srcPile, selected.cardIndex, -1 do
table.remove(srcPile)
end
for _, m in ipairs(moving) do table.insert(p, m) end
if #srcPile > 0 then srcPile[#srcPile].faceUp = true end
end
selected = nil
end
end
end
end
end
end
end
end
function games.euchre()
local function createEuchreDeck()
local suits = {"H", "D", "C", "S"}
local ranks = {"9", "10", "J", "Q", "K", "A"}
local deck = {}
for _, s in ipairs(suits) do
for _, r in ipairs(ranks) do
table.insert(deck, { suit = s, rank = r, faceUp = true })
end
end
return deck
end
local deck = createEuchreDeck()
shuffle(deck)
local hands = {{}, {}, {}, {}} -- 1=Human, 2=Left, 3=Partner, 4=Right
for i=1,4 do
for j=1,5 do table.insert(hands[i], table.remove(deck)) end
end
local trump = nil
local turn = 1
local tricks = {0, 0} -- Team 1 (Human/Partner), Team 2 (Opponents)
local currentTrick = {}
local function aiPlay(handIdx)
local hand = hands[handIdx]
local leadSuit = nil
if #currentTrick > 0 then leadSuit = currentTrick[1].card.suit end
for i, c in ipairs(hand) do
if not leadSuit or c.suit == leadSuit then
table.remove(hand, i)
return c
end
end
return table.remove(hand, 1) -- Fallback (renege possible in this simple logic, but ok for now)
end
local function draw()
ui.clear()
ui.drawFrame(1, 1, 50, 19, "Euchre")
ui.label(20, 2, "Partner")
ui.label(2, 9, "Left")
ui.label(45, 9, "Right")
ui.label(20, 17, "You")
ui.label(2, 2, "Tricks: " .. tricks[1] .. " - " .. tricks[2])
if trump then ui.label(40, 2, "Trump: " .. trump) end
for _, play in ipairs(currentTrick) do
local x, y = 25, 10
if play.player == 1 then y = 12
elseif play.player == 2 then x = 15
elseif play.player == 3 then y = 8
elseif play.player == 4 then x = 35 end
drawCard(x, y, play.card, false)
end
for i, card in ipairs(hands[1]) do
drawCard(10 + (i-1)*5, 15, card, false)
end
end
local kitty = deck[1]
trump = kitty.suit -- Force trump for simplicity in this version
while true do
draw()
if #currentTrick == 4 then
sleep(1)
local winner = math.random(1, 2)
tricks[winner] = tricks[winner] + 1
currentTrick = {}
if #hands[1] == 0 then
ui.clear()
print("Game Over. Team " .. (tricks[1] > tricks[2] and "1" or "2") .. " wins!")
sleep(2)
return
end
end
if turn == 1 then
local event, p1, p2, p3 = os.pullEvent("mouse_click")
if event == "mouse_click" then
local mx, my = p2, p3
if my >= 15 and my <= 16 then
local idx = math.floor((mx - 10) / 5) + 1
if idx >= 1 and idx <= #hands[1] then
local card = table.remove(hands[1], idx)
table.insert(currentTrick, { player = 1, card = card })
turn = 2
end
end
end
else
sleep(0.5)
local card = aiPlay(turn)
table.insert(currentTrick, { player = turn, card = card })
turn = (turn % 4) + 1
end
end
end
return games]=]
files["lib/lib_gps.lua"] = [[local gps_utils = {}
function gps_utils.detectFacingWithGps(logger)
if not gps or type(gps.locate) ~= "function" then
return nil, "gps_unavailable"
end
if not turtle or type(turtle.forward) ~= "function" or type(turtle.back) ~= "function" then
return nil, "turtle_api_unavailable"
end
local function locate(timeout)
local ok, x, y, z = pcall(gps.locate, timeout)
if ok and x then
return x, y, z
end
return nil, nil, nil
end
local x1, _, z1 = locate(0.5)
if not x1 then
x1, _, z1 = locate(1)
if not x1 then
return nil, "gps_initial_failed"
end
end
if not turtle.forward() then
return nil, "forward_blocked"
end
local x2, _, z2 = locate(0.5)
if not x2 then
x2, _, z2 = locate(1)
end
local returned = turtle.back()
if not returned then
local attempts = 0
while attempts < 5 and not returned do
returned = turtle.back()
attempts = attempts + 1
if not returned and sleep then
sleep(0)
end
end
if not returned then
if logger then
logger:warn("Facing detection failed to restore the turtle's start position; adjust the turtle manually and rerun.")
end
return nil, "return_failed"
end
end
if not x2 then
return nil, "gps_second_failed"
end
local dx = x2 - x1
local dz = z2 - z1
local threshold = 0.2
if math.abs(dx) < threshold and math.abs(dz) < threshold then
return nil, "gps_delta_small"
end
if math.abs(dx) >= math.abs(dz) then
if dx > threshold then
return "east"
elseif dx < -threshold then
return "west"
end
else
if dz > threshold then
return "south"
elseif dz < -threshold then
return "north"
end
end
return nil, "gps_delta_small"
end
return gps_utils]]
files["lib/lib_initialize.lua"] = [[local inventory = require("lib_inventory")
local logger = require("lib_logger")
local world = require("lib_world")
local table_utils = require("lib_table")
local initialize = {}
local DEFAULT_SIDES = { "forward", "down", "up", "left", "right", "back" }
local function mapSides(opts)
local sides = {}
local seen = {}
if type(opts) == "table" and type(opts.sides) == "table" then
for _, side in ipairs(opts.sides) do
local normalised = world.normaliseSide(side)
if normalised and not seen[normalised] then
sides[#sides + 1] = normalised
seen[normalised] = true
end
end
end
if #sides == 0 then
for _, side in ipairs(DEFAULT_SIDES) do
local normalised = world.normaliseSide(side)
if normalised and not seen[normalised] then
sides[#sides + 1] = normalised
seen[normalised] = true
end
end
end
return sides
end
local function normaliseManifest(manifest)
local result = {}
if type(manifest) ~= "table" then
return result
end
local function push(material, count)
if type(material) ~= "string" or material == "" then
return
end
if material == "minecraft:air" or material == "air" then
return
end
if type(count) ~= "number" or count <= 0 then
return
end
result[material] = math.max(result[material] or 0, math.floor(count))
end
local isArray = manifest[1] ~= nil
if isArray then
for _, entry in ipairs(manifest) do
if type(entry) == "table" then
local count = entry.count or entry.quantity or entry.amount or entry.required
push(entry.material or entry.name or entry.id, count or entry[2])
elseif type(entry) == "string" then
push(entry, 1)
end
end
else
for material, count in pairs(manifest) do
push(material, count)
end
end
return result
end
local function listChestTotals(peripheralObj)
local totals = {}
if type(peripheralObj) ~= "table" then
return totals
end
local ok, items = pcall(function()
if type(peripheralObj.list) == "function" then
return peripheralObj.list()
end
return nil
end)
if not ok or type(items) ~= "table" then
return totals
end
for _, stack in pairs(items) do
if type(stack) == "table" then
local name = stack.name or stack.id
local count = stack.count or stack.qty or stack.quantity
if type(name) == "string" and type(count) == "number" and count > 0 then
totals[name] = (totals[name] or 0) + count
end
end
end
return totals
end
local function gatherChestDataForSide(side, entries, combined)
local periphSide = world.toPeripheralSide(side) or side
local inspectOk, inspectDetail = world.inspectSide(side)
local inspectIsContainer = inspectOk and world.isContainer(inspectDetail)
local inspectName = nil
if inspectIsContainer and type(inspectDetail) == "table" and type(inspectDetail.name) == "string" and inspectDetail.name ~= "" then
inspectName = inspectDetail.name
end
local wrapOk, wrapped = pcall(peripheral.wrap, periphSide)
if not wrapOk then
wrapped = nil
end
local metaName, metaTags
if wrapped then
if type(peripheral.call) == "function" then
local metaOk, metadata = pcall(peripheral.call, periphSide, "getMetadata")
if metaOk and type(metadata) == "table" then
metaName = metadata.name or metadata.displayName or metaName
metaTags = metadata.tags
end
end
if not metaName and type(peripheral.getType) == "function" then
local typeOk, perType = pcall(peripheral.getType, periphSide)
if typeOk then
if type(perType) == "string" then
metaName = perType
elseif type(perType) == "table" and type(perType[1]) == "string" then
metaName = perType[1]
end
end
end
end
local metaIsContainer = false
if metaName then
metaIsContainer = world.isContainer({ name = metaName, tags = metaTags })
end
local hasInventoryMethods = wrapped and (type(wrapped.list) == "function" or type(wrapped.size) == "function")
local containerDetected = inspectIsContainer or metaIsContainer or hasInventoryMethods
if containerDetected then
local containerName = inspectName or metaName or "container"
if wrapped and hasInventoryMethods then
local totals = listChestTotals(wrapped)
table_utils.mergeTotals(combined, totals)
entries[#entries + 1] = {
side = side,
name = containerName,
totals = totals,
}
else
entries[#entries + 1] = {
side = side,
name = containerName,
totals = {},
error = "wrap_failed",
}
end
end
end
local function gatherChestData(ctx, opts)
local entries = {}
local combined = {}
if not peripheral then
return entries, combined
end
for _, side in ipairs(mapSides(opts)) do
gatherChestDataForSide(side, entries, combined)
end
if next(combined) == nil then
combined = {}
end
return entries, combined
end
local function gatherTurtleTotals(ctx)
local totals = {}
local ok, err = inventory.scan(ctx, { force = true })
if not ok then
return totals, err
end
local observed, mapErr = inventory.getTotals(ctx, { force = true })
if not observed then
return totals, mapErr
end
for material, count in pairs(observed) do
if type(count) == "number" and count > 0 then
totals[material] = count
end
end
return totals
end
local function summariseMissing(manifest, totals)
local missing = {}
for material, required in pairs(manifest) do
local have = totals[material] or 0
if have < required then
missing[#missing + 1] = {
material = material,
required = required,
have = have,
missing = required - have,
}
end
end
table.sort(missing, function(a, b)
if a.missing == b.missing then
return a.material < b.material
end
return a.missing > b.missing
end)
return missing
end
local function promptUser(report, attempt, opts)
if not read then
return false
end
print("\nMissing materials detected:")
for _, entry in ipairs(report.missing or {}) do
print(string.format(" - %s: need %d (have %d, short %d)", entry.material, entry.required, entry.have, entry.missing))
end
print("Add materials to the turtle or connected chests, then press Enter to retry.")
print("Type 'cancel' to abort.")
if type(write) == "function" then
write("> ")
end
local response = read()
if response and string.lower(response) == "cancel" then
return false
end
return true
end
local function checkMaterialsInternal(ctx, manifest, opts)
local report = {
manifest = table_utils.copyTotals(manifest),
}
if next(manifest) == nil then
report.ok = true
return true, report
end
local turtleTotals, invErr = gatherTurtleTotals(ctx)
if invErr then
report.inventoryError = invErr
logger.log(ctx, "warn", "Inventory scan failed: " .. tostring(invErr))
end
report.turtleTotals = table_utils.copyTotals(turtleTotals)
local chestEntries, chestTotals = gatherChestData(ctx, opts)
report.chests = chestEntries
report.chestTotals = table_utils.copyTotals(chestTotals)
local combinedTotals = table_utils.copyTotals(turtleTotals)
table_utils.mergeTotals(combinedTotals, chestTotals)
report.combinedTotals = combinedTotals
report.missing = summariseMissing(manifest, combinedTotals)
if #report.missing == 0 then
report.ok = true
return true, report
end
report.ok = false
return false, report
end
function initialize.checkMaterials(ctx, spec, opts)
opts = opts or {}
spec = spec or {}
local manifestSrc = spec.manifest or spec.materials or spec
if not manifestSrc and type(ctx) == "table" and type(ctx.schemaInfo) == "table" then
manifestSrc = ctx.schemaInfo.materials
end
local manifest = normaliseManifest(manifestSrc)
return checkMaterialsInternal(ctx, manifest, opts)
end
function initialize.ensureMaterials(ctx, spec, opts)
opts = opts or {}
local attempt = 0
while true do
local ok, report = initialize.checkMaterials(ctx, spec, opts)
if ok then
logger.log(ctx, "info", "Material check passed.")
return true, report
end
logger.log(ctx, "warn", "Materials missing; print halted.")
if opts.nonInteractive then
return false, report
end
attempt = attempt + 1
local continue = promptUser(report, attempt, opts)
if not continue then
return false, report
end
end
end
return initialize]]
files["lib/lib_inventory.lua"] = [[local inventory = {}
local movement = require("lib_movement")
local logger = require("lib_logger")
local SIDE_ACTIONS = {
forward = {
drop = turtle and turtle.drop or nil,
suck = turtle and turtle.suck or nil,
},
up = {
drop = turtle and turtle.dropUp or nil,
suck = turtle and turtle.suckUp or nil,
},
down = {
drop = turtle and turtle.dropDown or nil,
suck = turtle and turtle.suckDown or nil,
},
}
local PUSH_TARGETS = {
"front",
"back",
"left",
"right",
"top",
"bottom",
"north",
"south",
"east",
"west",
"up",
"down",
}
local OPPOSITE_FACING = {
north = "south",
south = "north",
east = "west",
west = "east",
}
local CONTAINER_KEYWORDS = {
"chest",
"barrel",
"shulker",
"crate",
"storage",
"inventory",
}
inventory.DEFAULT_TRASH = {
["minecraft:air"] = true,
["minecraft:stone"] = true,
["minecraft:cobblestone"] = true,
["minecraft:deepslate"] = true,
["minecraft:cobbled_deepslate"] = true,
["minecraft:tuff"] = true,
["minecraft:diorite"] = true,
["minecraft:granite"] = true,
["minecraft:andesite"] = true,
["minecraft:calcite"] = true,
["minecraft:netherrack"] = true,
["minecraft:end_stone"] = true,
["minecraft:basalt"] = true,
["minecraft:blackstone"] = true,
["minecraft:gravel"] = true,
["minecraft:dirt"] = true,
["minecraft:coarse_dirt"] = true,
["minecraft:rooted_dirt"] = true,
["minecraft:mycelium"] = true,
["minecraft:sand"] = true,
["minecraft:red_sand"] = true,
["minecraft:sandstone"] = true,
["minecraft:red_sandstone"] = true,
["minecraft:clay"] = true,
["minecraft:dripstone_block"] = true,
["minecraft:pointed_dripstone"] = true,
["minecraft:bedrock"] = true,
["minecraft:lava"] = true,
["minecraft:water"] = true,
}
local function noop()
end
local function normalizeSide(value)
if type(value) ~= "string" then
return nil
end
local lower = value:lower()
if lower == "forward" or lower == "front" or lower == "fwd" then
return "forward"
end
if lower == "up" or lower == "top" or lower == "above" then
return "up"
end
if lower == "down" or lower == "bottom" or lower == "below" then
return "down"
end
return nil
end
local function resolveSide(ctx, opts)
if type(opts) == "string" then
local direct = normalizeSide(opts)
return direct or "forward"
end
local candidate
if type(opts) == "table" then
candidate = opts.side or opts.direction or opts.facing or opts.containerSide or opts.defaultSide
if not candidate and type(opts.location) == "string" then
candidate = opts.location
end
end
if not candidate and type(ctx) == "table" then
local cfg = ctx.config
if type(cfg) == "table" then
candidate = cfg.inventorySide or cfg.materialSide or cfg.supplySide or cfg.defaultInventorySide
end
if not candidate and type(ctx.inventoryState) == "table" then
candidate = ctx.inventoryState.defaultSide
end
end
local normalised = normalizeSide(candidate)
if normalised then
return normalised
end
return "forward"
end
local function tableCount(tbl)
if type(tbl) ~= "table" then
return 0
end
local count = 0
for _ in pairs(tbl) do
count = count + 1
end
return count
end
local function copyArray(list)
if type(list) ~= "table" then
return {}
end
local result = {}
for index = 1, #list do
result[index] = list[index]
end
return result
end
local function copySummary(summary)
if type(summary) ~= "table" then
return {}
end
local result = {}
for key, value in pairs(summary) do
result[key] = value
end
return result
end
local function copySlots(slots)
if type(slots) ~= "table" then
return {}
end
local result = {}
for slot, info in pairs(slots) do
if type(info) == "table" then
result[slot] = {
slot = info.slot,
count = info.count,
name = info.name,
detail = info.detail,
}
else
result[slot] = info
end
end
return result
end
local function hasContainerTag(tags)
if type(tags) ~= "table" then
return false
end
for key, value in pairs(tags) do
if value and type(key) == "string" then
local lower = key:lower()
for _, keyword in ipairs(CONTAINER_KEYWORDS) do
if lower:find(keyword, 1, true) then
return true
end
end
end
end
return false
end
local function isContainerBlock(name, tags)
if type(name) ~= "string" then
return false
end
local lower = name:lower()
for _, keyword in ipairs(CONTAINER_KEYWORDS) do
if lower:find(keyword, 1, true) then
return true
end
end
return hasContainerTag(tags)
end
local function inspectForwardForContainer()
if not turtle or type(turtle.inspect) ~= "function" then
return false
end
local ok, data = turtle.inspect()
if not ok or type(data) ~= "table" then
return false
end
if isContainerBlock(data.name, data.tags) then
return true, data
end
return false
end
local function inspectUpForContainer()
if not turtle or type(turtle.inspectUp) ~= "function" then
return false
end
local ok, data = turtle.inspectUp()
if not ok or type(data) ~= "table" then
return false
end
if isContainerBlock(data.name, data.tags) then
return true, data
end
return false
end
local function inspectDownForContainer()
if not turtle or type(turtle.inspectDown) ~= "function" then
return false
end
local ok, data = turtle.inspectDown()
if not ok or type(data) ~= "table" then
return false
end
if isContainerBlock(data.name, data.tags) then
return true, data
end
return false
end
local function shouldSearchAllSides(opts)
if type(opts) ~= "table" then
return true
end
if opts.searchAllSides == false then
return false
end
return true
end
local function peripheralSideForDirection(side)
if side == "forward" or side == "front" then
return "front"
end
if side == "up" or side == "top" then
return "top"
end
if side == "down" or side == "bottom" then
return "bottom"
end
return side
end
local function computePrimaryPushDirection(ctx, periphSide)
if periphSide == "front" then
local facing = movement.getFacing(ctx)
if facing then
return OPPOSITE_FACING[facing]
end
elseif periphSide == "top" then
return "down"
elseif periphSide == "bottom" then
return "up"
end
return nil
end
local function tryPushItems(chest, periphSide, slot, amount, targetSlot, primaryDirection)
if type(chest) ~= "table" or type(chest.pushItems) ~= "function" then
return 0
end
local tried = {}
local function attempt(direction)
if not direction or tried[direction] then
return 0
end
tried[direction] = true
local ok, moved
if targetSlot then
ok, moved = pcall(chest.pushItems, direction, slot, amount, targetSlot)
else
ok, moved = pcall(chest.pushItems, direction, slot, amount)
end
if ok and type(moved) == "number" and moved > 0 then
return moved
end
return 0
end
local moved = attempt(primaryDirection)
if moved > 0 then
return moved
end
for _, direction in ipairs(PUSH_TARGETS) do
moved = attempt(direction)
if moved > 0 then
return moved
end
end
return 0
end
local function collectStacks(chest, material)
local stacks = {}
if type(chest) ~= "table" or not material then
return stacks
end
if type(chest.list) == "function" then
local ok, list = pcall(chest.list)
if ok and type(list) == "table" then
for slot, stack in pairs(list) do
local numericSlot = tonumber(slot)
if numericSlot and type(stack) == "table" then
local name = stack.name or stack.id
local count = stack.count or stack.qty or stack.quantity or 0
if name == material and type(count) == "number" and count > 0 then
stacks[#stacks + 1] = { slot = numericSlot, count = count }
end
end
end
end
end
if #stacks == 0 and type(chest.size) == "function" and type(chest.getItemDetail) == "function" then
local okSize, size = pcall(chest.size)
if okSize and type(size) == "number" and size > 0 then
for slot = 1, size do
local okDetail, detail = pcall(chest.getItemDetail, slot)
if okDetail and type(detail) == "table" then
local name = detail.name
local count = detail.count or detail.qty or detail.quantity or 0
if name == material and type(count) == "number" and count > 0 then
stacks[#stacks + 1] = { slot = slot, count = count }
end
end
end
end
end
table.sort(stacks, function(a, b)
return a.slot < b.slot
end)
return stacks
end
local function newContainerManifest()
return {
totals = {},
slots = {},
totalItems = 0,
orderedSlots = {},
size = nil,
metadata = nil,
}
end
local function addManifestEntry(manifest, slot, stack)
if type(manifest) ~= "table" or type(slot) ~= "number" then
return
end
if type(stack) ~= "table" then
return
end
local name = stack.name or stack.id
local count = stack.count or stack.qty or stack.quantity or stack.Count
if type(name) ~= "string" or type(count) ~= "number" or count <= 0 then
return
end
manifest.slots[slot] = {
name = name,
count = count,
tags = stack.tags,
nbt = stack.nbt,
displayName = stack.displayName or stack.label or stack.Name,
detail = stack,
}
manifest.totals[name] = (manifest.totals[name] or 0) + count
manifest.totalItems = manifest.totalItems + count
end
local function populateManifestSlots(manifest)
local ordered = {}
for slot in pairs(manifest.slots) do
ordered[#ordered + 1] = slot
end
table.sort(ordered)
manifest.orderedSlots = ordered
local materials = {}
for material in pairs(manifest.totals) do
materials[#materials + 1] = material
end
table.sort(materials)
manifest.materials = materials
end
local function attachMetadata(manifest, periphSide)
if not peripheral then
return
end
local metadata = manifest.metadata or {}
if type(peripheral.call) == "function" then
local okMeta, meta = pcall(peripheral.call, periphSide, "getMetadata")
if okMeta and type(meta) == "table" then
metadata.name = meta.name or metadata.name
metadata.displayName = meta.displayName or meta.label or metadata.displayName
metadata.tags = meta.tags or metadata.tags
end
end
if type(peripheral.getType) == "function" then
local okType, perType = pcall(peripheral.getType, periphSide)
if okType then
if type(perType) == "string" then
metadata.peripheralType = perType
elseif type(perType) == "table" and type(perType[1]) == "string" then
metadata.peripheralType = perType[1]
end
end
end
if next(metadata) ~= nil then
manifest.metadata = metadata
end
end
local function readContainerManifest(periphSide)
if not peripheral or type(peripheral.wrap) ~= "function" then
return nil, "peripheral_api_unavailable"
end
local wrapOk, chest = pcall(peripheral.wrap, periphSide)
if not wrapOk or type(chest) ~= "table" then
return nil, "wrap_failed"
end
local manifest = newContainerManifest()
if type(chest.list) == "function" then
local okList, list = pcall(chest.list)
if okList and type(list) == "table" then
for slot, stack in pairs(list) do
local numericSlot = tonumber(slot)
if numericSlot then
addManifestEntry(manifest, numericSlot, stack)
end
end
end
end
local haveSlots = next(manifest.slots) ~= nil
if type(chest.size) == "function" then
local okSize, size = pcall(chest.size)
if okSize and type(size) == "number" and size >= 0 then
manifest.size = size
if not haveSlots and type(chest.getItemDetail) == "function" then
for slot = 1, size do
local okDetail, detail = pcall(chest.getItemDetail, slot)
if okDetail then
addManifestEntry(manifest, slot, detail)
end
end
end
end
end
populateManifestSlots(manifest)
attachMetadata(manifest, periphSide)
return manifest
end
local function extractFromContainer(ctx, periphSide, material, amount, targetSlot)
if not material or not peripheral or type(peripheral.wrap) ~= "function" then
return 0
end
local wrapOk, chest = pcall(peripheral.wrap, periphSide)
if not wrapOk or type(chest) ~= "table" then
return 0
end
if type(chest.pushItems) ~= "function" then
return 0
end
local desired = amount
if not desired or desired <= 0 then
desired = 64
end
local stacks = collectStacks(chest, material)
if #stacks == 0 then
return 0
end
local remaining = desired
local transferred = 0
local primaryDirection = computePrimaryPushDirection(ctx, periphSide)
for _, stack in ipairs(stacks) do
local available = stack.count or 0
while remaining > 0 and available > 0 do
local toMove = math.min(available, remaining, 64)
local moved = tryPushItems(chest, periphSide, stack.slot, toMove, targetSlot, primaryDirection)
if moved <= 0 then
break
end
transferred = transferred + moved
remaining = remaining - moved
available = available - moved
end
if remaining <= 0 then
break
end
end
return transferred
end
local function ensureChestAhead(ctx, opts)
local frontOk, frontDetail = inspectForwardForContainer()
if frontOk then
return true, noop, { side = "forward", detail = frontDetail }
end
if not shouldSearchAllSides(opts) then
return false, nil, nil, "container_not_found"
end
if not turtle then
return false, nil, nil, "turtle_api_unavailable"
end
movement.ensureState(ctx)
local startFacing = movement.getFacing(ctx)
local function restoreFacing()
if not startFacing then
return
end
if movement.getFacing(ctx) ~= startFacing then
local okFace, faceErr = movement.faceDirection(ctx, startFacing)
if not okFace and faceErr then
logger.log(ctx, "warn", "Failed to restore facing: " .. tostring(faceErr))
end
end
end
local function makeRestore()
if not startFacing then
return noop
end
return function()
restoreFacing()
end
end
local ok, err = movement.turnLeft(ctx)
if not ok then
restoreFacing()
return false, nil, nil, err or "turn_failed"
end
local leftOk, leftDetail = inspectForwardForContainer()
if leftOk then
logger.log(ctx, "debug", "Found container on left side; using that")
return true, makeRestore(), { side = "left", detail = leftDetail }
end
ok, err = movement.turnRight(ctx)
if not ok then
restoreFacing()
return false, nil, nil, err or "turn_failed"
end
ok, err = movement.turnRight(ctx)
if not ok then
restoreFacing()
return false, nil, nil, err or "turn_failed"
end
local rightOk, rightDetail = inspectForwardForContainer()
if rightOk then
logger.log(ctx, "debug", "Found container on right side; using that")
return true, makeRestore(), { side = "right", detail = rightDetail }
end
ok, err = movement.turnLeft(ctx)
if not ok then
restoreFacing()
return false, nil, nil, err or "turn_failed"
end
ok, err = movement.turnRight(ctx)
if not ok then
restoreFacing()
return false, nil, nil, err or "turn_failed"
end
ok, err = movement.turnRight(ctx)
if not ok then
restoreFacing()
return false, nil, nil, err or "turn_failed"
end
local backOk, backDetail = inspectForwardForContainer()
if backOk then
logger.log(ctx, "debug", "Found container behind; using that")
return true, makeRestore(), { side = "back", detail = backDetail }
end
ok, err = movement.turnLeft(ctx)
if not ok then
restoreFacing()
return false, nil, nil, err or "turn_failed"
end
ok, err = movement.turnLeft(ctx)
if not ok then
restoreFacing()
return false, nil, nil, err or "turn_failed"
end
restoreFacing()
return false, nil, nil, "container_not_found"
end
local function ensureInventoryState(ctx)
if type(ctx) ~= "table" then
error("inventory library requires a context table", 2)
end
if type(ctx.inventoryState) ~= "table" then
ctx.inventoryState = ctx.inventory or {}
end
ctx.inventory = ctx.inventoryState
local state = ctx.inventoryState
state.scanVersion = state.scanVersion or 0
state.slots = state.slots or {}
state.materialSlots = state.materialSlots or {}
state.materialTotals = state.materialTotals or {}
state.emptySlots = state.emptySlots or {}
state.totalItems = state.totalItems or 0
if state.dirty == nil then
state.dirty = true
end
return state
end
function inventory.ensureState(ctx)
return ensureInventoryState(ctx)
end
function inventory.invalidate(ctx)
local state = ensureInventoryState(ctx)
state.dirty = true
return true
end
local function fetchSlotDetail(slot)
if not turtle then
return { slot = slot, count = 0 }
end
local detail
if turtle.getItemDetail then
detail = turtle.getItemDetail(slot)
end
local count
if turtle.getItemCount then
count = turtle.getItemCount(slot)
elseif detail then
count = detail.count
end
count = count or 0
local name = detail and detail.name or nil
return {
slot = slot,
count = count,
name = name,
detail = detail,
}
end
function inventory.scan(ctx, opts)
local state = ensureInventoryState(ctx)
if not turtle then
state.slots = {}
state.materialSlots = {}
state.materialTotals = {}
state.emptySlots = {}
state.totalItems = 0
state.dirty = false
state.scanVersion = state.scanVersion + 1
return false, "turtle API unavailable"
end
local slots = {}
local materialSlots = {}
local materialTotals = {}
local emptySlots = {}
local totalItems = 0
for slot = 1, 16 do
local info = fetchSlotDetail(slot)
slots[slot] = info
if info.count > 0 and info.name then
local list = materialSlots[info.name]
if not list then
list = {}
materialSlots[info.name] = list
end
list[#list + 1] = slot
materialTotals[info.name] = (materialTotals[info.name] or 0) + info.count
totalItems = totalItems + info.count
else
emptySlots[#emptySlots + 1] = slot
end
end
state.slots = slots
state.materialSlots = materialSlots
state.materialTotals = materialTotals
state.emptySlots = emptySlots
state.totalItems = totalItems
if os and type(os.clock) == "function" then
state.lastScanClock = os.clock()
else
state.lastScanClock = nil
end
local epochFn = os and os["epoch"]
if type(epochFn) == "function" then
state.lastScanEpoch = epochFn("utc")
else
state.lastScanEpoch = nil
end
state.scanVersion = state.scanVersion + 1
state.dirty = false
logger.log(ctx, "debug", string.format("Inventory scan complete: %d items across %d materials", totalItems, tableCount(materialSlots)))
return true
end
local function ensureScanned(ctx, opts)
local state = ensureInventoryState(ctx)
if state.dirty or (type(opts) == "table" and opts.force) or not state.slots or next(state.slots) == nil then
local ok, err = inventory.scan(ctx, opts)
if not ok and err then
return nil, err
end
end
return state
end
function inventory.getMaterialSlots(ctx, material, opts)
if type(material) ~= "string" or material == "" then
return nil, "invalid_material"
end
local state, err = ensureScanned(ctx, opts)
if not state then
return nil, err
end
local slots = state.materialSlots[material]
if not slots then
return {}
end
return copyArray(slots)
end
function inventory.getSlotForMaterial(ctx, material, opts)
local slots, err = inventory.getMaterialSlots(ctx, material, opts)
if slots == nil then
return nil, err
end
if slots[1] then
return slots[1]
end
return nil, "missing_material"
end
function inventory.countMaterial(ctx, material, opts)
if type(material) ~= "string" or material == "" then
return 0, "invalid_material"
end
local state, err = ensureScanned(ctx, opts)
if not state then
return 0, err
end
return state.materialTotals[material] or 0
end
function inventory.hasMaterial(ctx, material, amount, opts)
amount = amount or 1
if amount <= 0 then
return true
end
local total, err = inventory.countMaterial(ctx, material, opts)
if err then
return false, err
end
return total >= amount
end
function inventory.findEmptySlot(ctx, opts)
local state, err = ensureScanned(ctx, opts)
if not state then
return nil, err
end
local empty = state.emptySlots
if empty and empty[1] then
return empty[1]
end
return nil, "no_empty_slot"
end
function inventory.isEmpty(ctx, opts)
local state, err = ensureScanned(ctx, opts)
if not state then
return false, err
end
return state.totalItems == 0
end
function inventory.totalItemCount(ctx, opts)
local state, err = ensureScanned(ctx, opts)
if not state then
return 0, err
end
return state.totalItems
end
function inventory.getTotals(ctx, opts)
local state, err = ensureScanned(ctx, opts)
if not state then
return nil, err
end
return copySummary(state.materialTotals)
end
function inventory.snapshot(ctx, opts)
local state, err = ensureScanned(ctx, opts)
if not state then
return nil, err
end
return {
slots = copySlots(state.slots),
totals = copySummary(state.materialTotals),
emptySlots = copyArray(state.emptySlots),
totalItems = state.totalItems,
scanVersion = state.scanVersion,
lastScanClock = state.lastScanClock,
lastScanEpoch = state.lastScanEpoch,
}
end
function inventory.detectContainer(ctx, opts)
opts = opts or {}
local side = resolveSide(ctx, opts)
if side == "forward" then
local chestOk, restoreFn, info, err = ensureChestAhead(ctx, opts)
if not chestOk then
return nil, err or "container_not_found"
end
if type(restoreFn) == "function" then
restoreFn()
end
local result = info or { side = "forward" }
result.peripheralSide = "front"
return result
elseif side == "up" then
local okUp, detail = inspectUpForContainer()
if okUp then
return { side = "up", detail = detail, peripheralSide = "top" }
end
return nil, "container_not_found"
elseif side == "down" then
local okDown, detail = inspectDownForContainer()
if okDown then
return { side = "down", detail = detail, peripheralSide = "bottom" }
end
return nil, "container_not_found"
end
return nil, "unsupported_side"
end
function inventory.getContainerManifest(ctx, opts)
if not turtle then
return nil, "turtle API unavailable"
end
opts = opts or {}
local side = resolveSide(ctx, opts)
local periphSide = peripheralSideForDirection(side)
local restoreFacing = noop
local info
if side == "forward" then
local chestOk, restoreFn, chestInfo, err = ensureChestAhead(ctx, opts)
if not chestOk then
return nil, err or "container_not_found"
end
if type(restoreFn) == "function" then
restoreFacing = restoreFn
end
info = chestInfo or { side = "forward" }
periphSide = "front"
elseif side == "up" then
local okUp, detail = inspectUpForContainer()
if not okUp then
return nil, "container_not_found"
end
info = { side = "up", detail = detail }
periphSide = "top"
elseif side == "down" then
local okDown, detail = inspectDownForContainer()
if not okDown then
return nil, "container_not_found"
end
info = { side = "down", detail = detail }
periphSide = "bottom"
else
return nil, "unsupported_side"
end
local manifest, manifestErr = readContainerManifest(periphSide)
restoreFacing()
if not manifest then
return nil, manifestErr or "wrap_failed"
end
manifest.peripheralSide = periphSide
if info then
manifest.relativeSide = info.side
manifest.inspectDetail = info.detail
if not manifest.metadata and info.detail then
manifest.metadata = {
name = info.detail.name,
displayName = info.detail.displayName or info.detail.label,
tags = info.detail.tags,
}
elseif manifest.metadata and info.detail then
manifest.metadata.name = manifest.metadata.name or info.detail.name
manifest.metadata.displayName = manifest.metadata.displayName or info.detail.displayName or info.detail.label
manifest.metadata.tags = manifest.metadata.tags or info.detail.tags
end
end
return manifest
end
function inventory.selectMaterial(ctx, material, opts)
if not turtle then
return false, "turtle API unavailable"
end
local slot, err = inventory.getSlotForMaterial(ctx, material, opts)
if not slot then
return false, err or "missing_material"
end
if turtle.select(slot) then
return true
end
return false, "select_failed"
end
local function selectSlot(slot)
if not turtle then
return false, "turtle API unavailable"
end
if type(slot) ~= "number" or slot < 1 or slot > 16 then
return false, "invalid_slot"
end
if turtle.select(slot) then
return true
end
return false, "select_failed"
end
local function rescanIfNeeded(ctx, opts)
if opts and opts.deferScan then
inventory.invalidate(ctx)
return
end
local ok, err = inventory.scan(ctx)
if not ok and err then
logger.log(ctx, "warn", "Inventory rescan failed: " .. tostring(err))
inventory.invalidate(ctx)
end
end
function inventory.pushSlot(ctx, slot, amount, opts)
if not turtle then
return false, "turtle API unavailable"
end
local side = resolveSide(ctx, opts)
local actions = SIDE_ACTIONS[side]
if not actions or type(actions.drop) ~= "function" then
return false, "invalid_side"
end
local ok, err = selectSlot(slot)
if not ok then
return false, err
end
local restoreFacing = noop
if side == "forward" then
local chestOk, restoreFn, _, searchErr = ensureChestAhead(ctx, opts)
if not chestOk then
return false, searchErr or "container_not_found"
end
if type(restoreFn) == "function" then
restoreFacing = restoreFn
end
elseif side == "up" then
local okUp = inspectUpForContainer()
if not okUp then
return false, "container_not_found"
end
elseif side == "down" then
local okDown = inspectDownForContainer()
if not okDown then
return false, "container_not_found"
end
end
local count = turtle.getItemCount and turtle.getItemCount(slot) or nil
if count ~= nil and count <= 0 then
restoreFacing()
return false, "empty_slot"
end
if amount and amount > 0 then
ok = actions.drop(amount)
else
ok = actions.drop()
end
if not ok then
restoreFacing()
return false, "drop_failed"
end
restoreFacing()
rescanIfNeeded(ctx, opts)
return true
end
function inventory.pushMaterial(ctx, material, amount, opts)
if type(material) ~= "string" or material == "" then
return false, "invalid_material"
end
local slot, err = inventory.getSlotForMaterial(ctx, material, opts)
if not slot then
return false, err or "missing_material"
end
return inventory.pushSlot(ctx, slot, amount, opts)
end
local function resolveTargetSlotForPull(state, material, opts)
if opts and opts.slot then
return opts.slot
end
if material then
local materialSlots = state.materialSlots[material]
if materialSlots and materialSlots[1] then
return materialSlots[1]
end
end
local empty = state.emptySlots
if empty and empty[1] then
return empty[1]
end
return nil
end
function inventory.pullMaterial(ctx, material, amount, opts)
if not turtle then
return false, "turtle API unavailable"
end
local state, err = ensureScanned(ctx, opts)
if not state then
return false, err
end
local side = resolveSide(ctx, opts)
local actions = SIDE_ACTIONS[side]
if not actions or type(actions.suck) ~= "function" then
return false, "invalid_side"
end
if material ~= nil and (type(material) ~= "string" or material == "") then
return false, "invalid_material"
end
local targetSlot = resolveTargetSlotForPull(state, material, opts)
if not targetSlot then
return false, "no_empty_slot"
end
local ok, selectErr = selectSlot(targetSlot)
if not ok then
return false, selectErr
end
local periphSide = peripheralSideForDirection(side)
local restoreFacing = noop
if side == "forward" then
local chestOk, restoreFn, _, searchErr = ensureChestAhead(ctx, opts)
if not chestOk then
return false, searchErr or "container_not_found"
end
if type(restoreFn) == "function" then
restoreFacing = restoreFn
end
elseif side == "up" then
local okUp = inspectUpForContainer()
if not okUp then
return false, "container_not_found"
end
elseif side == "down" then
local okDown = inspectDownForContainer()
if not okDown then
return false, "container_not_found"
end
end
local desired = nil
if material then
if amount and amount > 0 then
desired = math.min(amount, 64)
else
desired = nil
end
elseif amount and amount > 0 then
desired = amount
end
local transferred = 0
if material then
transferred = extractFromContainer(ctx, periphSide, material, desired, targetSlot)
if transferred > 0 then
restoreFacing()
rescanIfNeeded(ctx, opts)
return true
end
end
if material == nil then
if amount and amount > 0 then
ok = actions.suck(amount)
else
ok = actions.suck()
end
if not ok then
restoreFacing()
return false, "suck_failed"
end
restoreFacing()
rescanIfNeeded(ctx, opts)
return true
end
local function makePushOpts()
local pushOpts = { side = side }
if type(opts) == "table" and opts.searchAllSides ~= nil then
pushOpts.searchAllSides = opts.searchAllSides
end
return pushOpts
end
local stashSlots = {}
local stashSet = {}
local function addStashSlot(slot)
stashSlots[#stashSlots + 1] = slot
stashSet[slot] = true
end
local function markSlotEmpty(slot)
if not slot then
return
end
local info = state.slots[slot]
if info then
info.count = 0
info.name = nil
info.detail = nil
end
for index = #state.emptySlots, 1, -1 do
if state.emptySlots[index] == slot then
return
end
end
state.emptySlots[#state.emptySlots + 1] = slot
end
local function freeAdditionalSlot()
local pushOpts = makePushOpts()
pushOpts.deferScan = true
for slot = 16, 1, -1 do
if slot ~= targetSlot and not stashSet[slot] then
local count = turtle.getItemCount(slot)
if count > 0 then
local info = state.slots[slot]
if not info or info.name ~= material then
local pushOk, pushErr = inventory.pushSlot(ctx, slot, nil, pushOpts)
if pushOk then
inventory.invalidate(ctx)
markSlotEmpty(slot)
local newState = ensureScanned(ctx, { force = true })
if newState then
state = newState
end
if turtle.getItemCount(slot) == 0 then
return slot
end
else
if pushErr then
logger.log(ctx, "debug", string.format("Unable to clear slot %d while restocking %s: %s", slot, material or "unknown", pushErr))
end
end
end
end
end
end
return nil
end
local function findTemporarySlot()
for slot = 1, 16 do
if slot ~= targetSlot and not stashSet[slot] and turtle.getItemCount(slot) == 0 then
return slot
end
end
local cleared = freeAdditionalSlot()
if cleared then
return cleared
end
for slot = 1, 16 do
if slot ~= targetSlot and not stashSet[slot] and turtle.getItemCount(slot) == 0 then
return slot
end
end
return nil
end
local function returnStash(deferScan)
if #stashSlots == 0 then
return
end
local pushOpts = makePushOpts()
pushOpts.deferScan = deferScan
for _, slot in ipairs(stashSlots) do
local pushOk, pushErr = inventory.pushSlot(ctx, slot, nil, pushOpts)
if not pushOk and pushErr then
logger.log(ctx, "warn", string.format("Failed to return cycled item from slot %d: %s", slot, tostring(pushErr)))
end
end
turtle.select(targetSlot)
inventory.invalidate(ctx)
local newState = ensureScanned(ctx, { force = true })
if newState then
state = newState
end
stashSlots = {}
stashSet = {}
end
local cycles = 0
local maxCycles = (type(opts) == "table" and opts.cycleLimit) or 48
local success = false
local failureReason
local cycled = 0
local assumedMatch = false
while cycles < maxCycles do
cycles = cycles + 1
local currentCount = turtle.getItemCount(targetSlot)
if desired and currentCount >= desired then
success = true
break
end
local need = desired and math.max(desired - currentCount, 1) or nil
local pulled
if need then
pulled = actions.suck(math.min(need, 64))
else
pulled = actions.suck()
end
if not pulled then
failureReason = failureReason or "suck_failed"
break
end
local detail
if turtle and turtle.getItemDetail then
detail = turtle.getItemDetail(targetSlot)
if detail == nil then
local okDetailed, detailed = pcall(turtle.getItemDetail, targetSlot, true)
if okDetailed then
detail = detailed
end
end
end
local updatedCount = turtle.getItemCount(targetSlot)
local assumedMatch = false
if not detail and material and updatedCount > 0 then
assumedMatch = true
end
if (detail and detail.name == material) or assumedMatch then
if not desired or updatedCount >= desired then
success = true
break
end
else
assumedMatch = false
local stashSlot = findTemporarySlot()
if not stashSlot then
failureReason = "no_empty_slot"
break
end
local moved = turtle.transferTo(stashSlot)
if not moved then
failureReason = "transfer_failed"
break
end
addStashSlot(stashSlot)
cycled = cycled + 1
inventory.invalidate(ctx)
turtle.select(targetSlot)
end
end
if success then
if assumedMatch then
logger.log(ctx, "debug", string.format("Pulled %s without detailed item metadata", material or "unknown"))
elseif cycled > 0 then
logger.log(ctx, "debug", string.format("Pulled %s after cycling %d other stacks", material, cycled))
else
logger.log(ctx, "debug", string.format("Pulled %s directly via turtle.suck", material))
end
returnStash(true)
restoreFacing()
rescanIfNeeded(ctx, opts)
return true
end
returnStash(true)
restoreFacing()
if failureReason then
logger.log(ctx, "debug", string.format("Failed to pull %s after cycling %d stacks: %s", material, cycled, failureReason))
end
if failureReason == "suck_failed" then
return false, "missing_material"
end
return false, failureReason or "missing_material"
end
function inventory.dumpTrash(ctx, trashList)
if not turtle then return false, "turtle API unavailable" end
trashList = trashList or inventory.DEFAULT_TRASH
local state, err = ensureScanned(ctx)
if not state then return false, err end
for slot, info in pairs(state.slots) do
if info and info.name and trashList[info.name] then
turtle.select(slot)
turtle.drop()
end
end
inventory.scan(ctx)
return true
end
function inventory.clearSlot(ctx, slot, opts)
if not turtle then
return false, "turtle API unavailable"
end
local state, err = ensureScanned(ctx, opts)
if not state then
return false, err
end
local info = state.slots[slot]
if not info or info.count == 0 then
return true
end
local ok, dropErr = inventory.pushSlot(ctx, slot, nil, opts)
if not ok then
return false, dropErr
end
return true
end
function inventory.describeMaterials(io, info)
if not io.print then
return
end
io.print("Schema manifest requirements:")
if not info or not info.materials then
io.print(" - <none>")
return
end
for _, entry in ipairs(info.materials) do
if entry.material ~= "minecraft:air" and entry.material ~= "air" then
io.print(string.format(" - %s x%d", entry.material, entry.count or 0))
end
end
end
function inventory.runCheck(ctx, io, opts)
local ok, report = initialize.ensureMaterials(ctx, { manifest = ctx.schemaInfo and ctx.schemaInfo.materials }, opts)
if io.print then
if ok then
io.print("Material check passed. Turtle and chests meet manifest requirements.")
else
io.print("Material check failed. Missing materials:")
for _, entry in ipairs(report.missing or {}) do
io.print(string.format(" - %s: need %d, have %d", entry.material, entry.required, entry.have))
end
end
end
return ok, report
end
function inventory.gatherSummary(io, report)
if not io.print then
return
end
io.print("\nDetailed totals:")
io.print(" Turtle inventory:")
for material, count in pairs(report.turtleTotals or {}) do
io.print(string.format("   - %s x%d", material, count))
end
io.print(" Nearby chests:")
for material, count in pairs(report.chestTotals or {}) do
io.print(string.format("   - %s x%d", material, count))
end
if #report.chests > 0 then
io.print(" Per-chest breakdown:")
for _, entry in ipairs(report.chests) do
io.print(string.format("   [%s] %s", entry.side, entry.name or "container"))
for material, count in pairs(entry.totals or {}) do
io.print(string.format("     * %s x%d", material, count))
end
end
end
end
function inventory.describeTotals(io, totals)
totals = totals or {}
local keys = {}
for material in pairs(totals) do
keys[#keys + 1] = material
end
table.sort(keys)
if io.print then
if #keys == 0 then
io.print("Inventory totals: <empty>")
else
io.print("Inventory totals:")
for _, material in ipairs(keys) do
io.print(string.format(" - %s x%d", material, totals[material] or 0))
end
end
end
end
function inventory.computeManifest(list)
local totals = {}
for _, sc in ipairs(list) do
if sc.material and sc.material ~= "" then
totals[sc.material] = (totals[sc.material] or 0) + 1
end
end
return totals
end
function inventory.printManifest(io, manifest)
if not io.print then
return
end
io.print("\nRequested manifest (minimum counts):")
local shown = false
for material, count in pairs(manifest) do
io.print(string.format(" - %s x%d", material, count))
shown = true
end
if not shown then
io.print(" - <empty>")
end
end
function inventory.condense(ctx)
if not turtle then return false, "turtle API unavailable" end
local state, err = ensureScanned(ctx)
if not state then return false, err end
local itemSlots = {}
for slot, info in pairs(state.slots) do
if info and info.name then
if not itemSlots[info.name] then
itemSlots[info.name] = {}
end
table.insert(itemSlots[info.name], slot)
end
end
local changes = false
for name, slots in pairs(itemSlots) do
if #slots > 1 then
table.sort(slots)
local targetIdx = 1
while targetIdx < #slots do
local targetSlot = slots[targetIdx]
local sourceIdx = targetIdx + 1
while sourceIdx <= #slots do
local sourceSlot = slots[sourceIdx]
local targetInfo = state.slots[targetSlot]
local sourceInfo = state.slots[sourceSlot]
if targetInfo and sourceInfo and targetInfo.count < 64 then
turtle.select(sourceSlot)
if turtle.transferTo(targetSlot) then
changes = true
end
end
if turtle.getItemCount(targetSlot) >= 64 then
break
end
sourceIdx = sourceIdx + 1
end
targetIdx = targetIdx + 1
end
end
end
if changes then
inventory.scan(ctx)
end
return true
end
function inventory.getCounts(ctx)
local counts = {}
for i = 1, 16 do
local item = turtle.getItemDetail(i)
if item then
counts[item.name] = (counts[item.name] or 0) + item.count
end
end
return counts
end
function inventory.retrieveFromNearby(ctx, missing)
local sides = {"front", "top", "bottom", "left", "right", "back"}
local pulledAny = false
for _, side in ipairs(sides) do
if peripheral.isPresent(side) then
local types = { peripheral.getType(side) }
local isInventory = false
for _, t in ipairs(types) do
if t == "inventory" then isInventory = true break end
end
if isInventory then
local p = peripheral.wrap(side)
if p and p.list then
local list = p.list()
local neededFromChest = {}
for slot, item in pairs(list) do
if item and missing[item.name] and missing[item.name] > 0 then
neededFromChest[item.name] = true
end
end
local hasNeeds = false
for k,v in pairs(neededFromChest) do hasNeeds = true break end
if hasNeeds then
local pullSide = "forward"
local turned = false
if side == "top" then pullSide = "up"
elseif side == "bottom" then pullSide = "down"
elseif side == "front" then pullSide = "forward"
elseif side == "left" then
movement.turnLeft(ctx)
turned = true
pullSide = "forward"
elseif side == "right" then
movement.turnRight(ctx)
turned = true
pullSide = "forward"
elseif side == "back" then
movement.turnRight(ctx)
movement.turnRight(ctx)
turned = true
pullSide = "forward"
end
for mat, _ in pairs(neededFromChest) do
local amount = missing[mat]
if amount > 0 then
print(string.format("Attempting to pull %s from %s...", mat, side))
local success, err = inventory.pullMaterial(ctx, mat, amount, { side = pullSide })
if success then
pulledAny = true
missing[mat] = math.max(0, missing[mat] - amount)
else
logger.log(ctx, "warn", "Failed to pull " .. mat .. ": " .. tostring(err))
end
end
end
if turned then
if side == "left" then movement.turnRight(ctx)
elseif side == "right" then movement.turnLeft(ctx)
elseif side == "back" then
movement.turnRight(ctx)
movement.turnRight(ctx)
end
end
end
end
end
end
end
return pulledAny
end
function inventory.checkNearby(ctx, missing)
local found = {}
local sides = {"front", "top", "bottom", "left", "right", "back"}
for _, side in ipairs(sides) do
if peripheral.isPresent(side) then
local types = { peripheral.getType(side) }
local isInventory = false
for _, t in ipairs(types) do
if t == "inventory" then isInventory = true break end
end
if isInventory then
local p = peripheral.wrap(side)
if p and p.list then
local list = p.list()
for slot, item in pairs(list) do
if item and missing[item.name] then
found[item.name] = (found[item.name] or 0) + item.count
end
end
end
end
end
end
return found
end
return inventory]]
files["lib/lib_items.lua"] = [[local items = {
{ id = "minecraft:stone", name = "Stone", color = colors.lightGray, sym = "#" },
{ id = "minecraft:granite", name = "Granite", color = colors.red, sym = "#" },
{ id = "minecraft:polished_granite", name = "Polished Granite", color = colors.red, sym = "#" },
{ id = "minecraft:diorite", name = "Diorite", color = colors.white, sym = "#" },
{ id = "minecraft:polished_diorite", name = "Polished Diorite", color = colors.white, sym = "#" },
{ id = "minecraft:andesite", name = "Andesite", color = colors.gray, sym = "#" },
{ id = "minecraft:polished_andesite", name = "Polished Andesite", color = colors.gray, sym = "#" },
{ id = "minecraft:grass_block", name = "Grass Block", color = colors.green, sym = "G" },
{ id = "minecraft:dirt", name = "Dirt", color = colors.brown, sym = "d" },
{ id = "minecraft:coarse_dirt", name = "Coarse Dirt", color = colors.brown, sym = "d" },
{ id = "minecraft:podzol", name = "Podzol", color = colors.brown, sym = "d" },
{ id = "minecraft:cobblestone", name = "Cobblestone", color = colors.gray, sym = "C" },
{ id = "minecraft:oak_planks", name = "Oak Planks", color = colors.brown, sym = "P" },
{ id = "minecraft:spruce_planks", name = "Spruce Planks", color = colors.brown, sym = "P" },
{ id = "minecraft:birch_planks", name = "Birch Planks", color = colors.yellow, sym = "P" },
{ id = "minecraft:jungle_planks", name = "Jungle Planks", color = colors.brown, sym = "P" },
{ id = "minecraft:acacia_planks", name = "Acacia Planks", color = colors.orange, sym = "P" },
{ id = "minecraft:dark_oak_planks", name = "Dark Oak Planks", color = colors.brown, sym = "P" },
{ id = "minecraft:mangrove_planks", name = "Mangrove Planks", color = colors.red, sym = "P" },
{ id = "minecraft:cherry_planks", name = "Cherry Planks", color = colors.pink, sym = "P" },
{ id = "minecraft:bamboo_planks", name = "Bamboo Planks", color = colors.yellow, sym = "P" },
{ id = "minecraft:bedrock", name = "Bedrock", color = colors.black, sym = "B" },
{ id = "minecraft:sand", name = "Sand", color = colors.yellow, sym = "s" },
{ id = "minecraft:red_sand", name = "Red Sand", color = colors.orange, sym = "s" },
{ id = "minecraft:gravel", name = "Gravel", color = colors.gray, sym = "g" },
{ id = "minecraft:gold_ore", name = "Gold Ore", color = colors.yellow, sym = "o" },
{ id = "minecraft:iron_ore", name = "Iron Ore", color = colors.brown, sym = "o" },
{ id = "minecraft:coal_ore", name = "Coal Ore", color = colors.black, sym = "o" },
{ id = "minecraft:nether_gold_ore", name = "Nether Gold Ore", color = colors.yellow, sym = "o" },
{ id = "minecraft:oak_log", name = "Oak Log", color = colors.brown, sym = "L" },
{ id = "minecraft:spruce_log", name = "Spruce Log", color = colors.brown, sym = "L" },
{ id = "minecraft:birch_log", name = "Birch Log", color = colors.white, sym = "L" },
{ id = "minecraft:jungle_log", name = "Jungle Log", color = colors.brown, sym = "L" },
{ id = "minecraft:acacia_log", name = "Acacia Log", color = colors.orange, sym = "L" },
{ id = "minecraft:dark_oak_log", name = "Dark Oak Log", color = colors.brown, sym = "L" },
{ id = "minecraft:mangrove_log", name = "Mangrove Log", color = colors.red, sym = "L" },
{ id = "minecraft:cherry_log", name = "Cherry Log", color = colors.pink, sym = "L" },
{ id = "minecraft:stripped_oak_log", name = "Stripped Oak Log", color = colors.brown, sym = "L" },
{ id = "minecraft:stripped_spruce_log", name = "Stripped Spruce Log", color = colors.brown, sym = "L" },
{ id = "minecraft:stripped_birch_log", name = "Stripped Birch Log", color = colors.white, sym = "L" },
{ id = "minecraft:stripped_jungle_log", name = "Stripped Jungle Log", color = colors.brown, sym = "L" },
{ id = "minecraft:stripped_acacia_log", name = "Stripped Acacia Log", color = colors.orange, sym = "L" },
{ id = "minecraft:stripped_dark_oak_log", name = "Stripped Dark Oak Log", color = colors.brown, sym = "L" },
{ id = "minecraft:stripped_mangrove_log", name = "Stripped Mangrove Log", color = colors.red, sym = "L" },
{ id = "minecraft:stripped_cherry_log", name = "Stripped Cherry Log", color = colors.pink, sym = "L" },
{ id = "minecraft:glass", name = "Glass", color = colors.lightBlue, sym = "G" },
{ id = "minecraft:lapis_ore", name = "Lapis Ore", color = colors.blue, sym = "o" },
{ id = "minecraft:diamond_ore", name = "Diamond Ore", color = colors.cyan, sym = "o" },
{ id = "minecraft:redstone_ore", name = "Redstone Ore", color = colors.red, sym = "o" },
{ id = "minecraft:emerald_ore", name = "Emerald Ore", color = colors.green, sym = "o" },
{ id = "minecraft:white_wool", name = "White Wool", color = colors.white, sym = "W" },
{ id = "minecraft:orange_wool", name = "Orange Wool", color = colors.orange, sym = "W" },
{ id = "minecraft:magenta_wool", name = "Magenta Wool", color = colors.magenta, sym = "W" },
{ id = "minecraft:light_blue_wool", name = "Light Blue Wool", color = colors.lightBlue, sym = "W" },
{ id = "minecraft:yellow_wool", name = "Yellow Wool", color = colors.yellow, sym = "W" },
{ id = "minecraft:lime_wool", name = "Lime Wool", color = colors.lime, sym = "W" },
{ id = "minecraft:pink_wool", name = "Pink Wool", color = colors.pink, sym = "W" },
{ id = "minecraft:gray_wool", name = "Gray Wool", color = colors.gray, sym = "W" },
{ id = "minecraft:light_gray_wool", name = "Light Gray Wool", color = colors.lightGray, sym = "W" },
{ id = "minecraft:cyan_wool", name = "Cyan Wool", color = colors.cyan, sym = "W" },
{ id = "minecraft:purple_wool", name = "Purple Wool", color = colors.purple, sym = "W" },
{ id = "minecraft:blue_wool", name = "Blue Wool", color = colors.blue, sym = "W" },
{ id = "minecraft:brown_wool", name = "Brown Wool", color = colors.brown, sym = "W" },
{ id = "minecraft:green_wool", name = "Green Wool", color = colors.green, sym = "W" },
{ id = "minecraft:red_wool", name = "Red Wool", color = colors.red, sym = "W" },
{ id = "minecraft:black_wool", name = "Black Wool", color = colors.black, sym = "W" },
{ id = "minecraft:bricks", name = "Bricks", color = colors.red, sym = "B" },
{ id = "minecraft:bookshelf", name = "Bookshelf", color = colors.brown, sym = "#" },
{ id = "minecraft:mossy_cobblestone", name = "Mossy Cobblestone", color = colors.gray, sym = "C" },
{ id = "minecraft:obsidian", name = "Obsidian", color = colors.black, sym = "O" },
{ id = "minecraft:torch", name = "Torch", color = colors.yellow, sym = "i" },
{ id = "minecraft:chest", name = "Chest", color = colors.brown, sym = "C" },
{ id = "minecraft:crafting_table", name = "Crafting Table", color = colors.brown, sym = "T" },
{ id = "minecraft:furnace", name = "Furnace", color = colors.gray, sym = "F" },
{ id = "minecraft:ladder", name = "Ladder", color = colors.brown, sym = "H" },
{ id = "minecraft:snow", name = "Snow", color = colors.white, sym = "S" },
{ id = "minecraft:ice", name = "Ice", color = colors.lightBlue, sym = "I" },
{ id = "minecraft:snow_block", name = "Snow Block", color = colors.white, sym = "S" },
{ id = "minecraft:clay", name = "Clay", color = colors.lightGray, sym = "C" },
{ id = "minecraft:pumpkin", name = "Pumpkin", color = colors.orange, sym = "P" },
{ id = "minecraft:netherrack", name = "Netherrack", color = colors.red, sym = "N" },
{ id = "minecraft:soul_sand", name = "Soul Sand", color = colors.brown, sym = "S" },
{ id = "minecraft:soul_soil", name = "Soul Soil", color = colors.brown, sym = "S" },
{ id = "minecraft:basalt", name = "Basalt", color = colors.gray, sym = "B" },
{ id = "minecraft:polished_basalt", name = "Polished Basalt", color = colors.gray, sym = "B" },
{ id = "minecraft:glowstone", name = "Glowstone", color = colors.yellow, sym = "G" },
{ id = "minecraft:stone_bricks", name = "Stone Bricks", color = colors.gray, sym = "B" },
{ id = "minecraft:mossy_stone_bricks", name = "Mossy Stone Bricks", color = colors.gray, sym = "B" },
{ id = "minecraft:cracked_stone_bricks", name = "Cracked Stone Bricks", color = colors.gray, sym = "B" },
{ id = "minecraft:chiseled_stone_bricks", name = "Chiseled Stone Bricks", color = colors.gray, sym = "B" },
{ id = "minecraft:deepslate", name = "Deepslate", color = colors.gray, sym = "D" },
{ id = "minecraft:cobbled_deepslate", name = "Cobbled Deepslate", color = colors.gray, sym = "D" },
{ id = "minecraft:polished_deepslate", name = "Polished Deepslate", color = colors.gray, sym = "D" },
{ id = "minecraft:deepslate_bricks", name = "Deepslate Bricks", color = colors.gray, sym = "D" },
{ id = "minecraft:deepslate_tiles", name = "Deepslate Tiles", color = colors.gray, sym = "D" },
{ id = "minecraft:reinforced_deepslate", name = "Reinforced Deepslate", color = colors.black, sym = "D" },
{ id = "minecraft:melon", name = "Melon", color = colors.green, sym = "M" },
{ id = "minecraft:mycelium", name = "Mycelium", color = colors.purple, sym = "M" },
{ id = "minecraft:nether_bricks", name = "Nether Bricks", color = colors.red, sym = "B" },
{ id = "minecraft:end_stone", name = "End Stone", color = colors.yellow, sym = "E" },
{ id = "minecraft:emerald_block", name = "Emerald Block", color = colors.green, sym = "E" },
{ id = "minecraft:quartz_block", name = "Quartz Block", color = colors.white, sym = "Q" },
{ id = "minecraft:white_terracotta", name = "White Terracotta", color = colors.white, sym = "T" },
{ id = "minecraft:orange_terracotta", name = "Orange Terracotta", color = colors.orange, sym = "T" },
{ id = "minecraft:magenta_terracotta", name = "Magenta Terracotta", color = colors.magenta, sym = "T" },
{ id = "minecraft:light_blue_terracotta", name = "Light Blue Terracotta", color = colors.lightBlue, sym = "T" },
{ id = "minecraft:yellow_terracotta", name = "Yellow Terracotta", color = colors.yellow, sym = "T" },
{ id = "minecraft:lime_terracotta", name = "Lime Terracotta", color = colors.lime, sym = "T" },
{ id = "minecraft:pink_terracotta", name = "Pink Terracotta", color = colors.pink, sym = "T" },
{ id = "minecraft:gray_terracotta", name = "Gray Terracotta", color = colors.gray, sym = "T" },
{ id = "minecraft:light_gray_terracotta", name = "Light Gray Terracotta", color = colors.lightGray, sym = "T" },
{ id = "minecraft:cyan_terracotta", name = "Cyan Terracotta", color = colors.cyan, sym = "T" },
{ id = "minecraft:purple_terracotta", name = "Purple Terracotta", color = colors.purple, sym = "T" },
{ id = "minecraft:blue_terracotta", name = "Blue Terracotta", color = colors.blue, sym = "T" },
{ id = "minecraft:brown_terracotta", name = "Brown Terracotta", color = colors.brown, sym = "T" },
{ id = "minecraft:green_terracotta", name = "Green Terracotta", color = colors.green, sym = "T" },
{ id = "minecraft:red_terracotta", name = "Red Terracotta", color = colors.red, sym = "T" },
{ id = "minecraft:black_terracotta", name = "Black Terracotta", color = colors.black, sym = "T" },
{ id = "minecraft:hay_block", name = "Hay Bale", color = colors.yellow, sym = "H" },
{ id = "minecraft:terracotta", name = "Terracotta", color = colors.orange, sym = "T" },
{ id = "minecraft:coal_block", name = "Block of Coal", color = colors.black, sym = "C" },
{ id = "minecraft:packed_ice", name = "Packed Ice", color = colors.lightBlue, sym = "I" },
{ id = "minecraft:blue_ice", name = "Blue Ice", color = colors.blue, sym = "I" },
{ id = "minecraft:prismarine", name = "Prismarine", color = colors.cyan, sym = "P" },
{ id = "minecraft:prismarine_bricks", name = "Prismarine Bricks", color = colors.cyan, sym = "P" },
{ id = "minecraft:dark_prismarine", name = "Dark Prismarine", color = colors.cyan, sym = "P" },
{ id = "minecraft:sea_lantern", name = "Sea Lantern", color = colors.white, sym = "L" },
{ id = "minecraft:red_sandstone", name = "Red Sandstone", color = colors.orange, sym = "S" },
{ id = "minecraft:magma_block", name = "Magma Block", color = colors.red, sym = "M" },
{ id = "minecraft:nether_wart_block", name = "Nether Wart Block", color = colors.red, sym = "W" },
{ id = "minecraft:warped_wart_block", name = "Warped Wart Block", color = colors.cyan, sym = "W" },
{ id = "minecraft:red_nether_bricks", name = "Red Nether Bricks", color = colors.red, sym = "B" },
{ id = "minecraft:bone_block", name = "Bone Block", color = colors.white, sym = "B" },
{ id = "minecraft:shulker_box", name = "Shulker Box", color = colors.purple, sym = "S" },
{ id = "minecraft:white_concrete", name = "White Concrete", color = colors.white, sym = "C" },
{ id = "minecraft:orange_concrete", name = "Orange Concrete", color = colors.orange, sym = "C" },
{ id = "minecraft:magenta_concrete", name = "Magenta Concrete", color = colors.magenta, sym = "C" },
{ id = "minecraft:light_blue_concrete", name = "Light Blue Concrete", color = colors.lightBlue, sym = "C" },
{ id = "minecraft:yellow_concrete", name = "Yellow Concrete", color = colors.yellow, sym = "C" },
{ id = "minecraft:lime_concrete", name = "Lime Concrete", color = colors.lime, sym = "C" },
{ id = "minecraft:pink_concrete", name = "Pink Concrete", color = colors.pink, sym = "C" },
{ id = "minecraft:gray_concrete", name = "Gray Concrete", color = colors.gray, sym = "C" },
{ id = "minecraft:light_gray_concrete", name = "Light Gray Concrete", color = colors.lightGray, sym = "C" },
{ id = "minecraft:cyan_concrete", name = "Cyan Concrete", color = colors.cyan, sym = "C" },
{ id = "minecraft:purple_concrete", name = "Purple Concrete", color = colors.purple, sym = "C" },
{ id = "minecraft:blue_concrete", name = "Blue Concrete", color = colors.blue, sym = "C" },
{ id = "minecraft:brown_concrete", name = "Brown Concrete", color = colors.brown, sym = "C" },
{ id = "minecraft:green_concrete", name = "Green Concrete", color = colors.green, sym = "C" },
{ id = "minecraft:red_concrete", name = "Red Concrete", color = colors.red, sym = "C" },
{ id = "minecraft:black_concrete", name = "Black Concrete", color = colors.black, sym = "C" },
{ id = "minecraft:white_concrete_powder", name = "White Concrete Powder", color = colors.white, sym = "P" },
{ id = "minecraft:orange_concrete_powder", name = "Orange Concrete Powder", color = colors.orange, sym = "P" },
{ id = "minecraft:magenta_concrete_powder", name = "Magenta Concrete Powder", color = colors.magenta, sym = "P" },
{ id = "minecraft:light_blue_concrete_powder", name = "Light Blue Concrete Powder", color = colors.lightBlue, sym = "P" },
{ id = "minecraft:yellow_concrete_powder", name = "Yellow Concrete Powder", color = colors.yellow, sym = "P" },
{ id = "minecraft:lime_concrete_powder", name = "Lime Concrete Powder", color = colors.lime, sym = "P" },
{ id = "minecraft:pink_concrete_powder", name = "Pink Concrete Powder", color = colors.pink, sym = "P" },
{ id = "minecraft:gray_concrete_powder", name = "Gray Concrete Powder", color = colors.gray, sym = "P" },
{ id = "minecraft:light_gray_concrete_powder", name = "Light Gray Concrete Powder", color = colors.lightGray, sym = "P" },
{ id = "minecraft:cyan_concrete_powder", name = "Cyan Concrete Powder", color = colors.cyan, sym = "P" },
{ id = "minecraft:purple_concrete_powder", name = "Purple Concrete Powder", color = colors.purple, sym = "P" },
{ id = "minecraft:blue_concrete_powder", name = "Blue Concrete Powder", color = colors.blue, sym = "P" },
{ id = "minecraft:brown_concrete_powder", name = "Brown Concrete Powder", color = colors.brown, sym = "P" },
{ id = "minecraft:green_concrete_powder", name = "Green Concrete Powder", color = colors.green, sym = "P" },
{ id = "minecraft:red_concrete_powder", name = "Red Concrete Powder", color = colors.red, sym = "P" },
{ id = "minecraft:black_concrete_powder", name = "Black Concrete Powder", color = colors.black, sym = "P" },
{ id = "minecraft:dried_kelp_block", name = "Dried Kelp Block", color = colors.green, sym = "K" },
{ id = "minecraft:dead_tube_coral_block", name = "Dead Tube Coral Block", color = colors.gray, sym = "C" },
{ id = "minecraft:dead_brain_coral_block", name = "Dead Brain Coral Block", color = colors.gray, sym = "C" },
{ id = "minecraft:dead_bubble_coral_block", name = "Dead Bubble Coral Block", color = colors.gray, sym = "C" },
{ id = "minecraft:dead_fire_coral_block", name = "Dead Fire Coral Block", color = colors.gray, sym = "C" },
{ id = "minecraft:dead_horn_coral_block", name = "Dead Horn Coral Block", color = colors.gray, sym = "C" },
{ id = "minecraft:tube_coral_block", name = "Tube Coral Block", color = colors.blue, sym = "C" },
{ id = "minecraft:brain_coral_block", name = "Brain Coral Block", color = colors.pink, sym = "C" },
{ id = "minecraft:bubble_coral_block", name = "Bubble Coral Block", color = colors.magenta, sym = "C" },
{ id = "minecraft:fire_coral_block", name = "Fire Coral Block", color = colors.red, sym = "C" },
{ id = "minecraft:horn_coral_block", name = "Horn Coral Block", color = colors.yellow, sym = "C" },
{ id = "minecraft:honey_block", name = "Honey Block", color = colors.orange, sym = "H" },
{ id = "minecraft:honeycomb_block", name = "Honeycomb Block", color = colors.orange, sym = "H" },
{ id = "minecraft:netherite_block", name = "Block of Netherite", color = colors.black, sym = "N" },
{ id = "minecraft:ancient_debris", name = "Ancient Debris", color = colors.brown, sym = "D" },
{ id = "minecraft:crying_obsidian", name = "Crying Obsidian", color = colors.purple, sym = "O" },
{ id = "minecraft:blackstone", name = "Blackstone", color = colors.black, sym = "B" },
{ id = "minecraft:polished_blackstone", name = "Polished Blackstone", color = colors.black, sym = "B" },
{ id = "minecraft:polished_blackstone_bricks", name = "Polished Blackstone Bricks", color = colors.black, sym = "B" },
{ id = "minecraft:gilded_blackstone", name = "Gilded Blackstone", color = colors.black, sym = "B" },
{ id = "minecraft:chiseled_polished_blackstone", name = "Chiseled Polished Blackstone", color = colors.black, sym = "B" },
{ id = "minecraft:quartz_bricks", name = "Quartz Bricks", color = colors.white, sym = "Q" },
{ id = "minecraft:amethyst_block", name = "Block of Amethyst", color = colors.purple, sym = "A" },
{ id = "minecraft:budding_amethyst", name = "Budding Amethyst", color = colors.purple, sym = "A" },
{ id = "minecraft:tuff", name = "Tuff", color = colors.gray, sym = "T" },
{ id = "minecraft:calcite", name = "Calcite", color = colors.white, sym = "C" },
{ id = "minecraft:tinted_glass", name = "Tinted Glass", color = colors.gray, sym = "G" },
{ id = "minecraft:smooth_basalt", name = "Smooth Basalt", color = colors.gray, sym = "B" },
{ id = "minecraft:raw_iron_block", name = "Block of Raw Iron", color = colors.brown, sym = "I" },
{ id = "minecraft:raw_copper_block", name = "Block of Raw Copper", color = colors.orange, sym = "C" },
{ id = "minecraft:raw_gold_block", name = "Block of Raw Gold", color = colors.yellow, sym = "G" },
{ id = "minecraft:dripstone_block", name = "Dripstone Block", color = colors.brown, sym = "D" },
{ id = "minecraft:moss_block", name = "Moss Block", color = colors.green, sym = "M" },
{ id = "minecraft:mud", name = "Mud", color = colors.brown, sym = "M" },
{ id = "minecraft:packed_mud", name = "Packed Mud", color = colors.brown, sym = "M" },
{ id = "minecraft:mud_bricks", name = "Mud Bricks", color = colors.brown, sym = "M" },
{ id = "minecraft:sculk", name = "Sculk", color = colors.cyan, sym = "S" },
{ id = "minecraft:sculk_catalyst", name = "Sculk Catalyst", color = colors.cyan, sym = "S" },
{ id = "minecraft:sculk_shrieker", name = "Sculk Shrieker", color = colors.cyan, sym = "S" },
{ id = "minecraft:ochre_froglight", name = "Ochre Froglight", color = colors.yellow, sym = "F" },
{ id = "minecraft:verdant_froglight", name = "Verdant Froglight", color = colors.green, sym = "F" },
{ id = "minecraft:pearlescent_froglight", name = "Pearlescent Froglight", color = colors.purple, sym = "F" },
}
return items]]
files["lib/lib_json.lua"] = [[local json_utils = {}
function json_utils.encode(data)
if textutils and textutils.serializeJSON then
return textutils.serializeJSON(data)
end
return nil, "json_encoder_unavailable"
end
function json_utils.decodeJson(text)
if type(text) ~= "string" then
return nil, "invalid_json"
end
if textutils and textutils.unserializeJSON then
local ok, result = pcall(textutils.unserializeJSON, text)
if ok and result ~= nil then
return result
end
return nil, "json_parse_failed"
end
local ok, json = pcall(require, "json")
if ok and type(json) == "table" and type(json.decode) == "function" then
local okDecode, result = pcall(json.decode, text)
if okDecode then
return result
end
return nil, "json_parse_failed"
end
return nil, "json_decoder_unavailable"
end
return json_utils]]
files["lib/lib_logger.lua"] = [[local logger = {}
local diagnostics
local diagnosticsOk, diagnosticsModule = pcall(require, "lib_diagnostics")
if diagnosticsOk then
diagnostics = diagnosticsModule
end
local DEFAULT_CRASH_FILE = "crashfile"
local DEFAULT_LEVEL = "info"
local DEFAULT_CAPTURE_LIMIT = 200
local LEVEL_VALUE = {
debug = 10,
info = 20,
warn = 30,
error = 40,
}
local LEVEL_LABEL = {
debug = "DEBUG",
info = "INFO",
warn = "WARN",
error = "ERROR",
}
local LEVEL_ALIAS = {
warning = "warn",
err = "error",
trace = "debug",
verbose = "debug",
fatal = "error",
}
local function isoTimestamp()
if os and type(os.date) == "function" then
return os.date("!%Y-%m-%dT%H:%M:%SZ")
end
if os and type(os.clock) == "function" then
return string.format("%.03f", os.clock())
end
return nil
end
local function getCrashFilePath(ctx)
if ctx then
local config = ctx.config
if config and type(config.crashFile) == "string" and config.crashFile ~= "" then
return config.crashFile
end
if type(ctx.crashFilePath) == "string" and ctx.crashFilePath ~= "" then
return ctx.crashFilePath
end
end
return DEFAULT_CRASH_FILE
end
local function buildCrashPayload(ctx, message, metadata)
local payload = {
message = message or "Unknown fatal error",
metadata = metadata,
timestamp = isoTimestamp(),
}
if diagnostics and ctx then
local ok, snapshot = pcall(diagnostics.snapshot, ctx)
if ok then
payload.context = snapshot
end
end
if ctx and ctx.logger and type(ctx.logger.getLastEntry) == "function" then
local ok, entry = pcall(ctx.logger.getLastEntry, ctx.logger)
if ok then
payload.lastLogEntry = entry
end
end
return payload
end
local function serializeCrashPayload(payload)
if textutils and type(textutils.serializeJSON) == "function" then
local ok, serialized = pcall(textutils.serializeJSON, payload, { compact = true })
if ok then
return serialized
end
end
if textutils and type(textutils.serialize) == "function" then
local ok, serialized = pcall(textutils.serialize, payload)
if ok then
return serialized
end
end
local parts = {}
for key, value in pairs(payload or {}) do
parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
end
table.sort(parts)
return table.concat(parts, "\n")
end
local function writeFile(path, contents)
if not fs or type(fs.open) ~= "function" then
return false, "fs_unavailable"
end
local handle, err = fs.open(path, "w")
if not handle then
return false, err or "open_failed"
end
handle.write(contents)
handle.close()
return true
end
local function copyTable(value, depth, seen)
if type(value) ~= "table" then
return value
end
if depth and depth <= 0 then
return value
end
seen = seen or {}
if seen[value] then
return "<recursive>"
end
seen[value] = true
local result = {}
for k, v in pairs(value) do
local newKey = copyTable(k, depth and (depth - 1) or nil, seen)
local newValue = copyTable(v, depth and (depth - 1) or nil, seen)
result[newKey] = newValue
end
seen[value] = nil
return result
end
local function trySerializers(meta)
if type(meta) ~= "table" then
return nil
end
if textutils and type(textutils.serialize) == "function" then
local ok, serialized = pcall(textutils.serialize, meta)
if ok then
return serialized
end
end
if textutils and type(textutils.serializeJSON) == "function" then
local ok, serialized = pcall(textutils.serializeJSON, meta)
if ok then
return serialized
end
end
return nil
end
local function formatMetadata(meta)
if meta == nil then
return ""
end
local metaType = type(meta)
if metaType == "string" then
return meta
elseif metaType == "number" or metaType == "boolean" then
return tostring(meta)
elseif metaType == "table" then
local serialized = trySerializers(meta)
if serialized then
return serialized
end
local parts = {}
local count = 0
for key, value in pairs(meta) do
parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
count = count + 1
if count >= 16 then
break
end
end
table.sort(parts)
return "{" .. table.concat(parts, ", ") .. "}"
end
return tostring(meta)
end
local function formatMessage(message)
if message == nil then
return ""
end
local msgType = type(message)
if msgType == "string" then
return message
elseif msgType == "number" or msgType == "boolean" then
return tostring(message)
elseif msgType == "table" then
if message.message and type(message.message) == "string" then
return message.message
end
local metaView = formatMetadata(message)
if metaView ~= "" then
return metaView
end
end
return tostring(message)
end
local function resolveLevel(level)
if type(level) == "string" then
local lowered = level:lower()
lowered = LEVEL_ALIAS[lowered] or lowered
if LEVEL_VALUE[lowered] then
return lowered
end
return nil
elseif type(level) == "number" then
local closest
local distance
for name, value in pairs(LEVEL_VALUE) do
local diff = math.abs(value - level)
if not closest or diff < distance then
closest = name
distance = diff
end
end
return closest
end
return nil
end
local function levelValue(level)
return LEVEL_VALUE[level] or LEVEL_VALUE[DEFAULT_LEVEL]
end
local function shouldEmit(level, thresholdValue)
return levelValue(level) >= thresholdValue
end
local function formatTimestamp(state)
if not state.timestamps then
return nil, nil
end
local fmt = state.timestampFormat or "%H:%M:%S"
if os and type(os.date) == "function" then
local timeNumber = os.time and os.time() or nil
local stamp = os.date(fmt)
return stamp, timeNumber
end
if os and type(os.clock) == "function" then
local clockValue = os.clock()
return string.format("%.03f", clockValue), clockValue
end
return nil, nil
end
local function cloneEntry(entry)
return copyTable(entry, 3)
end
local function pushHistory(state, entry)
local history = state.history
history[#history + 1] = cloneEntry(entry)
local limit = state.captureLimit or DEFAULT_CAPTURE_LIMIT
while #history > limit do
table.remove(history, 1)
end
end
local function defaultWriterFactory(state)
return function(entry)
local segments = {}
if entry.timestamp then
segments[#segments + 1] = entry.timestamp
elseif state.timestamps and state.lastTimestamp then
segments[#segments + 1] = state.lastTimestamp
end
if entry.tag then
segments[#segments + 1] = entry.tag
elseif state.tag then
segments[#segments + 1] = state.tag
end
segments[#segments + 1] = entry.levelLabel or entry.level
local prefix = "[" .. table.concat(segments, "][") .. "]"
local line = prefix .. " " .. entry.message
local metaStr = formatMetadata(entry.metadata)
if metaStr ~= "" then
line = line .. " | " .. metaStr
end
if print then
print(line)
elseif io and io.write then
io.write(line .. "\n")
end
end
end
local function addWriter(state, writer)
if type(writer) ~= "function" then
return false, "invalid_writer"
end
for _, existing in ipairs(state.writers) do
if existing == writer then
return false, "writer_exists"
end
end
state.writers[#state.writers + 1] = writer
return true
end
local function logInternal(state, level, message, metadata)
local resolved = resolveLevel(level)
if not resolved then
return false, "unknown_level"
end
if not shouldEmit(resolved, state.thresholdValue) then
return false, "level_filtered"
end
local timestamp, timeNumber = formatTimestamp(state)
state.lastTimestamp = timestamp or state.lastTimestamp
local entry = {
level = resolved,
levelLabel = LEVEL_LABEL[resolved],
message = formatMessage(message),
metadata = metadata,
timestamp = timestamp,
time = timeNumber,
sequence = state.sequence + 1,
tag = state.tag,
}
state.sequence = entry.sequence
state.lastEntry = entry
if state.capture then
pushHistory(state, entry)
end
for _, writer in ipairs(state.writers) do
local ok, err = pcall(writer, entry)
if not ok then
state.lastWriterError = err
end
end
return true, entry
end
function logger.new(opts)
local state = {
capture = opts and opts.capture or false,
captureLimit = (opts and type(opts.captureLimit) == "number" and opts.captureLimit > 0) and opts.captureLimit or DEFAULT_CAPTURE_LIMIT,
history = {},
sequence = 0,
writers = {},
timestamps = opts and (opts.timestamps or opts.timestamp) or false,
timestampFormat = opts and opts.timestampFormat or nil,
tag = opts and (opts.tag or opts.label) or nil,
}
local initialLevel = (opts and resolveLevel(opts.level)) or (opts and resolveLevel(opts.minLevel)) or DEFAULT_LEVEL
state.threshold = initialLevel
state.thresholdValue = levelValue(initialLevel)
local instance = {}
state.instance = instance
if not (opts and opts.silent) then
addWriter(state, defaultWriterFactory(state))
end
if opts and type(opts.writer) == "function" then
addWriter(state, opts.writer)
end
if opts and type(opts.writers) == "table" then
for _, writer in ipairs(opts.writers) do
if type(writer) == "function" then
addWriter(state, writer)
end
end
end
function instance:log(level, message, metadata)
return logInternal(state, level, message, metadata)
end
function instance:debug(message, metadata)
return logInternal(state, "debug", message, metadata)
end
function instance:info(message, metadata)
return logInternal(state, "info", message, metadata)
end
function instance:warn(message, metadata)
return logInternal(state, "warn", message, metadata)
end
function instance:error(message, metadata)
return logInternal(state, "error", message, metadata)
end
function instance:setLevel(level)
local resolved = resolveLevel(level)
if not resolved then
return false, "unknown_level"
end
state.threshold = resolved
state.thresholdValue = levelValue(resolved)
return true, resolved
end
function instance:getLevel()
return state.threshold
end
function instance:enableCapture(limit)
state.capture = true
if type(limit) == "number" and limit > 0 then
state.captureLimit = limit
end
return true
end
function instance:disableCapture()
state.capture = false
state.history = {}
return true
end
function instance:getHistory()
local result = {}
for index = 1, #state.history do
result[index] = cloneEntry(state.history[index])
end
return result
end
function instance:clearHistory()
state.history = {}
return true
end
function instance:addWriter(writer)
return addWriter(state, writer)
end
function instance:removeWriter(writer)
if type(writer) ~= "function" then
return false, "invalid_writer"
end
for index, existing in ipairs(state.writers) do
if existing == writer then
table.remove(state.writers, index)
return true
end
end
return false, "writer_missing"
end
function instance:setTag(tag)
state.tag = tag
return true
end
function instance:getTag()
return state.tag
end
function instance:getLastEntry()
if not state.lastEntry then
return nil
end
return cloneEntry(state.lastEntry)
end
function instance:getLastWriterError()
return state.lastWriterError
end
function instance:setTimestamps(enabled, format)
state.timestamps = not not enabled
if format then
state.timestampFormat = format
end
return true
end
return instance
end
function logger.attach(ctx, opts)
if type(ctx) ~= "table" then
error("logger.attach requires a context table", 2)
end
local instance = logger.new(opts)
ctx.logger = instance
return instance
end
function logger.isLogger(candidate)
if type(candidate) ~= "table" then
return false
end
return type(candidate.log) == "function"
and type(candidate.info) == "function"
and type(candidate.warn) == "function"
and type(candidate.error) == "function"
end
logger.DEFAULT_LEVEL = DEFAULT_LEVEL
logger.DEFAULT_CAPTURE_LIMIT = DEFAULT_CAPTURE_LIMIT
logger.LEVELS = copyTable(LEVEL_VALUE, 1)
logger.LABELS = copyTable(LEVEL_LABEL, 1)
logger.resolveLevel = resolveLevel
logger.DEFAULT_CRASH_FILE = DEFAULT_CRASH_FILE
function logger.log(ctx, level, message)
if type(ctx) ~= "table" then
return
end
local logInst = ctx.logger
if type(logInst) == "table" then
local fn = logInst[level]
if type(fn) == "function" then
fn(logInst, message)
return
end
if type(logInst.log) == "function" then
logInst.log(logInst, level, message)
return
end
end
if (level == "warn" or level == "error") and message then
print(string.format("[%s] %s", level:upper(), message))
end
end
function logger.writeCrashFile(ctx, message, metadata)
local path = getCrashFilePath(ctx)
local payload = buildCrashPayload(ctx, message, metadata)
local body = serializeCrashPayload(payload)
if not body or body == "" then
body = tostring(message or "Unknown fatal error")
end
local ok, err = writeFile(path, body .. "\n")
if not ok then
return false, err
end
if ctx then
ctx.crashFilePath = path
end
return true, path
end
return logger]]
files["lib/lib_menu.lua"] = [[local menu = {}
local function centerText(y, text)
local w, h = term.getSize()
local x = math.floor((w - #text) / 2) + 1
term.setCursorPos(x, y)
term.write(text)
end
function menu.draw(title, options, selectedIndex, scrollOffset)
local w, h = term.getSize()
if term.isColor() then
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
end
term.clear()
if term.isColor() then
term.setTextColor(colors.yellow)
end
centerText(1, title)
if term.isColor() then
term.setTextColor(colors.white)
end
term.setCursorPos(1, 2)
term.write(string.rep("-", w))
local listStart = 3
local listHeight = h - 4 -- Reserve space for title (2) and footer (1)
for i = 1, listHeight do
local optionIndex = i + scrollOffset
if optionIndex <= #options then
local option = options[optionIndex]
local text = type(option) == "table" and option.text or tostring(option)
if #text > w - 4 then
text = string.sub(text, 1, w - 7) .. "..."
end
term.setCursorPos(2, listStart + i - 1)
if optionIndex == selectedIndex then
if term.isColor() then
term.setTextColor(colors.lime)
end
term.write("> " .. text .. " <")
else
if term.isColor() then
term.setTextColor(colors.white)
end
term.write("  " .. text)
end
end
end
term.setCursorPos(1, h)
if term.isColor() then term.setTextColor(colors.gray) end
local footer = "Up/Down: Move | Enter: Select"
centerText(h, footer)
if term.isColor() then term.setTextColor(colors.white) end
end
function menu.run(title, options)
local selectedIndex = 1
local scrollOffset = 0
local w, h = term.getSize()
local listHeight = h - 4
while true do
if selectedIndex <= scrollOffset then
scrollOffset = selectedIndex - 1
elseif selectedIndex > scrollOffset + listHeight then
scrollOffset = selectedIndex - listHeight
end
menu.draw(title, options, selectedIndex, scrollOffset)
local event, key = os.pullEvent("key")
if key == keys.up then
selectedIndex = selectedIndex - 1
if selectedIndex < 1 then selectedIndex = #options end
elseif key == keys.down then
selectedIndex = selectedIndex + 1
if selectedIndex > #options then selectedIndex = 1 end
elseif key == keys.enter then
term.clear()
term.setCursorPos(1,1)
return selectedIndex, options[selectedIndex]
end
end
end
return menu]]
files["lib/lib_mining.lua"] = [[local mining = {}
local inventory = require("lib_inventory")
local movement = require("lib_movement")
local logger = require("lib_logger")
local json = require("lib_json")
local CONFIG_FILE = "data/trash_config.json"
mining.TRASH_BLOCKS = inventory.DEFAULT_TRASH
mining.TRASH_BLOCKS["minecraft:chest"] = true
mining.TRASH_BLOCKS["minecraft:barrel"] = true
mining.TRASH_BLOCKS["minecraft:trapped_chest"] = true
mining.TRASH_BLOCKS["minecraft:torch"] = true
function mining.loadConfig()
if fs.exists(CONFIG_FILE) then
local f = fs.open(CONFIG_FILE, "r")
if f then
local data = f.readAll()
f.close()
local config = json.decodeJson(data)
if config and config.trash then
for k, v in pairs(config.trash) do
mining.TRASH_BLOCKS[k] = v
end
end
end
end
end
function mining.saveConfig()
local config = { trash = mining.TRASH_BLOCKS }
local data = json.encode(config)
if not fs.exists("data") then
fs.makeDir("data")
end
local f = fs.open(CONFIG_FILE, "w")
if f then
f.write(data)
f.close()
end
end
mining.loadConfig()
mining.FILL_BLACKLIST = {
["minecraft:air"] = true,
["minecraft:water"] = true,
["minecraft:lava"] = true,
["minecraft:sand"] = true,
["minecraft:gravel"] = true,
["minecraft:torch"] = true,
["minecraft:bedrock"] = true,
["minecraft:chest"] = true,
["minecraft:barrel"] = true,
["minecraft:trapped_chest"] = true,
}
function mining.isOre(name)
if not name then return false end
return not mining.TRASH_BLOCKS[name]
end
local function findFillMaterial(ctx)
inventory.scan(ctx)
local state = inventory.ensureState(ctx)
if not state or not state.slots then return nil end
for slot, item in pairs(state.slots) do
if mining.TRASH_BLOCKS[item.name] and not mining.FILL_BLACKLIST[item.name] then
return slot, item.name
end
end
return nil
end
function mining.mineAndFill(ctx, dir)
local inspect, dig, place, suck
if dir == "front" then
inspect = turtle.inspect
dig = turtle.dig
place = turtle.place
suck = turtle.suck
elseif dir == "up" then
inspect = turtle.inspectUp
dig = turtle.digUp
place = turtle.placeUp
suck = turtle.suckUp
elseif dir == "down" then
inspect = turtle.inspectDown
dig = turtle.digDown
place = turtle.placeDown
suck = turtle.suckDown
else
return false, "Invalid direction"
end
local hasBlock, data = inspect()
if hasBlock and mining.isOre(data.name) then
logger.log(ctx, "info", "Mining valuable: " .. data.name)
if dig() then
sleep(0.2)
while suck() do sleep(0.1) end
local slot = findFillMaterial(ctx)
if slot then
turtle.select(slot)
place()
else
logger.log(ctx, "warn", "No trash blocks available to fill hole")
end
return true
else
logger.log(ctx, "warn", "Failed to dig " .. data.name)
end
end
return false
end
function mining.scanAndMineNeighbors(ctx)
mining.mineAndFill(ctx, "up")
mining.mineAndFill(ctx, "down")
for i = 1, 4 do
mining.mineAndFill(ctx, "front")
movement.turnRight(ctx)
end
end
return mining]]
files["lib/lib_movement.lua"] = [[local movement = {}
local logger = require("lib_logger")
local CARDINALS = {"north", "east", "south", "west"}
local DIRECTION_VECTORS = {
north = { x = 0, y = 0, z = -1 },
east = { x = 1, y = 0, z = 0 },
south = { x = 0, y = 0, z = 1 },
west = { x = -1, y = 0, z = 0 },
}
local AXIS_FACINGS = {
x = { positive = "east", negative = "west" },
z = { positive = "south", negative = "north" },
}
local DEFAULT_SOFT_BLOCKS = {
["minecraft:snow"] = true,
["minecraft:snow_layer"] = true,
["minecraft:powder_snow"] = true,
["minecraft:tall_grass"] = true,
["minecraft:large_fern"] = true,
["minecraft:grass"] = true,
["minecraft:fern"] = true,
["minecraft:cave_vines"] = true,
["minecraft:cave_vines_plant"] = true,
["minecraft:kelp"] = true,
["minecraft:kelp_plant"] = true,
["minecraft:sweet_berry_bush"] = true,
}
local DEFAULT_SOFT_TAGS = {
["minecraft:snow"] = true,
["minecraft:replaceable_plants"] = true,
["minecraft:flowers"] = true,
["minecraft:saplings"] = true,
["minecraft:carpets"] = true,
}
local DEFAULT_SOFT_NAME_HINTS = {
"sapling",
"propagule",
"seedling",
}
local function cloneLookup(source)
local lookup = {}
for key, value in pairs(source) do
if value then
lookup[key] = true
end
end
return lookup
end
local function extendLookup(lookup, entries)
if type(entries) ~= "table" then
return lookup
end
if #entries > 0 then
for _, name in ipairs(entries) do
if type(name) == "string" then
lookup[name] = true
end
end
else
for name, enabled in pairs(entries) do
if enabled and type(name) == "string" then
lookup[name] = true
end
end
end
return lookup
end
local function buildSoftNameHintList(configHints)
local seen = {}
local list = {}
local function append(value)
if type(value) ~= "string" then
return
end
local normalized = value:lower()
if normalized == "" or seen[normalized] then
return
end
seen[normalized] = true
list[#list + 1] = normalized
end
for _, hint in ipairs(DEFAULT_SOFT_NAME_HINTS) do
append(hint)
end
if type(configHints) == "table" then
if #configHints > 0 then
for _, entry in ipairs(configHints) do
append(entry)
end
else
for name, enabled in pairs(configHints) do
if enabled then
append(name)
end
end
end
elseif type(configHints) == "string" then
append(configHints)
end
return list
end
local function matchesSoftNameHint(hints, blockName)
if type(blockName) ~= "string" then
return false
end
local lowered = blockName:lower()
for _, hint in ipairs(hints or {}) do
if lowered:find(hint, 1, true) then
return true
end
end
return false
end
local function isSoftBlock(state, inspectData)
if type(state) ~= "table" or type(inspectData) ~= "table" then
return false
end
local name = inspectData.name
if type(name) == "string" then
if state.softBlockLookup and state.softBlockLookup[name] then
return true
end
if matchesSoftNameHint(state.softNameHints, name) then
return true
end
end
local tags = inspectData.tags
if type(tags) == "table" and state.softTagLookup then
for tag, value in pairs(tags) do
if value and state.softTagLookup[tag] then
return true
end
end
end
return false
end
local function canonicalFacing(name)
if type(name) ~= "string" then
return nil
end
name = name:lower()
if DIRECTION_VECTORS[name] then
return name
end
return nil
end
local function copyPosition(pos)
if not pos then
return { x = 0, y = 0, z = 0 }
end
return { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
end
local function vecAdd(a, b)
return { x = (a.x or 0) + (b.x or 0), y = (a.y or 0) + (b.y or 0), z = (a.z or 0) + (b.z or 0) }
end
local function getPlannedMaterial(ctx, pos)
if type(ctx) ~= "table" or type(pos) ~= "table" then
return nil
end
local plan = ctx.buildPlan
if type(plan) ~= "table" then
return nil
end
local x = pos.x
local xLayer = plan[x] or plan[tostring(x)]
if type(xLayer) ~= "table" then
return nil
end
local y = pos.y
local yLayer = xLayer[y] or xLayer[tostring(y)]
if type(yLayer) ~= "table" then
return nil
end
local z = pos.z
return yLayer[z] or yLayer[tostring(z)]
end
local function tryInspect(inspectFn)
if type(inspectFn) ~= "function" then
return nil
end
local ok, success, data = pcall(inspectFn)
if not ok or not success then
return nil
end
if type(data) == "table" then
return data
end
return nil
end
local function ensureMovementState(ctx)
if type(ctx) ~= "table" then
error("movement library requires a context table", 2)
end
ctx.movement = ctx.movement or {}
local state = ctx.movement
local cfg = ctx.config or {}
if not state.position then
if ctx.origin then
state.position = copyPosition(ctx.origin)
else
state.position = { x = 0, y = 0, z = 0 }
end
end
if not state.homeFacing then
state.homeFacing = canonicalFacing(cfg.homeFacing) or canonicalFacing(cfg.initialFacing) or "north"
end
if not state.facing then
state.facing = canonicalFacing(cfg.initialFacing) or state.homeFacing
end
state.position = copyPosition(state.position)
if not state.softBlockLookup then
state.softBlockLookup = extendLookup(cloneLookup(DEFAULT_SOFT_BLOCKS), cfg.movementSoftBlocks)
end
if not state.softTagLookup then
state.softTagLookup = extendLookup(cloneLookup(DEFAULT_SOFT_TAGS), cfg.movementSoftTags)
end
if not state.softNameHints then
state.softNameHints = buildSoftNameHintList(cfg.movementSoftNameHints)
end
state.hasSoftClearRules = (next(state.softBlockLookup) ~= nil)
or (next(state.softTagLookup) ~= nil)
or ((state.softNameHints and #state.softNameHints > 0) or false)
return state
end
function movement.ensureState(ctx)
return ensureMovementState(ctx)
end
function movement.getPosition(ctx)
local state = ensureMovementState(ctx)
return copyPosition(state.position)
end
function movement.setPosition(ctx, pos)
local state = ensureMovementState(ctx)
state.position = copyPosition(pos)
return true
end
function movement.getFacing(ctx)
local state = ensureMovementState(ctx)
return state.facing
end
function movement.setFacing(ctx, facing)
local state = ensureMovementState(ctx)
local canonical = canonicalFacing(facing)
if not canonical then
return false, "unknown facing: " .. tostring(facing)
end
state.facing = canonical
logger.log(ctx, "debug", "Set facing to " .. canonical)
return true
end
local function turn(ctx, direction)
local state = ensureMovementState(ctx)
if not turtle then
return false, "turtle API unavailable"
end
local rotateFn
if direction == "left" then
rotateFn = turtle.turnLeft
elseif direction == "right" then
rotateFn = turtle.turnRight
else
return false, "invalid turn direction"
end
if not rotateFn then
return false, "turn function missing"
end
local ok = rotateFn()
if not ok then
return false, "turn " .. direction .. " failed"
end
local current = state.facing
local index
for i, name in ipairs(CARDINALS) do
if name == current then
index = i
break
end
end
if not index then
index = 1
current = CARDINALS[index]
end
if direction == "left" then
index = ((index - 2) % #CARDINALS) + 1
else
index = (index % #CARDINALS) + 1
end
state.facing = CARDINALS[index]
logger.log(ctx, "debug", "Turned " .. direction .. ", now facing " .. state.facing)
return true
end
function movement.turnLeft(ctx)
return turn(ctx, "left")
end
function movement.turnRight(ctx)
return turn(ctx, "right")
end
function movement.turnAround(ctx)
local ok, err = movement.turnRight(ctx)
if not ok then
return false, err
end
ok, err = movement.turnRight(ctx)
if not ok then
return false, err
end
return true
end
function movement.faceDirection(ctx, targetFacing)
local state = ensureMovementState(ctx)
local canonical = canonicalFacing(targetFacing)
if not canonical then
return false, "unknown facing: " .. tostring(targetFacing)
end
local currentIndex
local targetIndex
for i, name in ipairs(CARDINALS) do
if name == state.facing then
currentIndex = i
end
if name == canonical then
targetIndex = i
end
end
if not targetIndex then
return false, "cannot face unknown cardinal"
end
if currentIndex == targetIndex then
return true
end
if not currentIndex then
state.facing = canonical
return true
end
local diff = (targetIndex - currentIndex) % #CARDINALS
if diff == 0 then
return true
elseif diff == 1 then
return movement.turnRight(ctx)
elseif diff == 2 then
local ok, err = movement.turnRight(ctx)
if not ok then
return false, err
end
ok, err = movement.turnRight(ctx)
if not ok then
return false, err
end
return true
else -- diff == 3
return movement.turnLeft(ctx)
end
end
local function getMoveConfig(ctx, opts)
local cfg = ctx.config or {}
local maxRetries = (opts and opts.maxRetries) or cfg.maxMoveRetries or 5
local allowDig = opts and opts.dig
if allowDig == nil then
allowDig = cfg.digOnMove
if allowDig == nil then
allowDig = true
end
end
local allowAttack = opts and opts.attack
if allowAttack == nil then
allowAttack = cfg.attackOnMove
if allowAttack == nil then
allowAttack = true
end
end
local delay = (opts and opts.retryDelay) or cfg.moveRetryDelay or 0.5
return maxRetries, allowDig, allowAttack, delay
end
local function moveWithRetries(ctx, opts, moveFns, delta)
local state = ensureMovementState(ctx)
if not turtle then
return false, "turtle API unavailable"
end
local maxRetries, allowDig, allowAttack, delay = getMoveConfig(ctx, opts)
if type(maxRetries) ~= "number" or maxRetries < 1 then
maxRetries = 1
else
maxRetries = math.floor(maxRetries)
end
if (allowDig or state.hasSoftClearRules) and maxRetries < 2 then
maxRetries = 2
end
local attempt = 0
while attempt < maxRetries do
attempt = attempt + 1
local targetPos = vecAdd(state.position, delta)
if moveFns.move() then
state.position = targetPos
logger.log(ctx, "debug", string.format("Moved to x=%d y=%d z=%d", state.position.x, state.position.y, state.position.z))
return true
end
local handled = false
if allowAttack and moveFns.attack then
if moveFns.attack() then
handled = true
logger.log(ctx, "debug", "Attacked entity blocking movement")
end
end
local blocked = moveFns.detect and moveFns.detect() or false
local inspectData
if blocked then
inspectData = tryInspect(moveFns.inspect)
end
if blocked and moveFns.dig then
local plannedMaterial
local canClear = false
local softBlock = inspectData and isSoftBlock(state, inspectData)
if softBlock then
canClear = true
elseif allowDig then
plannedMaterial = getPlannedMaterial(ctx, targetPos)
canClear = true
if inspectData and inspectData.name and (inspectData.name:find("chest") or inspectData.name:find("barrel")) then
if not opts or not opts.forceDigChests then
canClear = false
logger.log(ctx, "warn", "Refusing to dig chest/barrel at " .. tostring(inspectData.name))
end
end
if plannedMaterial then
if inspectData and inspectData.name then
if inspectData.name == plannedMaterial then
canClear = false
end
else
canClear = false
end
end
end
if canClear and moveFns.dig() then
handled = true
if moveFns.suck then
moveFns.suck()
end
if softBlock then
local foundName = inspectData and inspectData.name or "unknown"
logger.log(ctx, "debug", string.format(
"Cleared soft obstruction %s at x=%d y=%d z=%d",
tostring(foundName),
targetPos.x or 0,
targetPos.y or 0,
targetPos.z or 0
))
elseif plannedMaterial then
local foundName = inspectData and inspectData.name or "unknown"
logger.log(ctx, "debug", string.format(
"Cleared mismatched block %s (expected %s) at x=%d y=%d z=%d",
tostring(foundName),
tostring(plannedMaterial),
targetPos.x or 0,
targetPos.y or 0,
targetPos.z or 0
))
else
local foundName = inspectData and inspectData.name
if foundName then
logger.log(ctx, "debug", string.format(
"Dug blocking block %s at x=%d y=%d z=%d",
foundName,
targetPos.x or 0,
targetPos.y or 0,
targetPos.z or 0
))
else
logger.log(ctx, "debug", string.format(
"Dug blocking block at x=%d y=%d z=%d",
targetPos.x or 0,
targetPos.y or 0,
targetPos.z or 0
))
end
end
elseif plannedMaterial and not canClear and allowDig then
logger.log(ctx, "debug", string.format(
"Preserving planned block %s at x=%d y=%d z=%d",
tostring(plannedMaterial),
targetPos.x or 0,
targetPos.y or 0,
targetPos.z or 0
))
end
end
if attempt < maxRetries then
if delay and delay > 0 and _G.sleep then
sleep(delay)
end
end
end
local axisDelta = string.format("(dx=%d, dy=%d, dz=%d)", delta.x or 0, delta.y or 0, delta.z or 0)
return false, "unable to move " .. axisDelta .. " after " .. tostring(maxRetries) .. " attempts"
end
function movement.forward(ctx, opts)
local state = ensureMovementState(ctx)
local facing = state.facing or "north"
local delta = copyPosition(DIRECTION_VECTORS[facing])
local moveFns = {
move = turtle and turtle.forward or nil,
detect = turtle and turtle.detect or nil,
dig = turtle and turtle.dig or nil,
attack = turtle and turtle.attack or nil,
inspect = turtle and turtle.inspect or nil,
suck = turtle and turtle.suck or nil,
}
if not moveFns.move then
return false, "turtle API unavailable"
end
return moveWithRetries(ctx, opts, moveFns, delta)
end
function movement.up(ctx, opts)
local moveFns = {
move = turtle and turtle.up or nil,
detect = turtle and turtle.detectUp or nil,
dig = turtle and turtle.digUp or nil,
attack = turtle and turtle.attackUp or nil,
inspect = turtle and turtle.inspectUp or nil,
suck = turtle and turtle.suckUp or nil,
}
if not moveFns.move then
return false, "turtle API unavailable"
end
return moveWithRetries(ctx, opts, moveFns, { x = 0, y = 1, z = 0 })
end
function movement.down(ctx, opts)
local moveFns = {
move = turtle and turtle.down or nil,
detect = turtle and turtle.detectDown or nil,
dig = turtle and turtle.digDown or nil,
attack = turtle and turtle.attackDown or nil,
inspect = turtle and turtle.inspectDown or nil,
suck = turtle and turtle.suckDown or nil,
}
if not moveFns.move then
return false, "turtle API unavailable"
end
return moveWithRetries(ctx, opts, moveFns, { x = 0, y = -1, z = 0 })
end
local function axisFacing(axis, delta)
if delta > 0 then
return AXIS_FACINGS[axis].positive
else
return AXIS_FACINGS[axis].negative
end
end
local function moveAxis(ctx, axis, delta, opts)
if delta == 0 then
return true
end
if axis == "y" then
local moveFn = delta > 0 and movement.up or movement.down
for _ = 1, math.abs(delta) do
local ok, err = moveFn(ctx, opts)
if not ok then
return false, err
end
end
return true
end
local targetFacing = axisFacing(axis, delta)
local ok, err = movement.faceDirection(ctx, targetFacing)
if not ok then
return false, err
end
for step = 1, math.abs(delta) do
ok, err = movement.forward(ctx, opts)
if not ok then
return false, string.format("failed moving along %s on step %d: %s", axis, step, err or "unknown")
end
end
return true
end
function movement.goTo(ctx, targetPos, opts)
ensureMovementState(ctx)
if type(targetPos) ~= "table" then
return false, "target position must be a table"
end
local state = ctx.movement
local axisOrder = (opts and opts.axisOrder) or (ctx.config and ctx.config.movementAxisOrder) or { "x", "z", "y" }
for _, axis in ipairs(axisOrder) do
local desired = targetPos[axis]
if desired == nil then
return false, "target position missing axis " .. axis
end
local delta = desired - (state.position[axis] or 0)
local ok, err = moveAxis(ctx, axis, delta, opts)
if not ok then
return false, err
end
end
return true
end
function movement.stepPath(ctx, pathNodes, opts)
if type(pathNodes) ~= "table" then
return false, "pathNodes must be a table"
end
for index, node in ipairs(pathNodes) do
local ok, err = movement.goTo(ctx, node, opts)
if not ok then
return false, string.format("failed at path node %d: %s", index, err or "unknown")
end
end
return true
end
function movement.returnToOrigin(ctx, opts)
ensureMovementState(ctx)
if not ctx.origin then
return false, "ctx.origin is required"
end
local ok, err = movement.goTo(ctx, ctx.origin, opts)
if not ok then
return false, err
end
local desiredFacing = (opts and opts.facing) or ctx.movement.homeFacing
if desiredFacing then
ok, err = movement.faceDirection(ctx, desiredFacing)
if not ok then
return false, err
end
end
return true
end
function movement.turnLeftOf(facing)
facing = world.normaliseFacing(facing)
if facing == "north" then
return "west"
elseif facing == "west" then
return "south"
elseif facing == "south" then
return "east"
else -- east
return "north"
end
end
function movement.turnRightOf(facing)
facing = world.normaliseFacing(facing)
if facing == "north" then
return "east"
elseif facing == "east" then
return "south"
elseif facing == "south" then
return "west"
else -- west
return "north"
end
end
function movement.turnBackOf(facing)
facing = world.normaliseFacing(facing)
if facing == "north" then
return "south"
elseif facing == "south" then
return "north"
elseif facing == "east" then
return "west"
else -- west
return "east"
end
end
function movement.describePosition(ctx)
local pos = movement.getPosition(ctx)
local facing = movement.getFacing(ctx)
return string.format("(x=%d, y=%d, z=%d, facing=%s)", pos.x, pos.y, pos.z, tostring(facing))
end
function movement.face(ctx, targetFacing)
return movement.faceDirection(ctx, targetFacing)
end
return movement]]
files["lib/lib_navigation.lua"] = [[local okMovement, movement = pcall(require, "lib_movement")
if not okMovement then
movement = nil
end
local logger = require("lib_logger")
local table_utils = require("lib_table")
local world = require("lib_world")
local navigation = {}
local function isCoordinateSpec(tbl)
if type(tbl) ~= "table" then
return false
end
if tbl.route or tbl.waypoint or tbl.path or tbl.nodes or tbl.sequence or tbl.via or tbl.target or tbl.align then
return false
end
local hasX = tbl.x ~= nil or tbl[1] ~= nil
local hasY = tbl.y ~= nil or tbl[2] ~= nil
local hasZ = tbl.z ~= nil or tbl[3] ~= nil
return hasX and hasY and hasZ
end
local function cloneNodeDefinition(def)
if type(def) ~= "table" then
return nil, "invalid_route_definition"
end
local result = {}
for index, value in ipairs(def) do
if type(value) == "table" then
result[index] = table_utils.copyValue(value)
else
result[index] = value
end
end
return result
end
local function ensureNavigationState(ctx)
if type(ctx) ~= "table" then
error("navigation library requires a context table", 2)
end
if type(ctx.navigationState) ~= "table" then
ctx.navigationState = ctx.navigation or {}
end
ctx.navigation = ctx.navigationState
local state = ctx.navigationState
state.waypoints = state.waypoints or {}
state.routes = state.routes or {}
state.restock = state.restock or {}
state._configLoaded = state._configLoaded or false
if ctx.origin then
local originPos, originErr = world.normalisePosition(ctx.origin)
if originPos then
state.waypoints.origin = originPos
elseif originErr then
logger.log(ctx, "warn", "Origin position invalid: " .. tostring(originErr))
end
end
if not state._configLoaded then
state._configLoaded = true
local cfg = ctx.config
if type(cfg) == "table" and type(cfg.navigation) == "table" then
local navCfg = cfg.navigation
if type(navCfg.waypoints) == "table" then
for name, pos in pairs(navCfg.waypoints) do
local normalised, err = world.normalisePosition(pos)
if normalised then
state.waypoints[name] = normalised
else
logger.log(ctx, "warn", string.format("Ignoring navigation waypoint '%s': %s", tostring(name), tostring(err)))
end
end
end
if type(navCfg.routes) == "table" then
for name, def in pairs(navCfg.routes) do
local cloned, err = cloneNodeDefinition(def)
if cloned then
state.routes[name] = cloned
else
logger.log(ctx, "warn", string.format("Ignoring navigation route '%s': %s", tostring(name), tostring(err)))
end
end
end
if type(navCfg.restock) == "table" then
state.restock = table_utils.copyValue(navCfg.restock)
end
end
end
return state
end
local function resolveWaypoint(ctx, name)
local state = ensureNavigationState(ctx)
if type(name) ~= "string" or name == "" then
return nil, "invalid_waypoint"
end
local pos = state.waypoints[name]
if not pos then
return nil, "unknown_waypoint"
end
return { x = pos.x, y = pos.y, z = pos.z }
end
local expandSpec
local function expandListToNodes(ctx, list, visited)
if type(list) ~= "table" then
return nil, "invalid_path_list"
end
local nodes = {}
local meta = {}
for index, entry in ipairs(list) do
local entryNodes, entryMeta = expandSpec(ctx, entry, visited)
if not entryNodes then
return nil, string.format("path[%d]: %s", index, tostring(entryMeta or "invalid"))
end
for _, node in ipairs(entryNodes) do
nodes[#nodes + 1] = node
end
if entryMeta and entryMeta.finalFacing and not meta.finalFacing then
meta.finalFacing = entryMeta.finalFacing
end
end
return nodes, meta
end
local function expandRouteByName(ctx, name, visited)
if type(name) ~= "string" or name == "" then
return nil, "invalid_route_name"
end
local state = ensureNavigationState(ctx)
local def = state.routes[name]
if not def then
return nil, "unknown_route"
end
visited = visited or {}
if visited[name] then
return nil, "route_cycle"
end
visited[name] = true
local nodes, meta = expandListToNodes(ctx, def, visited)
visited[name] = nil
return nodes, meta
end
function expandSpec(ctx, spec, visited)
local specType = type(spec)
if specType == "string" then
local routeNodes, routeMeta = expandRouteByName(ctx, spec, visited)
if routeNodes then
return routeNodes, routeMeta
end
if routeMeta ~= "unknown_route" then
return nil, routeMeta
end
local pos, err = resolveWaypoint(ctx, spec)
if not pos then
return nil, err or "unknown_reference"
end
return { pos }, {}
elseif specType == "function" then
local ok, result = pcall(spec, ctx)
if not ok then
return nil, "navigation_callback_failed"
end
if result == nil then
return {}, {}
end
return expandSpec(ctx, result, visited)
elseif specType ~= "table" then
return nil, "invalid_navigation_spec"
end
if isCoordinateSpec(spec) then
local pos, err = world.normalisePosition(spec)
if not pos then
return nil, err
end
local meta = {}
if spec.finalFacing or spec.facing then
meta.finalFacing = spec.finalFacing or spec.facing
end
return { pos }, meta
end
local nodes = {}
local meta = {}
local facing = spec.finalFacing or spec.facing
if facing then
meta.finalFacing = facing
end
if spec.sequence then
local seqNodes, seqMeta = expandListToNodes(ctx, spec.sequence, visited)
if not seqNodes then
return nil, seqMeta
end
for _, node in ipairs(seqNodes) do
nodes[#nodes + 1] = node
end
if seqMeta.finalFacing and not meta.finalFacing then
meta.finalFacing = seqMeta.finalFacing
end
end
if spec.via then
local viaNodes, viaMeta = expandListToNodes(ctx, spec.via, visited)
if not viaNodes then
return nil, viaMeta
end
for _, node in ipairs(viaNodes) do
nodes[#nodes + 1] = node
end
if viaMeta.finalFacing and not meta.finalFacing then
meta.finalFacing = viaMeta.finalFacing
end
end
if spec.path then
local pathNodes, pathMeta = expandListToNodes(ctx, spec.path, visited)
if not pathNodes then
return nil, pathMeta
end
for _, node in ipairs(pathNodes) do
nodes[#nodes + 1] = node
end
if pathMeta.finalFacing and not meta.finalFacing then
meta.finalFacing = pathMeta.finalFacing
end
elseif spec.nodes then
local pathNodes, pathMeta = expandListToNodes(ctx, spec.nodes, visited)
if not pathNodes then
return nil, pathMeta
end
for _, node in ipairs(pathNodes) do
nodes[#nodes + 1] = node
end
if pathMeta.finalFacing and not meta.finalFacing then
meta.finalFacing = pathMeta.finalFacing
end
end
if spec.route then
if type(spec.route) == "table" then
local routeNodes, routeMeta = expandListToNodes(ctx, spec.route, visited)
if not routeNodes then
return nil, routeMeta
end
for _, node in ipairs(routeNodes) do
nodes[#nodes + 1] = node
end
if routeMeta.finalFacing and not meta.finalFacing then
meta.finalFacing = routeMeta.finalFacing
end
else
local routeNodes, routeMeta = expandRouteByName(ctx, spec.route, visited)
if not routeNodes then
return nil, routeMeta
end
for _, node in ipairs(routeNodes) do
nodes[#nodes + 1] = node
end
if routeMeta and routeMeta.finalFacing and not meta.finalFacing then
meta.finalFacing = routeMeta.finalFacing
end
end
end
if spec.waypoint then
local pos, err = resolveWaypoint(ctx, spec.waypoint)
if not pos then
return nil, err
end
nodes[#nodes + 1] = pos
end
if spec.position then
local pos, err = world.normalisePosition(spec.position)
if not pos then
return nil, err
end
nodes[#nodes + 1] = pos
end
if spec.target then
local targetNodes, targetMeta = expandSpec(ctx, spec.target, visited)
if not targetNodes then
return nil, targetMeta
end
for _, node in ipairs(targetNodes) do
nodes[#nodes + 1] = node
end
if targetMeta.finalFacing and not meta.finalFacing then
meta.finalFacing = targetMeta.finalFacing
end
end
if spec.align then
local alignNodes, alignMeta = expandSpec(ctx, spec.align, visited)
if not alignNodes then
return nil, alignMeta
end
for _, node in ipairs(alignNodes) do
nodes[#nodes + 1] = node
end
if alignMeta.finalFacing then
meta.finalFacing = alignMeta.finalFacing
end
end
return nodes, meta
end
function navigation.ensureState(ctx)
return ensureNavigationState(ctx)
end
function navigation.registerWaypoint(ctx, name, position)
if type(name) ~= "string" or name == "" then
return false, "invalid_waypoint_name"
end
local state = ensureNavigationState(ctx)
local pos, err = world.normalisePosition(position)
if not pos then
return false, err or "invalid_position"
end
state.waypoints[name] = pos
return true
end
function navigation.getWaypoint(ctx, name)
return resolveWaypoint(ctx, name)
end
function navigation.listWaypoints(ctx)
local state = ensureNavigationState(ctx)
local result = {}
for name, pos in pairs(state.waypoints) do
result[name] = { x = pos.x, y = pos.y, z = pos.z }
end
return result
end
function navigation.registerRoute(ctx, name, nodes)
if type(name) ~= "string" or name == "" then
return false, "invalid_route_name"
end
local state = ensureNavigationState(ctx)
local cloned, err = cloneNodeDefinition(nodes)
if not cloned then
return false, err or "invalid_route"
end
state.routes[name] = cloned
return true
end
function navigation.getRoute(ctx, name)
local nodes, meta = expandRouteByName(ctx, name, {})
if not nodes then
return nil, meta
end
return nodes, meta
end
function navigation.plan(ctx, targetSpec, opts)
ensureNavigationState(ctx)
if targetSpec == nil then
return nil, "missing_target"
end
local nodes, meta = expandSpec(ctx, targetSpec, {})
if not nodes then
return nil, meta
end
if opts and opts.includeCurrent == false and #nodes > 0 then
end
return nodes, meta
end
local function resolveRestockSpec(ctx, kind)
local state = ensureNavigationState(ctx)
local restock = state.restock
local spec
if type(restock) == "table" then
if kind and restock[kind] ~= nil then
spec = restock[kind]
elseif restock.default ~= nil then
spec = restock.default
elseif restock.fallback ~= nil then
spec = restock.fallback
end
end
if spec == nil and state.waypoints.restock then
spec = state.waypoints.restock
end
if spec == nil and state.waypoints.origin then
spec = state.waypoints.origin
end
if spec == nil then
return nil
end
return table_utils.copyValue(spec)
end
function navigation.getRestockTarget(ctx, kind)
local spec = resolveRestockSpec(ctx, kind)
if spec == nil then
return nil, "restock_target_missing"
end
return spec
end
function navigation.setRestockTarget(ctx, kind, spec)
local state = ensureNavigationState(ctx)
if type(kind) ~= "string" or kind == "" then
kind = "default"
end
if spec == nil then
state.restock[kind] = nil
return true
end
local specType = type(spec)
if specType ~= "string" and specType ~= "table" and specType ~= "function" then
return false, "invalid_restock_spec"
end
state.restock[kind] = table_utils.copyValue(spec)
return true
end
function navigation.planRestock(ctx, opts)
local kind = nil
if type(opts) == "table" then
kind = opts.kind or opts.type or opts.category
end
local spec = resolveRestockSpec(ctx, kind)
if spec == nil then
return nil, "restock_target_missing"
end
local nodes, meta = navigation.plan(ctx, spec, opts)
if not nodes then
return nil, meta
end
return nodes, meta
end
function navigation.travel(ctx, targetSpec, opts)
ensureNavigationState(ctx)
if not movement then
return false, "movement_library_unavailable"
end
local nodes, meta = navigation.plan(ctx, targetSpec, opts)
if not nodes then
return false, meta
end
movement.ensureState(ctx)
if #nodes > 0 then
local moveOpts = opts and opts.move
local ok, err = movement.stepPath(ctx, nodes, moveOpts)
if not ok then
return false, err
end
end
local finalFacing = (opts and opts.finalFacing) or (meta and meta.finalFacing)
if finalFacing then
local ok, err = movement.faceDirection(ctx, finalFacing)
if not ok then
return false, err
end
end
return true
end
function navigation.travelToRestock(ctx, opts)
local kind = nil
if type(opts) == "table" then
kind = opts.kind or opts.type or opts.category
end
local spec, err = navigation.getRestockTarget(ctx, kind)
if not spec then
return false, err
end
return navigation.travel(ctx, spec, opts)
end
return navigation]]
files["lib/lib_orientation.lua"] = [[local movement = require("lib_movement")
local world = require("lib_world")
local gps_utils = require("lib_gps")
local orientation = {}
local START_ORIENTATIONS = {
[1] = { label = "Forward + Left", key = "forward_left" },
[2] = { label = "Forward + Right", key = "forward_right" },
}
local DEFAULT_ORIENTATION = 1
function orientation.resolveOrientationKey(raw)
if type(raw) == "string" then
local key = raw:lower()
if key == "forward_left" or key == "forward-left" or key == "left" or key == "l" then
return "forward_left"
elseif key == "forward_right" or key == "forward-right" or key == "right" or key == "r" then
return "forward_right"
end
elseif type(raw) == "number" and START_ORIENTATIONS[raw] then
return START_ORIENTATIONS[raw].key
end
return START_ORIENTATIONS[DEFAULT_ORIENTATION].key
end
function orientation.orientationLabel(key)
local resolved = orientation.resolveOrientationKey(key)
for _, entry in pairs(START_ORIENTATIONS) do
if entry.key == resolved then
return entry.label
end
end
return START_ORIENTATIONS[DEFAULT_ORIENTATION].label
end
function orientation.normaliseFacing(facing)
return world.normaliseFacing(facing)
end
function orientation.facingVectors(facing)
return world.facingVectors(facing)
end
function orientation.rotateLocalOffset(localOffset, facing)
return world.rotateLocalOffset(localOffset, facing)
end
function orientation.localToWorld(localOffset, facing)
return world.localToWorld(localOffset, facing)
end
function orientation.detectFacingWithGps(logger)
return gps_utils.detectFacingWithGps(logger)
end
function orientation.turnLeftOf(facing)
return movement.turnLeftOf(facing)
end
function orientation.turnRightOf(facing)
return movement.turnRightOf(facing)
end
function orientation.turnBackOf(facing)
return movement.turnBackOf(facing)
end
return orientation]]
files["lib/lib_parser.lua"] = [[local parser = {}
local logger = require("lib_logger")
local table_utils = require("lib_table")
local fs_utils = require("lib_fs")
local json_utils = require("lib_json")
local schema_utils = require("lib_schema")
local function parseLayerRows(schema, bounds, counts, layerDef, legend, opts)
local rows = layerDef.rows
if type(rows) ~= "table" then
return false, "invalid_layer"
end
local height = #rows
if height == 0 then
return true
end
local width = nil
for rowIndex, row in ipairs(rows) do
if type(row) ~= "string" then
return false, "invalid_row"
end
if width == nil then
width = #row
if width == 0 then
return false, "empty_row"
end
elseif width ~= #row then
return false, "ragged_row"
end
for col = 1, #row do
local symbol = row:sub(col, col)
local entry, err = schema_utils.resolveSymbol(symbol, legend, opts)
if err then
return false, string.format("legend_error:%s", symbol)
end
if entry then
local x = (layerDef.x or 0) + (col - 1)
local y = layerDef.y or 0
local z = (layerDef.z or 0) + (rowIndex - 1)
local ok, addErr = schema_utils.addBlock(schema, bounds, counts, x, y, z, entry.material, entry.meta)
if not ok then
return false, addErr
end
end
end
end
return true
end
local function toLayerRows(layer)
if type(layer) == "string" then
local rows = {}
for line in layer:gmatch("([^\r\n]+)") do
rows[#rows + 1] = line
end
return { rows = rows }
end
if type(layer) == "table" then
if layer.rows then
local rows = {}
for i = 1, #layer.rows do
rows[i] = tostring(layer.rows[i])
end
return {
rows = rows,
y = layer.y or layer.height or layer.level or 0,
x = layer.x or layer.offsetX or 0,
z = layer.z or layer.offsetZ or 0,
}
end
local rows = {}
local count = 0
for _, value in ipairs(layer) do
rows[#rows + 1] = tostring(value)
count = count + 1
end
if count > 0 then
return { rows = rows, y = layer.y or 0, x = layer.x or 0, z = layer.z or 0 }
end
end
return nil
end
local function parseLayers(schema, bounds, counts, def, legend, opts)
local layers = def.layers
if type(layers) ~= "table" then
return false, "invalid_layers"
end
local used = 0
for index, layer in ipairs(layers) do
local layerRows = toLayerRows(layer)
if not layerRows then
return false, "invalid_layer"
end
if not layerRows.y then
layerRows.y = (def.baseY or 0) + (index - 1)
else
layerRows.y = layerRows.y + (def.baseY or 0)
end
if def.baseX then
layerRows.x = (layerRows.x or 0) + def.baseX
end
if def.baseZ then
layerRows.z = (layerRows.z or 0) + def.baseZ
end
local ok, err = parseLayerRows(schema, bounds, counts, layerRows, legend, opts)
if not ok then
return false, err
end
used = used + 1
end
if used == 0 then
return false, "empty_layers"
end
return true
end
local function parseBlockList(schema, bounds, counts, blocks)
local used = 0
for _, block in ipairs(blocks) do
if type(block) ~= "table" then
return false, "invalid_block"
end
local x = block.x or block[1]
local y = block.y or block[2]
local z = block.z or block[3]
local material = block.material or block.name or block.block
local meta = block.meta or block.data
if type(meta) ~= "table" then
meta = {}
end
local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
if not ok then
return false, err
end
used = used + 1
end
if used == 0 then
return false, "empty_blocks"
end
return true
end
local function parseVoxelGrid(schema, bounds, counts, grid)
if type(grid) ~= "table" then
return false, "invalid_grid"
end
local used = 0
for xKey, xColumn in pairs(grid) do
local x = tonumber(xKey) or xKey
if type(x) ~= "number" then
return false, "invalid_coordinate"
end
if type(xColumn) ~= "table" then
return false, "invalid_grid"
end
for yKey, yColumn in pairs(xColumn) do
local y = tonumber(yKey) or yKey
if type(y) ~= "number" then
return false, "invalid_coordinate"
end
if type(yColumn) ~= "table" then
return false, "invalid_grid"
end
for zKey, entry in pairs(yColumn) do
local z = tonumber(zKey) or zKey
if type(z) ~= "number" then
return false, "invalid_coordinate"
end
if entry ~= nil then
local material
local meta = {}
if type(entry) == "string" then
material = entry
elseif type(entry) == "table" then
material = entry.material or entry.name or entry.block
meta = type(entry.meta) == "table" and entry.meta or {}
else
return false, "invalid_block"
end
if material and material ~= "" then
local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
if not ok then
return false, err
end
used = used + 1
end
end
end
end
end
if used == 0 then
return false, "empty_grid"
end
return true
end
local function summarise(bounds, counts)
local materials = {}
for material, count in pairs(counts) do
materials[#materials + 1] = { material = material, count = count }
end
table.sort(materials, function(a, b)
if a.count == b.count then
return a.material < b.material
end
return a.count > b.count
end)
local total = 0
for _, entry in ipairs(materials) do
total = total + entry.count
end
return {
bounds = {
min = table_utils.shallowCopy(bounds.min),
max = table_utils.shallowCopy(bounds.max),
},
materials = materials,
totalBlocks = total,
}
end
local function buildCanonical(def, opts)
local schema = {}
local bounds = schema_utils.newBounds()
local counts = {}
local ok, err
if def.blocks then
ok, err = parseBlockList(schema, bounds, counts, def.blocks)
elseif def.layers then
ok, err = parseLayers(schema, bounds, counts, def, def.legend, opts)
elseif def.grid then
ok, err = parseVoxelGrid(schema, bounds, counts, def.grid)
else
return nil, "unknown_definition"
end
if not ok then
return nil, err
end
if bounds.min.x == math.huge then
return nil, "empty_schema"
end
return schema, summarise(bounds, counts)
end
local function detectFormatFromExtension(path)
if type(path) ~= "string" then
return nil
end
local ext = path:match("%.([%w_%-]+)$")
if not ext then
return nil
end
ext = ext:lower()
if ext == "json" or ext == "schem" then
return "json"
end
if ext == "txt" or ext == "grid" then
return "grid"
end
if ext == "vox" or ext == "voxel" then
return "voxel"
end
return nil
end
local function detectFormatFromText(text)
if type(text) ~= "string" then
return nil
end
local trimmed = text:match("^%s*(.-)%s*$") or text
local firstChar = trimmed:sub(1, 1)
if firstChar == "{" or firstChar == "[" then
return "json"
end
return "grid"
end
local function parseLegendBlock(lines, index)
local legend = {}
local pos = index
while pos <= #lines do
local line = lines[pos]
if line == "" then
break
end
if line:match("^layer") then
break
end
local symbol, rest = line:match("^(%S+)%s*[:=]%s*(.+)$")
if not symbol then
symbol, rest = line:match("^(%S+)%s+(.+)$")
end
if symbol and rest then
rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
local value
if rest:sub(1, 1) == "{" then
local parsed = json_utils.decodeJson(rest)
if parsed then
value = parsed
else
value = rest
end
else
value = rest
end
legend[symbol] = value
end
pos = pos + 1
end
return legend, pos
end
local function parseTextGridContent(text, opts)
local lines = {}
for line in (text .. "\n"):gmatch("([^\n]*)\n") do
line = line:gsub("\r$", "")
lines[#lines + 1] = line
end
local legend = schema_utils.mergeLegend(opts and opts.legend or nil, nil)
local layers = {}
local current = {}
local currentY = nil
local lineIndex = 1
while lineIndex <= #lines do
local line = lines[lineIndex]
local trimmed = line:match("^%s*(.-)%s*$")
if trimmed == "" then
if #current > 0 then
layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
current = {}
currentY = nil
end
lineIndex = lineIndex + 1
elseif trimmed:lower() == "legend:" then
local legendBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1)
legend = schema_utils.mergeLegend(legend, legendBlock)
lineIndex = nextIndex
elseif trimmed:match("^layer") then
if #current > 0 then
layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
current = {}
end
local yValue = trimmed:match("layer%s*[:=]%s*(-?%d+)")
currentY = yValue and tonumber(yValue) or (#layers)
lineIndex = lineIndex + 1
else
current[#current + 1] = line
lineIndex = lineIndex + 1
end
end
if #current > 0 then
layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
end
if not legend or next(legend) == nil then
return nil, "missing_legend"
end
if #layers == 0 then
return nil, "empty_layers"
end
return {
layers = layers,
legend = legend,
}
end
local function parseJsonContent(obj, opts)
if type(obj) ~= "table" then
return nil, "invalid_json_root"
end
local legend = schema_utils.mergeLegend(opts and opts.legend or nil, obj.legend or nil)
if obj.blocks then
return {
blocks = obj.blocks,
legend = legend,
}
end
if obj.layers then
return {
layers = obj.layers,
legend = legend,
baseX = obj.baseX,
baseY = obj.baseY,
baseZ = obj.baseZ,
}
end
if obj.grid or obj.voxels then
return {
grid = obj.grid or obj.voxels,
legend = legend,
}
end
if #obj > 0 then
return {
blocks = obj,
legend = legend,
}
end
return nil, "unrecognised_json"
end
local function assignToContext(ctx, schema, info)
if type(ctx) ~= "table" then
return
end
ctx.schema = schema
ctx.schemaInfo = info
end
local function ensureSpecTable(spec)
if type(spec) == "table" then
return table_utils.shallowCopy(spec)
end
if type(spec) == "string" then
return { source = spec }
end
return {}
end
function parser.parse(ctx, spec)
spec = ensureSpecTable(spec)
local format = spec.format
local text = spec.text
local data = spec.data
local path = spec.path or spec.sourcePath
local source = spec.source
if not format and spec.path then
format = detectFormatFromExtension(spec.path)
end
if not format and spec.formatHint then
format = spec.formatHint
end
if not text and not data then
if spec.textContent then
text = spec.textContent
elseif spec.raw then
text = spec.raw
elseif spec.sourceText then
text = spec.sourceText
end
end
if not path and type(source) == "string" and text == nil and data == nil then
local maybeFormat = detectFormatFromExtension(source)
if maybeFormat then
path = source
format = format or maybeFormat
else
text = source
end
end
if text == nil and path then
local contents, err = fs_utils.readFile(path)
if not contents then
return false, err or "read_failed"
end
text = contents
if not format then
format = detectFormatFromExtension(path) or detectFormatFromText(text)
end
end
if not format then
if data then
if data.layers then
format = "grid"
elseif data.blocks then
format = "json"
elseif data.grid or data.voxels then
format = "voxel"
end
elseif text then
format = detectFormatFromText(text)
end
end
if not format then
return false, "unknown_format"
end
local definition, err
if format == "json" then
if data then
definition, err = parseJsonContent(data, spec)
else
local obj, decodeErr = json_utils.decodeJson(text)
if not obj then
return false, decodeErr
end
definition, err = parseJsonContent(obj, spec)
end
elseif format == "grid" then
if data and (data.layers or data.rows) then
definition = {
layers = data.layers or { data.rows },
legend = schema_utils.mergeLegend(spec.legend or nil, data.legend or nil),
}
else
definition, err = parseTextGridContent(text, spec)
end
elseif format == "voxel" then
if data then
definition = {
grid = data.grid or data.voxels or data,
}
else
local obj, decodeErr = json_utils.decodeJson(text)
if not obj then
return false, decodeErr
end
if obj.grid or obj.voxels then
definition = {
grid = obj.grid or obj.voxels,
}
else
definition, err = parseJsonContent(obj, spec)
end
end
else
return false, "unsupported_format"
end
if not definition then
return false, err or "invalid_definition"
end
if spec.legend then
definition.legend = schema_utils.mergeLegend(definition.legend, spec.legend)
end
local schema, metadata = buildCanonical(definition, spec)
if not schema then
return false, metadata or "parse_failed"
end
if type(metadata) ~= "table" then
metadata = { note = metadata }
end
metadata = metadata or {}
metadata.format = format
metadata.path = path
assignToContext(ctx, schema, metadata)
logger.log(ctx, "debug", string.format("Parsed schema with %d blocks", metadata.totalBlocks or 0))
return true, schema, metadata
end
function parser.parseFile(ctx, path, opts)
opts = opts or {}
opts.path = path
return parser.parse(ctx, opts)
end
function parser.parseText(ctx, text, opts)
opts = opts or {}
opts.text = text
opts.format = opts.format or "grid"
return parser.parse(ctx, opts)
end
function parser.parseJson(ctx, data, opts)
opts = opts or {}
opts.data = data
opts.format = "json"
return parser.parse(ctx, opts)
end
return parser]]
files["lib/lib_placement.lua"] = [[local placement = {}
local logger = require("lib_logger")
local world = require("lib_world")
local fuel = require("lib_fuel")
local schema_utils = require("lib_schema")
local strategy_utils = require("lib_strategy")
local SIDE_APIS = {
forward = {
place = turtle and turtle.place or nil,
detect = turtle and turtle.detect or nil,
inspect = turtle and turtle.inspect or nil,
dig = turtle and turtle.dig or nil,
attack = turtle and turtle.attack or nil,
},
up = {
place = turtle and turtle.placeUp or nil,
detect = turtle and turtle.detectUp or nil,
inspect = turtle and turtle.inspectUp or nil,
dig = turtle and turtle.digUp or nil,
attack = turtle and turtle.attackUp or nil,
},
down = {
place = turtle and turtle.placeDown or nil,
detect = turtle and turtle.detectDown or nil,
inspect = turtle and turtle.inspectDown or nil,
dig = turtle and turtle.digDown or nil,
attack = turtle and turtle.attackDown or nil,
},
}
local function ensurePlacementState(ctx)
if type(ctx) ~= "table" then
error("placement library requires a context table", 2)
end
ctx.placement = ctx.placement or {}
local state = ctx.placement
state.cachedSlots = state.cachedSlots or {}
return state
end
local function selectMaterialSlot(ctx, material)
local state = ensurePlacementState(ctx)
if not turtle or not turtle.getItemDetail or not turtle.select then
return nil, "turtle API unavailable"
end
if type(material) ~= "string" or material == "" then
return nil, "invalid_material"
end
local cached = state.cachedSlots[material]
if cached then
local detail = turtle.getItemDetail(cached)
local count = detail and detail.count
if (not count or count <= 0) and turtle.getItemCount then
count = turtle.getItemCount(cached)
end
if detail and detail.name == material and count and count > 0 then
if turtle.select(cached) then
state.lastSlot = cached
return cached
end
state.cachedSlots[material] = nil
else
state.cachedSlots[material] = nil
end
end
for slot = 1, 16 do
local detail = turtle.getItemDetail(slot)
local count = detail and detail.count
if (not count or count <= 0) and turtle.getItemCount then
count = turtle.getItemCount(slot)
end
if detail and detail.name == material and count and count > 0 then
if turtle.select(slot) then
state.cachedSlots[material] = slot
state.lastSlot = slot
return slot
end
end
end
return nil, "missing_material"
end
local function resolveSide(ctx, block, opts)
if type(opts) == "table" and opts.side then
return opts.side
end
if type(block) == "table" and type(block.meta) == "table" and block.meta.side then
return block.meta.side
end
if type(ctx.config) == "table" and ctx.config.defaultPlacementSide then
return ctx.config.defaultPlacementSide
end
return "forward"
end
local function resolveOverwrite(ctx, block, opts)
if type(opts) == "table" and opts.overwrite ~= nil then
return opts.overwrite
end
if type(block) == "table" and type(block.meta) == "table" and block.meta.overwrite ~= nil then
return block.meta.overwrite
end
if type(ctx.config) == "table" and ctx.config.allowOverwrite ~= nil then
return ctx.config.allowOverwrite
end
return false
end
local function detectBlock(sideFns)
if type(sideFns.inspect) == "function" then
local hasBlock, data = sideFns.inspect()
if hasBlock then
return true, data
end
return false, nil
end
if type(sideFns.detect) == "function" then
local exists = sideFns.detect()
if exists then
return true, nil
end
end
return false, nil
end
local function clearBlockingBlock(sideFns, allowDig, allowAttack)
if not allowDig and not allowAttack then
return false
end
local attempts = 0
local maxAttempts = 4
while attempts < maxAttempts do
attempts = attempts + 1
local cleared = false
if allowDig and type(sideFns.dig) == "function" then
cleared = sideFns.dig() or cleared
end
if not cleared and allowAttack and type(sideFns.attack) == "function" then
cleared = sideFns.attack() or cleared
end
if cleared then
if type(sideFns.detect) ~= "function" or not sideFns.detect() then
return true
end
end
if sleep and attempts < maxAttempts then
sleep(0)
end
end
return false
end
function placement.placeMaterial(ctx, material, opts)
local state = ensurePlacementState(ctx)
if not turtle then
return false, "turtle API unavailable"
end
if material == nil or material == "" or material == "minecraft:air" or material == "air" then
state.lastPlacement = { skipped = true, reason = "air", material = material }
return true
end
local side = resolveSide(ctx, opts and opts.block or nil, opts)
local sideFns = SIDE_APIS[side]
if not sideFns or type(sideFns.place) ~= "function" then
return false, "invalid_side"
end
local slot, slotErr = selectMaterialSlot(ctx, material)
if not slot then
state.lastPlacement = { success = false, material = material, error = slotErr }
return false, slotErr
end
local allowDig = opts and opts.dig
if allowDig == nil then
allowDig = true
end
local allowAttack = opts and opts.attack
if allowAttack == nil then
allowAttack = true
end
local allowOverwrite = resolveOverwrite(ctx, opts and opts.block or nil, opts)
local blockPresent, blockData = detectBlock(sideFns)
local blockingName = blockData and blockData.name or nil
if blockPresent then
if blockData and blockData.name == material then
state.lastPlacement = { success = true, material = material, reused = true, side = side, blocking = blockingName }
return true, "already_present"
end
local needsReplacement = not (blockData and blockData.name == material)
local canForce = allowOverwrite or needsReplacement
if not canForce then
state.lastPlacement = { success = false, material = material, error = "occupied", side = side, blocking = blockingName }
return false, "occupied"
end
local cleared = clearBlockingBlock(sideFns, allowDig, allowAttack)
if not cleared then
local reason = needsReplacement and "mismatched_block" or "blocked"
state.lastPlacement = { success = false, material = material, error = reason, side = side, blocking = blockingName }
return false, reason
end
end
if not turtle.select(slot) then
state.cachedSlots[material] = nil
state.lastPlacement = { success = false, material = material, error = "select_failed", side = side, slot = slot }
return false, "select_failed"
end
local placed, placeErr = sideFns.place()
if not placed then
if placeErr then
logger.log(ctx, "debug", string.format("Place failed for %s: %s", material, placeErr))
end
local stillBlocked = type(sideFns.detect) == "function" and sideFns.detect()
local slotCount
if turtle.getItemCount then
slotCount = turtle.getItemCount(slot)
elseif turtle.getItemDetail then
local detail = turtle.getItemDetail(slot)
slotCount = detail and detail.count or nil
end
local lowerErr = type(placeErr) == "string" and placeErr:lower() or nil
if slotCount ~= nil and slotCount <= 0 then
state.cachedSlots[material] = nil
state.lastPlacement = { success = false, material = material, error = "missing_material", side = side, slot = slot, message = placeErr }
return false, "missing_material"
end
if lowerErr then
if lowerErr:find("no items") or lowerErr:find("no block") or lowerErr:find("missing item") then
state.cachedSlots[material] = nil
state.lastPlacement = { success = false, material = material, error = "missing_material", side = side, slot = slot, message = placeErr }
return false, "missing_material"
end
if lowerErr:find("protect") or lowerErr:find("denied") or lowerErr:find("cannot place") or lowerErr:find("can't place") or lowerErr:find("occupied") then
state.lastPlacement = { success = false, material = material, error = "blocked", side = side, slot = slot, message = placeErr }
return false, "blocked"
end
end
if stillBlocked then
state.lastPlacement = { success = false, material = material, error = "blocked", side = side, slot = slot, message = placeErr }
return false, "blocked"
end
state.lastPlacement = { success = false, material = material, error = "placement_failed", side = side, slot = slot, message = placeErr }
return false, "placement_failed"
end
state.lastPlacement = {
success = true,
material = material,
side = side,
slot = slot,
timestamp = os and os.time and os.time() or nil,
}
return true
end
function placement.advancePointer(ctx)
return strategy_utils.advancePointer(ctx)
end
function placement.ensureState(ctx)
return ensurePlacementState(ctx)
end
function placement.executeBuildState(ctx, opts)
opts = opts or {}
local state = ensurePlacementState(ctx)
local pointer, pointerErr = strategy_utils.ensurePointer(ctx)
if not pointer then
logger.log(ctx, "debug", "No build pointer available: " .. tostring(pointerErr))
return "DONE", { reason = pointerErr or "no_pointer" }
end
if fuel.isFuelLow(ctx) then
state.resumeState = "BUILD"
logger.log(ctx, "info", "Fuel below threshold, switching to REFUEL")
return "REFUEL", { reason = "fuel_low", pointer = world.copyPosition(pointer) }
end
local block, schemaErr = schema_utils.fetchSchemaEntry(ctx.schema, pointer)
if not block then
logger.log(ctx, "debug", string.format("No schema entry at x=%d y=%d z=%d (%s)", pointer.x or 0, pointer.y or 0, pointer.z or 0, tostring(schemaErr)))
local autoAdvance = opts.autoAdvance
if autoAdvance == nil then
autoAdvance = true
end
if autoAdvance then
local advanced = placement.advancePointer(ctx)
if advanced then
return "BUILD", { reason = "skip_empty", pointer = world.copyPosition(ctx.pointer) }
end
end
return "DONE", { reason = "schema_exhausted" }
end
if block.material == nil or block.material == "minecraft:air" or block.material == "air" then
local autoAdvance = opts.autoAdvance
if autoAdvance == nil then
autoAdvance = true
end
if autoAdvance then
local advanced = placement.advancePointer(ctx)
if advanced then
return "BUILD", { reason = "skip_air", pointer = world.copyPosition(ctx.pointer) }
end
end
return "DONE", { reason = "no_material" }
end
local side = resolveSide(ctx, block, opts)
local overwrite = resolveOverwrite(ctx, block, opts)
local allowDig = opts.dig
local allowAttack = opts.attack
if allowDig == nil and block.meta and block.meta.dig ~= nil then
allowDig = block.meta.dig
end
if allowAttack == nil and block.meta and block.meta.attack ~= nil then
allowAttack = block.meta.attack
end
local placementOpts = {
side = side,
overwrite = overwrite,
dig = allowDig,
attack = allowAttack,
block = block,
}
local ok, err = placement.placeMaterial(ctx, block.material, placementOpts)
if not ok then
if err == "missing_material" then
state.resumeState = "BUILD"
state.pendingMaterial = block.material
logger.log(ctx, "warn", string.format("Need to restock %s", block.material))
return "RESTOCK", {
reason = err,
material = block.material,
pointer = world.copyPosition(pointer),
}
end
if err == "blocked" then
state.resumeState = "BUILD"
logger.log(ctx, "warn", "Placement blocked; invoking BLOCKED state")
return "BLOCKED", {
reason = err,
pointer = world.copyPosition(pointer),
material = block.material,
}
end
if err == "turtle API unavailable" then
state.lastError = err
return "ERROR", { reason = err }
end
state.lastError = err
logger.log(ctx, "error", string.format("Placement failed for %s: %s", block.material, tostring(err)))
return "ERROR", {
reason = err,
material = block.material,
pointer = world.copyPosition(pointer),
}
end
state.lastPlaced = {
material = block.material,
pointer = world.copyPosition(pointer),
side = side,
meta = block.meta,
timestamp = os and os.time and os.time() or nil,
}
local autoAdvance = opts.autoAdvance
if autoAdvance == nil then
autoAdvance = true
end
if autoAdvance then
local advanced = placement.advancePointer(ctx)
if advanced then
return "BUILD", { reason = "continue", pointer = world.copyPosition(ctx.pointer) }
end
return "DONE", { reason = "complete" }
end
return "BUILD", { reason = "await_pointer_update" }
end
return placement]]
files["lib/lib_reporter.lua"] = [[local reporter = {}
local initialize = require("lib_initialize")
local movement = require("lib_movement")
local fuel = require("lib_fuel")
local inventory = require("lib_inventory")
local world = require("lib_world")
local schema_utils = require("lib_schema")
local string_utils = require("lib_string")
function reporter.describeFuel(io, report)
fuel.describeFuel(io, report)
end
function reporter.describeService(io, report)
fuel.describeService(io, report)
end
function reporter.describeMaterials(io, info)
inventory.describeMaterials(io, info)
end
function reporter.detectContainers(io)
world.detectContainers(io)
end
function reporter.runCheck(ctx, io, opts)
inventory.runCheck(ctx, io, opts)
end
function reporter.gatherSummary(io, report)
inventory.gatherSummary(io, report)
end
function reporter.describeTotals(io, totals)
inventory.describeTotals(io, totals)
end
function reporter.showHistory(io, entries)
if not io.print then
return
end
if not entries or #entries == 0 then
io.print("Captured history: <empty>")
return
end
io.print("Captured history:")
for _, entry in ipairs(entries) do
local label = entry.levelLabel or entry.level
local stamp = entry.timestamp and (entry.timestamp .. " ") or ""
local tag = entry.tag and (entry.tag .. " ") or ""
io.print(string.format(" - %s%s%s%s", stamp, tag, label, entry.message and (" " .. entry.message) or ""))
end
end
function reporter.describePosition(ctx)
return movement.describePosition(ctx)
end
function reporter.printMaterials(io, info)
schema_utils.printMaterials(io, info)
end
function reporter.printBounds(io, info)
schema_utils.printBounds(io, info)
end
function reporter.detailToString(value, depth)
return string_utils.detailToString(value, depth)
end
function reporter.computeManifest(list)
return inventory.computeManifest(list)
end
function reporter.printManifest(io, manifest)
inventory.printManifest(io, manifest)
end
return reporter]]
files["lib/lib_schema.lua"] = [[local schema_utils = {}
local table_utils = require("lib_table")
local function copyTable(tbl)
if type(tbl) ~= "table" then return {} end
return table_utils.shallowCopy(tbl)
end
function schema_utils.pushMaterialCount(counts, material)
counts[material] = (counts[material] or 0) + 1
end
function schema_utils.cloneMeta(meta)
return copyTable(meta)
end
function schema_utils.newBounds()
return {
min = { x = math.huge, y = math.huge, z = math.huge },
max = { x = -math.huge, y = -math.huge, z = -math.huge },
}
end
function schema_utils.updateBounds(bounds, x, y, z)
local minB = bounds.min
local maxB = bounds.max
if x < minB.x then minB.x = x end
if y < minB.y then minB.y = y end
if z < minB.z then minB.z = z end
if x > maxB.x then maxB.x = x end
if y > maxB.y then maxB.y = y end
if z > maxB.z then maxB.z = z end
end
function schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
return false, "invalid_coordinate"
end
if type(material) ~= "string" or material == "" then
return false, "invalid_material"
end
meta = schema_utils.cloneMeta(meta)
schema[x] = schema[x] or {}
local yLayer = schema[x]
yLayer[y] = yLayer[y] or {}
local zLayer = yLayer[y]
if zLayer[z] ~= nil then
return false, "duplicate_coordinate"
end
zLayer[z] = { material = material, meta = meta }
schema_utils.updateBounds(bounds, x, y, z)
schema_utils.pushMaterialCount(counts, material)
return true
end
function schema_utils.mergeLegend(base, override)
local result = {}
if type(base) == "table" then
for symbol, entry in pairs(base) do
result[symbol] = entry
end
end
if type(override) == "table" then
for symbol, entry in pairs(override) do
result[symbol] = entry
end
end
return result
end
function schema_utils.normaliseLegendEntry(symbol, entry)
if entry == nil then
return nil, "unknown_symbol"
end
if entry == false or entry == "" then
return false
end
if type(entry) == "string" then
return { material = entry, meta = {} }
end
if type(entry) == "table" then
if entry.material == nil and entry[1] then
entry = { material = entry[1], meta = entry[2] }
end
local material = entry.material
if material == nil or material == "" then
return false
end
local meta = entry.meta
if meta ~= nil and type(meta) ~= "table" then
return nil, "invalid_meta"
end
return { material = material, meta = meta or {} }
end
return nil, "invalid_legend_entry"
end
function schema_utils.resolveSymbol(symbol, legend, opts)
if symbol == "" then
return nil, "empty_symbol"
end
if legend == nil then
return nil, "missing_legend"
end
local entry = legend[symbol]
if entry == nil then
if symbol == "." or symbol == " " then
return false
end
if opts and opts.allowImplicitAir and symbol:match("^%p?$") then
return false
end
return nil, "unknown_symbol"
end
local normalised, err = schema_utils.normaliseLegendEntry(symbol, entry)
if err then
return nil, err
end
return normalised
end
function schema_utils.fetchSchemaEntry(schema, pos)
if type(schema) ~= "table" or type(pos) ~= "table" then
return nil, "missing_schema"
end
local xLayer = schema[pos.x] or schema[tostring(pos.x)]
if type(xLayer) ~= "table" then
return nil, "empty"
end
local yLayer = xLayer[pos.y] or xLayer[tostring(pos.y)]
if type(yLayer) ~= "table" then
return nil, "empty"
end
local block = yLayer[pos.z] or yLayer[tostring(pos.z)]
if block == nil then
return nil, "empty"
end
return block
end
function schema_utils.canonicalToGrid(schema, opts)
opts = opts or {}
local grid = {}
if type(schema) ~= "table" then
return grid
end
for x, xColumn in pairs(schema) do
if type(xColumn) == "table" then
for y, yColumn in pairs(xColumn) do
if type(yColumn) == "table" then
for z, block in pairs(yColumn) do
if block and type(block) == "table" then
local material = block.material
if material and material ~= "" then
local gx = tostring(x)
local gy = tostring(y)
local gz = tostring(z)
grid[gx] = grid[gx] or {}
grid[gx][gy] = grid[gx][gy] or {}
grid[gx][gy][gz] = {
material = material,
meta = copyTable(block.meta),
}
end
end
end
end
end
end
end
return grid
end
function schema_utils.canonicalToVoxelDefinition(schema, opts)
return { grid = schema_utils.canonicalToGrid(schema, opts) }
end
function schema_utils.printMaterials(io, info)
if not io.print then
return
end
if not info or not info.materials or #info.materials == 0 then
io.print("Materials: <none>")
return
end
io.print("Materials:")
for _, entry in ipairs(info.materials) do
io.print(string.format(" - %s x%d", entry.material, entry.count))
end
end
function schema_utils.printBounds(io, info)
if not io.print then
return
end
if not info or not info.bounds or not info.bounds.min then
io.print("Bounds: <unknown>")
return
end
local minB = info.bounds.min
local maxB = info.bounds.max
local dims = {
x = (maxB.x - minB.x) + 1,
y = (maxB.y - minB.y) + 1,
z = (maxB.z - minB.z) + 1,
}
io.print(string.format("Bounds: min(%d,%d,%d) max(%d,%d,%d) dims(%d,%d,%d)",
minB.x, minB.y, minB.z, maxB.x, maxB.y, maxB.z, dims.x, dims.y, dims.z))
end
return schema_utils]]
files["lib/lib_startup.lua"] = [[local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local movement = require("lib_movement")
local wizard = require("lib_wizard")
local startup = {}
function startup.runFuelCheck(ctx, chests, threshold, target)
threshold = threshold or 200
target = target or 1000
local current = turtle.getFuelLevel()
if current == "unlimited" then return true end
if type(current) ~= "number" then current = 0 end
if current < threshold then
logger.log(ctx, "warn", "Fuel low (" .. current .. "). Attempting refuel...")
fuelLib.refuel(ctx, { target = target })
current = turtle.getFuelLevel()
if current == "unlimited" then current = math.huge end
if type(current) ~= "number" then current = 0 end
if current < threshold then
if chests and chests.fuel then
logger.log(ctx, "info", "Going to fuel chest...")
movement.goTo(ctx, { x=0, y=0, z=0 })
movement.face(ctx, chests.fuel)
turtle.suck()
fuelLib.refuel(ctx, { target = target })
end
end
current = turtle.getFuelLevel()
if current == "unlimited" then current = math.huge end
if type(current) ~= "number" then current = 0 end
if current < threshold then
logger.log(ctx, "error", "Critical fuel shortage. Waiting.")
sleep(10)
return false
end
end
return true
end
function startup.runChestSetup(ctx)
local requirements = {
south = { type = "chest", name = "Output Chest" },
east = { type = "chest", name = "Trash Chest" },
west = { type = "chest", name = "Fuel Chest" }
}
wizard.runChestSetup(ctx, requirements)
local chests = {
output = "south",
trash = "east",
fuel = "west"
}
return chests
end
return startup]]
files["lib/lib_strategy_branchmine.lua"] = [[local strategy = {}
local function normalizePositiveInt(value, default)
local numberValue = tonumber(value)
if not numberValue or numberValue < 1 then
return default
end
return math.floor(numberValue)
end
local function pushStep(steps, x, y, z, facing, stepType, data)
steps[#steps + 1] = {
type = stepType,
x = x,
y = y,
z = z,
facing = facing,
data = data,
}
end
local function forward(x, z, facing)
if facing == 0 then
z = z + 1
elseif facing == 1 then
x = x + 1
elseif facing == 2 then
z = z - 1
else
x = x - 1
end
return x, z
end
local function turnLeft(facing)
return (facing + 3) % 4
end
local function turnRight(facing)
return (facing + 1) % 4
end
function strategy.generate(length, branchInterval, branchLength, torchInterval)
length = normalizePositiveInt(length, 60)
branchInterval = normalizePositiveInt(branchInterval, 3)
branchLength = normalizePositiveInt(branchLength, 16)
torchInterval = normalizePositiveInt(torchInterval, 6)
local steps = {}
local x, y, z = 0, 0, 0
local facing = 0 -- 0: forward, 1: right, 2: back, 3: left
pushStep(steps, x, y, z, facing, "place_chest")
for i = 1, length do
x, z = forward(x, z, facing)
pushStep(steps, x, y, z, facing, "move")
pushStep(steps, x, y, z, facing, "mine_neighbors")
if i % torchInterval == 0 then
pushStep(steps, x, y, z, facing, "place_torch")
end
if i % branchInterval == 0 then
facing = turnLeft(facing)
pushStep(steps, x, y, z, facing, "turn", "left")
for _ = 1, branchLength do
x, z = forward(x, z, facing)
pushStep(steps, x, y, z, facing, "move")
pushStep(steps, x, y, z, facing, "mine_neighbors")
end
y = y + 1
pushStep(steps, x, y, z, facing, "move")
pushStep(steps, x, y, z, facing, "mine_neighbors")
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
for _ = 1, branchLength do
x, z = forward(x, z, facing)
pushStep(steps, x, y, z, facing, "move")
pushStep(steps, x, y, z, facing, "mine_neighbors")
end
y = y - 1
pushStep(steps, x, y, z, facing, "move")
facing = turnLeft(facing)
pushStep(steps, x, y, z, facing, "turn", "left")
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
for _ = 1, branchLength do
x, z = forward(x, z, facing)
pushStep(steps, x, y, z, facing, "move")
pushStep(steps, x, y, z, facing, "mine_neighbors")
end
y = y + 1
pushStep(steps, x, y, z, facing, "move")
pushStep(steps, x, y, z, facing, "mine_neighbors")
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
for _ = 1, branchLength do
x, z = forward(x, z, facing)
pushStep(steps, x, y, z, facing, "move")
pushStep(steps, x, y, z, facing, "mine_neighbors")
end
y = y - 1
pushStep(steps, x, y, z, facing, "move")
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
end
if i % 5 == 0 then
pushStep(steps, x, y, z, facing, "dump_trash")
end
end
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
for _ = 1, length do
x, z = forward(x, z, facing)
pushStep(steps, x, y, z, facing, "move")
end
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
facing = turnRight(facing)
pushStep(steps, x, y, z, facing, "turn", "right")
pushStep(steps, x, y, z, facing, "done")
return steps
end
return strategy]]
files["lib/lib_strategy_excavate.lua"] = [[local strategy = {}
local function normalizePositiveInt(value, default)
local numberValue = tonumber(value)
if not numberValue or numberValue < 1 then
return default
end
return math.floor(numberValue)
end
local function pushStep(steps, x, y, z, facing, stepType, data)
steps[#steps + 1] = {
type = stepType,
x = x,
y = y,
z = z,
facing = facing,
data = data,
}
end
function strategy.generate(length, width, depth)
length = normalizePositiveInt(length, 8)
width = normalizePositiveInt(width, 8)
depth = normalizePositiveInt(depth, 3)
local steps = {}
local x, y, z = 0, 0, 0
local facing = 0 -- 0: forward (z+), 1: right (x+), 2: back (z-), 3: left (x-)
for d = 0, depth - 1 do
local currentY = -d
local zStart, zEnd, zStep
if d % 2 == 0 then
zStart, zEnd, zStep = 0, length - 1, 1
else
zStart, zEnd, zStep = length - 1, 0, -1
end
for z = zStart, zEnd, zStep do
local xStart, xEnd, xStep
if d == 0 and z == zStart then
x = 0
end
if x == 0 then
xStart, xEnd, xStep = 0, width - 1, 1
else
xStart, xEnd, xStep = width - 1, 0, -1
end
for ix = xStart, xEnd, xStep do
x = ix
pushStep(steps, x, currentY, z, 0, "move")
end
end
end
return steps
end
return strategy]]
files["lib/lib_strategy_farm.lua"] = [[local strategy = {}
local MATERIALS = {
dirt = "minecraft:dirt",
sand = "minecraft:sand",
water = "minecraft:water",
log = "minecraft:oak_log",
sapling = "minecraft:oak_sapling",
cane = "minecraft:sugar_cane",
potato = "minecraft:potatoes",
carrot = "minecraft:carrots",
wheat = "minecraft:wheat",
beetroot = "minecraft:beetroots",
nether_wart = "minecraft:nether_wart",
soul_sand = "minecraft:soul_sand",
farmland = "minecraft:farmland",
stone = "minecraft:stone_bricks", -- Border
torch = "minecraft:torch",
furnace = "minecraft:furnace",
chest = "minecraft:chest"
}
local function createBlock(mat)
return { material = mat }
end
function strategy.generate(farmType, width, length)
width = tonumber(width) or 9
length = tonumber(length) or 9
local schema = {}
local function set(x, y, z, mat)
schema[x] = schema[x] or {}
schema[x][y] = schema[x][y] or {}
schema[x][y][z] = createBlock(mat)
end
if farmType == "tree" then
for x = 0, width - 1 do
for z = 0, length - 1 do
set(x, 0, z, MATERIALS.dirt)
if x == 0 or x == width - 1 or z == 0 or z == length - 1 then
set(x, 0, z, MATERIALS.stone)
else
if x % 3 == 1 and z % 3 == 1 then
set(x, 1, z, MATERIALS.sapling)
elseif (x % 3 == 1 and z % 3 == 0) or (x % 3 == 0 and z % 3 == 1) then
elseif x % 5 == 0 and z % 5 == 0 then
set(x, 1, z, MATERIALS.torch)
end
end
end
end
set(0, 1, 1, MATERIALS.furnace)
set(0, 1, 2, MATERIALS.chest)
elseif farmType == "cane" then
for x = 0, width - 1 do
for z = 0, length - 1 do
if z == 0 or z == length - 1 then
set(x, 0, z, MATERIALS.stone)
else
local pattern = x % 3
if pattern == 0 then
set(x, 0, z, MATERIALS.water)
else
set(x, 0, z, MATERIALS.sand)
set(x, 1, z, MATERIALS.cane)
end
end
end
end
elseif farmType == "potato" or farmType == "carrot" or farmType == "wheat" or farmType == "beetroot" then
for x = 0, width - 1 do
for z = 0, length - 1 do
if z == 0 or z == length - 1 or x == 0 or x == width - 1 then
set(x, 0, z, MATERIALS.stone)
else
if x % 4 == 0 then
set(x, 0, z, MATERIALS.water)
else
set(x, 0, z, MATERIALS.dirt) -- Turtle will till this later or we place dirt
if farmType == "potato" then set(x, 1, z, MATERIALS.potato)
elseif farmType == "carrot" then set(x, 1, z, MATERIALS.carrot)
elseif farmType == "wheat" then set(x, 1, z, MATERIALS.wheat)
elseif farmType == "beetroot" then set(x, 1, z, MATERIALS.beetroot)
end
end
end
end
end
elseif farmType == "nether_wart" then
for x = 0, width - 1 do
for z = 0, length - 1 do
if z == 0 or z == length - 1 or x == 0 or x == width - 1 then
set(x, 0, z, MATERIALS.stone)
else
set(x, 0, z, MATERIALS.soul_sand)
set(x, 1, z, MATERIALS.nether_wart)
end
end
end
end
return schema
end
return strategy]]
files["lib/lib_strategy_tunnel.lua"] = [[local strategy = {}
local function normalizePositiveInt(value, default)
local numberValue = tonumber(value)
if not numberValue or numberValue < 1 then
return default
end
return math.floor(numberValue)
end
local function pushStep(steps, x, y, z, facing, stepType, data)
steps[#steps + 1] = {
type = stepType,
x = x,
y = y,
z = z,
facing = facing,
data = data,
}
end
local function forward(x, z, facing)
if facing == 0 then
z = z + 1
elseif facing == 1 then
x = x + 1
elseif facing == 2 then
z = z - 1
else
x = x - 1
end
return x, z
end
local function turnLeft(facing)
return (facing + 3) % 4
end
local function turnRight(facing)
return (facing + 1) % 4
end
function strategy.generate(length, width, height, torchInterval)
length = normalizePositiveInt(length, 16)
width = normalizePositiveInt(width, 1)
height = normalizePositiveInt(height, 2)
torchInterval = normalizePositiveInt(torchInterval, 6)
local steps = {}
local x, y, z = 0, 0, 0
local facing = 0 -- 0: forward (z+), 1: right (x+), 2: back (z-), 3: left (x-)
for l = 1, length do
end
local currentX, currentY, currentZ = 0, 0, 0
for d = 1, length do
local slicePoints = {}
for y = 0, height - 1 do
for x = 0, width - 1 do
table.insert(slicePoints, {x=x, y=y})
end
end
local yStart, yEnd, yStep
if d % 2 == 1 then
yStart, yEnd, yStep = 0, height - 1, 1
else
yStart, yEnd, yStep = height - 1, 0, -1
end
for y = yStart, yEnd, yStep do
local xStart, xEnd, xStep
if currentX == 0 then
xStart, xEnd, xStep = 0, width - 1, 1
else
xStart, xEnd, xStep = width - 1, 0, -1
end
for x = xStart, xEnd, xStep do
pushStep(steps, x, y, d, 0, "move")
currentX, currentY, currentZ = x, y, d
if y == 0 and x == math.floor((width-1)/2) and d % torchInterval == 0 then
pushStep(steps, x, y, d, 0, "place_torch")
end
end
end
end
return steps
end
return strategy]]
files["lib/lib_strategy.lua"] = [[local strategy_utils = {}
local world = require("lib_world")
function strategy_utils.ensurePointer(ctx)
if type(ctx.pointer) == "table" then
return ctx.pointer
end
local strategy = ctx.strategy
if type(strategy) == "table" and type(strategy.order) == "table" then
local idx = strategy.index or 1
local pos = strategy.order[idx]
if pos then
ctx.pointer = world.copyPosition(pos)
strategy.index = idx
return ctx.pointer
end
return nil, "strategy_exhausted"
end
return nil, "no_pointer"
end
function strategy_utils.advancePointer(ctx)
if type(ctx.strategy) == "table" then
local strategy = ctx.strategy
if type(strategy.advance) == "function" then
local nextPos, doneFlag = strategy.advance(strategy, ctx)
if nextPos then
ctx.pointer = world.copyPosition(nextPos)
return true
end
if doneFlag == false then
return false
end
ctx.pointer = nil
return false
end
if type(strategy.next) == "function" then
local nextPos = strategy.next(strategy, ctx)
if nextPos then
ctx.pointer = world.copyPosition(nextPos)
return true
end
ctx.pointer = nil
return false
end
if type(strategy.order) == "table" then
local idx = (strategy.index or 1) + 1
strategy.index = idx
local pos = strategy.order[idx]
if pos then
ctx.pointer = world.copyPosition(pos)
return true
end
ctx.pointer = nil
return false
end
elseif type(ctx.strategy) == "function" then
local nextPos = ctx.strategy(ctx)
if nextPos then
ctx.pointer = world.copyPosition(nextPos)
return true
end
ctx.pointer = nil
return false
end
ctx.pointer = nil
return false
end
return strategy_utils]]
files["lib/lib_string.lua"] = [[local string_utils = {}
function string_utils.trim(text)
if type(text) ~= "string" then
return text
end
return text:match("^%s*(.-)%s*$")
end
function string_utils.detailToString(value, depth)
depth = (depth or 0) + 1
if depth > 4 then
return "..."
end
if type(value) ~= "table" then
return tostring(value)
end
if textutils and textutils.serialize then
return textutils.serialize(value)
end
local parts = {}
for k, v in pairs(value) do
parts[#parts + 1] = tostring(k) .. "=" .. string_utils.detailToString(v, depth)
end
return "{" .. table.concat(parts, ", ") .. "}"
end
return string_utils]]
files["lib/lib_table.lua"] = [[local table_utils = {}
local function deepCopy(value)
if type(value) ~= "table" then
return value
end
local result = {}
for k, v in pairs(value) do
result[k] = deepCopy(v)
end
return result
end
table_utils.deepCopy = deepCopy
function table_utils.merge(base, overrides)
if type(base) ~= "table" and type(overrides) ~= "table" then
return overrides or base
end
local result = {}
if type(base) == "table" then
for k, v in pairs(base) do
result[k] = deepCopy(v)
end
end
if type(overrides) == "table" then
for k, v in pairs(overrides) do
if type(v) == "table" and type(result[k]) == "table" then
result[k] = table_utils.merge(result[k], v)
else
result[k] = deepCopy(v)
end
end
elseif overrides ~= nil then
return deepCopy(overrides)
end
return result
end
function table_utils.copyArray(source)
local result = {}
if type(source) ~= "table" then
return result
end
for i = 1, #source do
result[i] = source[i]
end
return result
end
function table_utils.sumValues(tbl)
local total = 0
if type(tbl) ~= "table" then
return total
end
for _, value in pairs(tbl) do
if type(value) == "number" then
total = total + value
end
end
return total
end
function table_utils.copyTotals(totals)
local result = {}
for material, count in pairs(totals or {}) do
result[material] = count
end
return result
end
function table_utils.mergeTotals(target, source)
for material, count in pairs(source or {}) do
target[material] = (target[material] or 0) + count
end
end
function table_utils.tableCount(tbl)
if type(tbl) ~= "table" then
return 0
end
local count = 0
for _ in pairs(tbl) do
count = count + 1
end
return count
end
function table_utils.copyArray(list)
if type(list) ~= "table" then
return {}
end
local result = {}
for index = 1, #list do
result[index] = list[index]
end
return result
end
function table_utils.copySummary(summary)
if type(summary) ~= "table" then
return {}
end
local result = {}
for key, value in pairs(summary) do
result[key] = value
end
return result
end
function table_utils.copySlots(slots)
if type(slots) ~= "table" then
return {}
end
local result = {}
for slot, info in pairs(slots) do
if type(info) == "table" then
result[slot] = {
slot = info.slot,
count = info.count,
name = info.name,
detail = info.detail,
}
else
result[slot] = info
end
end
return result
end
function table_utils.copyValue(value, seen)
if type(value) ~= "table" then
return value
end
seen = seen or {}
if seen[value] then
return seen[value]
end
local result = {}
seen[value] = result
for k, v in pairs(value) do
result[k] = table_utils.copyValue(v, seen)
end
return result
end
function table_utils.shallowCopy(tbl)
local result = {}
for k, v in pairs(tbl) do
result[k] = v
end
return result
end
return table_utils]]
files["lib/lib_ui.lua"] = [=[local ui = {}
local colors_bg = colors.blue
local colors_fg = colors.white
local colors_btn = colors.lightGray
local colors_btn_text = colors.black
local colors_input = colors.black
local colors_input_text = colors.white
function ui.clear()
term.setBackgroundColor(colors_bg)
term.setTextColor(colors_fg)
term.clear()
end
function ui.drawBox(x, y, w, h, bg, fg)
term.setBackgroundColor(bg)
term.setTextColor(fg)
for i = 0, h - 1 do
term.setCursorPos(x, y + i)
term.write(string.rep(" ", w))
end
end
function ui.drawFrame(x, y, w, h, title)
ui.drawBox(x, y, w, h, colors.gray, colors.white)
ui.drawBox(x + 1, y + 1, w - 2, h - 2, colors_bg, colors_fg)
term.setBackgroundColor(colors.black)
for i = 1, h do
term.setCursorPos(x + w, y + i)
term.write(" ")
end
for i = 1, w do
term.setCursorPos(x + i, y + h)
term.write(" ")
end
if title then
term.setCursorPos(x + 2, y + 1)
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.write(" " .. title .. " ")
end
end
function ui.button(x, y, text, active)
term.setCursorPos(x, y)
if active then
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
else
term.setBackgroundColor(colors_btn)
term.setTextColor(colors_btn_text)
end
term.write(" " .. text .. " ")
end
function ui.label(x, y, text)
term.setCursorPos(x, y)
term.setBackgroundColor(colors_bg)
term.setTextColor(colors_fg)
term.write(text)
end
function ui.inputText(x, y, width, value, active)
term.setCursorPos(x, y)
term.setBackgroundColor(colors_input)
term.setTextColor(colors_input_text)
local display = value or ""
if #display > width then
display = display:sub(-width)
end
term.write(display .. string.rep(" ", width - #display))
if active then
term.setCursorPos(x + #display, y)
term.setCursorBlink(true)
else
term.setCursorBlink(false)
end
end
function ui.drawPreview(schema, x, y, w, h)
local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
for sx, row in pairs(schema) do
local nx = tonumber(sx)
if nx then
if nx < minX then minX = nx end
if nx > maxX then maxX = nx end
for sy, col in pairs(row) do
for sz, block in pairs(col) do
local nz = tonumber(sz)
if nz then
if nz < minZ then minZ = nz end
if nz > maxZ then maxZ = nz end
end
end
end
end
end
if minX > maxX then return end -- Empty schema
local scaleX = w / (maxX - minX + 1)
local scaleZ = h / (maxZ - minZ + 1)
local scale = math.min(scaleX, scaleZ, 1) -- Keep aspect ratio, max 1:1
term.setBackgroundColor(colors.black)
for i = 0, h - 1 do
term.setCursorPos(x, y + i)
term.write(string.rep(" ", w))
end
for sx, row in pairs(schema) do
local nx = tonumber(sx)
if nx then
for sy, col in pairs(row) do
for sz, block in pairs(col) do
local nz = tonumber(sz)
if nz then
local scrX = math.floor((nx - minX) * scale) + x
local scrY = math.floor((nz - minZ) * scale) + y
if scrX >= x and scrX < x + w and scrY >= y and scrY < y + h then
term.setCursorPos(scrX, scrY)
local mat = block.material
local color = colors.gray
local char = " "
if mat:find("water") then color = colors.blue
elseif mat:find("log") then color = colors.brown
elseif mat:find("leaves") then color = colors.green
elseif mat:find("sapling") then color = colors.green; char = "T"
elseif mat:find("sand") then color = colors.yellow
elseif mat:find("dirt") then color = colors.brown
elseif mat:find("grass") then color = colors.green
elseif mat:find("stone") then color = colors.lightGray
elseif mat:find("cane") then color = colors.lime; char = "!"
elseif mat:find("potato") then color = colors.orange; char = "."
elseif mat:find("torch") then color = colors.orange; char = "i"
end
term.setBackgroundColor(color)
if color == colors.black then term.setTextColor(colors.white) else term.setTextColor(colors.black) end
term.write(char)
end
end
end
end
end
end
end
function ui.runForm(form)
local w, h = term.getSize()
local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
local running = true
local result = nil
local activeInput = nil
local focusableIndices = {}
for i, el in ipairs(form.elements) do
if el.type == "input" or el.type == "button" then
table.insert(focusableIndices, i)
end
end
local currentFocusIndex = 1
if #focusableIndices > 0 then
local el = form.elements[focusableIndices[currentFocusIndex]]
if el.type == "input" then activeInput = el end
end
while running do
ui.clear()
ui.drawFrame(fx, fy, fw, fh, form.title)
if form.onDraw then
form.onDraw(fx, fy, fw, fh)
end
for i, el in ipairs(form.elements) do
local ex, ey = fx + el.x, fy + el.y
local isFocused = false
if #focusableIndices > 0 and focusableIndices[currentFocusIndex] == i then
isFocused = true
end
if el.type == "button" then
ui.button(ex, ey, el.text, isFocused)
elseif el.type == "label" then
ui.label(ex, ey, el.text)
elseif el.type == "input" then
ui.inputText(ex, ey, el.width, el.value, activeInput == el or isFocused)
end
end
local event, p1, p2, p3 = os.pullEvent()
if event == "mouse_click" then
local btn, mx, my = p1, p2, p3
local clickedSomething = false
for i, el in ipairs(form.elements) do
local ex, ey = fx + el.x, fy + el.y
if el.type == "button" then
if my == ey and mx >= ex and mx < ex + #el.text + 2 then
ui.button(ex, ey, el.text, true) -- Flash
sleep(0.1)
if el.callback then
local res = el.callback(form)
if res then return res end
end
clickedSomething = true
for fi, idx in ipairs(focusableIndices) do
if idx == i then currentFocusIndex = fi; break end
end
activeInput = nil
end
elseif el.type == "input" then
if my == ey and mx >= ex and mx < ex + el.width then
activeInput = el
clickedSomething = true
for fi, idx in ipairs(focusableIndices) do
if idx == i then currentFocusIndex = fi; break end
end
end
end
end
if not clickedSomething then
activeInput = nil
end
elseif event == "char" and activeInput then
activeInput.value = (activeInput.value or "") .. p1
elseif event == "key" then
local key = p1
if key == keys.backspace and activeInput then
local val = activeInput.value or ""
if #val > 0 then
activeInput.value = val:sub(1, -2)
end
elseif key == keys.tab or key == keys.down then
if #focusableIndices > 0 then
currentFocusIndex = currentFocusIndex + 1
if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
local el = form.elements[focusableIndices[currentFocusIndex]]
activeInput = (el.type == "input") and el or nil
end
elseif key == keys.up then
if #focusableIndices > 0 then
currentFocusIndex = currentFocusIndex - 1
if currentFocusIndex < 1 then currentFocusIndex = #focusableIndices end
local el = form.elements[focusableIndices[currentFocusIndex]]
activeInput = (el.type == "input") and el or nil
end
elseif key == keys.enter then
if activeInput then
activeInput = nil
if #focusableIndices > 0 then
currentFocusIndex = currentFocusIndex + 1
if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
local el = form.elements[focusableIndices[currentFocusIndex]]
activeInput = (el.type == "input") and el or nil
end
else
if #focusableIndices > 0 then
local el = form.elements[focusableIndices[currentFocusIndex]]
if el.type == "button" then
ui.button(fx + el.x, fy + el.y, el.text, true) -- Flash
sleep(0.1)
if el.callback then
local res = el.callback(form)
if res then return res end
end
elseif el.type == "input" then
activeInput = el
end
end
end
end
end
end
end
function ui.runMenu(title, items)
local w, h = term.getSize()
local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
local scroll = 0
local maxVisible = fh - 4 -- Title + padding (top/bottom)
local selectedIndex = 1
while true do
ui.clear()
ui.drawFrame(fx, fy, fw, fh, title)
for i = 1, maxVisible do
local idx = i + scroll
if idx <= #items then
local item = items[idx]
local isSelected = (idx == selectedIndex)
ui.button(fx + 2, fy + 1 + i, item.text, isSelected)
end
end
if scroll > 0 then
ui.label(fx + fw - 2, fy + 2, "^")
end
if scroll + maxVisible < #items then
ui.label(fx + fw - 2, fy + fh - 2, "v")
end
local event, p1, p2, p3 = os.pullEvent()
if event == "mouse_click" then
local btn, mx, my = p1, p2, p3
for i = 1, maxVisible do
local idx = i + scroll
if idx <= #items then
local item = items[idx]
local bx, by = fx + 2, fy + 1 + i
if my == by and mx >= bx and mx < bx + #item.text + 2 then
ui.button(bx, by, item.text, true) -- Flash
sleep(0.1)
if item.callback then
local res = item.callback()
if res then return res end
end
selectedIndex = idx
end
end
end
elseif event == "mouse_scroll" then
local dir = p1
if dir > 0 then
if scroll + maxVisible < #items then scroll = scroll + 1 end
else
if scroll > 0 then scroll = scroll - 1 end
end
elseif event == "key" then
local key = p1
if key == keys.up then
if selectedIndex > 1 then
selectedIndex = selectedIndex - 1
if selectedIndex <= scroll then
scroll = selectedIndex - 1
end
end
elseif key == keys.down then
if selectedIndex < #items then
selectedIndex = selectedIndex + 1
if selectedIndex > scroll + maxVisible then
scroll = selectedIndex - maxVisible
end
end
elseif key == keys.enter then
local item = items[selectedIndex]
if item and item.callback then
ui.button(fx + 2, fy + 1 + (selectedIndex - scroll), item.text, true) -- Flash
sleep(0.1)
local res = item.callback()
if res then return res end
end
end
end
end
end
function ui.Form(title)
local self = {
title = title,
elements = {}
}
function self:addInput(id, label, value)
local y = 2 + (#self.elements * 2)
table.insert(self.elements, { type = "label", x = 2, y = y, text = label })
table.insert(self.elements, { type = "input", x = 15, y = y, width = 20, value = value, id = id })
end
function self:addButton(id, label, callback)
local y = 2 + (#self.elements * 2)
table.insert(self.elements, { type = "button", x = 2, y = y, text = label, id = id, callback = callback })
end
function self:run()
local y = 2 + (#self.elements * 2) + 2
table.insert(self.elements, {
type = "button", x = 2, y = y, text = "OK",
callback = function(form) return "ok" end
})
table.insert(self.elements, {
type = "button", x = 10, y = y, text = "Cancel",
callback = function(form) return "cancel" end
})
return ui.runForm(self)
end
return self
end
function ui.toBlit(color)
if colors.toBlit then return colors.toBlit(color) end
local exponent = math.log(color) / math.log(2)
return string.sub("0123456789abcdef", exponent + 1, exponent + 1)
end
return ui]=]
files["lib/lib_wizard.lua"] = [[local ui = require("lib_ui")
local movement = require("lib_movement")
local logger = require("lib_logger")
local wizard = {}
function wizard.runChestSetup(ctx, requirements)
while true do
ui.clear()
print("Setup Wizard")
print("============")
print("Please place the following chests:")
local w = requirements.west and "C" or " "
local e = requirements.east and "C" or " "
local n = requirements.north and "C" or " "
local s = requirements.south and "C" or " "
print(string.format("      %s", n))
print(string.format("   %s  T  %s", w, e))
print(string.format("      %s", s))
print("")
for dir, req in pairs(requirements) do
local label = dir:upper()
if dir == "north" then label = "FRONT (North)"
elseif dir == "south" then label = "BACK (South)"
elseif dir == "east" then label = "RIGHT (East)"
elseif dir == "west" then label = "LEFT (West)"
end
print(string.format("- %s: %s", label, req.name))
end
print("\nPress [Enter] to verify setup.")
read()
print("Aligning to NORTH (Front)...")
movement.faceDirection(ctx, "north")
local missing = {}
for dir, req in pairs(requirements) do
if not movement.faceDirection(ctx, dir) then
table.insert(missing, "Could not face " .. dir)
else
sleep(0.25)
local hasBlock, data = turtle.inspect()
if not hasBlock then
table.insert(missing, "Missing " .. req.name .. " at " .. dir .. " (Is turtle facing correctly?)")
elseif req.type == "chest" and not data.name:find("chest") and not data.name:find("barrel") then
table.insert(missing, "Incorrect block at " .. dir .. " (Found " .. data.name .. ") [Facing: " .. movement.getFacing(ctx) .. "]")
end
end
end
if #missing == 0 then
print("Setup verified!")
sleep(1)
return true
else
print("\nIssues found:")
for _, m in ipairs(missing) do
print("- " .. m)
end
print("\nOptions:")
print("  [Enter] Auto-align orientation (Recommended)")
print("  'r'     Retry manually")
print("  'skip'  Ignore errors")
local input = read()
if input == "skip" then return true end
if input ~= "r" then
print("Scanning surroundings to auto-align...")
local surroundings = {}
for i = 0, 3 do
local hasBlock, data = turtle.inspect()
if hasBlock and (data.name:find("chest") or data.name:find("barrel")) then
surroundings[i] = true
else
surroundings[i] = false
end
turtle.turnRight()
end
local CARDINALS = {"north", "east", "south", "west"}
local bestScore = -1
local bestFacing = nil
for i, candidate in ipairs(CARDINALS) do
local score = 0
for dir, req in pairs(requirements) do
if req.type == "chest" then
local dirIdx = -1
for k, v in ipairs(CARDINALS) do if v == dir then dirIdx = k break end end
local candIdx = i
if dirIdx ~= -1 then
local offset = (dirIdx - candIdx) % 4
if surroundings[offset] then
score = score + 1
end
end
end
end
if score > bestScore then
bestScore = score
bestFacing = candidate
end
end
if bestFacing and bestScore > 0 then
print("Auto-aligned to " .. bestFacing .. " (Score: " .. bestScore .. ")")
ctx.movement = ctx.movement or {}
ctx.movement.facing = bestFacing
ctx.origin = ctx.origin or {}
ctx.origin.facing = bestFacing
sleep(1)
else
print("Could not determine orientation.")
sleep(1)
end
end
end
end
end
return wizard]]
files["lib/lib_world.lua"] = [[local world = {}
function world.getInspect(side)
if side == "forward" then
return turtle.inspect
elseif side == "up" then
return turtle.inspectUp
elseif side == "down" then
return turtle.inspectDown
end
return nil
end
local SIDE_ALIASES = {
forward = "forward",
front = "forward",
down = "down",
bottom = "down",
up = "up",
top = "up",
left = "left",
right = "right",
back = "back",
behind = "back",
}
function world.normaliseSide(side)
if type(side) ~= "string" then
return nil
end
return SIDE_ALIASES[string.lower(side)]
end
function world.toPeripheralSide(side)
local normalised = world.normaliseSide(side) or side
if normalised == "forward" then
return "front"
elseif normalised == "up" then
return "top"
elseif normalised == "down" then
return "bottom"
elseif normalised == "back" then
return "back"
elseif normalised == "left" then
return "left"
elseif normalised == "right" then
return "right"
end
return normalised
end
function world.inspectSide(side)
local normalised = world.normaliseSide(side)
if normalised == "forward" then
return turtle and turtle.inspect and turtle.inspect()
elseif normalised == "up" then
return turtle and turtle.inspectUp and turtle.inspectUp()
elseif normalised == "down" then
return turtle and turtle.inspectDown and turtle.inspectDown()
end
return false
end
function world.isContainer(detail)
if type(detail) ~= "table" then
return false
end
local name = string.lower(detail.name or "")
if name:find("chest", 1, true) or name:find("barrel", 1, true) or name:find("drawer", 1, true) then
return true
end
if type(detail.tags) == "table" then
for tag in pairs(detail.tags) do
local lowered = string.lower(tag)
if lowered:find("inventory", 1, true) or lowered:find("chest", 1, true) or lowered:find("barrel", 1, true) then
return true
end
end
end
return false
end
function world.normalizeSide(value)
if type(value) ~= "string" then
return nil
end
local lower = value:lower()
if lower == "forward" or lower == "front" or lower == "fwd" then
return "forward"
end
if lower == "up" or lower == "top" or lower == "above" then
return "up"
end
if lower == "down" or lower == "bottom" or lower == "below" then
return "down"
end
return nil
end
function world.resolveSide(ctx, opts)
if type(opts) == "string" then
local direct = world.normalizeSide(opts)
return direct or "forward"
end
local candidate
if type(opts) == "table" then
candidate = opts.side or opts.direction or opts.facing or opts.containerSide or opts.defaultSide
if not candidate and type(opts.location) == "string" then
candidate = opts.location
end
end
if not candidate and type(ctx) == "table" then
local cfg = ctx.config
if type(cfg) == "table" then
candidate = cfg.inventorySide or cfg.materialSide or cfg.supplySide or cfg.defaultInventorySide
end
if not candidate and type(ctx.inventoryState) == "table" then
candidate = ctx.inventoryState.defaultSide
end
end
local normalised = world.normalizeSide(candidate)
if normalised then
return normalised
end
return "forward"
end
function world.isContainerBlock(name, tags)
if type(name) ~= "string" then
return false
end
local lower = name:lower()
for _, keyword in ipairs(CONTAINER_KEYWORDS) do
if lower:find(keyword, 1, true) then
return true
end
end
return world.hasContainerTag(tags)
end
function world.inspectForwardForContainer()
if not turtle or type(turtle.inspect) ~= "function" then
return false
end
local ok, data = turtle.inspect()
if not ok or type(data) ~= "table" then
return false
end
if world.isContainerBlock(data.name, data.tags) then
return true, data
end
return false
end
function world.inspectUpForContainer()
if not turtle or type(turtle.inspectUp) ~= "function" then
return false
end
local ok, data = turtle.inspectUp()
if not ok or type(data) ~= "table" then
return false
end
if world.isContainerBlock(data.name, data.tags) then
return true, data
end
return false
end
function world.inspectDownForContainer()
if not turtle or type(turtle.inspectDown) ~= "function" then
return false
end
local ok, data = turtle.inspectDown()
if not ok or type(data) ~= "table" then
return false
end
if world.isContainerBlock(data.name, data.tags) then
return true, data
end
return false
end
function world.peripheralSideForDirection(side)
if side == "forward" or side == "front" then
return "front"
end
if side == "up" or side == "top" then
return "top"
end
if side == "down" or side == "bottom" then
return "bottom"
end
return side
end
function world.computePrimaryPushDirection(ctx, periphSide)
if periphSide == "front" then
local facing = movement.getFacing(ctx)
if facing then
return OPPOSITE_FACING[facing]
end
elseif periphSide == "top" then
return "down"
elseif periphSide == "bottom" then
return "up"
end
return nil
end
function world.normaliseCoordinate(value)
local number = tonumber(value)
if number == nil then
return nil
end
if number >= 0 then
return math.floor(number + 0.5)
end
return math.ceil(number - 0.5)
end
function world.normalisePosition(pos)
if type(pos) ~= "table" then
return nil, "invalid_position"
end
local xRaw = pos.x
if xRaw == nil then
xRaw = pos[1]
end
local yRaw = pos.y
if yRaw == nil then
yRaw = pos[2]
end
local zRaw = pos.z
if zRaw == nil then
zRaw = pos[3]
end
local x = world.normaliseCoordinate(xRaw)
local y = world.normaliseCoordinate(yRaw)
local z = world.normaliseCoordinate(zRaw)
if not x or not y or not z then
return nil, "invalid_position"
end
return { x = x, y = y, z = z }
end
function world.normaliseFacing(facing)
facing = type(facing) == "string" and facing:lower() or "north"
if facing ~= "north" and facing ~= "east" and facing ~= "south" and facing ~= "west" then
return "north"
end
return facing
end
function world.facingVectors(facing)
facing = world.normaliseFacing(facing)
if facing == "north" then
return { forward = { x = 0, z = -1 }, right = { x = 1, z = 0 } }
elseif facing == "east" then
return { forward = { x = 1, z = 0 }, right = { x = 0, z = 1 } }
elseif facing == "south" then
return { forward = { x = 0, z = 1 }, right = { x = -1, z = 0 } }
else -- west
return { forward = { x = -1, z = 0 }, right = { x = 0, z = -1 } }
end
end
function world.rotateLocalOffset(localOffset, facing)
local vectors = world.facingVectors(facing)
local dx = localOffset.x or 0
local dz = localOffset.z or 0
local right = vectors.right
local forward = vectors.forward
return {
x = (right.x * dx) + (forward.x * dz),
z = (right.z * dx) + (forward.z * dz),
}
end
function world.localToWorld(localOffset, facing)
facing = world.normaliseFacing(facing)
local dx = localOffset and localOffset.x or 0
local dz = localOffset and localOffset.z or 0
local rotated = world.rotateLocalOffset({ x = dx, z = dz }, facing)
return {
x = rotated.x,
y = localOffset and localOffset.y or 0,
z = rotated.z,
}
end
function world.localToWorldRelative(origin, localPos)
local rotated = world.localToWorld(localPos, origin.facing)
return {
x = origin.x + rotated.x,
y = origin.y + rotated.y,
z = origin.z + rotated.z
}
end
function world.copyPosition(pos)
if type(pos) ~= "table" then
return nil
end
return {
x = pos.x or 0,
y = pos.y or 0,
z = pos.z or 0,
}
end
function world.detectContainers(io)
local found = {}
local sides = { "forward", "down", "up" }
local labels = {
forward = "front",
down = "below",
up = "above",
}
for _, side in ipairs(sides) do
local inspect
if side == "forward" then
inspect = turtle.inspect
elseif side == "up" then
inspect = turtle.inspectUp
else
inspect = turtle.inspectDown
end
if type(inspect) == "function" then
local ok, detail = inspect()
if ok then
local name = type(detail.name) == "string" and detail.name or "unknown"
found[#found + 1] = string.format(" %s: %s", labels[side] or side, name)
end
end
end
if io.print then
if #found == 0 then
io.print("Detected containers: <none>")
else
io.print("Detected containers:")
for _, line in ipairs(found) do
io.print(" -" .. line)
end
end
end
end
return world]]
files["lib/lib_worldstate.lua"] = [[local movement = require("lib_movement")
local worldstate = {}
local CARDINALS = { "north", "east", "south", "west" }
local CARDINAL_INDEX = {
north = 1,
east = 2,
south = 3,
west = 4,
}
local MOVE_OPTS_CLEAR = { dig = true, attack = true }
local MOVE_OPTS_SOFT = { dig = false, attack = false }
local MOVE_AXIS_FALLBACK = { "z", "x", "y" }
local function cloneTable(source)
if type(source) ~= "table" then
return nil
end
local copy = {}
for key, value in pairs(source) do
if type(value) == "table" then
copy[key] = cloneTable(value)
else
copy[key] = value
end
end
return copy
end
local function canonicalFacing(name)
if type(name) ~= "string" then
return nil
end
local normalized = name:lower()
if CARDINAL_INDEX[normalized] then
return normalized
end
return nil
end
local function rotateFacing(facing, steps)
local canonical = canonicalFacing(facing)
if not canonical then
return facing
end
local index = CARDINAL_INDEX[canonical]
local count = #CARDINALS
local rotated = ((index - 1 + steps) % count) + 1
return CARDINALS[rotated]
end
local function rotate2D(x, z, steps)
local normalized = steps % 4
if normalized < 0 then
normalized = normalized + 4
end
if normalized == 0 then
return x, z
elseif normalized == 1 then
return -z, x
elseif normalized == 2 then
return -x, -z
else
return z, -x
end
end
local function mergeTables(target, source)
if type(target) ~= "table" or type(source) ~= "table" then
return target
end
for key, value in pairs(source) do
if type(value) == "table" then
target[key] = target[key] or {}
mergeTables(target[key], value)
else
target[key] = value
end
end
return target
end
local function ensureWorld(ctx)
ctx.world = ctx.world or {}
local world = ctx.world
world.origin = world.origin or cloneTable(ctx.origin) or { x = 0, y = 0, z = 0 }
ctx.origin = ctx.origin or cloneTable(world.origin)
world.frame = world.frame or {}
world.grid = world.grid or {}
world.walkway = world.walkway or {}
world.traversal = world.traversal or {}
world.bounds = world.bounds or {}
return world
end
function worldstate.buildReferenceFrame(ctx, opts)
local world = ensureWorld(ctx)
opts = opts or {}
local desired = canonicalFacing(opts.homeFacing)
or canonicalFacing(opts.initialFacing)
or canonicalFacing(ctx.config and (ctx.config.homeFacing or ctx.config.initialFacing))
or canonicalFacing(world.frame.homeFacing)
or "east"
local baseline = canonicalFacing(opts.referenceFacing) or "east"
local desiredIndex = CARDINAL_INDEX[desired]
local baselineIndex = CARDINAL_INDEX[baseline]
local rotationSteps = ((desiredIndex - baselineIndex) % 4)
world.frame.rotationSteps = rotationSteps
world.frame.homeFacing = desired
world.frame.referenceFacing = baseline
return world.frame
end
function worldstate.referenceToWorld(ctx, refPos)
if not refPos then
return nil
end
local world = ensureWorld(ctx)
local rotationSteps = world.frame.rotationSteps or 0
local x = refPos.x or 0
local z = refPos.z or 0
local rotatedX, rotatedZ = rotate2D(x, z, rotationSteps)
return {
x = (world.origin.x or 0) + rotatedX,
y = (world.origin.y or 0) + (refPos.y or 0),
z = (world.origin.z or 0) + rotatedZ,
}
end
function worldstate.worldToReference(ctx, worldPos)
if not worldPos then
return nil
end
local world = ensureWorld(ctx)
local rotationSteps = world.frame.rotationSteps or 0
local dx = (worldPos.x or 0) - (world.origin.x or 0)
local dz = (worldPos.z or 0) - (world.origin.z or 0)
local refX, refZ = rotate2D(dx, dz, -rotationSteps)
return {
x = refX,
y = (worldPos.y or 0) - (world.origin.y or 0),
z = refZ,
}
end
function worldstate.resolveFacing(ctx, facing)
local world = ensureWorld(ctx)
local rotationSteps = world.frame.rotationSteps or 0
return rotateFacing(facing, rotationSteps)
end
local function mergeMoveOpts(baseOpts, extraOpts)
if not extraOpts then
if not baseOpts then
return nil
end
return cloneTable(baseOpts)
end
local merged = {}
if baseOpts then
for key, value in pairs(baseOpts) do
merged[key] = value
end
end
for key, value in pairs(extraOpts) do
merged[key] = value
end
return merged
end
local function goToWithFallback(ctx, position, moveOpts)
local ok, err = movement.goTo(ctx, position, moveOpts)
if ok or (moveOpts and moveOpts.axisOrder) then
return ok, err
end
local fallbackOpts = mergeMoveOpts(moveOpts, { axisOrder = MOVE_AXIS_FALLBACK })
return movement.goTo(ctx, position, fallbackOpts)
end
function worldstate.goToReference(ctx, refPos, moveOpts)
if not refPos then
return false, "invalid_reference_position"
end
local worldPos = worldstate.referenceToWorld(ctx, refPos)
return goToWithFallback(ctx, worldPos, moveOpts)
end
function worldstate.goAndFaceReference(ctx, refPos, facing, moveOpts)
if not refPos then
return false, "invalid_reference_position"
end
local ok, err = worldstate.goToReference(ctx, refPos, moveOpts)
if not ok then
return false, err
end
if facing then
return movement.faceDirection(ctx, worldstate.resolveFacing(ctx, facing))
end
return true
end
function worldstate.returnHome(ctx, moveOpts)
local world = ensureWorld(ctx)
local opts = moveOpts or MOVE_OPTS_SOFT
local ok, err = goToWithFallback(ctx, world.origin, opts)
if not ok then
return false, err
end
local facing = world.frame.homeFacing or ctx.config and (ctx.config.homeFacing or ctx.config.initialFacing) or "east"
ok, err = movement.faceDirection(ctx, facing)
if not ok then
return false, err
end
return true
end
function worldstate.configureNoDigBounds(ctx, bounds)
local world = ensureWorld(ctx)
world.bounds.noDig = cloneTable(bounds)
return world.bounds.noDig
end
local function positionWithinBounds(pos, bounds)
if not pos or not bounds then
return false
end
local x, z = pos.x or 0, pos.z or 0
if bounds.minX and x < bounds.minX then
return false
end
if bounds.maxX and x > bounds.maxX then
return false
end
if bounds.minZ and z < bounds.minZ then
return false
end
if bounds.maxZ and z > bounds.maxZ then
return false
end
return true
end
function worldstate.moveOptsForPosition(ctx, position)
local world = ensureWorld(ctx)
local bounds = world.bounds.noDig
if not bounds then
return MOVE_OPTS_CLEAR
end
local ref = worldstate.worldToReference(ctx, position) or position
if positionWithinBounds(ref, bounds) then
return MOVE_OPTS_SOFT
end
return MOVE_OPTS_CLEAR
end
local function isColumnX(grid, testX)
if not grid or not grid.origin then
return false
end
local spacing = grid.spacingX or 1
local width = grid.width or 0
local baseX = grid.origin.x or 0
for offset = 0, math.max(width - 1, 0) do
local columnX = baseX + offset * spacing
if columnX == testX then
return true
end
end
return false
end
local function insertUnique(list, value)
if not list or value == nil then
return
end
for _, entry in ipairs(list) do
if entry == value then
return
end
end
table.insert(list, value)
end
function worldstate.configureGrid(ctx, cfg)
local world = ensureWorld(ctx)
cfg = cfg or {}
world.grid.width = cfg.width or world.grid.width or ctx.config and ctx.config.gridWidth or 1
world.grid.length = cfg.length or world.grid.length or ctx.config and ctx.config.gridLength or 1
world.grid.spacingX = cfg.spacingX or cfg.spacing or world.grid.spacingX or ctx.config and (ctx.config.treeSpacingX or ctx.config.treeSpacing) or 1
world.grid.spacingZ = cfg.spacingZ or cfg.spacing or world.grid.spacingZ or ctx.config and (ctx.config.treeSpacingZ or ctx.config.treeSpacing) or 1
world.grid.origin = cloneTable(cfg.origin) or world.grid.origin or cloneTable(ctx.fieldOrigin) or { x = 0, y = 0, z = 0 }
ctx.fieldOrigin = cloneTable(world.grid.origin)
return world.grid
end
function worldstate.configureWalkway(ctx, cfg)
local world = ensureWorld(ctx)
cfg = cfg or {}
local walkway = world.walkway
walkway.offset = cfg.offset
or walkway.offset
or ctx.config and (ctx.config.walkwayOffsetX)
or -world.grid.spacingX
walkway.candidates = cloneTable(cfg.candidates) or walkway.candidates or {}
if #walkway.candidates == 0 then
insertUnique(walkway.candidates, world.grid.origin.x + (walkway.offset or -1))
insertUnique(walkway.candidates, world.grid.origin.x)
insertUnique(walkway.candidates, ctx.origin and ctx.origin.x)
end
worldstate.ensureWalkwayAvailability(ctx)
return walkway
end
function worldstate.ensureWalkwayAvailability(ctx)
local world = ensureWorld(ctx)
local walkway = world.walkway
walkway.candidates = walkway.candidates or {}
local safe, selected = {}, walkway.selected
for _, candidate in ipairs(walkway.candidates) do
if candidate ~= nil and not isColumnX(world.grid, candidate) then
insertUnique(safe, candidate)
selected = selected or candidate
end
end
if not selected then
local spacing = world.grid.spacingX or 1
local maxX = (world.grid.origin.x or 0) + math.max((world.grid.width or 1) - 1, 0) * spacing
selected = maxX + spacing
insertUnique(safe, selected)
end
walkway.candidates = safe
walkway.selected = selected
ctx.walkwayEntranceX = selected
return selected
end
local function moveToAvailableWalkway(ctx, yLevel, targetZ)
local world = ensureWorld(ctx)
local walkway = world.walkway
local candidates = walkway.candidates or { walkway.selected }
local lastErr
for _, safeX in ipairs(candidates) do
if safeX then
local currentWorld = movement.getPosition(ctx)
local currentRef = worldstate.worldToReference(ctx, currentWorld) or { x = 0, y = 0, z = 0 }
local stageOne = { x = safeX, y = yLevel, z = currentRef.z }
local ok, err = worldstate.goToReference(ctx, stageOne, MOVE_OPTS_SOFT)
if not ok then
lastErr = err
goto next_candidate
end
local stageTwo = { x = safeX, y = yLevel, z = targetZ }
ok, err = worldstate.goToReference(ctx, stageTwo, MOVE_OPTS_SOFT)
if not ok then
lastErr = err
goto next_candidate
end
walkway.selected = safeX
ctx.walkwayEntranceX = safeX
return true
end
::next_candidate::
end
return false, lastErr or "walkway_blocked"
end
function worldstate.moveAlongWalkway(ctx, targetRef)
if not ctx or not targetRef then
return false, "invalid_target"
end
local world = ensureWorld(ctx)
local currentWorld = movement.getPosition(ctx)
local currentRef = worldstate.worldToReference(ctx, currentWorld) or { x = 0, y = 0, z = 0 }
local yLevel = targetRef.y or world.grid.origin.y or 0
if currentRef.z ~= targetRef.z then
local ok, err = moveToAvailableWalkway(ctx, yLevel, targetRef.z)
if not ok then
return false, err
end
currentRef = { x = world.walkway.selected or currentRef.x, y = yLevel, z = targetRef.z }
end
if currentRef.x ~= targetRef.x then
local ok, err = worldstate.goToReference(ctx, { x = targetRef.x, y = yLevel, z = targetRef.z }, MOVE_OPTS_SOFT)
if not ok then
return false, err
end
end
return true
end
function worldstate.resetTraversal(ctx, overrides)
local world = ensureWorld(ctx)
world.traversal = {
row = 1,
col = 1,
forward = true,
done = false,
}
if type(overrides) == "table" then
mergeTables(world.traversal, overrides)
end
ctx.traverse = world.traversal
return world.traversal
end
function worldstate.advanceTraversal(ctx)
local world = ensureWorld(ctx)
local tr = world.traversal
if not tr then
tr = worldstate.resetTraversal(ctx)
end
if tr.done then
return tr
end
if tr.forward then
if tr.col < (world.grid.width or 1) then
tr.col = tr.col + 1
return tr
end
tr.forward = false
else
if tr.col > 1 then
tr.col = tr.col - 1
return tr
end
tr.forward = true
end
tr.row = tr.row + 1
if tr.row > (world.grid.length or 1) then
tr.done = true
else
tr.col = tr.forward and 1 or (world.grid.width or 1)
end
return tr
end
function worldstate.currentCellRef(ctx)
local world = ensureWorld(ctx)
local tr = world.traversal or worldstate.resetTraversal(ctx)
return {
x = (world.grid.origin.x or 0) + (tr.col - 1) * (world.grid.spacingX or 1),
y = world.grid.origin.y or 0,
z = (world.grid.origin.z or 0) + (tr.row - 1) * (world.grid.spacingZ or 1),
}
end
function worldstate.currentCellWorld(ctx)
return worldstate.referenceToWorld(ctx, worldstate.currentCellRef(ctx))
end
function worldstate.offsetFromCell(ctx, offset)
offset = offset or {}
local base = worldstate.currentCellRef(ctx)
return {
x = base.x + (offset.x or 0),
y = base.y + (offset.y or 0),
z = base.z + (offset.z or 0),
}
end
function worldstate.currentWalkPositionRef(ctx)
local world = ensureWorld(ctx)
local ref = worldstate.currentCellRef(ctx)
return {
x = (ref.x or 0) + (world.walkway.offset or -1),
y = ref.y,
z = ref.z,
}
end
function worldstate.currentWalkPositionWorld(ctx)
return worldstate.referenceToWorld(ctx, worldstate.currentWalkPositionRef(ctx))
end
function worldstate.ensureTraversal(ctx)
local world = ensureWorld(ctx)
if not world.traversal then
worldstate.resetTraversal(ctx)
end
return world.traversal
end
worldstate.MOVE_OPTS_CLEAR = MOVE_OPTS_CLEAR
worldstate.MOVE_OPTS_SOFT = MOVE_OPTS_SOFT
return worldstate]]
files["lib/log.lua"] = [[local Log = {}
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
function Log:log(level, message)
local numeric = LEVELS[level] or LEVELS.info
if numeric > self.threshold then return end
local safeMessage = tostring(message)
local line = string.format("[%s] %-5s %s", now(), level:upper(), safeMessage)
local success, err = tryWrite(self.logFile, line)
if not success and term then
term.setTextColor(colors.red)
print("Log write failed: " .. tostring(err))
term.setTextColor(colors.white)
end
end
function Log:error(message) self:log("error", message) end
function Log:warn(message) self:log("warn", message) end
function Log:info(message) self:log("info", message) end
function Log:debug(message) self:log("debug", message) end
return Log]]
files["lib/version.lua"] = [[local version = {}
version.MAJOR = 2
version.MINOR = 1
version.PATCH = 1
version.BUILD = 40
function version.toString()
return string.format("v%d.%d.%d (build %d)",
version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end
function version.display()
return string.format("TurtleOS v%d.%d.%d #%d",
version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end
return version]]
files["net_installer.lua"] = [[local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/"
local files = {
"arcade/arcade_shell.lua",
"arcade/arcade.lua",
"arcade/arcadeos.lua",
"arcade/data/programs.lua",
"arcade/data/valhelsia_blocks.lua",
"arcade/games/cantstop.lua",
"arcade/games/idlecraft.lua",
"arcade/games/slots.lua",
"arcade/games/themes.lua",
"arcade/license_store.lua",
"arcade/store.lua",
"arcade/ui/renderer.lua",
"factory/factory.lua",
"factory/harness_common.lua",
"factory/harness_fuel.lua",
"factory/harness_initialize.lua",
"factory/harness_inventory.lua",
"factory/harness_logger.lua",
"factory/harness_movement.lua",
"factory/harness_navigation_steps.lua",
"factory/harness_navigation.lua",
"factory/harness_parser_data.lua",
"factory/harness_parser.lua",
"factory/harness_placement_data.lua",
"factory/harness_placement.lua",
"factory/harness_worldstate.lua",
"factory/main.lua",
"factory/state_blocked.lua",
"factory/state_build.lua",
"factory/state_check_requirements.lua",
"factory/state_done.lua",
"factory/state_error.lua",
"factory/state_initialize.lua",
"factory/state_mine.lua",
"factory/state_refuel.lua",
"factory/state_restock.lua",
"factory/state_treefarm.lua",
"factory/turtle_os.lua",
"games/arcade.lua",
"installer.lua",
"lib/lib_designer.lua",
"lib/lib_diagnostics.lua",
"lib/lib_fs.lua",
"lib/lib_fuel.lua",
"lib/lib_games.lua",
"lib/lib_gps.lua",
"lib/lib_initialize.lua",
"lib/lib_inventory_utils.lua",
"lib/lib_inventory.lua",
"lib/lib_items.lua",
"lib/lib_json.lua",
"lib/lib_logger.lua",
"lib/lib_mining.lua",
"lib/lib_movement.lua",
"lib/lib_navigation.lua",
"lib/lib_orientation.lua",
"lib/lib_parser.lua",
"lib/lib_placement.lua",
"lib/lib_reporter.lua",
"lib/lib_schema.lua",
"lib/lib_strategy_branchmine.lua",
"lib/lib_strategy_excavate.lua",
"lib/lib_strategy_farm.lua",
"lib/lib_strategy_tunnel.lua",
"lib/lib_strategy.lua",
"lib/lib_string.lua",
"lib/lib_table.lua",
"lib/lib_ui.lua",
"lib/lib_world.lua",
"lib/lib_worldstate.lua",
"lib/log.lua",
"startup.lua",
}
print("Starting Network Install...")
print("Source: " .. BASE_URL)
local function download(path)
local url = BASE_URL .. path
print("Downloading " .. path .. "...")
local response = http.get(url)
if not response then
printError("Failed to download " .. path)
return false
end
local content = response.readAll()
response.close()
local dir = fs.getDir(path)
if dir ~= "" and not fs.exists(dir) then
fs.makeDir(dir)
end
local file = fs.open(path, "w")
if not file then
printError("Failed to write " .. path)
return false
end
file.write(content)
file.close()
return true
end
local successCount = 0
local failCount = 0
for _, file in ipairs(files) do
if download(file) then
successCount = successCount + 1
else
failCount = failCount + 1
end
sleep(0.1)
end
print("")
print("Install Complete!")
print("Downloaded: " .. successCount)
print("Failed: " .. failCount)
print("Verifying installation...")
local errors = 0
for _, file in ipairs(files) do
if not fs.exists(file) then
printError("Missing: " .. file)
errors = errors + 1
end
end
if failCount == 0 and errors == 0 then
print("Verification successful.")
print("Reboot or run startup to launch.")
else
print("Installation issues detected.")
if failCount > 0 then print("Failed downloads: " .. failCount) end
if errors > 0 then print("Missing files: " .. errors) end
end]]
files["startup.lua"] = [[local platform = turtle and "turtle" or "computer"
package.path = package.path .. ";/?.lua;/lib/?.lua;/arcade/?.lua;/factory/?.lua"
if platform == "turtle" then
local factory_main = "/factory/main.lua"
if fs.exists(factory_main) then
shell.run(factory_main)
else
print("Factory Main not found at " .. factory_main)
end
else
local arcade_shell = "/arcade/arcade_shell.lua"
if fs.exists(arcade_shell) then
shell.run(arcade_shell)
else
print("Arcade Shell not found at " .. arcade_shell)
end
end]]
files["ui/trash_config.lua"] = [[local ui = require("lib_ui")
local mining = require("lib_mining")
local valhelsia_blocks = require("arcade.data.valhelsia_blocks")
local trash_config = {}
function trash_config.run()
local searchTerm = ""
local scroll = 0
local selectedIndex = 1
local filteredBlocks = {}
local function updateFilter()
filteredBlocks = {}
for _, block in ipairs(valhelsia_blocks) do
if searchTerm == "" or
block.label:lower():find(searchTerm:lower()) or
block.id:lower():find(searchTerm:lower()) then
table.insert(filteredBlocks, block)
end
end
end
updateFilter()
while true do
ui.clear()
ui.drawFrame(2, 2, 48, 16, "Trash Configuration")
ui.label(4, 4, "Search: ")
ui.inputText(12, 4, 30, searchTerm, true)
ui.label(4, 6, "Name")
ui.label(35, 6, "Trash?")
ui.drawBox(4, 7, 44, 1, colors.gray, colors.white)
local listHeight = 8
local maxScroll = math.max(0, #filteredBlocks - listHeight)
if scroll > maxScroll then scroll = maxScroll end
for i = 1, listHeight do
local idx = i + scroll
if idx <= #filteredBlocks then
local block = filteredBlocks[idx]
local y = 7 + i
local isTrash = mining.TRASH_BLOCKS[block.id]
local trashLabel = isTrash and "[YES]" or "[NO ]"
local trashColor = isTrash and colors.red or colors.green
if i == selectedIndex then
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
else
term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
end
term.setCursorPos(4, y)
local label = block.label
if #label > 30 then label = label:sub(1, 27) .. "..." end
term.write(label .. string.rep(" ", 31 - #label))
term.setCursorPos(35, y)
if i == selectedIndex then
term.setTextColor(colors.black)
else
term.setTextColor(trashColor)
end
term.write(trashLabel)
end
end
ui.label(4, 17, "Arrows: Move/Scroll  Enter: Toggle  Esc: Save")
local event, p1 = os.pullEvent()
if event == "char" then
searchTerm = searchTerm .. p1
updateFilter()
selectedIndex = 1
scroll = 0
elseif event == "key" then
if p1 == keys.backspace then
searchTerm = searchTerm:sub(1, -2)
updateFilter()
selectedIndex = 1
scroll = 0
elseif p1 == keys.up then
if selectedIndex > 1 then
selectedIndex = selectedIndex - 1
elseif scroll > 0 then
scroll = scroll - 1
end
elseif p1 == keys.down then
if selectedIndex < math.min(listHeight, #filteredBlocks) then
selectedIndex = selectedIndex + 1
elseif scroll < maxScroll then
scroll = scroll + 1
end
elseif p1 == keys.enter then
local idx = selectedIndex + scroll
if filteredBlocks[idx] then
local block = filteredBlocks[idx]
if mining.TRASH_BLOCKS[block.id] then
mining.TRASH_BLOCKS[block.id] = nil -- Remove from trash
else
mining.TRASH_BLOCKS[block.id] = true -- Add to trash
end
end
elseif p1 == keys.enter or p1 == keys.escape then
mining.saveConfig()
return
end
end
end
end
return trash_config]]

print("Cleaning old installation...")
if fs.exists("arcade") then fs.delete("arcade") end
if fs.exists("lib") then fs.delete("lib") end
if fs.exists("factory") then fs.delete("factory") end

print("Unpacking 70 files...")
for path, content in pairs(files) do
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local handle = fs.open(path, "w")
    if not handle then
        printError("Failed to write " .. path)
    else
        handle.write(content)
        handle.close()
    end
end

print("Verifying installation...")
local errors = 0
for path, _ in pairs(files) do
    if not fs.exists(path) then
        printError("Missing: " .. path)
        errors = errors + 1
    end
end
if errors == 0 then
    print("Verification successful.")
    print("Arcadesys install complete. Reboot or run startup to launch.")
else
    printError("Verification failed with " .. errors .. " missing files.")
end
