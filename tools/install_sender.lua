-- install_sender.lua
-- Run this on the designer/PC side (in-game computer) to push files from
-- `install_payload/` to discovered devices (turtles/computers) using the
-- project's `lib_network.sendSchema` message format.
--
-- Usage: put files to send under `install_payload/` (paths preserved), then run:
--   install_sender.lua

local network = require("lib_network")

local payloadDir = "install_payload"
local timeout = 3

local function collectFiles(dir, prefix)
    prefix = prefix or ""
    local files = {}
    if not fs.exists(dir) then return files end
    for _, name in ipairs(fs.list(dir)) do
        local path = dir .. "/" .. name
        local rel = prefix .. name
        if fs.isDir(path) then
            local sub = collectFiles(path, rel .. "/")
            for _, v in ipairs(sub) do table.insert(files, v) end
        else
            local h = fs.open(path, "r")
            if h then
                local content = h.readAll()
                h.close()
                table.insert(files, { path = rel, content = content })
            end
        end
    end
    return files
end

local function main()
    if not network.openModem() then
        print("No wireless modem found or unable to open rednet. Attach a wireless modem and try again.")
        return
    end

    local files = collectFiles(payloadDir)
    if #files == 0 then
        print("No files found in '" .. payloadDir .. "'. Place files there and try again.")
        return
    end

    print("Scanning for devices...")
    local devices = network.findDevices(timeout)
    if #devices == 0 then
        print("No devices found. Ensure receivers are running and try again.")
        return
    end

    print("Found " .. #devices .. " devices. Sending files...")
    for _, dev in ipairs(devices) do
        print("-> " .. dev.label .. " (ID: " .. dev.id .. ")")
        for _, f in ipairs(files) do
            -- Reuse sendSchema message format so receivers already implemented can handle it
            network.sendSchema(dev.id, f.path, f.content)
            os.sleep(0.05)
        end
    end

    print("Done sending.")
end

main()
