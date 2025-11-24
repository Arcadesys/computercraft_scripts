---@diagnostic disable: undefined-global
-- arcade_shell.lua
-- Simple shell UI that lists arcade programs, lets players buy licenses,
-- and launches games once unlocked.

-- Ensure package path includes lib and arcade
if not string.find(package.path, "/lib/?.lua") then
    package.path = package.path .. ";/lib/?.lua;/arcade/?.lua;/factory/?.lua"
end

local LicenseStore = require("license_store")

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

local programs = {
  {
    id = "blackjack",
    name = "Blackjack",
    path = "games/blackjack.lua",
    price = 5,
    description = "Beat the dealer in a race to 21.",
    category = "games",
  },
  {
    id = "slots",
    name = "Slots",
    path = "games/slots.lua",
    price = 3,
    description = "Spin reels for quick wins.",
    category = "games",
  },
  {
    id = "cantstop",
    name = "Can't Stop",
    path = "games/cantstop.lua",
    price = 4,
    description = "Push your luck dice classic.",
    category = "games",
  },
  {
    id = "idlecraft",
    name = "IdleCraft",
    path = "games/idlecraft.lua",
    price = 6,
    description = "AFK-friendly cobble empire.",
    category = "games",
  },
  {
    id = "artillery",
    name = "Artillery",
    path = "games/artillery.lua",
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
    prodReady = false,
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
  },
  environment = DEFAULT_ENVIRONMENT.mode,
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
    shell.run(resolvePath(program.path))
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
            if shouldShowProgram(p, currentMenu) then table.insert(list, p) end
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
