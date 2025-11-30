--[[
Arcadesys launcher

Goals:
- Run on CraftOS-PC for both computer and turtle profiles.
- Keep the turtle state machine untouched; we just dispatch to existing entrypoints.
- Avoid in-game testing by making it easy to start common programs from one menu.
]]

---@diagnostic disable: undefined-global

local function ensurePackagePaths(baseDir)
    local paths = {
        fs.combine(baseDir, "?.lua"),
        fs.combine(baseDir, "lib/?.lua"),
        fs.combine(baseDir, "arcade/?.lua"),
        fs.combine(baseDir, "arcade/ui/?.lua"),
        fs.combine(baseDir, "factory/?.lua"),
        fs.combine(baseDir, "ui/?.lua"),
        fs.combine(baseDir, "tools/?.lua"),
        "/?.lua",
        "/lib/?.lua",
    }

    for _, pattern in ipairs(paths) do
        local needle = ";" .. pattern
        if not string.find(package.path, needle, 1, true) then
            package.path = package.path .. needle
        end
    end
end

local function detectBaseDir()
    if shell and shell.getRunningProgram then
        return fs.getDir(shell.getRunningProgram())
    end
    if debug and debug.getinfo then
        local info = debug.getinfo(1, "S")
        if info and info.source then
            local src = info.source
            if src:sub(1, 1) == "@" then src = src:sub(2) end
            return fs.getDir(src)
        end
    end
    return ""
end

local baseDir = detectBaseDir()
ensurePackagePaths(baseDir == "" and "/" or baseDir)

local okBoot, boot = pcall(require, "arcade.boot")
if okBoot and type(boot) == "table" and boot.setupPaths then
    pcall(boot.setupPaths)
end

local hub = require("ui.hub")

local function runProgram(path, ...)
    local args = { ... }
    local function go()
        if shell and shell.run then
            shell.run(path, table.unpack(args))
        elseif dofile then
            _G.arg = args
            dofile(path)
        else
            error("No shell available to run " .. path)
        end
    end
    local ok, err = pcall(go)
    if not ok then
        print("Failed to run " .. path .. ": " .. tostring(err))
        if _G.sleep then sleep(1) end
    end
end

local function maybe(label, path, hint)
    if not fs.exists(path) then return nil end
    return {
        label = label,
        hint = hint,
        action = function(_, ui)
            ui:notify("Launching " .. label .. "...")
            runProgram(path)
        end
    }
end

local isTurtle = type(_G.turtle) == "table"

local sections = {}

if not isTurtle then
    local computerItems = {}
    local planner = maybe("Factory Planner", "factory_planner.lua", "Design schemas")
    if planner then table.insert(computerItems, planner) end
    local ae2Drive = maybe("AE2 Drive Monitor", "ae2_drive_monitor.lua", "Requires ME Bridge")
    if ae2Drive then table.insert(computerItems, ae2Drive) end
    local ae2Me = maybe("AE2 ME Bridge Monitor", "ae2_me_bridge_monitor.lua", "ME Bridge + Modem")
    if ae2Me then table.insert(computerItems, ae2Me) end
    if #computerItems > 0 then
        table.insert(sections, { label = "Computer", items = computerItems })
    end
end

local shared = {
    maybe("Receive Schemas", "tools/receive_schema.lua", "Keep running to listen"),
    maybe("Install Sender", "tools/install_sender.lua", "Push payloads over rednet"),
}

local filteredShared = {}
for _, item in ipairs(shared) do
    if item then table.insert(filteredShared, item) end
end
if #filteredShared > 0 then
    table.insert(sections, { label = "Network Tools", items = filteredShared })
end

if isTurtle then
    local turtleItems = {}
    local turtleUi = maybe("TurtleOS UI", "factory/turtle_os.lua", "Full menu")
    if turtleUi then table.insert(turtleItems, turtleUi) end
    local turtleAgent = maybe("Factory Agent (headless)", "factory/main.lua", "State machine")
    if turtleAgent then table.insert(turtleItems, turtleAgent) end
    if #turtleItems > 0 then
        table.insert(sections, { label = "Turtle", items = turtleItems })
    end
end

if #sections == 0 then
    print("Nothing to run. Are the files synced?")
    return
end

hub.run({
    title = "Arcadesys",
    subtitle = isTurtle and "Turtle profile" or "Computer profile",
    sections = sections,
})
