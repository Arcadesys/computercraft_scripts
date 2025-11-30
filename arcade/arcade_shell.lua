---@diagnostic disable: undefined-global, undefined-field
-- arcade_shell.lua
-- Simple shell UI that lists arcade programs, lets players buy licenses,
-- and launches games once unlocked.

-- Clear potentially failed loads from previous runs
package.loaded["arcade"] = nil
package.loaded["log"] = nil
package.loaded["data.programs"] = nil

local function detectProgramPath()
  if shell and shell.getRunningProgram then
    return shell.getRunningProgram()
  end
  if debug and debug.getinfo then
    local info = debug.getinfo(1, "S")
    if info and info.source then
      local src = info.source
      if src:sub(1, 1) == "@" then
        src = src:sub(2)
      end
      return src
    end
  end
  return nil
end

local function setupPaths()
  local program = detectProgramPath()
  if not program then return end
  local dir = fs.getDir(program)
    -- We expect to be in /arcade or /disk/arcade
    -- So parent of dir is the root.
    local root = fs.getDir(dir)
    
    local function add(path)
        local part = fs.combine(root, path)
        -- fs.combine strips leading slashes, so we force absolute path
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

local monitorUtil
do
  local ok, mod = pcall(require, "lib_monitor")
  if ok and mod then
    monitorUtil = mod
  end
end

local MONITOR_AUTO_SETTING = "arcadesys.monitor.auto"

local function getMonitorAutoPreference()
  if settings and type(settings.get) == "function" then
    local value = settings.get(MONITOR_AUTO_SETTING)
    if type(value) == "boolean" then
      return value
    end
  end
  return false
end

local function setMonitorAutoPreference(value)
  if settings and type(settings.set) == "function" then
    settings.set(MONITOR_AUTO_SETTING, value == true)
    if type(settings.save) == "function" then
      pcall(settings.save)
    end
  end
end

local BASE_DIR = fs.getDir(detectProgramPath() or "") or ""
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

-- ==========================
-- Persistence helpers
-- ==========================

local CREDIT_FILE = "credits.txt"
local DEFAULT_LICENSE_DIR = "licenses"
local SECRET_SALT = "arcade-license-v1"
local ENVIRONMENT_FILE = "environment.settings"

local DEFAULT_ENVIRONMENT = {
  -- Accepts "development" (show everything) or "production" (hide unfinished entries)
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

-- ==========================
-- Program catalog
-- ==========================

package.loaded["data.programs"] = nil -- Force reload
local programs = require("data.programs")

local function hasGames()
  for _, program in ipairs(programs) do
    if program.category == "games" then
      return true
    end
  end
  return false
end

-- ==========================
-- Package Manager
-- ==========================

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


-- ==========================
-- Shell state
-- ==========================

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
        -- Map skin to theme
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
    paintutils.drawFilledBox(x, y, x + w - 1, y + h - 1, state.theme.windowBg)
    -- Title Bar
    paintutils.drawFilledBox(x, y, x + w - 1, y, state.theme.header)
    term.setTextColor(colors.white)
    term.setBackgroundColor(state.theme.header)
    term.setCursorPos(x + math.floor((w - #title) / 2), y)
    term.write(title)
    -- Close button
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

local function shouldShowProgram(program, currentMenu)
  if program.category ~= currentMenu then
    return false
  end

  if state.environment == "production" and program.prodReady == false then
    return false
  end

  return true
end

-- ==========================
-- Package Manager
-- ==========================

local REPO_BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/"

local function downloadFile(url, path)
  if not http then
    return false, "HTTP API disabled"
  end
    
  local response, err = http.get(url)
  if not response then
    return false, err or "Failed to connect"
  end
    
  local status = response.getResponseCode and response.getResponseCode() or 200
  if status >= 400 then
    local body = response.readAll()
    response.close()
    return false, string.format("HTTP %d", status)
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

-- ==========================
-- Main Loop
-- ==========================

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

local function launchArcadeArcadeUI()
  local path = resolvePath("arcade_arcade.lua")
  if not fs.exists(path) then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    print("ArcadeArcade UI missing at " .. path)
    print("Press Enter to return...")
    read()
    return
  end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1,1)
  local ok, err = pcall(function()
    shell.run(path)
  end)
  if not ok then
    print("ArcadeArcade error: " .. tostring(err))
    print("Press Enter to return...")
    read()
  else
    os.sleep(0.4)
  end
  initState() -- Reload credits/licenses after returning
end

local function runUpdater()
  -- Try absolute path first so it works no matter where the shell lives.
  local updaterPath = "/arcadesys_installer.lua"
  if not fs.exists(updaterPath) then
    -- Fallback to local directory (e.g., running off a disk)
    updaterPath = resolvePath("arcadesys_installer.lua")
  end

  if not fs.exists(updaterPath) then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    print("Updater not found (" .. updaterPath .. ")")
    os.sleep(2)
    return
  end

  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1,1)
  print("Launching updater...")
  local ok, err = pcall(function()
    shell.run(updaterPath)
  end)
  if not ok then
    print("Update failed: " .. tostring(err))
    os.sleep(2)
  end
end

local function main()
  initState()

  local autoMonitorDefault = getMonitorAutoPreference()

  local function nowSeconds()
    if type(os.epoch) == "function" then
      return os.epoch("utc") / 1000
    end
    if type(os.clock) == "function" then
      return os.clock()
    end
    return os.time()
  end

  local statusMessage, statusUntil = nil, 0
  local function setStatus(msg)
    statusMessage = msg
    statusUntil = nowSeconds() + 2
  end
  
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
                      {text = "Update", action = runUpdater},
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
  local monitorSession = nil

  local function refreshTerminalSize()
    w, h = term.getSize()
    lastMenu = "" -- Force redraw state so layout resets.
  end

  if term and type(term.current) == "function" and type(term.native) == "function" then
    local native = term.native()
    local current = term.current()
    if native and current and native ~= current then
      monitorSession = {
        restore = function()
          pcall(term.redirect, native)
        end
      }
    end
  end

  local function useMonitor()
    if not monitorUtil or type(monitorUtil.redirectToMonitor) ~= "function" then
      setStatus("Monitor API unavailable")
      return
    end
    if monitorSession then
      setStatus("Already on monitor")
      return
    end
    local session, err = monitorUtil.redirectToMonitor({ textScale = 0.5 })
    if not session then
      setStatus(err or "Monitor not found")
      return
    end
    monitorSession = session
    refreshTerminalSize()
    setStatus("Now using external monitor")
  end

  local function useComputerScreen()
    if not monitorSession then
      setStatus("Already on computer")
      return
    end
    if monitorSession.restore then
      monitorSession.restore()
    elseif term and type(term.native) == "function" then
      pcall(term.redirect, term.native())
    end
    monitorSession = nil
    refreshTerminalSize()
    setStatus("Now using computer screen")
  end

  local function toggleDefaultDisplay()
    autoMonitorDefault = not autoMonitorDefault
    setMonitorAutoPreference(autoMonitorDefault)
    if autoMonitorDefault then
      setStatus("Will auto-use monitor next launch")
    else
      setStatus("Will stay on computer next launch")
    end
  end

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

    -- Draw Desktop
    UI.clear(state.theme.bg)
    
    -- Draw Window
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
    
    -- Define Buttons
    local buttons = {}
    local startY = winY + 2
    local btnW = winW - 8
    local btnX = winX + 4
    
    if currentMenu == "main" then
      local function addButton(label, action)
        local y = startY + (#buttons * 2)
        table.insert(buttons, {text = label, y = y, action = action})
      end

      if hasGames() then
        addButton("ArcadeArcade", function()
          launchArcadeArcadeUI()
        end)
      end

      addButton("Store", function()
        for _, p in ipairs(programs) do
          if p.id == "store" then launchProgram(p) return end
        end
      end)

      addButton("My Apps", function()
        currentMenu = "library"
      end)

      addButton("System", function()
        currentMenu = "system"
      end)

      addButton("Exit", function()
        running = false
      end)
    elseif currentMenu == "library" then
      local list = {}
      for _, p in ipairs(programs) do
        -- Show purchased games/actions
        if p.id ~= "store" and p.category ~= "games" and state.licenseStore:has(p.id) then
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
        local nextY = startY
        local function addSystemOption(label, fn)
            table.insert(buttons, {text = label, y = nextY, action = fn})
            nextY = nextY + 2
        end

        addSystemOption("Themes", function() 
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
        end)
        addSystemOption("Disk Info", function() 
            term.setBackgroundColor(colors.black)
            term.clear()
            term.setCursorPos(1,1)
            print("Free Space: " .. fs.getFreeSpace(detectDiskMount() or "/"))
            os.sleep(2)
        end)
        addSystemOption("Update", runUpdater)
        if monitorUtil then
            if monitorSession then
                addSystemOption("Use Computer Screen", useComputerScreen)
            else
                addSystemOption("Use External Monitor", useMonitor)
            end
        end
        addSystemOption("Default Display: " .. (autoMonitorDefault and "Monitor" or "Computer"), toggleDefaultDisplay)
        addSystemOption("Back", function() currentMenu = "main" end)
    end
    
    -- Draw Buttons
    if selectedButtonIndex > #buttons then selectedButtonIndex = #buttons end
    if selectedButtonIndex < 1 and #buttons > 0 then selectedButtonIndex = 1 end

    for i, btn in ipairs(buttons) do
        local isHovered = (mouseX >= btnX and mouseX <= btnX + btnW - 1 and mouseY == btn.y)
        local isSelected = (i == selectedButtonIndex)
        UI.drawButton(btnX, btn.y, btnW, btn.text, false, isHovered or isSelected)
    end

    -- Build badge in bottom-right corner so installers can be verified quickly
    local buildLabel = string.format("Build %d", version.BUILD or 0)
    local badgeX = math.max(1, w - #buildLabel + 1)
    term.setBackgroundColor(state.theme.bg or colors.black)
    term.setTextColor(state.theme.text or colors.white)
    term.setCursorPos(badgeX, h)
    term.write(buildLabel)

    if statusMessage then
        local nowVal = nowSeconds()
        if nowVal > statusUntil then
            statusMessage = nil
        else
            local msgX = math.max(1, math.floor((w - #statusMessage) / 2) + 1)
            local msgY = math.max(1, h - 1)
            term.setBackgroundColor(state.theme.bg or colors.black)
            term.setTextColor(state.theme.text or colors.white)
            term.setCursorPos(msgX, msgY)
            term.write(statusMessage)
        end
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
  
  if monitorSession and monitorSession.restore then
    monitorSession.restore()
  end

  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1,1)
end


local function runWithMonitor(fn)
    if monitorUtil and monitorUtil.runOnMonitor then
        return monitorUtil.runOnMonitor(fn, { textScale = 0.5, auto = getMonitorAutoPreference() })
    end
    return fn()
end

runWithMonitor(main)
