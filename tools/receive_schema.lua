-- receive_schema.lua
-- Run this on a ComputerCraft computer or turtle to receive schema files sent over the wireless network
-- Usage: place in a computer/turtle and run: `receive_schema.lua`

local network = require("lib_network")

local saveDir = ""

local function writeFile(filename, content)
    local path = filename
    -- If caller included directories, keep them. Ensure .json extension
    if not path:find("%.json$") then path = path .. ".json" end
    path = saveDir .. path

    local f, err = fs.open(path, "w")
    if not f then
        print("Error opening file for write: " .. tostring(err))
        return false
    end
    f.write(content)
    f.close()
    print("Saved " .. path)
    return true
end

local function main()
    if fs.exists("disk") and fs.isDir("disk") then
        saveDir = "disk/"
        print("Disk detected. Received files will be written to: " .. saveDir)
    else
        print("No disk detected. Files will be written to the local filesystem.")
    end

    print("Opening wireless modem (if present)...")
    if not network.openModem() then
        print("No wireless modem found or unable to open rednet. Attach a wireless modem and try again.")
        return
    end

    print("Broadcasting presence and listening for schema sends. Press Ctrl+T to exit.")
    network.broadcastPresence()
    network.listen(function(senderId, filename, content)
        print("Received " .. tostring(filename) .. " from " .. tostring(senderId))
        local ok, err = pcall(writeFile, filename, content)
        if not ok then
            print("Failed to save file: " .. tostring(err))
        end
    end)
end

local function runWithMonitor(fn)
    local ok, monitorUtil = pcall(require, "lib_monitor")
    if ok and monitorUtil and monitorUtil.runOnMonitor then
        return monitorUtil.runOnMonitor(fn, { textScale = 0.5 })
    end
    return fn()
end

runWithMonitor(main)
