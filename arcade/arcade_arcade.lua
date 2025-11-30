---@diagnostic disable: undefined-global, undefined-field
package.loaded["arcade"] = nil
package.loaded["log"] = nil
package.loaded["data.programs"] = nil

local function ensurePackage()
    if type(package) ~= "table" then
        package = { path = "" }
    elseif type(package.path) ~= "string" then
        package.path = package.path or ""
    end
end

local function detectProgramPath()
    if shell and shell.getRunningProgram then
        return shell.getRunningProgram()
    end
    if debug and debug.getinfo then
        local info = debug.getinfo(2, "S")
        if not info then info = debug.getinfo(1, "S") end
        if info and info.source then
            local src = info.source
            if src:sub(1, 1) == "@" then
                src = src:sub(2)
            end
            return src
        end
    end
    return nil
end

local function setupPaths()
    ensurePackage()
    local program = detectProgramPath()
    if not program then return end
    local dir = fs.getDir(program)
    local root = fs.getDir(dir)

    local function add(path)
        local part = fs.combine(root, path)
        local pattern = "/" .. fs.combine(part, "?.lua")
        if not string.find(package.path, pattern, 1, true) then
            package.path = package.path .. ";" .. pattern
        end
    end

    add("lib")
    add("arcade")
    add("arcade/ui")
    add("factory")
end

setupPaths()

local LicenseStore = require("license_store")
local version = require("version")
local programs = require("data.programs")

local PROGRAM_PATH = detectProgramPath() or ""
local BASE_DIR = fs.getDir(PROGRAM_PATH) or ""
if BASE_DIR == "" then
    BASE_DIR = "."
end

local function resolvePath(rel)
    if type(rel) ~= "string" or rel == "" then return rel end
    if rel:sub(1, 1) == "/" then return rel end
    if BASE_DIR == "." then return rel end
    return fs.combine(BASE_DIR, rel)
end

local CREDIT_FILE = "credits.txt"
local DEFAULT_LICENSE_DIR = "licenses"
local SECRET_SALT = "arcade-license-v1"
local THEME_FILE = "arcade_skin.settings"
local ENVIRONMENT_FILE = "environment.settings"

local DEFAULT_THEME = {
    text = colors.white,
    bg = colors.cyan,
    highlight = colors.yellow,
}

local state = {
    credits = 0,
    licenseStore = nil,
    theme = DEFAULT_THEME,
    environment = "development",
}

local function detectDiskMount()
    local drive = peripheral.find and peripheral.find("drive") or nil
    if drive and drive.getMountPath then
        return drive.getMountPath()
    end
    return nil
end

local function combinePath(base, child)
    if base and base ~= "" then
        return fs.combine(base, child)
    end
    return child
end

local function creditsPath()
    return combinePath(detectDiskMount(), CREDIT_FILE)
end

local function loadCredits()
    local path = creditsPath()
    if fs.exists(path) then
        local handle = fs.open(path, "r")
        if handle then
            local text = handle.readAll()
            handle.close()
            local amount = tonumber(text)
            if amount then
                return math.max(0, amount)
            end
        end
    end
    return 0
end

local function saveCredits(amount)
    local path = creditsPath()
    local handle = fs.open(path, "w")
    if handle then
        handle.write(tostring(amount))
        handle.close()
    end
end

local function loadTheme()
    state.theme = {
        text = DEFAULT_THEME.text,
        bg = DEFAULT_THEME.bg,
        highlight = DEFAULT_THEME.highlight,
    }
    if fs.exists(THEME_FILE) then
        local h = fs.open(THEME_FILE, "r")
        if h then
            local data = textutils.unserialize(h.readAll())
            h.close()
            if type(data) == "table" then
                state.theme.text = data.titleColor or data.text or state.theme.text
                state.theme.bg = data.background or state.theme.bg
                state.theme.highlight = (data.highlight or data.buttons and data.buttons.enabled and data.buttons.enabled.labelColor) or state.theme.highlight
            end
        end
    end
end

local function loadEnvironment()
    state.environment = "development"
    if fs.exists(ENVIRONMENT_FILE) then
        local handle = fs.open(ENVIRONMENT_FILE, "r")
        if handle then
            local data = textutils.unserialize(handle.readAll())
            handle.close()
            if data and type(data.mode) == "string" then
                state.environment = data.mode
            end
        end
    end
end

local function initState()
    state.credits = loadCredits()
    local base = combinePath(detectDiskMount(), DEFAULT_LICENSE_DIR)
    state.licenseStore = LicenseStore.new(base, SECRET_SALT)
    loadTheme()
    loadEnvironment()
end

initState()

local function shouldShowGame(program)
    if program.category ~= "games" then return false end
    if state.environment == "production" and program.prodReady == false then
        return false
    end
    return true
end

local games = {}
for _, program in ipairs(programs) do
    if shouldShowGame(program) then
        table.insert(games, program)
    end
end

table.sort(games, function(a, b)
    return a.name < b.name
end)

local function showNoGamesMessage()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    print("No games are installed for this experience.")
    print("Press any key to return.")
    os.pullEvent("key")
end

local function downloadFile(url, path)
    if not http then
        return false, "HTTP disabled"
    end
    local response, err = http.get(url)
    if not response then
        return false, err or "Failed to connect"
    end
    local status = response.getResponseCode and response.getResponseCode() or 200
    if status >= 400 then
        local body = response.readAll()
        response.close()
        return false, string.format("HTTP %d", status)
    end
    local content = response.readAll()
    response.close()

    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local file = fs.open(path, "w")
    if not file then
        return false, "Write failed"
    end
    file.write(content)
    file.close()
    return true
end

local function ensureLicense(program)
    if state.licenseStore:has(program.id) or (program.price or 0) == 0 then
        return true
    end

    term.setBackgroundColor(colors.blue)
    term.clear()
    local w, h = term.getSize()
    local function center(y, text)
        term.setCursorPos(math.max(1, math.floor((w - #text) / 2) + 1), y)
        term.setTextColor(colors.white)
        term.write(text)
    end

    center(math.floor(h/2) - 2, string.format("%s costs %d credits", program.name, program.price))
    center(math.floor(h/2), string.format("Credits: %d", state.credits))
    center(math.floor(h/2) + 2, "Purchase? (Y/N)")

    while true do
        local event, key = os.pullEvent("char")
        key = string.lower(key)
        if key == "n" then
            return false
        elseif key == "y" then
            if state.credits < program.price then
                center(math.floor(h/2) + 4, "Not enough credits!")
                os.sleep(1.2)
                return false
            end
            state.credits = state.credits - program.price
            saveCredits(state.credits)
            state.licenseStore:save(program.id, program.price, "purchased via ArcadeArcade")
            return true
        end
    end
end

local function ensureInstalled(program)
    local fullPath = resolvePath(program.path)
    if fs.exists(fullPath) then
        return true
    end
    local ok, err = downloadFile(program.url, fullPath)
    if ok then
        return true
    end
    return false, err
end

local function launchProgram(program)
    local fullPath = resolvePath(program.path)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    print("Launching " .. program.name .. "...")
    local ok, err = pcall(function()
        shell.run(fullPath)
    end)
    if not ok then
        print("Program error: " .. tostring(err))
        print("Press Enter to return...")
        read()
    else
        print("Program finished cleanly.")
        os.sleep(0.8)
    end
end

local statusMessage = "Select a game and press Enter"
local selectedIndex = 1
local scrollOffset = 0

local function describeStatus(program)
    local owned = state.licenseStore:has(program.id)
    local fullPath = resolvePath(program.path)
    local installed = fs.exists(fullPath)
    if installed then return "Ready" end
    if owned then return "Download" end
    local price = program.price or 0
    if price == 0 then return "Free" end
    return string.format("%d C", price)
end

local function clampSelection()
    if selectedIndex < 1 then selectedIndex = 1 end
    if selectedIndex > #games then selectedIndex = #games end
    if selectedIndex < 1 then selectedIndex = 1 end
end

local function refreshScroll()
    local w, h = term.getSize()
    local listHeight = math.max(1, h - 5)
    if selectedIndex - scrollOffset > listHeight then
        scrollOffset = selectedIndex - listHeight
    elseif selectedIndex <= scrollOffset then
        scrollOffset = selectedIndex - 1
    end
    if scrollOffset < 0 then scrollOffset = 0 end
end

local function playSelected()
    local program = games[selectedIndex]
    if not program then return end
    if not ensureLicense(program) then
        statusMessage = "Purchase cancelled"
        return
    end
    local ok, err = ensureInstalled(program)
    if not ok then
        statusMessage = "Install failed: " .. (err or "?")
        return
    end
    statusMessage = "Launching " .. program.name .. "..."
    launchProgram(program)
    statusMessage = "Select a game and press Enter"
end

local function drawUI()
    local w, h = term.getSize()
    term.setBackgroundColor(state.theme.bg)
    term.setTextColor(state.theme.text)
    term.clear()

    term.setCursorPos(2, 1)
    term.write("ArcadeArcade")
    local buildLabel = string.format("Build %d", version.BUILD or 0)
    term.setCursorPos(math.max(1, w - #buildLabel + 1), 1)
    term.write(buildLabel)

    term.setCursorPos(2, 2)
    term.clearLine()
    term.write(string.format("Credits: %d", state.credits))

    local listY = 4
    local listHeight = math.max(1, h - 5)
    for i = 0, listHeight - 1 do
        local idx = scrollOffset + i + 1
        local prog = games[idx]
        local y = listY + i
        term.setCursorPos(2, y)
        if prog then
            local bg = (idx == selectedIndex) and state.theme.highlight or state.theme.bg
            local fg = (idx == selectedIndex) and colors.black or state.theme.text
            term.setBackgroundColor(bg)
            term.setTextColor(fg)
            term.write(string.rep(" ", w - 2))
            term.setCursorPos(2, y)
            term.write(prog.name)
            local status = describeStatus(prog)
            term.setCursorPos(math.max(2, w - #status + 1), y)
            term.write(status)
        else
            term.setBackgroundColor(state.theme.bg)
            term.setTextColor(state.theme.text)
            term.write(string.rep(" ", w - 2))
        end
    end

    term.setBackgroundColor(state.theme.bg)
    term.setTextColor(state.theme.text)
    term.setCursorPos(2, h)
    term.clearLine()
    term.write(statusMessage or "")
    term.setCursorPos(2, h - 1)
    term.clearLine()
    term.write("Up/Down to select  Enter=Play  Q=Quit")
end

local function main()
    if #games == 0 then
        showNoGamesMessage()
        return
    end

    local running = true
    while running do
        drawUI()
        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            if p1 == keys.up then
                selectedIndex = selectedIndex - 1
                clampSelection()
                refreshScroll()
            elseif p1 == keys.down then
                selectedIndex = selectedIndex + 1
                clampSelection()
                refreshScroll()
            elseif p1 == keys.enter or p1 == keys.numPadEnter then
                playSelected()
                initState() -- refresh credits/licenses after potential purchase
            elseif p1 == keys.q or p1 == keys.backspace then
                running = false
            elseif p1 == keys.pageUp then
                selectedIndex = selectedIndex - 5
                clampSelection()
                refreshScroll()
            elseif p1 == keys.pageDown then
                selectedIndex = selectedIndex + 5
                clampSelection()
                refreshScroll()
            end
        elseif event == "mouse_scroll" then
            if p1 > 0 then
                selectedIndex = math.min(#games, selectedIndex + 1)
            else
                selectedIndex = math.max(1, selectedIndex - 1)
            end
            refreshScroll()
        elseif event == "mouse_click" then
            if p3 >= 4 then
                local idx = scrollOffset + (p3 - 4) + 1
                if games[idx] then
                    selectedIndex = idx
                    refreshScroll()
                    if p1 == 1 then
                        playSelected()
                        initState()
                    end
                end
            end
        end
    end

    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    print("Returning to ArcadeOS...")
    os.sleep(0.2)
end

local function runWithMonitor(fn)
    local ok, monitorUtil = pcall(require, "lib_monitor")
    if ok and monitorUtil and monitorUtil.runOnMonitor then
        return monitorUtil.runOnMonitor(fn, { textScale = 0.5 })
    end
    return fn()
end

runWithMonitor(main)
