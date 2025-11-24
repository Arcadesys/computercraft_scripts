---@diagnostic disable: undefined-global, undefined-field
-- arcadeos.lua
-- A lightweight "desktop" shell that lists available arcade games and launches
-- them. Games are regular Lua programs that ultimately call arcade.start(...) to
-- render inside the shared arcade adapter.
--
-- Lua Tip: Small tables holding related data (like the registry entries below)
-- keep code organized without needing classes. You can copy a table with a
-- helper if you want to mutate it without touching the original definition.

local registry = {
        { name = "Blackjack", path = "blackjack.lua", metadata = { genre = "Cards", blurb = "Beat the dealer to 21." } },
        { name = "IdleCraft", path = "idlecraft.lua", metadata = { genre = "Idle", blurb = "Incremental crafting clicks." } },
        { name = "Poker", path = "poker.lua", metadata = { genre = "Cards", blurb = "Texas Hold'em against bots." } },
        { name = "Slots", path = "slots.lua", metadata = { genre = "Casino", blurb = "Spin to win credits." } },
        -- Add more entries here as new arcade-enabled games are written.
}

local session = {
        programs = {},
        selectedIndex = 1,
        status = "Use arrow keys to pick a game, Enter to launch, R to rescan, Q to exit.",
}

local function shallowCopy(tbl)
        local out = {}
        for k, v in pairs(tbl) do out[k] = v end
        return out
end

local function normalizePath(entry)
        -- Accept registry entries with or without the .lua suffix to reduce typos.
        if entry.path:sub(-4) == ".lua" then return entry.path end
        return entry.path .. ".lua"
end

local function discoverPrograms()
        local found = {}
        for _, entry in ipairs(registry) do
                local candidate = normalizePath(entry)
                if fs.exists(candidate) then
                        local copy = shallowCopy(entry)
                        copy.path = candidate
                        copy.installed = true
                        table.insert(found, copy)
                end
        end
        table.sort(found, function(a, b) return a.name:lower() < b.name:lower() end)
        return found
end

local function titleBar(text)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.setCursorPos(1, 1)
        term.clearLine()
        term.write(text)
end

local function drawPrograms()
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        titleBar("ArcadeOS · Pick a game")

        if #session.programs == 0 then
                term.setCursorPos(1, 3)
                term.write("No arcade-enabled games were found in this folder.")
                term.setCursorPos(1, 4)
                term.write("Add a script that calls arcade.start(...) then press R to rescan.")
                term.setCursorPos(1, 6)
                term.write(session.status)
                return
        end

        local startRow = 3
        for idx, program in ipairs(session.programs) do
                local row = startRow + (idx - 1) * 2
                local selected = idx == session.selectedIndex
                term.setCursorPos(1, row)
                if selected then
                        term.setBackgroundColor(colors.gray)
                        term.setTextColor(colors.black)
                else
                        term.setBackgroundColor(colors.black)
                        term.setTextColor(colors.white)
                end
                term.clearLine()
                term.write(string.format("%s %s", selected and ">" or " ", program.name))

                term.setCursorPos(3, row + 1)
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.lightGray)
                local meta = program.metadata or {}
                local details = {}
                if meta.genre then table.insert(details, meta.genre) end
                if meta.blurb then table.insert(details, meta.blurb) end
                term.clearLine()
                term.write(table.concat(details, " · "))
        end

        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.setCursorPos(1, startRow + #session.programs * 2 + 1)
        term.clearLine()
        term.write(session.status)
end

local function refreshPrograms()
        session.programs = discoverPrograms()
        if #session.programs == 0 then
                session.selectedIndex = 0
                return
        end
        if session.selectedIndex > #session.programs then
                session.selectedIndex = #session.programs
        end
        if session.selectedIndex < 1 then session.selectedIndex = 1 end
end

local function launchProgram(program)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1, 1)
        term.write("Launching " .. program.name .. "...")

        local ok, err = pcall(function()
                -- Lua Tip: shell.run executes the target in a fresh environment so games
                -- cannot clobber the launcher. We still preserve the working directory.
                shell.run(program.path)
        end)

        if not ok then
                session.status = "Failed to start " .. program.name .. ": " .. tostring(err)
        else
                session.status = program.name .. " exited. Use arrows to pick another game."
        end

        refreshPrograms() -- Re-scan in case files changed while the game was running.
end

local function handleKey(keyCode)
        if #session.programs == 0 then
                if keyCode == keys.r then
                        session.status = "Rescanning for games..."
                        refreshPrograms()
                elseif keyCode == keys.q then
                        return false
                end
                return true
        end
        if keyCode == keys.up then
                session.selectedIndex = math.max(1, session.selectedIndex - 1)
        elseif keyCode == keys.down then
                session.selectedIndex = math.min(#session.programs, session.selectedIndex + 1)
        elseif keyCode == keys.r then
                session.status = "Rescanning for games..."
                refreshPrograms()
        elseif keyCode == keys.enter then
                local program = session.programs[session.selectedIndex]
                if program then launchProgram(program) end
        elseif keyCode == keys.q then
                return false
        end
        return true
end

local function mainLoop()
        refreshPrograms()
        while true do
                drawPrograms()
                local event, keyCode = os.pullEvent("key")
                if event == "key" then
                        local continue = handleKey(keyCode)
                        if not continue then return end
                end
        end
end

-- Entry point
mainLoop()
