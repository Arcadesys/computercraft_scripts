--[[
Arcadesys launcher

Goals:
- Run on CraftOS-PC for both computer and turtle profiles.
- Keep the turtle state machine untouched; we just dispatch to existing entrypoints.
- Avoid in-game testing by making it easy to start common programs from one menu.
]]

---@diagnostic disable: undefined-global

local DEFAULT_MANIFEST_URL =
    "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/manifest.json"

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

local function readAll(handle)
    local content = handle.readAll()
    handle.close()
    return content
end

local function fetch(url)
    if not http then
        return nil, "HTTP API is disabled"
    end

    local response, err = http.get(url)
    if not response then
        return nil, err or "unknown HTTP error"
    end

    return readAll(response)
end

local function decodeJson(payload)
    local ok, result = pcall(textutils.unserializeJSON, payload)
    if not ok then
        return nil, "Invalid JSON: " .. tostring(result)
    end
    return result
end

local function sanitizeManifest(manifest)
    if type(manifest) ~= "table" then
        return nil, "Manifest is not a table"
    end
    if type(manifest.files) ~= "table" or #manifest.files == 0 then
        return nil, "Manifest contains no files"
    end
    return manifest
end

local function loadManifest(url)
    if not url then
        return nil, "No manifest URL provided"
    end

    local body, err = fetch(url)
    if not body then
        return nil, err
    end

    local manifest, decodeErr = decodeJson(body)
    if not manifest then
        return nil, decodeErr
    end

    local valid, reason = sanitizeManifest(manifest)
    if not valid then
        return nil, reason
    end

    return manifest
end

local function downloadFiles(manifest)
    local bundle = {
        name = manifest.name or "Arcadesys",
        version = manifest.version or "unknown",
        files = {},
    }

    for _, file in ipairs(manifest.files) do
        if not file.path then
            return nil, "File entry missing 'path'"
        end

        if file.content then
            table.insert(bundle.files, { path = file.path, content = file.content })
        elseif file.url then
            local data, err = fetch(file.url)
            if not data then
                return nil, err or ("Failed to download " .. file.url)
            end
            table.insert(bundle.files, { path = file.path, content = data })
        else
            return nil, "File entry for " .. file.path .. " needs 'url' or 'content'"
        end
    end

    return bundle
end

local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" then
        fs.makeDir(dir)
    end

    local handle = fs.open(path, "wb") or fs.open(path, "w")
    if not handle then
        error("Unable to write to " .. path)
    end

    handle.write(content or "")
    handle.close()
end

local function performUpdate(ui)
    if not http then
        ui:notify("Update requires HTTP; enable it in the ComputerCraft config.")
        return
    end

    ui:notify("Checking for updates...")
    local manifest, err = loadManifest(DEFAULT_MANIFEST_URL)
    if not manifest then
        ui:notify("Manifest error: " .. tostring(err))
        return
    end

    local bundle, downloadErr = downloadFiles(manifest)
    if not bundle then
        ui:notify("Download failed: " .. tostring(downloadErr))
        return
    end

    ui:notify(string.format("Installing %s (%s)...", bundle.name, bundle.version))
    for _, file in ipairs(bundle.files) do
        writeFile(file.path, file.content)
    end

    ui:notify("Update complete. Designs and saved work were left untouched.")
end

local baseDir = detectBaseDir()
ensurePackagePaths(baseDir == "" and "/" or baseDir)

local okBoot, boot = pcall(require, "arcade.boot")
if okBoot and type(boot) == "table" and boot.setupPaths then
    pcall(boot.setupPaths)
end

local hub = require("ui.hub")

local function runProgram(path, ui, ...)
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
        local msg = "Failed to run " .. path .. ": " .. tostring(err)
        if ui and ui.notify then
            ui:notify(msg)
            ui:pause("(Press Enter to return)")
        else
            print(msg)
            if _G.sleep then sleep(1) end
        end
    end
end

local function installMockTurtle()
    local original = _G.turtle
    if type(original) == "table" then return function() end end

    local function okReturn()
        return true
    end

    local function detectReturn()
        return false
    end

    local function inspectReturn()
        return true, { name = "minecraft:air", state = {}, tags = {} }
    end

    local stub = {
        forward = okReturn,
        back = okReturn,
        up = okReturn,
        down = okReturn,
        turnLeft = okReturn,
        turnRight = okReturn,
        dig = okReturn,
        digUp = okReturn,
        digDown = okReturn,
        place = okReturn,
        placeUp = okReturn,
        placeDown = okReturn,
        attack = okReturn,
        attackUp = okReturn,
        attackDown = okReturn,
        select = okReturn,
        getSelectedSlot = function() return 1 end,
        compare = okReturn,
        compareUp = okReturn,
        compareDown = okReturn,
        compareTo = okReturn,
        transferTo = okReturn,
        drop = okReturn,
        dropUp = okReturn,
        dropDown = okReturn,
        suck = okReturn,
        suckUp = okReturn,
        suckDown = okReturn,
        detect = detectReturn,
        detectUp = detectReturn,
        detectDown = detectReturn,
        inspect = inspectReturn,
        inspectUp = inspectReturn,
        inspectDown = inspectReturn,
        getItemDetail = function() return nil end,
        getItemCount = function() return 0 end,
        getItemSpace = function() return 64 end,
        getItemLimit = function() return 64 end,
        getFuelLevel = function() return math.huge end,
        getFuelLimit = function() return math.huge end,
        refuel = okReturn,
        craft = okReturn,
        equipLeft = okReturn,
        equipRight = okReturn,
    }

    setmetatable(stub, { __index = function()
        return okReturn
    end })

    _G.turtle = stub
    return function()
        _G.turtle = original
    end
end

local function maybe(label, path, hint)
    if not fs.exists(path) then return nil end
    return {
        label = label,
        hint = hint,
        action = function(_, ui)
            ui:notify("Launching " .. label .. "...")
            runProgram(path, ui)
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
    local mockTurtleUi = {
        label = "TurtleOS (mock turtle)",
        hint = "Preview Turtle UI on CraftOS-PC",
        action = function(_, ui)
            ui:notify("Mocking turtle API... Launching TurtleOS UI.")
            local cleanup = installMockTurtle()
            runProgram("factory/turtle_os.lua", ui)
            if cleanup then cleanup() end
        end
    }
    table.insert(computerItems, mockTurtleUi)
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

local systemItems = {
    {
        label = "Update Arcadesys",
        hint = "Reinstall without wiping designs",
        action = function(_, ui)
            performUpdate(ui)
        end
    },
}
table.insert(sections, { label = "System", items = systemItems })

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
