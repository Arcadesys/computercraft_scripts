---@diagnostic disable: undefined-global, undefined-field

local NOTE_INSTRUMENTS = {
    "harp", "bass", "snare", "hat", "basedrum", "bell", "flute",
    "chime", "guitar", "xylophone", "iron_xylophone", "cow_bell",
    "didgeridoo", "bit", "banjo", "pling"
}

local bit32 = bit32 or error("ComputerCraft bit32 API is required")
local fs = fs or error("ComputerCraft fs API is required")
local term = term or error("ComputerCraft term API is required")
local peripheral = peripheral or error("ComputerCraft peripheral API is required")
local read = read or error("read() is required")
local write = write or error("write() is required")
local os = os or error("ComputerCraft os API is required")

local MIN_PITCH, MAX_PITCH = 0, 24

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function midiNoteToPitch(note)
    return clamp((note or 0) - 54, MIN_PITCH, MAX_PITCH)
end

local function formatSeconds(value)
    value = math.max(value or 0, 0)
    local minutes = math.floor(value / 60)
    local seconds = math.floor(value % 60)
    return string.format("%02d:%02d", minutes, seconds)
end

local function bytesToNumber(str)
    local total = 0
    for i = 1, #str do
        total = total * 256 + str:byte(i)
    end
    return total
end

local function readVarLen(data, startPos)
    local value = 0
    local consumed = 0
    while true do
        local byte = data:byte(startPos + consumed)
        if not byte then
            error("Unexpected end of track while reading variable-length value")
        end
        consumed = consumed + 1
        value = bit32.bor(bit32.lshift(value, 7), bit32.band(byte, 0x7F))
        if bit32.band(byte, 0x80) == 0 then
            break
        end
    end
    return value, consumed
end

local function readByte(data, pos)
    local byte = data:byte(pos)
    if not byte then
        error("Unexpected end of track data")
    end
    return byte
end

local function parseTrackData(data)
    local idx = 1
    local len = #data
    local currentTick = 0
    local runningStatus
    local events = {}
    local tempoChanges = {}
    local channelPrograms = {}
    local activeNotes = {}

    while idx <= len do
        local delta, consumed = readVarLen(data, idx)
        idx = idx + consumed
        currentTick = currentTick + delta
        if idx > len then break end
        local statusByte = data:byte(idx)
        if not statusByte then break end
        if statusByte >= 0x80 then
            runningStatus = statusByte
            idx = idx + 1
        else
            statusByte = runningStatus
        end
        if not statusByte then
            error("Missing running status in MIDI track")
        end

        if statusByte == 0xFF then
            local metaType = readByte(data, idx)
            idx = idx + 1
            local length, count = readVarLen(data, idx)
            idx = idx + count
            local payload = data:sub(idx, idx + length - 1)
            if #payload < length then
                error("Truncated meta event in MIDI track")
            end
            idx = idx + length
            if metaType == 0x51 and length == 3 then
                table.insert(tempoChanges, { tick = currentTick, tempo = bytesToNumber(payload) })
            elseif metaType == 0x2F then
                break -- end of track
            end
        elseif statusByte == 0xF0 or statusByte == 0xF7 then
            local length, count = readVarLen(data, idx)
            idx = idx + count + length -- skip SysEx
        else
            local eventType = bit32.rshift(statusByte, 4)
            local channel = bit32.band(statusByte, 0x0F) + 1
            local param1 = readByte(data, idx)
            idx = idx + 1
            local param2 = nil
            if eventType ~= 0xC and eventType ~= 0xD then
                param2 = readByte(data, idx)
                idx = idx + 1
            end

            if eventType == 0x9 then -- Note On
                local velocity = param2 or 0
                if velocity > 0 then
                    activeNotes[channel] = activeNotes[channel] or {}
                    activeNotes[channel][param1] = { startTick = currentTick, velocity = velocity }
                else
                    local active = activeNotes[channel] and activeNotes[channel][param1]
                    if active then
                        local duration = math.max(currentTick - active.startTick, 1)
                        table.insert(events, {
                            channel = channel,
                            note = param1,
                            startTick = active.startTick,
                            durationTicks = duration,
                            velocity = active.velocity
                        })
                        activeNotes[channel][param1] = nil
                    end
                end
            elseif eventType == 0x8 then -- Note Off
                local active = activeNotes[channel] and activeNotes[channel][param1]
                if active then
                    local duration = math.max(currentTick - active.startTick, 1)
                    table.insert(events, {
                        channel = channel,
                        note = param1,
                        startTick = active.startTick,
                        durationTicks = duration,
                        velocity = active.velocity
                    })
                    activeNotes[channel][param1] = nil
                end
            elseif eventType == 0xC then -- Program change
                channelPrograms[channel] = param1
            end
        end
    end

    for channel, notes in pairs(activeNotes) do
        for note, info in pairs(notes) do
            table.insert(events, {
                channel = channel,
                note = note,
                startTick = info.startTick,
                durationTicks = 30,
                velocity = info.velocity
            })
        end
    end

    return events, tempoChanges, channelPrograms
end

local function buildTempoTimeline(tempoChanges, ticksPerQuarter)
    local timeline = {}
    if #tempoChanges == 0 then
        table.insert(timeline, { tick = 0, tempo = 500000 })
    else
        table.sort(tempoChanges, function(a, b) return a.tick < b.tick end)
        if tempoChanges[1].tick ~= 0 then
            table.insert(timeline, { tick = 0, tempo = 500000 })
        end
        for _, change in ipairs(tempoChanges) do
            local last = timeline[#timeline]
            if last and last.tick == change.tick then
                last.tempo = change.tempo
            else
                table.insert(timeline, { tick = change.tick, tempo = change.tempo })
            end
        end
    end

    timeline[1].secondsAtTick = 0
    for i = 2, #timeline do
        local prev = timeline[i - 1]
        local current = timeline[i]
        local microsPerTick = (prev.tempo or 500000) / ticksPerQuarter
        local deltaTicks = math.max(current.tick - prev.tick, 0)
        current.secondsAtTick = (prev.secondsAtTick or 0) + (deltaTicks * microsPerTick / 1000000)
    end

    return timeline
end

local function stampEventTimes(events, timeline, ticksPerQuarter)
    table.sort(events, function(a, b)
        if a.startTick == b.startTick then
            return a.channel < b.channel
        end
        return a.startTick < b.startTick
    end)

    local idx = 1
    local totalSeconds = 0
    for _, event in ipairs(events) do
        while idx < #timeline and event.startTick >= timeline[idx + 1].tick do
            idx = idx + 1
        end
        local tempo = timeline[idx]
        local microsPerTick = (tempo.tempo or 500000) / ticksPerQuarter
        local baseSeconds = tempo.secondsAtTick or 0
        local deltaTicks = math.max(event.startTick - tempo.tick, 0)
        event.startSeconds = baseSeconds + (deltaTicks * microsPerTick / 1000000)
        event.durationSeconds = math.max(event.durationTicks, 1) * microsPerTick / 1000000
        local finish = event.startSeconds + event.durationSeconds
        if finish > totalSeconds then
            totalSeconds = finish
        end
    end

    return totalSeconds
end

local function parseMidiFile(path)
    local function parse()
        local handle = fs.open(path, "rb") or fs.open(path, "r")
        if not handle then
            error("Unable to open file: " .. path)
        end
        local content = handle.readAll()
        handle.close()
        if not content or #content == 0 then
            error("File is empty")
        end

        local cursor = 1
        local function readBytes(count)
            if cursor + count - 1 > #content then
                error("Unexpected end of file while reading chunk")
            end
            local slice = content:sub(cursor, cursor + count - 1)
            cursor = cursor + count
            return slice
        end

        local function readUInt16()
            local bytes = readBytes(2)
            return bytes:byte(1) * 256 + bytes:byte(2)
        end

        local function readUInt32()
            local bytes = readBytes(4)
            return ((bytes:byte(1) * 256 + bytes:byte(2)) * 256 + bytes:byte(3)) * 256 + bytes:byte(4)
        end

        local headerId = readBytes(4)
        if headerId ~= "MThd" then
            error("Not a MIDI file (missing MThd header)")
        end
        local headerLength = readUInt32()
        local headerData = readBytes(headerLength)
        if #headerData < 6 then
            error("Corrupt MIDI header")
        end

        local format = headerData:byte(1) * 256 + headerData:byte(2)
        local trackCount = headerData:byte(3) * 256 + headerData:byte(4)
        local division = headerData:byte(5) * 256 + headerData:byte(6)
        if bit32.band(division, 0x8000) ~= 0 then
            division = 480 -- fallback when SMPTE timing is used
        end
        if division <= 0 then
            division = 480
        end

        local events = {}
        local tempoChanges = { { tick = 0, tempo = 500000 } }
        local channelPrograms = {}

        for _ = 1, trackCount do
            if cursor > #content then break end
            local chunkId = readBytes(4)
            local chunkLength = readUInt32()
            local chunkData = readBytes(chunkLength)
            if chunkId == "MTrk" then
                local trackEvents, trackTempos, trackProgs = parseTrackData(chunkData)
                for _, ev in ipairs(trackEvents) do table.insert(events, ev) end
                for _, tempo in ipairs(trackTempos) do table.insert(tempoChanges, tempo) end
                for channel, program in pairs(trackProgs) do channelPrograms[channel] = program end
            end
        end

        if #events == 0 then
            error("The MIDI file does not contain any note data")
        end

        local timeline = buildTempoTimeline(tempoChanges, division)
        local totalSeconds = stampEventTimes(events, timeline, division)
        local channelSet = {}
        for _, ev in ipairs(events) do channelSet[ev.channel] = true end
        local channelList = {}
        for channel in pairs(channelSet) do table.insert(channelList, channel) end
        table.sort(channelList)
        if #channelList == 0 then
            channelList[1] = 1
        end

        return {
            format = format,
            events = events,
            tempoChanges = timeline,
            ticksPerQuarter = division,
            totalSeconds = totalSeconds,
            channelPrograms = channelPrograms,
            channelList = channelList
        }
    end

    local ok, result = pcall(parse)
    if ok then
        return result
    end
    return nil, tostring(result)
end

local function listMidiFiles(directory)
    local files = {}
    if not fs.exists(directory) then
        return files
    end
    for _, name in ipairs(fs.list(directory)) do
        local fullPath = fs.combine(directory, name)
        if not fs.isDir(fullPath) and name:lower():match("%.mid$") then
            table.insert(files, name)
        end
    end
    table.sort(files)
    return files
end

local function chooseMidiFile(libraryPath, providedPath)
    if providedPath then
        if fs.exists(providedPath) then
            return providedPath
        end
        local fallback = fs.combine(libraryPath, providedPath)
        if fs.exists(fallback) then
            return fallback
        end
        return nil, "File not found: " .. providedPath
    end

    if not fs.exists(libraryPath) then
        fs.makeDir(libraryPath)
    end

    local files = listMidiFiles(libraryPath)
    if #files == 0 then
        return nil, "No .mid files found in /" .. libraryPath
    end

    print("Select a MIDI file to play:")
    for i, name in ipairs(files) do
        print(string.format(" %d) %s", i, name))
    end
    write("Enter number: ")
    local selection = tonumber(read())
    if not selection or selection < 1 or selection > #files then
        return nil, "Invalid selection"
    end

    return fs.combine(libraryPath, files[selection])
end

local function promptInstrumentMapping(channelList)
    if not channelList or #channelList == 0 then
        channelList = { 1 }
    end

    print("Available ComputerCraft instruments:")
    for i, name in ipairs(NOTE_INSTRUMENTS) do
        print(string.format(" %2d) %s", i, name))
    end

    local mapping = {}
    for _, channel in ipairs(channelList) do
        local defaultIndex = ((channel - 1) % #NOTE_INSTRUMENTS) + 1
        while true do
            write(string.format("Channel %02d instrument [%s]: ", channel, NOTE_INSTRUMENTS[defaultIndex]))
            local input = read()
            if not input or input == "" then
                mapping[channel] = NOTE_INSTRUMENTS[defaultIndex]
                break
            end
            local numericIndex = tonumber(input)
            if numericIndex and NOTE_INSTRUMENTS[numericIndex] then
                mapping[channel] = NOTE_INSTRUMENTS[numericIndex]
                break
            end
            local lowered = input:lower()
            local matched
            for _, name in ipairs(NOTE_INSTRUMENTS) do
                if name == lowered then
                    matched = name
                    break
                end
            end
            if matched then
                mapping[channel] = matched
                break
            end
            print("Invalid instrument. Type a number from the list or an instrument name.")
        end
    end

    return mapping
end

local function playSong(midi, instrumentMap, shouldLoop, speaker)
    local interval = 0.05
    local timerId = nil
    local playing = true
    local eventIndex = 1
    local sustain = {}
    local playStart = 0
    local statusY
    local lastProgress = -1

    local function resetPlayback()
        eventIndex = 1
        sustain = {}
        playStart = os.clock()
    end

    local function updateProgress(elapsed)
        if not statusY then
            local _, cursorY = term.getCursorPos()
            statusY = cursorY + 1
        end
        if math.floor(elapsed) == lastProgress then return end
        lastProgress = math.floor(elapsed)
        term.setCursorPos(1, statusY)
        term.clearLine()
        term.write(string.format("Progress %s / %s", formatSeconds(elapsed), formatSeconds(midi.totalSeconds)))
    end

    resetPlayback()
    timerId = os.startTimer(interval)
    print("Playing... press Ctrl+T to stop")

    while playing do
        local event, param1 = os.pullEvent()
        if event == "timer" and param1 == timerId then
            local elapsed = os.clock() - playStart
            updateProgress(elapsed)

            while eventIndex <= #midi.events do
                local ev = midi.events[eventIndex]
                if ev.startSeconds <= elapsed then
                    local instrument = instrumentMap[ev.channel] or NOTE_INSTRUMENTS[1]
                    local pitch = midiNoteToPitch(ev.note)
                    speaker.playNote(instrument, 1, pitch)
                    local sustainFrames = math.max(math.floor(ev.durationSeconds / interval), 1)
                    sustain[ev.channel] = {
                        remaining = sustainFrames - 1,
                        instrument = instrument,
                        pitch = pitch
                    }
                    eventIndex = eventIndex + 1
                else
                    break
                end
            end

            for channel, info in pairs(sustain) do
                if info.remaining and info.remaining > 0 then
                    speaker.playNote(info.instrument, 1, info.pitch)
                    info.remaining = info.remaining - 1
                end
            end

            if eventIndex > #midi.events then
                local active = false
                for _, info in pairs(sustain) do
                    if info.remaining and info.remaining > 0 then
                        active = true
                        break
                    end
                end
                if not active then
                    if shouldLoop then
                        print("Looping...")
                        resetPlayback()
                    else
                        playing = false
                        updateProgress(midi.totalSeconds)
                        print("\nPlayback finished.")
                    end
                end
            end

            if playing then
                timerId = os.startTimer(interval)
            end
        elseif event == "terminate" then
            print("\nPlayback stopped by user.")
            return
        end
    end
end

local function main(...)
    local args = { ... }
    local requestedPath
    local loopFlag = false
    for _, arg in ipairs(args) do
        if arg == "--loop" or arg == "-l" then
            loopFlag = true
        elseif not requestedPath then
            requestedPath = arg
        end
    end

    local libraryPath = "midi"
    local midiPath, pathErr = chooseMidiFile(libraryPath, requestedPath)
    if not midiPath then
        print(pathErr)
        return
    end

    local midi, err = parseMidiFile(midiPath)
    if not midi then
        print("Failed to load MIDI: " .. err)
        return
    end

    print(string.format("Loaded %s (%d events, %s long)", midiPath, #midi.events, formatSeconds(midi.totalSeconds)))
    local instrumentMap = promptInstrumentMapping(midi.channelList)

    if not loopFlag then
        write("Loop playback? (y/N): ")
        local resp = read()
        if resp and resp:lower():sub(1, 1) == "y" then
            loopFlag = true
        end
    end

    local speaker = peripheral.find("speaker")
    if not speaker then
        print("No speaker peripheral detected. Attach at least one speaker and try again.")
        return
    end

    print("Instrument routing:")
    for _, channel in ipairs(midi.channelList) do
        print(string.format(" Ch%02d -> %s", channel, instrumentMap[channel] or NOTE_INSTRUMENTS[1]))
    end

    playSong(midi, instrumentMap, loopFlag, speaker)
end

main(...)
