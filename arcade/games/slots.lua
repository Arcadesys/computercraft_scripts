---@diagnostic disable: undefined-global, undefined-field
-- Slots with animated reels and weighted symbols
-- Uses the shared arcade wrapper (games/arcade.lua) for a monitor UI and credits.
-- Features: weighted virtual reels, animated spin frames in onTick, adjustable bet,
-- multi-line slot window with colored icons, and win flashes/sounds when possible.

local arcade = require("games.arcade")

-- Optional: play celebratory sounds if a speaker peripheral is attached.
local speaker = peripheral and peripheral.find and peripheral.find("speaker") or nil

local function playSound(note, vol)
        if speaker and speaker.playNote then
                speaker.playNote(note or "pling", vol or 1)
        end
end

-- Symbol definitions with weights and payouts (multipliers on the bet).
local symbolDefs = {
        { id = "cherry", icon = "@", color = colors.red,       weight = 8, pay3 = 6, pay2 = 1 },
        { id = "lemon",  icon = "O", color = colors.yellow,    weight = 7, pay3 = 5, pay2 = 1 },
        { id = "plum",   icon = "P", color = colors.magenta,  weight = 6, pay3 = 7, pay2 = 2 },
        { id = "bar",    icon = "#", color = colors.gray,     weight = 5, pay3 = 10, pay2 = 3 },
        { id = "diamond",icon = "*", color = colors.cyan,     weight = 3, pay3 = 14, pay2 = 4 },
        { id = "seven",  icon = "7", color = colors.orange,   weight = 2, pay3 = 20, pay2 = 5 },
}

local symbolLookup = {}
for _, def in ipairs(symbolDefs) do symbolLookup[def.id] = def end

-- Paylines to evaluate (row/col pairs). Three horizontal + two diagonals.
local paylines = {
        { {r=1,c=1}, {r=1,c=2}, {r=1,c=3} },
        { {r=2,c=1}, {r=2,c=2}, {r=2,c=3} },
        { {r=3,c=1}, {r=3,c=2}, {r=3,c=3} },
        { {r=1,c=1}, {r=2,c=2}, {r=3,c=3} },
        { {r=3,c=1}, {r=2,c=2}, {r=1,c=3} },
}

-- Game state table keeps timing and reel info together.
local state = {
        reels = {},
        reelPositions = {1,1,1},
        targetStops = {1,1,1},
        stopTimes = {0,0,0},
        spinning = false,
        reelLocked = {false,false,false},
        time = 0,
        betSteps = {1,2,5,10},
        betIndex = 1,
        message = "Spin to win!",
        lastWins = {},
        flashTimer = 0,
        flashVisible = false,
}

local function buildReel()
        local reel = {}
        for _, def in ipairs(symbolDefs) do
                for _ = 1, def.weight do table.insert(reel, def.id) end
        end
        -- Shuffle to avoid identical strips per reel.
        for i = #reel, 2, -1 do
                local j = math.random(i)
                reel[i], reel[j] = reel[j], reel[i]
        end
        return reel
end

local function wrapIndex(idx, len)
        local m = (idx - 1) % len
        return m + 1
end

local function currentWindow()
        -- Returns a 3x3 grid of symbols centered on reelPositions.
        local grid = {}
        for r = 1, 3 do grid[r] = {} end
        for col = 1, 3 do
                local reel = state.reels[col]
                local len = #reel
                local center = state.reelPositions[col]
                for rowOffset = -1, 1 do
                        local row = rowOffset + 2 -- map -1/0/1 to 1/2/3
                        grid[row][col] = reel[wrapIndex(center + rowOffset, len)]
                end
        end
        return grid
end

local function pickWeightedStop(reel)
        return math.random(#reel)
end

local function resetFlash()
        state.flashTimer = 0
        state.flashVisible = false
end

local function summarizeWins(totalWin)
        if totalWin <= 0 then return "No win" end
        local summary = {}
        for _, win in ipairs(state.lastWins) do
                table.insert(summary, string.format("Line %d %s x%d", win.line, win.symbol:upper(), win.amount))
        end
        return table.concat(summary, "  ")
end

local function scoreSpin(adapter)
        state.lastWins = {}
        local grid = currentWindow()
        local totalWin = 0
        for i, line in ipairs(paylines) do
                local a = grid[line[1].r][line[1].c]
                local b = grid[line[2].r][line[2].c]
                local c = grid[line[3].r][line[3].c]
                if a == b and b == c then
                        local def = symbolLookup[a]
                        local win = state.betSteps[state.betIndex] * def.pay3
                        totalWin = totalWin + win
                        table.insert(state.lastWins, { line = i, symbol = def.icon, amount = def.pay3 })
                elseif a == b or b == c or a == c then
                        -- Small consolation for pairs.
                        local pairId = a == b and a or b == c and b or a
                        local def = symbolLookup[pairId]
                        local win = state.betSteps[state.betIndex] * def.pay2
                        totalWin = totalWin + win
                        table.insert(state.lastWins, { line = i, symbol = def.icon, amount = def.pay2 })
                end
        end
        if totalWin > 0 then
                adapter:addCredits(totalWin)
                state.message = string.format("WIN! +%d credits (%s)", totalWin, summarizeWins(totalWin))
                state.flashTimer = 3
                playSound("bell", 1)
        else
                state.message = "Better luck next time"
        end
end

local function canSpin(adapter)
        return not state.spinning and adapter:getCredits() >= state.betSteps[state.betIndex]
end

local function refreshButtons(adapter)
        local leftLabel = state.spinning and "Spinning" or ("Spin (" .. state.betSteps[state.betIndex] .. ")")
        local centerLabel = state.spinning and "Bet+" or ("Bet+ -> " .. state.betSteps[state.betIndex])
        local rightLabel = state.spinning and "CashOut" or "CashOut"
        adapter:setButtons({ leftLabel, centerLabel, rightLabel }, { canSpin(adapter), not state.spinning, true })
end

local function startSpin(adapter)
        if state.spinning then return end
        local bet = state.betSteps[state.betIndex]
        if not adapter:consumeCredits(bet) then
                state.message = string.format("Need %d credits to spin", bet)
                resetFlash()
                refreshButtons(adapter)
                return
        end
        state.spinning = true
        state.reelLocked = {false,false,false}
        state.time = 0
        resetFlash()
        for i = 1, 3 do
                state.targetStops[i] = pickWeightedStop(state.reels[i])
                state.stopTimes[i] = (i * 0.6) -- staggered stops
        end
        state.message = "Reels spinning..."
        refreshButtons(adapter)
        playSound("pling", 0.8)
end

local function updateSpin(dt, adapter)
        if not state.spinning then
                if state.flashTimer > 0 then
                        state.flashTimer = math.max(0, state.flashTimer - dt)
                        if state.flashTimer > 0 then
                                state.flashVisible = not state.flashVisible
                        else
                                state.flashVisible = false
                        end
                end
                return
        end
        state.time = state.time + dt
        local allLocked = true
        for i = 1, 3 do
                local reel = state.reels[i]
                local len = #reel
                if not state.reelLocked[i] then
                        state.reelPositions[i] = wrapIndex(state.reelPositions[i] + 1, len)
                        if state.time >= state.stopTimes[i] then
                                state.reelPositions[i] = state.targetStops[i]
                                state.reelLocked[i] = true
                                playSound("pling", 0.5 + i * 0.1)
                        end
                end
                allLocked = allLocked and state.reelLocked[i]
        end
        if allLocked then
                                state.spinning = false
                                scoreSpin(adapter)
                                refreshButtons(adapter)
        end
end

local function drawPayoutTable()
        local _, screenH = term.getSize()
        local startY = math.max(8, screenH - 8)
        term.setTextColor(colors.lightGray)
        term.setCursorPos(2, startY)
        term.write("Payouts (xBet):")
        for idx, def in ipairs(symbolDefs) do
                term.setCursorPos(2, startY + idx)
                term.setTextColor(def.color)
                term.write(string.format(" %s%s 3=%d 2=%d", def.icon, def.id:sub(1,1), def.pay3, def.pay2))
        end
        term.setTextColor(colors.white)
end

local function drawWindow(grid)
        local w = term.getSize()
        local windowWidth = 3 * 4 + 1 -- columns plus separators
        local left = math.floor((w - windowWidth) / 2)
        local top = 3
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.setCursorPos(left, top)
        term.write("+---+---+---+")
        for row = 1, 3 do
                term.setCursorPos(left, top + (row * 1) + (row - 1))
                term.write("|   |   |   |")
                term.setCursorPos(left, top + row * 2)
                term.write("+---+---+---+")
        end
        -- Fill symbols (two lines inside each row block)
        for row = 1, 3 do
                for col = 1, 3 do
                        local symbolId = grid[row][col]
                        local def = symbolLookup[symbolId]
                        local x = left + 2 + (col - 1) * 4
                        local y = top + (row - 1) * 2 + 1
                        term.setCursorPos(x, y)
                        local highlight = false
                        for _, win in ipairs(state.lastWins) do
                                local line = paylines[win.line]
                                for _, cell in ipairs(line) do
                                        if cell.r == row and cell.c == col and state.flashVisible then
                                                highlight = true
                                        end
                                end
                        end
                        if highlight then
                                term.setBackgroundColor(colors.green)
                                term.setTextColor(colors.black)
                        else
                                term.setBackgroundColor(colors.black)
                                term.setTextColor(def and def.color or colors.white)
                        end
                        term.write(def and def.icon or "?")
                        term.setBackgroundColor(colors.black)
                end
        end
end

local function draw(adapter)
        adapter:clearPlayfield(colors.black, colors.white)
        local creditsText = string.format("Credits: %d", adapter:getCredits())
        local betText = string.format("Bet: %d", state.betSteps[state.betIndex])
        adapter:centerPrint(1, "Slots", colors.white)
        adapter:centerPrint(2, creditsText .. "  |  " .. betText, colors.lightGray)
        local grid = currentWindow()
        drawWindow(grid)
        local _, screenH = term.getSize()
        local playfieldBottom = screenH - 3
        local messageY = math.min(playfieldBottom, 11)
        adapter:centerPrint(messageY, state.message, colors.yellow)
        drawPayoutTable()
end

local game = {
        name = "Slots",
        init = function(a)
                math.randomseed(os.epoch and os.epoch("utc") or os.clock())
                state.reels = { buildReel(), buildReel(), buildReel() }
                state.reelPositions = { math.random(#state.reels[1]), math.random(#state.reels[2]), math.random(#state.reels[3]) }
                refreshButtons(a)
        end,
        draw = function(a)
                draw(a)
        end,
        onButton = function(a, which)
                if which == "left" then
                        startSpin(a)
                elseif which == "center" then
                        if not state.spinning then
                                state.betIndex = state.betIndex % #state.betSteps + 1
                                state.message = string.format("Bet set to %d", state.betSteps[state.betIndex])
                                refreshButtons(a)
                        end
                elseif which == "right" then
                        a:requestQuit()
                end
        end,
        onTick = function(a, dt)
                updateSpin(dt, a)
                refreshButtons(a)
                draw(a)
        end,
}

arcade.start(game, { tickSeconds = 0.15 })
