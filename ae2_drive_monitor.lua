-- AE2 Drive Monitor
-- Shows ME item/fluid usage on a 2x3 advanced monitor.
-- Requires an Advanced Peripherals ME Bridge connected to the network.

local REFRESH_SECONDS = 5
local TEXT_SCALE = 0.5 -- Gives more columns on a 2x3 monitor

local function findPeripheral(kind)
    local obj = peripheral.find(kind)
    if obj then return obj end
    error("Missing peripheral: " .. kind .. " (attach and restart)", 0)
end

local mon = findPeripheral("monitor")
local me = findPeripheral("meBridge")

mon.setTextScale(TEXT_SCALE)
mon.setBackgroundColor(colors.black)
mon.clear()

local function fmtNumber(n)
    if type(n) ~= "number" then return "?" end
    local abs = math.abs(n)
    if abs >= 1e9 then
        return string.format("%.1fG", n / 1e9)
    elseif abs >= 1e6 then
        return string.format("%.1fM", n / 1e6)
    elseif abs >= 1e3 then
        return string.format("%.1fk", n / 1e3)
    else
        return tostring(math.floor(n))
    end
end

local function parseStorage(tbl)
    if type(tbl) ~= "table" then return nil, nil end
    local used = tbl.used or tbl.stored or tbl.usage or tbl.usedBytes
    local total = tbl.total or tbl.max or tbl.capacity or tbl.totalBytes
    if type(used) == "number" and type(total) == "number" then
        return used, total
    end
    return nil, nil
end

local function safeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

local function fetchStorage(kind)
    local suffix = kind == "fluid" and "FluidStorage" or "ItemStorage"
    local used, total

    used, total = parseStorage(safeCall(me["get" .. suffix]))
    if not total then total = safeCall(me["getMax" .. suffix]) end
    if not used then used = safeCall(me["getUsed" .. suffix]) end
    if type(used) == "table" then
        local u, t = parseStorage(used)
        used = u or used
        total = t or total
    end
    if type(total) == "table" then
        local _, t = parseStorage(total)
        total = t or total
    end

    if type(used) ~= "number" then used = nil end
    if type(total) ~= "number" then total = nil end
    return used, total
end

local function drawBar(y, label, used, total, color)
    local w, _ = mon.getSize()
    mon.setCursorPos(1, y)
    mon.clearLine()

    local pct = (used and total and total > 0) and (used / total) or 0
    pct = math.min(math.max(pct, 0), 1)
    local barWidth = math.max(4, w - 2)
    local fill = math.floor(barWidth * pct)

    local text = label
    if used and total then
        text = string.format("%s %s/%s (%d%%)", label, fmtNumber(used), fmtNumber(total), math.floor(pct * 100 + 0.5))
    elseif used then
        text = string.format("%s %s", label, fmtNumber(used))
    else
        text = string.format("%s ?", label)
    end

    mon.write(text:sub(1, w))

    mon.setCursorPos(1, y + 1)
    mon.clearLine()
    mon.write("[")
    mon.setBackgroundColor(color)
    mon.write(string.rep(" ", fill))
    mon.setBackgroundColor(colors.gray)
    mon.write(string.rep(" ", barWidth - fill))
    mon.setBackgroundColor(colors.black)
    mon.write("]")
end

local function draw()
    local w, _ = mon.getSize()
    mon.setCursorPos(1, 1)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    local title = "AE2 DRIVE STATUS"
    mon.setCursorPos(math.max(1, math.floor((w - #title) / 2)), 1)
    mon.write(title)

    local itemUsed, itemTotal = fetchStorage("item")
    local fluidUsed, fluidTotal = fetchStorage("fluid")
    local energyUse = safeCall(me.getEnergyUsage)
    local energyCap = safeCall(me.getEnergyStorage) -- Some versions return { stored=?, max=? }
    local storedEnergy, maxEnergy = parseStorage(energyCap)
    if type(energyUse) ~= "number" then energyUse = nil end

    drawBar(3, "Items", itemUsed, itemTotal, colors.lime)
    drawBar(6, "Fluids", fluidUsed, fluidTotal, colors.lightBlue)

    mon.setCursorPos(1, 9)
    mon.clearLine()
    local energyLine
    if energyUse and storedEnergy and maxEnergy then
        energyLine = string.format("Energy: %s/t  %s/%s", fmtNumber(energyUse), fmtNumber(storedEnergy), fmtNumber(maxEnergy))
    elseif energyUse then
        energyLine = string.format("Energy: %s/t", fmtNumber(energyUse))
    else
        energyLine = "Energy: ?"
    end
    mon.write(energyLine:sub(1, w))

    mon.setCursorPos(1, 11)
    mon.clearLine()
    mon.write("Updated: " .. textutils.formatTime(os.time(), true))
end

while true do
    draw()
    sleep(REFRESH_SECONDS)
end
