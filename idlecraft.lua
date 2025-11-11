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

local arcade = require("games.arcade")

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
    mode = nil,               -- nil | 'upgrade' | 'hire' | 'mod'
    messages = {},
}

-- Lua Tip: Keeping formatting helpers local avoids re-computation / global pollution.
local function formatNumber(value)
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
-- Mode Handling / Button Logic
-- ==========================

local modeCycle = { nil, "upgrade", "hire", "mod" } -- nil means plain mining

local function nextMode()
    -- Lua Tip: ipairs iterates sequential numeric keys 1..n; we use it to find current mode index.
    local idx
    for i, m in ipairs(modeCycle) do
        if m == state.mode then idx = i break end
    end
    idx = (idx or 1) + 1
    if idx > #modeCycle then idx = 1 end
    -- Skip 'mod' if stage not yet unlocked
    if modeCycle[idx] == "mod" and state.stage < 2 then idx = 1 end
    state.mode = modeCycle[idx]
end

local function performPrimary()
    if state.mode == "upgrade" then upgradeTools()
    elseif state.mode == "hire" then hireSteve()
    elseif state.mode == "mod" then installMod()
    else mineBlock() end
    -- Ensure stage transitions can happen immediately after manual actions
    checkStageProgress()
end

-- ==========================
-- Rendering (arcade draw callback)
-- ==========================

local function getStageName()
    return config.stageNames[state.stage] or ("Stage " .. tostring(state.stage))
end

local function currentModeLabel()
    if not state.mode then return "Mine" end
    if state.mode == "upgrade" then return "Upgrade" end
    if state.mode == "hire" then return "Hire" end
    if state.mode == "mod" then return "Mods" end
end

local function modeStatusLine()
    if not state.mode then
        return "Mode: Mine (Center cycles)"
    elseif state.mode == "upgrade" then
        return string.format("Upgrade cost %s (Next +%s)",
            formatNumber(state.toolUpgradeCost),
            formatNumber(calculateManualGain(state.toolLevel+1)))
    elseif state.mode == "hire" then
        return string.format("Hire Steve cost %s (+%s/sec)",
            formatNumber(state.steveCost), formatRate(state.stevePassiveRate))
    elseif state.mode == "mod" then
        return string.format("Install Mod cost %s (+%s/sec each)",
            formatNumber(state.modCost), formatRate(state.modPassiveRate))
    end
end

local function drawGame(a)
    a:clearPlayfield(colors.black, colors.white)
    -- Header
    a:centerPrint(1, string.format("IdleCraft — %s", getStageName()), colors.cyan)
    -- Resources
    a:centerPrint(2, string.format("Cobble %s  Steves %s  Mods %s  OPS %s", 
        formatNumber(state.cobble), formatNumber(state.steves), formatNumber(state.mods), formatRate(state.ops)), colors.white)
    -- Mode line
    a:centerPrint(3, modeStatusLine(), colors.lightGray)
    -- Messages
    local baseY = 5
    local msgs = state.messages
    local start = math.max(1, #msgs - (config.maxMessages) + 1)
    local line = 0
    for i = start, #msgs do
        line = line + 1
        a:centerPrint(baseY + line - 1, msgs[i], colors.white)
    end
    if #msgs == 0 then a:centerPrint(baseY, "(No messages yet. Mine something!)", colors.lightGray) end
end

-- ==========================
-- Game Table for arcade.start
-- ==========================

local game = {
    name = "IdleCraft",
    init = function(a)
        math.randomseed(os.epoch and os.epoch("utc") or os.clock()) -- Reseed per session
        -- Enable/disable left button if an action mode is selected but not affordable
        local enableLeft = true
        if state.mode == "upgrade" then enableLeft = state.cobble >= state.toolUpgradeCost
        elseif state.mode == "hire" then enableLeft = state.cobble >= state.steveCost
        elseif state.mode == "mod" then enableLeft = (state.stage >= 2) and (state.cobble >= state.modCost) end
        a:setButtons({currentModeLabel(), "Cycle", "Quit"}, {enableLeft, true, true})
        addMessage("Welcome to IdleCraft (Arcade edition). Press Center to pick an action mode.")
    end,
    draw = function(a)
        -- Update button labels each frame (mode can change between ticks)
        local enableLeft = true
        if state.mode == "upgrade" then enableLeft = state.cobble >= state.toolUpgradeCost
        elseif state.mode == "hire" then enableLeft = state.cobble >= state.steveCost
        elseif state.mode == "mod" then enableLeft = (state.stage >= 2) and (state.cobble >= state.modCost) end
        a:setButtons({currentModeLabel(), "Cycle", "Quit"}, {enableLeft, true, true})
        drawGame(a)
    end,
    onButton = function(a, which)
        if which == "left" then
            performPrimary()
        elseif which == "center" then
            nextMode()
        elseif which == "right" then
            a:requestQuit()
            return
        end
    end,
    onTick = function(a, dt)
        passiveTick()
    end,
}

-- Start via arcade wrapper. Provide custom tick interval from config.
arcade.start(game, { tickSeconds = config.tickSeconds })

-- END OF FILE