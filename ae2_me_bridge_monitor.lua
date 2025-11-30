-- AE2 ME Bridge Monitor
-- Monitors AE2 storage via Advanced Peripherals meBridge.
-- Features:
--   * Item/energy/CPU overview UI on an attached monitor or terminal.
--   * Track specific items with min/max thresholds and optional auto-crafting.
--   * ChatBox/Redstone alarms with cooldowns to avoid spam.
--   * Config persisted to disk for tuning without code edits.
--
-- Place requirements nearby:
--   - meBridge attached to AE2 network.
--   - monitor (optional, for UI; computer terminal works too).
--   - chatBox (optional) for alerts.
--   - redstoneIntegrator (optional) for alarm channel.

local CONFIG_PATH = "/etc/ae2_monitor.cfg"
local POLL_TICKS = 20 -- Default poll interval (seconds ~= ticks on computers)
local ALERT_COOLDOWN = 60

local function findPeripheral(kind)
    local obj = peripheral.find(kind)
    if obj then return obj end
    error("Missing peripheral: " .. kind .. " (attach and restart)", 0)
end

local me = findPeripheral("meBridge")
local mon = peripheral.find("monitor")
local chat = peripheral.find("chatBox")
local rsInt = peripheral.find("redstoneIntegrator")

local cfg = {
    poll = POLL_TICKS,
    track = {
        -- ["minecraft:redstone"] = { min = 1024, max = 32768, autocraft = false },
    },
    redstone = {
        side = "front",
        mode = "pulse", -- "pulse" or "hold"
    },
    alerts = true,
}

local function loadConfig()
    if not fs.exists(CONFIG_PATH) then return end
    local ok, data = pcall(function()
        local h = fs.open(CONFIG_PATH, "r")
        if not h then return nil end
        local text = h.readAll()
        h.close()
        return text and textutils.unserialize(text)
    end)
    if ok and type(data) == "table" then
        for k, v in pairs(data) do
            cfg[k] = v
        end
    end
end

local function saveConfig()
    fs.makeDir(fs.getDir(CONFIG_PATH))
    local h = fs.open(CONFIG_PATH, "w")
    if not h then return end
    h.write(textutils.serialize(cfg))
    h.close()
end

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

local function debounceLog(lastTimes, key, cooldown)
    local now = os.epoch("utc") / 1000
    if not lastTimes[key] or now - lastTimes[key] >= cooldown then
        lastTimes[key] = now
        return true
    end
    return false
end

local function sendAlert(message, color)
    if not cfg.alerts then return end
    if chat then
        chat.sendMessage(message)
    end
    if rsInt then
        if cfg.redstone.mode == "pulse" then
            rsInt.setOutput(cfg.redstone.side, true)
            sleep(0.2)
            rsInt.setOutput(cfg.redstone.side, false)
        else
            rsInt.setOutput(cfg.redstone.side, true)
        end
    end
    if mon then
        mon.setTextColor(color or colors.red)
        local w, h = mon.getSize()
        mon.setCursorPos(1, h)
        mon.clearLine()
        mon.write(message:sub(1, w))
        mon.setTextColor(colors.white)
    end
    print(message)
end

local function clearRedstone()
    if rsInt and cfg.redstone.mode == "hold" then
        rsInt.setOutput(cfg.redstone.side, false)
    end
end

local function fetchSummary()
    local summary = {
        items = me.getItemStorage(),
        fluids = me.getFluidStorage and me.getFluidStorage() or nil,
        energy = me.getEnergyStorage and me.getEnergyStorage() or nil,
        usage = me.getEnergyUsage and me.getEnergyUsage() or nil,
        cpus = me.getCraftingCPUs and me.getCraftingCPUs() or nil,
    }
    return summary
end

local function getTrackedCounts()
    local items = {}
    for name, rule in pairs(cfg.track) do
        local detail = me.getItem({ name = name })
        local count = detail and detail.amount or 0
        items[name] = { count = count, rule = rule }
    end
    return items
end

local function requestCraft(name, rule)
    if not rule.autocraft then return false end
    if not me.requestCrafting then return false end
    local craftAmount = math.max(1, (rule.min or 0) * 2)
    local ok, err = pcall(function()
        return me.requestCrafting({ name = name, count = craftAmount })
    end)
    if not ok then
        print("Craft failed for " .. name .. ": " .. tostring(err))
        return false
    end
    return true
end

local function drawUI(summary, tracked)
    local w, h
    if mon then
        mon.setTextScale(0.5)
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
        mon.clear()
        mon.setCursorPos(1, 1)
        w, h = mon.getSize()
    else
        term.clear()
        term.setCursorPos(1, 1)
        w, h = term.getSize()
    end

    local function writeLine(y, text, color)
        if mon then
            mon.setCursorPos(1, y)
            mon.setTextColor(color or colors.white)
            mon.clearLine()
            mon.write(text:sub(1, w))
        else
            term.setCursorPos(1, y)
            term.clearLine()
            term.setTextColor(color or colors.white)
            term.write(text:sub(1, w))
        end
    end

    writeLine(1, "AE2 MONITOR (" .. textutils.formatTime(os.time(), true) .. ")", colors.cyan)

    local itemUsed = summary.items and summary.items.used or summary.items and summary.items.stored
    local itemTotal = summary.items and summary.items.total or summary.items and summary.items.max or summary.items and summary.items.capacity
    writeLine(3, string.format("Items: %s / %s", fmtNumber(itemUsed), fmtNumber(itemTotal)), colors.lime)

    if summary.fluids then
        local fluidUsed = summary.fluids.used or summary.fluids.stored
        local fluidTotal = summary.fluids.total or summary.fluids.max or summary.fluids.capacity
        writeLine(4, string.format("Fluids: %s / %s", fmtNumber(fluidUsed), fmtNumber(fluidTotal)), colors.lightBlue)
    else
        writeLine(4, "Fluids: (bridge lacks fluid methods)", colors.lightGray)
    end

    local energyStored = summary.energy and (summary.energy.stored or summary.energy.used)
    local energyMax = summary.energy and (summary.energy.max or summary.energy.total or summary.energy.capacity)
    if energyStored and energyMax then
        writeLine(5, string.format("Energy: %s / %s", fmtNumber(energyStored), fmtNumber(energyMax)), colors.yellow)
    else
        writeLine(5, "Energy: " .. fmtNumber(summary.usage) .. "/t", colors.yellow)
    end

    local cpuCount = summary.cpus and #summary.cpus or 0
    local busy = 0
    if summary.cpus then
        for _, cpu in ipairs(summary.cpus) do
            if cpu.busy then busy = busy + 1 end
        end
    end
    writeLine(6, string.format("Crafting CPUs: %d total, %d busy", cpuCount, busy), colors.orange)

    writeLine(8, "Tracked:", colors.white)
    local row = 9
    for name, data in pairs(tracked) do
        if row > h then break end
        local rule = data.rule
        local warn = (rule.min and data.count < rule.min) or (rule.max and data.count > rule.max)
        local color = warn and colors.red or colors.white
        local ruleText = string.format("min %s max %s", rule.min or "-", rule.max or "-")
        writeLine(row, string.format("%s: %s (%s)", name, fmtNumber(data.count), ruleText), color)
        row = row + 1
    end
end

local function printHelp()
    print("Commands:")
    print("  watch <item> <min> [max] [autocraft:true|false]")
    print("  unwatch <item>")
    print("  poll <seconds>")
    print("  alerts <on|off>")
    print("  side <left|right|front|back|top|bottom>")
    print("  mode <pulse|hold>")
    print("  help")
end

loadConfig()

local lastAlert = {}
local function evaluate(tracked)
    for name, data in pairs(tracked) do
        local rule = data.rule
        if rule.min and data.count < rule.min then
            if debounceLog(lastAlert, name .. ":low", ALERT_COOLDOWN) then
                sendAlert(string.format("[AE] Low %s: %s / %s (min)", name, fmtNumber(data.count), fmtNumber(rule.min)))
                requestCraft(name, rule)
            end
        elseif rule.max and data.count > rule.max then
            if debounceLog(lastAlert, name .. ":high", ALERT_COOLDOWN) then
                sendAlert(string.format("[AE] High %s: %s / %s (max)", name, fmtNumber(data.count), fmtNumber(rule.max)))
            end
        else
            clearRedstone()
        end
    end
end

local function commandLoop()
    while true do
        io.write("> ")
        local line = read()
        if not line then break end
        local args = {}
        for part in string.gmatch(line, "%S+") do
            table.insert(args, part)
        end
        local cmd = args[1]
        if cmd == "watch" and args[2] and args[3] then
            local item = args[2]
            local min = tonumber(args[3])
            local max = args[4] and tonumber(args[4]) or nil
            local autocraft = args[5] == "true"
            cfg.track[item] = { min = min, max = max, autocraft = autocraft }
            saveConfig()
            print("Watching " .. item)
        elseif cmd == "unwatch" and args[2] then
            cfg.track[args[2]] = nil
            saveConfig()
            print("Stopped watching " .. args[2])
        elseif cmd == "poll" and args[2] then
            cfg.poll = tonumber(args[2]) or cfg.poll
            saveConfig()
            print("Poll set to " .. tostring(cfg.poll))
        elseif cmd == "alerts" and args[2] then
            cfg.alerts = args[2] == "on"
            saveConfig()
            print("Alerts " .. (cfg.alerts and "on" or "off"))
        elseif cmd == "side" and args[2] then
            cfg.redstone.side = args[2]
            saveConfig()
            print("Redstone side " .. args[2])
        elseif cmd == "mode" and args[2] then
            cfg.redstone.mode = args[2]
            saveConfig()
            print("Redstone mode " .. args[2])
        elseif cmd == "help" then
            printHelp()
        elseif cmd == "" or cmd == nil then
            -- ignore
        else
            print("Unknown command. Type 'help'.")
        end
    end
end

local function main()
    local lastPoll = 0
    parallel.waitForAny(function()
        while true do
            local now = os.clock()
            if now - lastPoll >= (cfg.poll or POLL_TICKS) then
                local summary = fetchSummary()
                local tracked = getTrackedCounts()
                drawUI(summary, tracked)
                evaluate(tracked)
                lastPoll = now
            end
            sleep(0.5)
        end
    end, commandLoop)
end

print("AE2 monitor starting...")
print("Type 'help' for commands.")
main()
