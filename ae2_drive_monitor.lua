-- AE2 Drive Monitor
-- Shows ME item/fluid usage on a 2x3 advanced monitor with color, bars, and trends.
-- Requires an Advanced Peripherals ME Bridge connected to the network.

local REFRESH_SECONDS = 5
local TEXT_SCALE = 0.75 -- Larger text while still fitting a 2x3 monitor

local palette = {
    bg = colors.black,
    frame = colors.gray,
    accent = colors.cyan,
    item = colors.lime,
    fluid = colors.blue,
    energy = colors.yellow,
    warn = colors.orange,
    danger = colors.red,
    text = colors.white,
    muted = colors.lightGray,
}

local function findPeripheral(kind)
    local obj = peripheral.find(kind)
    if obj then return obj end
    error("Missing peripheral: " .. kind .. " (attach and restart)", 0)
end

local mon = findPeripheral("monitor")
local me = findPeripheral("meBridge")

mon.setTextScale(TEXT_SCALE)
mon.setBackgroundColor(palette.bg)
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
        return tostring(math.floor(n + 0.5))
    end
end

local function parseStorage(tbl)
    if type(tbl) ~= "table" then return nil, nil, nil, nil end
    local used = tbl.used or tbl.stored or tbl.usage or tbl.usedBytes
    local total = tbl.total or tbl.max or tbl.capacity or tbl.totalBytes
    local usedTypes = tbl.types or tbl.usedTypes or tbl.storedTypes
    local typeCap = tbl.typeCapacity or tbl.typeCap or tbl.maxTypes or tbl.totalTypes
    if type(used) ~= "number" then used = nil end
    if type(total) ~= "number" then total = nil end
    if type(usedTypes) ~= "number" then usedTypes = nil end
    if type(typeCap) ~= "number" then typeCap = nil end
    return used, total, usedTypes, typeCap
end

local function safeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

local function fetchStorage(kind)
    local suffix = kind == "fluid" and "FluidStorage" or "ItemStorage"
    local used, total, usedTypes, typeCap

    used, total, usedTypes, typeCap = parseStorage(safeCall(me["get" .. suffix]))
    if not total then total = safeCall(me["getMax" .. suffix]) end
    if not used then used = safeCall(me["getUsed" .. suffix]) end
    if type(used) == "table" then
        local u, t, ut, tc = parseStorage(used)
        used = u or used
        total = t or total
        usedTypes = ut or usedTypes
        typeCap = tc or typeCap
    end
    if type(total) == "table" then
        local _, t, ut, tc = parseStorage(total)
        total = t or total
        usedTypes = ut or usedTypes
        typeCap = tc or typeCap
    end

    if type(used) ~= "number" then used = nil end
    if type(total) ~= "number" then total = nil end
    if type(usedTypes) ~= "number" then usedTypes = nil end
    if type(typeCap) ~= "number" then typeCap = nil end
    return used, total, usedTypes, typeCap
end

local itemHistory = {}
local fluidHistory = {}

local function pushHistory(history, value, maxLen)
    table.insert(history, value or 0)
    while #history > maxLen do
        table.remove(history, 1)
    end
end

local function drawHeader(w)
    mon.setBackgroundColor(palette.accent)
    mon.setTextColor(palette.bg)
    mon.setCursorPos(1, 1)
    mon.write(string.rep(" ", w))
    local title = "AE2 DRIVE STATUS"
    mon.setCursorPos(math.max(1, math.floor((w - #title) / 2)), 1)
    mon.write(title)
    mon.setBackgroundColor(palette.bg)
    mon.setTextColor(palette.text)
end

local function drawBar(y, label, used, total, color)
    local w, _ = mon.getSize()
    local pct = (used and total and total > 0) and (used / total) or 0
    pct = math.min(math.max(pct, 0), 1)
    local barWidth = math.max(6, w - 4)
    local fill = math.floor(barWidth * pct)

    mon.setCursorPos(1, y)
    mon.setTextColor(palette.muted)
    mon.clearLine()
    mon.write(label)
    local pctText = string.format("%3d%%", math.floor(pct * 100 + 0.5))
    mon.setCursorPos(w - #pctText + 1, y)
    mon.setTextColor(palette.text)
    mon.write(pctText)

    mon.setCursorPos(2, y + 1)
    mon.setBackgroundColor(palette.frame)
    mon.write(string.rep(" ", barWidth))
    mon.setCursorPos(2, y + 1)
    mon.setBackgroundColor(color)
    mon.write(string.rep(" ", fill))
    mon.setBackgroundColor(palette.bg)

    mon.setCursorPos(2, y + 2)
    mon.setTextColor(color)
    if used and total then
        mon.write(string.format("%s / %s", fmtNumber(used), fmtNumber(total)))
    elseif used then
        mon.write(fmtNumber(used))
    else
        mon.write("No data")
    end
    mon.setTextColor(palette.text)
end

local function drawTypes(y, usedTypes, typeCap)
    local w, _ = mon.getSize()
    mon.setCursorPos(1, y)
    mon.setTextColor(palette.muted)
    mon.clearLine()
    local txt
    if usedTypes and typeCap then
        txt = string.format("Item types: %s / %s", fmtNumber(usedTypes), fmtNumber(typeCap))
    elseif usedTypes then
        txt = string.format("Item types: %s", fmtNumber(usedTypes))
    else
        txt = "Item types: ?"
    end
    mon.write(txt:sub(1, w))
end

local function drawEnergy(y, energyUse, storedEnergy, maxEnergy)
    local w, _ = mon.getSize()
    mon.setCursorPos(1, y)
    mon.clearLine()
    mon.setTextColor(palette.energy)
    local line
    if energyUse and storedEnergy and maxEnergy then
        line = string.format("Energy: %s/t  %s/%s", fmtNumber(energyUse), fmtNumber(storedEnergy), fmtNumber(maxEnergy))
    elseif energyUse then
        line = string.format("Energy: %s/t", fmtNumber(energyUse))
    elseif storedEnergy and maxEnergy then
        line = string.format("Energy: %s/%s", fmtNumber(storedEnergy), fmtNumber(maxEnergy))
    else
        line = "Energy: ?"
    end
    mon.write(line:sub(1, w))
    mon.setTextColor(palette.text)
end

local ramp = { " ", ".", ":", "-", "=", "+", "*", "#", "@" }
local function drawTrend(y, label, history, color)
    local w, _ = mon.getSize()
    local maxLen = w - 2
    mon.setCursorPos(1, y)
    mon.setTextColor(palette.muted)
    mon.clearLine()
    mon.write(label)

    mon.setCursorPos(1, y + 1)
    mon.clearLine()
    local len = math.min(#history, maxLen)
    local start = #history - len + 1
    mon.setTextColor(color)
    for i = start, #history do
        local pct = history[i] or 0
        local idx = math.floor(pct * (#ramp - 1) + 1)
        idx = math.max(1, math.min(idx, #ramp))
        mon.write(ramp[idx])
    end
    mon.setTextColor(palette.text)
end

local function draw()
    local w, h = mon.getSize()
    mon.setBackgroundColor(palette.bg)
    mon.setTextColor(palette.text)
    mon.clear()

    drawHeader(w)

    local itemUsed, itemTotal, itemTypes, itemTypeCap = fetchStorage("item")
    local fluidUsed, fluidTotal = fetchStorage("fluid")
    local energyUse = safeCall(me.getEnergyUsage)
    local energyCap = safeCall(me.getEnergyStorage) -- Some versions return { stored=?, max=? }
    local storedEnergy, maxEnergy = parseStorage(energyCap)
    if type(energyUse) ~= "number" then energyUse = nil end

    local row = 3
    drawBar(row, "ITEM STORAGE", itemUsed, itemTotal, palette.item)
    drawTypes(row + 3, itemTypes, itemTypeCap)
    row = row + 4
    drawBar(row, "FLUID STORAGE", fluidUsed, fluidTotal, palette.fluid)
    row = row + 4
    drawEnergy(row, energyUse, storedEnergy, maxEnergy)
    row = row + 2

    -- Trends live near the bottom to form a mini graph for quick glances.
    local trendStart = h - 3
    local itemPct = (itemUsed and itemTotal and itemTotal > 0) and (itemUsed / itemTotal) or 0
    local fluidPct = (fluidUsed and fluidTotal and fluidTotal > 0) and (fluidUsed / fluidTotal) or 0
    pushHistory(itemHistory, itemPct, w - 2)
    pushHistory(fluidHistory, fluidPct, w - 2)
    drawTrend(trendStart, "Items trend", itemHistory, palette.item)
    drawTrend(trendStart + 2, "Fluids trend", fluidHistory, palette.fluid)

    mon.setCursorPos(1, h)
    mon.setTextColor(palette.muted)
    mon.clearLine()
    mon.write("Updated: " .. textutils.formatTime(os.time(), true))
    mon.setTextColor(palette.text)
end

while true do
    draw()
    sleep(REFRESH_SECONDS)
end
