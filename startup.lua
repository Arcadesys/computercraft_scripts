-- Simple Windows-like OS for ComputerCraft
-- Style: Early Windows (95/98 ish)

local w, h = term.getSize()
local running = true
local menuOpen = false

-- Colors
local DESKTOP_COLOR = colors.cyan
local TASKBAR_COLOR = colors.lightGray
local WINDOW_BG_COLOR = colors.white
local TITLE_BAR_COLOR = colors.blue
local TITLE_TEXT_COLOR = colors.white

-- Music helpers
local NOTE_INSTRUMENTS = {
    "harp", "bass", "snare", "hat", "basedrum", "bell", "flute",
    "chime", "guitar", "xylophone", "iron_xylophone", "cow_bell",
    "didgeridoo", "bit", "banjo", "pling"
}
local TRACK_COLORS = { colors.orange, colors.green, colors.purple, colors.blue }
local MIN_PITCH, MAX_PITCH = 0, 24
local MIN_LENGTH, MAX_LENGTH = 1, 8

local function buildDefaultStep()
    return {
        active = false,
        pitch = 12,
        length = 1
    }
end

-- Sequencer State
local sequencer = {
    tracks = {},
    currentStep = 1,
    interval = 0.2,
    playing = true,
    timerId = nil,
    selectedTrack = 1,
    selectedStep = 1,
    sustain = {},
    uiControls = {}
}

for trackIdx = 1, 4 do
    local track = {
        instrumentIndex = ((trackIdx - 1) % #NOTE_INSTRUMENTS) + 1,
        steps = {}
    }
    for step = 1, 16 do
        local cell = buildDefaultStep()
        if step == 1 and trackIdx == 1 then
            cell.active = true
        end
        track.steps[step] = cell
    end
    sequencer.tracks[trackIdx] = track
    sequencer.sustain[trackIdx] = { remaining = 0, pitch = 12, instrument = NOTE_INSTRUMENTS[track.instrumentIndex] }
end

local speaker = peripheral.find("speaker")

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function registerSequencerButton(name, x, y, width)
    sequencer.uiControls[name] = {
        x = x,
        y = y,
        width = width or 3
    }
end

local function pointInControl(control, x, y)
    if not control then return false end
    return y == control.y and x >= control.x and x <= (control.x + control.width - 1)
end

-- State
local windows = {
    {
        id = 1,
        title = "Welcome",
        x = 3,
        y = 3,
        width = 20,
        height = 8,
        visible = true,
        dragging = false
    },
    {
        id = 2,
        title = "Notepad",
        x = 26,
        y = 4,
        width = 18,
        height = 10,
        visible = true,
        dragging = false
    },
    {
        id = 3,
        title = "Sequencer",
        x = 4,
        y = 11,
        width = 48,
        height = 12,
        visible = true,
        dragging = false
    }
}

local function drawDesktop()
    term.setBackgroundColor(DESKTOP_COLOR)
    term.clear()
end

local function drawTaskbar()
    term.setCursorPos(1, h)
    term.setBackgroundColor(TASKBAR_COLOR)
    term.clearLine()
    
    -- Start Button
    term.setCursorPos(2, h)
    if menuOpen then
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
    else
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.black)
    end
    term.write(" Start ")
end

local function drawStartMenu()
    if not menuOpen then return end
    
    local menuWidth = 12
    local menuHeight = 6
    local startX = 1
    local startY = h - menuHeight
    
    paintutils.drawFilledBox(startX, startY, startX + menuWidth - 1, h - 1, colors.lightGray)
    
    term.setTextColor(colors.black)
    term.setCursorPos(startX + 1, startY + 1)
    term.write("Programs")
    term.setCursorPos(startX + 1, startY + 2)
    term.write("Settings")
    term.setCursorPos(startX + 1, startY + 4)
    term.write("Shutdown")
end

local function drawWindow(win)
    if not win.visible then return end
    
    -- Draw Frame/Background
    paintutils.drawFilledBox(win.x, win.y, win.x + win.width - 1, win.y + win.height - 1, WINDOW_BG_COLOR)
    
    -- Draw Title Bar
    paintutils.drawFilledBox(win.x, win.y, win.x + win.width - 1, win.y, TITLE_BAR_COLOR)
    term.setCursorPos(win.x + 1, win.y)
    term.setTextColor(TITLE_TEXT_COLOR)
    term.setBackgroundColor(TITLE_BAR_COLOR)
    term.write(win.title)
    
    -- Close Button (X)
    term.setCursorPos(win.x + win.width - 2, win.y)
    term.setBackgroundColor(colors.red)
    term.write("X")
    
    -- Content
    term.setBackgroundColor(WINDOW_BG_COLOR)
    term.setTextColor(colors.black)
    
    if win.title == "Sequencer" then
        sequencer.uiControls = {}
        local gridStartX = win.x + 11
        local gridStartY = win.y + 2
        for trackIdx = 1, #sequencer.tracks do
            local track = sequencer.tracks[trackIdx]
            local rowY = gridStartY + (trackIdx - 1) * 2
            term.setBackgroundColor(WINDOW_BG_COLOR)
            term.setCursorPos(win.x + 1, rowY)
            local name = NOTE_INSTRUMENTS[track.instrumentIndex]
            term.write(string.format("T%d %s", trackIdx, name))
            for stepIdx = 1, 16 do
                local cell = track.steps[stepIdx]
                local color = cell.active and (TRACK_COLORS[trackIdx] or colors.lightGray) or colors.lightGray
                if stepIdx == sequencer.currentStep then
                    color = cell.active and colors.lime or colors.yellow
                end
                if sequencer.selectedTrack == trackIdx and sequencer.selectedStep == stepIdx then
                    color = colors.white
                end
                term.setBackgroundColor(color)
                term.setCursorPos(gridStartX + (stepIdx - 1) * 2, rowY)
                term.write("  ")
            end
        end
        local infoY = gridStartY + (#sequencer.tracks * 2) + 1
        local selectedTrack = sequencer.tracks[sequencer.selectedTrack]
        local selectedStep = selectedTrack.steps[sequencer.selectedStep]
        term.setBackgroundColor(WINDOW_BG_COLOR)
        term.setCursorPos(win.x + 1, infoY)
        term.write(string.format("Selected: T%d S%02d", sequencer.selectedTrack, sequencer.selectedStep))
        local instrumentName = NOTE_INSTRUMENTS[selectedTrack.instrumentIndex]
        local instLineY = infoY + 1
        term.setCursorPos(win.x + 1, instLineY)
        term.write("Instrument: " .. instrumentName)
        local instMinusX = win.x + 25
        term.setCursorPos(instMinusX, instLineY)
        term.write("[-]")
        registerSequencerButton("instrumentMinus", instMinusX, instLineY)
        local instPlusX = instMinusX + 4
        term.setCursorPos(instPlusX, instLineY)
        term.write("[+]")
        registerSequencerButton("instrumentPlus", instPlusX, instLineY)
        local pitchLineY = instLineY + 1
        term.setCursorPos(win.x + 1, pitchLineY)
        term.write(string.format("Pitch: %02d", selectedStep.pitch))
        local pitchMinusX = win.x + 16
        term.setCursorPos(pitchMinusX, pitchLineY)
        term.write("[-]")
        registerSequencerButton("pitchMinus", pitchMinusX, pitchLineY)
        local pitchPlusX = pitchMinusX + 4
        term.setCursorPos(pitchPlusX, pitchLineY)
        term.write("[+]")
        registerSequencerButton("pitchPlus", pitchPlusX, pitchLineY)
        local lenLabelX = win.x + 26
        term.setCursorPos(lenLabelX, pitchLineY)
        term.write(string.format("Length: %d", selectedStep.length))
        local lenMinusX = lenLabelX + 11
        term.setCursorPos(lenMinusX, pitchLineY)
        term.write("[-]")
        registerSequencerButton("lengthMinus", lenMinusX, pitchLineY)
        local lenPlusX = lenMinusX + 4
        term.setCursorPos(lenPlusX, pitchLineY)
        term.write("[+]")
        registerSequencerButton("lengthPlus", lenPlusX, pitchLineY)
        term.setCursorPos(win.x + 1, pitchLineY + 1)
        term.write("Left click step = toggle & select | Right click = select")
    else
        term.setCursorPos(win.x + 1, win.y + 2)
        term.write("Hello World!")
    end
end

local function draw()
    drawDesktop()
    
    for _, win in ipairs(windows) do -- Draw bottom to top (1 to N)
        drawWindow(win)
    end
    
    drawTaskbar()
    drawStartMenu()
end

local function handleClick(button, x, y)
    -- Check Start Button
    if y == h and x >= 2 and x <= 8 then
        menuOpen = not menuOpen
        return
    end
    
    -- Check Start Menu
    if menuOpen then
        local menuWidth = 12
        local menuHeight = 6
        if x <= menuWidth and y >= h - menuHeight and y < h then
            -- Menu click handling would go here
            if y == h - 2 then -- Shutdown position roughly
                 running = false
            end
            menuOpen = false
            return
        else
            menuOpen = false -- Clicked outside menu
        end
    end
    
    -- Check Windows (Top to Bottom -> N to 1)
    local clickedWindowIndex = nil
    for i = #windows, 1, -1 do
        local win = windows[i]
        if win.visible and x >= win.x and x < win.x + win.width and y >= win.y and y < win.y + win.height then
            clickedWindowIndex = i
            
            -- Title bar click (Dragging)
            if y == win.y then
                -- Check Close Button
                if x >= win.x + win.width - 2 then
                    win.visible = false
                    clickedWindowIndex = nil -- Don't bring to front if closed
                else
                    win.dragging = true
                    win.dragOffsetX = x - win.x
                    win.dragOffsetY = y - win.y
                end
            elseif win.title == "Sequencer" then
                local gridStartX = win.x + 11
                local gridStartY = win.y + 2
                for trackIdx = 1, #sequencer.tracks do
                    local rowY = gridStartY + (trackIdx - 1) * 2
                    if y == rowY then
                        if x >= gridStartX and x < gridStartX + 32 then
                            local step = math.floor((x - gridStartX) / 2) + 1
                            step = clamp(step, 1, 16)
                            sequencer.selectedTrack = trackIdx
                            sequencer.selectedStep = step
                            if button == 1 then
                                local cell = sequencer.tracks[trackIdx].steps[step]
                                cell.active = not cell.active
                            end
                            break
                        elseif x >= win.x + 1 and x < gridStartX then
                            -- Clicked on track label -> select track
                            sequencer.selectedTrack = trackIdx
                            break
                        end
                    end
                end
            end
            break -- Found the top-most window under cursor
        end
    end

    -- Bring to front
    if clickedWindowIndex then
        local win = table.remove(windows, clickedWindowIndex)
        table.insert(windows, win)
    end

    -- Sequencer controls outside grid (buttons)
    if clickedWindowIndex and windows[#windows] and windows[#windows].title == "Sequencer" then
        local selectedTrack = sequencer.tracks[sequencer.selectedTrack]
        local selectedStep = selectedTrack.steps[sequencer.selectedStep]
        if pointInControl(sequencer.uiControls.instrumentMinus, x, y) then
            selectedTrack.instrumentIndex = selectedTrack.instrumentIndex - 1
            if selectedTrack.instrumentIndex < 1 then
                selectedTrack.instrumentIndex = #NOTE_INSTRUMENTS
            end
        elseif pointInControl(sequencer.uiControls.instrumentPlus, x, y) then
            selectedTrack.instrumentIndex = selectedTrack.instrumentIndex + 1
            if selectedTrack.instrumentIndex > #NOTE_INSTRUMENTS then
                selectedTrack.instrumentIndex = 1
            end
        elseif pointInControl(sequencer.uiControls.pitchMinus, x, y) then
            selectedStep.pitch = clamp(selectedStep.pitch - 1, MIN_PITCH, MAX_PITCH)
        elseif pointInControl(sequencer.uiControls.pitchPlus, x, y) then
            selectedStep.pitch = clamp(selectedStep.pitch + 1, MIN_PITCH, MAX_PITCH)
        elseif pointInControl(sequencer.uiControls.lengthMinus, x, y) then
            selectedStep.length = clamp(selectedStep.length - 1, MIN_LENGTH, MAX_LENGTH)
        elseif pointInControl(sequencer.uiControls.lengthPlus, x, y) then
            selectedStep.length = clamp(selectedStep.length + 1, MIN_LENGTH, MAX_LENGTH)
        end
    end
end

local function handleDrag(button, x, y)
    for _, win in ipairs(windows) do
        if win.dragging then
            win.x = x - win.dragOffsetX
            win.y = y - win.dragOffsetY
        end
    end
end

local function handleRelease(button, x, y)
    for _, win in ipairs(windows) do
        win.dragging = false
    end
end

-- Start timer
sequencer.timerId = os.startTimer(sequencer.interval)

-- Main Loop
while running do
    draw()
    
    local event, p1, p2, p3 = os.pullEvent()
    
        if event == "timer" and p1 == sequencer.timerId then
            if sequencer.playing then
                sequencer.currentStep = sequencer.currentStep + 1
                if sequencer.currentStep > 16 then sequencer.currentStep = 1 end
                for idx, track in ipairs(sequencer.tracks) do
                    local sustain = sequencer.sustain[idx]
                    if sustain and sustain.remaining > 0 then
                        if speaker and sustain.instrument then
                            speaker.playNote(sustain.instrument, 1, sustain.pitch)
                        end
                        sustain.remaining = sustain.remaining - 1
                    end
                    local cell = track.steps[sequencer.currentStep]
                    if cell.active then
                        local instrument = NOTE_INSTRUMENTS[track.instrumentIndex]
                        if speaker then
                            speaker.playNote(instrument, 1, cell.pitch)
                        end
                        sustain.remaining = math.max(cell.length - 1, 0)
                        sustain.pitch = cell.pitch
                        sustain.instrument = instrument
                    end
                end
            end
            sequencer.timerId = os.startTimer(sequencer.interval)
    elseif event == "mouse_click" then
        handleClick(p1, p2, p3)
    elseif event == "mouse_drag" then
        handleDrag(p1, p2, p3)
    elseif event == "mouse_up" then
        handleRelease(p1, p2, p3)
    elseif event == "key" then
        -- Optional key handling
    end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("OS Shutdown.")
