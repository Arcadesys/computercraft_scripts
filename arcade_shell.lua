---@diagnostic disable: undefined-global
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
  },
  {
    id = "slots",
    name = "Slots",
    path = "slots.lua",
    price = 3,
    description = "Spin reels for quick wins.",
  },
  {
    id = "cantstop",
    name = "Can't Stop",
    path = "cantstop.lua",
    price = 4,
    description = "Push your luck dice classic.",
  },
  {
    id = "idlecraft",
    name = "IdleCraft",
    path = "idlecraft.lua",
    price = 6,
    description = "AFK-friendly cobble empire.",
  },
}

-- ==========================
-- Shell state
-- ==========================

local state = {
  credits = 0,
  licenseStore = nil,
}

local function initState()
  state.credits = loadCredits()
  local base = combinePath(detectDiskMount(), DEFAULT_LICENSE_DIR)
  state.licenseStore = LicenseStore.new(base, SECRET_SALT)
end

-- ==========================
-- UI helpers
-- ==========================

local function printDivider()
  print(string.rep("-", 40))
end

local function pause(message)
  print(message or "Press Enter to continue…")
  read()
end

local function showHeader()
  term.clear()
  term.setCursorPos(1, 1)
  print("Arcade Shell")
  printDivider()
  print(string.format("Credits: %d", state.credits))
  printDivider()
end

local function drawProgramList(showPrices)
  for index, program in ipairs(programs) do
    local owned = state.licenseStore:has(program.id)
    local label = string.format("%d) %s", index, program.name)
    if showPrices then
      local status = owned and "Owned" or ("Price: " .. program.price)
      print(string.format("%-18s [%s]", label, status))
    else
      print(label)
    end
    print("   " .. program.description)
  end
end

-- ==========================
-- License helpers
-- ==========================

local function ensureLicense(program)
  local owned = state.licenseStore:has(program.id)
  if owned then
    return true
  end

  printDivider()
  print(string.format("%s is locked. Purchase for %d credits? (y/n)", program.name, program.price))
  write("> ")
  local answer = string.lower(read())
  if answer ~= "y" then
    return false
  end

  if state.credits < program.price then
    print("Not enough credits. Visit the store to top up or pick a cheaper game.")
    return false
  end

  state.credits = state.credits - program.price
  saveCredits(state.credits)
  state.licenseStore:save(program.id, program.price, "purchased via shell")
  print("License purchased! Enjoy your new game.")
  return true
end

-- ==========================
-- Screens
-- ==========================

local function launchProgram(program)
  if not ensureLicense(program) then
    pause()
    return
  end

  printDivider()
  print("Launching " .. program.name .. "…")
  -- Lua tip: pcall prevents the whole shell from crashing if the program errors.
  local ok, err = pcall(function()
    shell.run(program.path)
  end)
  if not ok then
    print("Program error: " .. tostring(err))
  end
  pause("Returning to shell. Press Enter…")
end

local function playScreen()
  while true do
    showHeader()
    print("Pick a program to launch:")
    drawProgramList(true)
    print("0) Back")
    printDivider()
    write("Choice: ")
    local choice = tonumber(read())
    if not choice or choice < 0 or choice > #programs then
      print("Invalid selection")
      pause()
    elseif choice == 0 then
      return
    else
      launchProgram(programs[choice])
    end
  end
end

local function storeScreen()
  while true do
    showHeader()
    print("Store - buy licenses with your credits")
    drawProgramList(true)
    print("0) Back")
    printDivider()
    write("Purchase which program? ")
    local choice = tonumber(read())
    if choice == 0 then
      return
    end
    local program = programs[choice]
    if not program then
      print("Invalid selection")
      pause()
    else
      if state.licenseStore:has(program.id) then
        print("You already own " .. program.name .. ".")
        pause()
      else
        ensureLicense(program)
        pause()
      end
    end
  end
end

-- ==========================
-- Main loop
-- ==========================

local function main()
  initState()
  while true do
    showHeader()
    print("1) Play a game")
    print("2) Store (buy/unlock programs)")
    print("3) Add credits manually")
    print("0) Exit")
    printDivider()
    write("Select: ")
    local choice = tonumber(read())
    if choice == 1 then
      playScreen()
    elseif choice == 2 then
      storeScreen()
    elseif choice == 3 then
      print("Enter amount to add (for testing / admin):")
      write("> ")
      local delta = tonumber(read()) or 0
      state.credits = math.max(0, state.credits + delta)
      saveCredits(state.credits)
    elseif choice == 0 then
      return
    else
      print("Unknown option")
      pause()
    end
  end
end

main()
