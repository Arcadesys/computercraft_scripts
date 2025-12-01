--[[
TurtleOS v2.0
Graphical launcher for the factory agent.
--]]

---@diagnostic disable: undefined-global

-- Minimal require compat so this file can run even when Arcadesys didn't
-- install a global require (eg. when invoked directly on CraftOS turtles).
if type(package) ~= "table" then package = { path = "" } end
if type(package.path) ~= "string" then package.path = package.path or "" end
package.loaded = package.loaded or {}

local function requireCompat(name)
    if package.loaded[name] ~= nil then return package.loaded[name] end

    local lastErr
    for pattern in string.gmatch(package.path or "", "([^;]+)") do
        local candidate = pattern:gsub("%?", name)
        if fs.exists(candidate) and not fs.isDir(candidate) then
            local fn, err = loadfile(candidate)
            if not fn then
                lastErr = err
            else
                local ok, res = pcall(fn)
                if not ok then
                    lastErr = res
                else
                    package.loaded[name] = res
                    return res
                end
            end
        end
    end

    error(string.format("module '%s' not found%s", name, lastErr and (": " .. tostring(lastErr)) or ""))
end

local function ensurePackagePaths(baseDir)
    local root = baseDir == "" and "/" or baseDir
    local paths = {
        "/?.lua",
        "/lib/?.lua",
        fs.combine(root, "?.lua"),
        fs.combine(root, "lib/?.lua"),
        fs.combine(root, "factory/?.lua"),
        fs.combine(root, "ui/?.lua"),
        fs.combine(root, "tools/?.lua"),
    }

    local current = package.path or ""
    if current ~= "" then table.insert(paths, current) end

    local seen, final = {}, {}
    for _, p in ipairs(paths) do
        if p and p ~= "" and not seen[p] then
            seen[p] = true
            table.insert(final, p)
        end
    end
    package.path = table.concat(final, ";")
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

ensurePackagePaths(detectBaseDir())
local require = _G.require or requireCompat
_G.require = require

local ui = require("lib_ui")
local parser = require("lib_parser")
local json = require("lib_json")
local schema_utils = require("lib_schema")

-- Hack to load factory without running it immediately
_G.__FACTORY_EMBED__ = true
local factory = require("factory")
_G.__FACTORY_EMBED__ = nil

-- Helper to pause before returning
local function pauseAndReturn(retVal)
    print("\nOperation finished.")
    print("Press Enter to continue...")
    read()
    return retVal
end

-- --- ACTIONS ---

local function runMining(form)
    local length = 64
    local interval = 3
    local torch = 6
    
    for _, el in ipairs(form.elements) do
        if el.id == "length" then length = tonumber(el.value) or 64 end
        if el.id == "interval" then interval = tonumber(el.value) or 3 end
        if el.id == "torch" then torch = tonumber(el.value) or 6 end
    end
    
    ui.clear()
    print("Starting Mining Operation...")
    print(string.format("Length: %d, Interval: %d", length, interval))
    sleep(1)
    
    factory.run({ "mine", "--length", tostring(length), "--branch-interval", tostring(interval), "--torch-interval", tostring(torch) })
    
    return pauseAndReturn("stay")
end

local function runTunnel()
    local length = 16
    local width = 1
    local height = 2
    local torch = 6
    
    local form = ui.Form("Tunnel Configuration")
    form:addInput("length", "Length", tostring(length))
    form:addInput("width", "Width", tostring(width))
    form:addInput("height", "Height", tostring(height))
    form:addInput("torch", "Torch Interval", tostring(torch))
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "length" then length = tonumber(el.value) or 16 end
        if el.id == "width" then width = tonumber(el.value) or 1 end
        if el.id == "height" then height = tonumber(el.value) or 2 end
        if el.id == "torch" then torch = tonumber(el.value) or 6 end
    end
    
    ui.clear()
    print("Starting Tunnel Operation...")
    print(string.format("L: %d, W: %d, H: %d", length, width, height))
    sleep(1)
    
    factory.run({ "tunnel", "--length", tostring(length), "--width", tostring(width), "--height", tostring(height), "--torch-interval", tostring(torch) })
    
    return pauseAndReturn("stay")
end

local function runExcavate()
    local length = 8
    local width = 8
    local depth = 3
    
    local form = ui.Form("Excavation Configuration")
    form:addInput("length", "Length", tostring(length))
    form:addInput("width", "Width", tostring(width))
    form:addInput("depth", "Depth", tostring(depth))
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "length" then length = tonumber(el.value) or 8 end
        if el.id == "width" then width = tonumber(el.value) or 8 end
        if el.id == "depth" then depth = tonumber(el.value) or 3 end
    end
    
    ui.clear()
    print("Starting Excavation Operation...")
    print(string.format("L: %d, W: %d, D: %d", length, width, depth))
    sleep(1)
    
    factory.run({ "excavate", "--length", tostring(length), "--width", tostring(width), "--depth", tostring(depth) })
    
    return pauseAndReturn("stay")
end

local function runTreeFarm()
    ui.clear()
    print("Starting Tree Farm...")
    sleep(1)
    factory.run({ "treefarm" })
    return pauseAndReturn("stay")
end

local function runPotatoFarm()
    local width = 9
    local length = 9
    
    local form = ui.Form("Potato Farm Configuration")
    form:addStepper("width", "Width", width, { min = 3, max = 25 })
    form:addStepper("length", "Length", length, { min = 3, max = 25 })
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "width" then width = tonumber(el.value) or 9 end
        if el.id == "length" then length = tonumber(el.value) or 9 end
    end
    
    ui.clear()
    print("Starting Potato Farm Build...")
    print(string.format("W: %d, L: %d", width, length))
    sleep(1)
    
    factory.run({ "farm", "--farm-type", "potato", "--width", tostring(width), "--length", tostring(length) })
    
    return pauseAndReturn("stay")
end

local function runBuild(schemaFile)
    ui.clear()
    print("Starting Build Operation...")
    print("Schema: " .. schemaFile)
end

main()
