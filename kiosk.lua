--[[
    Kiosk - The Arcadesys Store
    Handles credit exchange, license purchasing, and software installation.
]]

local ui = require("lib_ui")
local menu = require("lib_menu")
local fs_utils = require("lib_fs")
local logger = require("lib_logger")
local license_lib = require("lib_license")

local KIOSK_VERSION = "1.0.0"
local SECRET_KEY = "arcade-license-v1" -- Should match what clients expect

-- Configuration
local DISK_SIDE = "right" -- Where the disk drive is
local INPUT_CHEST = "left" -- Where payment is inserted
local PRICING = {
    ["minecraft:diamond"] = 100,
    ["minecraft:gold_ingot"] = 10,
    ["minecraft:iron_ingot"] = 1,
    ["computercraft:disk"] = 5
}

local LICENSES = {
    { name = "Arcade License", id = "license_arcade", cost = 500 },
    { name = "Factory License", id = "license_factory", cost = 1000 },
    { name = "Kiosk License", id = "license_kiosk", cost = 2000 }
}

local INSTALLERS = {
    { name = "Arcade OS (PC)", url = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/installer_arcade.lua" },
    { name = "Turtle/Factory OS", url = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/installer_factory.lua" },
    { name = "Kiosk OS (Store)", url = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/installer_kiosk.lua" }
}

local function drawHeader()
    ui.clear()
    ui.drawFrame(1, 1, 51, 19, "Arcadesys Kiosk v" .. KIOSK_VERSION)
end

local function getDiskPath()
    if fs.exists("disk") then return "disk" end
    return nil
end

local function getCredits(diskPath)
    local p = fs.combine(diskPath, "credits.txt")
    if fs.exists(p) then
        local f = fs.open(p, "r")
        local c = tonumber(f.readAll())
        f.close()
        return c or 0
    end
    return 0
end

local function setCredits(diskPath, amount)
    local p = fs.combine(diskPath, "credits.txt")
    local f = fs.open(p, "w")
    f.write(tostring(amount))
    f.close()
end

local function downloadFile(url, path)
    print("Downloading " .. url .. "...")
    local response = http.get(url)
    if not response then
        print("Failed to download.")
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    local f = fs.open(path, "w")
    f.write(content)
    f.close()
    print("Saved to " .. path)
    return true
end

local function menuBuyLicense()
    local disk = getDiskPath()
    if not disk then
        ui.clear()
        ui.label(3, 4, "Please insert a disk.")
        sleep(2)
        return
    end

    local credits = getCredits(disk)
    
    local options = {}
    for _, lic in ipairs(LICENSES) do
        table.insert(options, string.format("%s (%d cr)", lic.name, lic.cost))
    end
    table.insert(options, "Back")
    
    local choice = menu.run("Buy License (Bal: " .. credits .. ")", options)
    if choice > #LICENSES then return end
    
    local selected = LICENSES[choice]
    
    if credits < selected.cost then
        ui.clear()
        ui.label(3, 4, "Insufficient credits!")
        sleep(2)
        return
    end
    
    -- Deduct credits
    setCredits(disk, credits - selected.cost)
    
    -- Issue license
    local store = license_lib.new(fs.combine(disk, "licenses"), SECRET_KEY)
    store:issue(selected.id, selected.cost, "Kiosk Purchase")
    
    ui.clear()
    ui.label(3, 4, "Purchased " .. selected.name)
    ui.label(3, 6, "License saved to disk.")
    sleep(2)
end

local function menuExchange()
    -- Placeholder for item exchange
    ui.clear()
    ui.label(3, 4, "Insert items into chest...")
    ui.label(3, 6, "Feature coming soon.")
    sleep(2)
end

local function menuInstall()
    local options = {}
    for _, inst in ipairs(INSTALLERS) do
        table.insert(options, inst.name)
    end
    table.insert(options, "Back")
    
    local choice = menu.run("Select OS to Install", options)
    if choice > #INSTALLERS then return end
    
    local selected = INSTALLERS[choice]
    
    drawHeader()
    ui.label(3, 4, "Insert Disk...")
    ui.label(3, 6, "Press Enter when ready.")
    read()
    
    local disk = getDiskPath()
    if not disk then
        ui.label(3, 8, "No disk detected!")
        sleep(2)
        return
    end
    
    ui.label(3, 8, "Installing " .. selected.name .. "...")
    if downloadFile(selected.url, fs.combine(disk, "startup.lua")) then
        ui.label(3, 10, "Success! Disk is bootable.")
        ui.label(3, 11, "Put disk in Turtle/PC to install.")
    else
        ui.label(3, 10, "Installation Failed.")
    end
    sleep(2)
end

local function menuMain()
    while true do
        local options = {
            "Install Software",
            "Buy License",
            "Exchange Credits",
            "Exit"
        }
        
        local choice = menu.run("Main Menu", options)
        
        if choice == 1 then
            menuInstall()
        elseif choice == 2 then
            menuBuyLicense()
        elseif choice == 3 then
            menuExchange()
        elseif choice == 4 then
            break
        end
    end
end

local function runWithMonitor(fn)
    local ok, monitorUtil = pcall(require, "lib_monitor")
    if ok and monitorUtil and monitorUtil.runOnMonitor then
        return monitorUtil.runOnMonitor(fn, { textScale = 0.5 })
    end
    return fn()
end

runWithMonitor(menuMain)
