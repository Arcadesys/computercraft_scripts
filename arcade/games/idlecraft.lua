---@diagnostic disable: undefined-global, undefined-field
-- IdleCraft (Arcade wrapper version)
-- Refactored to run inside the generic three‑button arcade framework in `games/arcade.lua`.
-- The original standalone event / layout system has been removed. All rendering now
-- happens inside a single playfield using arcade's helper methods.
--
-- Button semantics (shown on bottom bar):
--  Left  : Mine (or Execute current selected upgrade action if a mode is active)
--  Center: Cycle action mode (None -> Upgrade -> Hire -> Mod -> None ...)
--  Right : Quit
-- When a mode (Upgrade/Hire/Mod) is selected the left button performs that action
-- instead of mining. Messages explain results. Passive cobble generation & random
-- events occur via onTick.
--
-- Lua Tips (search 'Lua Tip:') are sprinkled in for learning.

-- Clear potentially failed loads
package.loaded["arcade"] = nil
package.loaded["log"] = nil

local function setupPaths()
    local program = shell.getRunningProgram()
    local dir = fs.getDir(program)
    -- idlecraft is in arcade/games/idlecraft.lua
    -- dir is arcade/games
    -- root is arcade
    -- parent of root is installation root
    local gamesDir = fs.getDir(program)
    local arcadeDir = fs.getDir(gamesDir)
    local root = fs.getDir(arcadeDir)
    
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
    -- Explicitly add ui folder just in case
    add("arcade/ui")
    
    -- Ensure root is in path so require("arcade.ui.renderer") works
    if not string.find(package.path, ";/?.lua", 1, true) then
        package.path = package.path .. ";/?.lua"
    end
end

setupPaths()

local arcade = require("arcade")

-- ==========================
-- Configuration
-- ==========================

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

-- ==========================
-- Game State
-- ==========================

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

-- Lua Tip: Keeping formatting helpers local avoids re-computation / global pollution.
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

-- ==========================
-- Core Actions
-- ==========================

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

-- Random event system (subset of original for brevity while preserving flavor)
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

-- ==========================
-- Persistence
-- ==========================

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

-- ==========================
-- Menu Logic
-- ==========================

local function getMenuItems()
    local items = {}
    
    -- Upgrade
    table.insert(items, {
        label = "Upgrade Tools (" .. formatNumber(state.toolUpgradeCost) .. ")",
        action = function() upgradeTools() end,
        enabled = state.cobble >= state.toolUpgradeCost
    })

    -- MODS (if stage 2)
    if state.stage >= 2 then
        table.insert(items, {
            label = "MODS (" .. formatNumber(state.modCost) .. ")",
            action = function() installMod() end,
            enabled = state.cobble >= state.modCost
        })
    end

    -- Resume
    table.insert(items, {
        label = "Resume",
        action = function() state.menuOpen = false end,
        enabled = true
    })

    -- EXIT
    table.insert(items, {
        label = "EXIT",
        action = function(a) a:requestQuit() end,
        enabled = true
    })

    return items
end

-- ==========================
-- Rendering (arcade draw callback)
-- ==========================

local function getStageName()
    return config.stageNames[state.stage] or ("Stage " .. tostring(state.stage))
end

local function drawGame(a)
    local r = a:getRenderer()
    if not r then return end
    
    a:clearPlayfield(colors.black)
    local w, h = r:getSize()
    
    -- Header Bar
    r:fillRect(1, 1, w, 1, colors.blue, colors.white, " ")
    r:drawLabelCentered(1, 1, w, "IdleCraft - " .. getStageName(), colors.white)
    
    -- Stats Panel
    r:fillRect(1, 2, w, 3, colors.gray, colors.white, " ")
    r:drawLabelCentered(1, 2, math.floor(w/2), "Cobble: " .. formatNumber(state.cobble), colors.white)
    r:drawLabelCentered(math.floor(w/2)+1, 2, math.floor(w/2), "OPS: " .. formatRate(state.ops), colors.white)
    r:drawLabelCentered(1, 3, math.floor(w/2), "Steves: " .. formatNumber(state.steves), colors.lightGray)
    r:drawLabelCentered(math.floor(w/2)+1, 3, math.floor(w/2), "Mods: " .. formatNumber(state.mods), colors.lightGray)
    
    -- Messages
    local msgY = 5
    local msgs = state.messages
    local start = math.max(1, #msgs - 7)
    for i = start, #msgs do
        r:drawLabelCentered(1, msgY, w, msgs[i], colors.white)
        msgY = msgY + 1
    end

    -- Menu Overlay
    if state.menuOpen then
        local menuWidth = 30
        local menuX = w - menuWidth + 1
        local menuH = h - 1
        
        -- Draw shadow/dimming (optional, but let's just draw the menu)
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
            
            -- Draw selection bar
            if i == state.menuSelection then
                r:fillRect(menuX + 1, y, menuWidth - 2, 1, bg, fg, " ")
            end
            r:drawLabel(menuX + 2, y, prefix .. item.label, fg, bg)
        end
    end
end

-- ==========================
-- Game Table for arcade.start
-- ==========================

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

-- Start via arcade wrapper. Provide custom tick interval from config.
arcade.start(game, { tickSeconds = config.tickSeconds })

-- END OF FILE