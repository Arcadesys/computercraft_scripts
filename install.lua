--[[
 Workstation installer for ComputerCraft / CC:Tweaked
 -----------------------------------------------------
 This script wipes the computer (except the ROM) and then installs the
 Workstation OS from a manifest, similar to applying an image. It works on
 both computers and turtles.

 Usage examples:
   install                 -- use the default manifest URL
   install <manifest_url>  -- override the manifest location

 The manifest is expected to look like:
 {
   "name": "Workstation",
   "version": "1.0.0",
   "files": [
     { "path": "startup.lua", "url": "https://.../startup.lua" },
     { "path": "apps/home.lua", "url": "https://.../home.lua" }
   ]
 }

 If HTTP is disabled or the manifest download fails, the installer falls
 back to a tiny embedded Workstation image so that the machine remains
 bootable.
]]

local tArgs = { ... }

-- Change this to point at your canonical Workstation manifest.
local DEFAULT_MANIFEST_URL =
  "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/manifest.json"

-- Minimal offline image that keeps the computer usable even if remote
-- downloads fail.
local EMBEDDED_IMAGE = {
  name = "Workstation",
  version = "embedded",
  files = {}
}

local function addEmbeddedFile(path, content)
  table.insert(EMBEDDED_IMAGE.files, { path = path, content = content })
end

-- START_EMBEDDED_FILES
addEmbeddedFile("startup.lua", [[
-- startup.lua
-- Simplified launcher for TurtleOS

package.path = package.path .. ";/?.lua;/lib/?.lua"

if fs.exists("factory/turtle_os.lua") then
    shell.run("factory/turtle_os.lua")
elseif fs.exists("/factory/turtle_os.lua") then
    shell.run("/factory/turtle_os.lua")
else
    print("Error: factory/turtle_os.lua not found.")
end
]])

addEmbeddedFile("arcadesys_os.lua", [===[
--[[
Arcadesys launcher

Goals:
- Run on CraftOS-PC for both computer and turtle profiles.
- Keep the turtle state machine untouched; we just dispatch to existing entrypoints.
- Avoid in-game testing by making it easy to start common programs from one menu.
]]

---@diagnostic disable: undefined-global

local VERSION = "2.0.2"

if type(package) ~= "table" then package = { path = "" } end
if type(package.path) ~= "string" then package.path = package.path or "" end
package.loaded = package.loaded or {}

local upstreamRequire = _G.require

local function requireCompat(name)
    if package.loaded[name] ~= nil then return package.loaded[name] end
    if upstreamRequire and upstreamRequire ~= requireCompat then
        local result = upstreamRequire(name)
        package.loaded[name] = result
        return result
    end

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

_G.require = _G.require or requireCompat

local DEFAULT_MANIFEST_URL =
    "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/manifest.json"

local function ensurePackagePaths(baseDir)
    local root = baseDir == "" and "/" or baseDir
    local paths = {
        "/?.lua",
        "/lib/?.lua",
        fs.combine(root, "?.lua"),
        fs.combine(root, "lib/?.lua"),
        fs.combine(root, "arcade/?.lua"),
        fs.combine(root, "arcade/ui/?.lua"),
        fs.combine(root, "factory/?.lua"),
        fs.combine(root, "ui/?.lua"),
        fs.combine(root, "tools/?.lua"),
    }

    -- Rebuild path with guaranteed leading entries, plus any existing paths.
    local current = package.path or ""
    if current ~= "" then table.insert(paths, current) end
    -- Deduplicate while preserving order.
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

local function logError(msg)
    local stamp = textutils and textutils.formatTime and textutils.formatTime(os.epoch and os.epoch("utc") / 1000 or 0, true)
        or tostring(os.time and os.time() or "")
    local line = string.format("[%s] %s", stamp, msg)
    local f = fs.open("/arcadesys_error.log", "a")
    if f then
        f.writeLine(line)
        f.close()
    end
end

local baseDir = detectBaseDir()
ensurePackagePaths(baseDir == "" and "/" or baseDir)

local okBoot, boot = pcall(require, "arcade.boot")
if okBoot and type(boot) == "table" and boot.setupPaths then
    pcall(boot.setupPaths)
end

print(string.format("Arcadesys %s - launching Turtle UI", VERSION))

local function runProgram(path, ui, ...)
    local args = { ... }
    local function go()
        local fn, loadErr = loadfile(path)
        if not fn then
            error("Unable to load " .. path .. ": " .. tostring(loadErr))
        end
        _G.arg = args
        return fn(table.unpack(args))
    end

    local ok, err = pcall(go)
    if not ok then
        local msg = "Failed to run " .. path .. ": " .. tostring(err)
        logError(msg)
        if ui and ui.notify then
            ui:notify(msg)
            ui:pause("(Press Enter to return)")
        else
            print(msg)
            if _G.read then
                print("(Press Enter to continue)")
                pcall(read)
            elseif _G.sleep then
                sleep(2)
            end
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

local function launchTurtleUi()
    local cleanup
    if not isTurtle then
        cleanup = installMockTurtle()
    end

    if fs.exists("factory/turtle_os.lua") then
        runProgram("factory/turtle_os.lua")
    elseif fs.exists("/factory/turtle_os.lua") then
        runProgram("/factory/turtle_os.lua")
    else
        print("Turtle UI missing. Try running 'Update Arcadesys' or reinstall.")
        if _G.read then
            print("(Press Enter to continue)")
            pcall(read)
        elseif _G.sleep then
            sleep(2)
        end
    end

    if cleanup then cleanup() end
end

launchTurtleUi()
]===])

addEmbeddedFile("factory/main.lua", [=[
--[[
Main entry point for the modular agent system.
Implements the finite state machine loop.
--]]

-- Ensure package path includes lib and arcade
if not string.find(package.path, "/lib/?.lua") then
    package.path = package.path .. ";/?.lua;/lib/?.lua;/arcade/?.lua;/factory/?.lua"
end

local logger = require("lib_logger")
local movement = require("lib_movement")
local ui = require("lib_ui")
local trash_config = require("ui.trash_config")

local function interactiveSetup(ctx)
    local mode = "treefarm"
    -- Farm params
    local width = 9
    local height = 9
    -- Mine params
    local length = 60
    local branchInterval = 3
    local branchLength = 16
    local torchInterval = 6
    
    local selected = 1 
    
    while true do
        ui.clear()
        ui.drawFrame(2, 2, 30, 16, "Factory Setup")
        
        -- Mode
        ui.label(4, 4, "Mode: ")
        local modeLabel = "Tree"
        if mode == "potatofarm" then modeLabel = "Potato" end
        if mode == "mine" then modeLabel = "Mine" end
        
        if selected == 1 then
            if term.isColor() then term.setTextColor(colors.yellow) end
            term.write("< " .. modeLabel .. " >")
        else
            if term.isColor() then term.setTextColor(colors.white) end
            term.write("  " .. modeLabel .. "  ")
        end

        local startIdx = 4
        
        if mode == "treefarm" or mode == "potatofarm" then
            startIdx = 4
            -- Width
            ui.label(4, 6, "Width: ")
            if selected == 2 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. width .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. width .. "  ")
            end
            
            -- Height
            ui.label(4, 8, "Height:")
            if selected == 3 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. height .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. height .. "  ")
            end
        elseif mode == "mine" then
            startIdx = 7
            -- Length
            ui.label(4, 6, "Length: ")
            if selected == 2 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. length .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. length .. "  ")
            end

            -- Branch Interval
            ui.label(4, 7, "Br. Int:")
            if selected == 3 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. branchInterval .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. branchInterval .. "  ")
            end

            -- Branch Length
            ui.label(4, 8, "Br. Len:")
            if selected == 4 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. branchLength .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. branchLength .. "  ")
            end

            -- Torch Interval
            ui.label(4, 9, "Torch Int:")
            if selected == 5 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. torchInterval .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. torchInterval .. "  ")
            end

            -- Trash Config
            ui.label(4, 10, "Trash:")
            if selected == 6 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write(" < EDIT > ")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("   EDIT   ")
            end
        end
        
        -- Button
        ui.button(8, 12, "START", selected == startIdx)
        
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = selected - 1
            if selected < 1 then selected = startIdx end
        elseif key == keys.down then
            selected = selected + 1
            if selected > startIdx then selected = 1 end
        elseif key == keys.left then
            if selected == 1 then 
                if mode == "treefarm" then mode = "potatofarm"
                elseif mode == "potatofarm" then mode = "mine"
                else mode = "treefarm" end
                selected = 1
            end
            if mode == "treefarm" or mode == "potatofarm" then
                if selected == 2 then width = math.max(1, width - 1) end
                if selected == 3 then height = math.max(1, height - 1) end
            elseif mode == "mine" then
                if selected == 2 then length = math.max(10, length - 10) end
                if selected == 3 then branchInterval = math.max(1, branchInterval - 1) end
                if selected == 4 then branchLength = math.max(1, branchLength - 1) end
                if selected == 5 then torchInterval = math.max(1, torchInterval - 1) end
            end
        elseif key == keys.right then
            if selected == 1 then 
                if mode == "treefarm" then mode = "mine"
                elseif mode == "mine" then mode = "potatofarm"
                else mode = "treefarm" end
                selected = 1
            end
            if mode == "treefarm" or mode == "potatofarm" then
                if selected == 2 then width = width + 1 end
                if selected == 3 then height = height + 1 end
            elseif mode == "mine" then
                if selected == 2 then length = length + 10 end
                if selected == 3 then branchInterval = branchInterval + 1 end
                if selected == 4 then branchLength = branchLength + 1 end
                if selected == 5 then torchInterval = torchInterval + 1 end
            end
        elseif key == keys.enter then
            if selected == startIdx then
                return { 
                    mode = mode, 
                    width = width, 
                    height = height, 
                    length = length, 
                    branchInterval = branchInterval, 
                    branchLength = branchLength, 
                    torchInterval = torchInterval 
                }
            elseif mode == "mine" and selected == 6 then
                trash_config.run()
            end
        end
    end
end

-- Load states
local states = {
    INITIALIZE = require("state_initialize"),
    BUILD = require("state_build"),
    MINE = require("state_mine"),
    RESTOCK = require("state_restock"),
    REFUEL = require("state_refuel"),
    BLOCKED = require("state_blocked"),
    ERROR = require("state_error"),
    DONE = require("state_done"),
    CHECK_REQUIREMENTS = require("state_check_requirements"),
    TREEFARM = require("state_treefarm"),
    POTATOFARM = require("state_potatofarm"),
    BRANCHMINE = require("state_branchmine")
}

local function main(args)
    -- Initialize context
    local ctx = {
        state = "INITIALIZE",
        config = {
            verbose = false,
            schemaPath = nil
        },
        origin = { x=0, y=0, z=0, facing="north" }, -- Default home
        pointer = 1, -- Current step in the build path
        schema = nil, -- Will be loaded by INITIALIZE
        strategy = nil, -- Will be computed by INITIALIZE
        inventoryState = {},
        fuelState = {},
        retries = 0
    }

    -- Parse args
    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "--verbose" then
            ctx.config.verbose = true
        elseif arg == "mine" then
            ctx.config.mode = "mine"
        elseif arg == "treefarm" then
            ctx.config.mode = "treefarm"
        elseif arg == "potatofarm" then
            ctx.config.mode = "potatofarm"
        elseif arg == "--length" then
            i = i + 1
            ctx.config.length = tonumber(args[i])
        elseif arg == "--width" then
            i = i + 1
            ctx.config.width = tonumber(args[i])
        elseif arg == "--height" then
            i = i + 1
            ctx.config.height = tonumber(args[i])
        elseif arg == "--branch-interval" then
            i = i + 1
            ctx.config.branchInterval = tonumber(args[i])
        elseif arg == "--branch-length" then
            i = i + 1
            ctx.config.branchLength = tonumber(args[i])
        elseif arg == "--torch-interval" then
            i = i + 1
            ctx.config.torchInterval = tonumber(args[i])
        elseif not arg:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
             ctx.config.schemaPath = arg
        end
        i = i + 1
    end
    
    -- If no args provided, run interactive setup
    if #args == 0 then
        local setupConfig = interactiveSetup(ctx)
        for k, v in pairs(setupConfig) do
            ctx.config[k] = v
        end
    end
    
    if not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
        ctx.config.schemaPath = "schema.json"
    end

    ctx.logger = logger.new({
        level = ctx.config.verbose and "debug" or "info"
    })
    ctx.logger:info("Agent starting...")

    -- Attempt a safe step-out: 2 forward, then 2 to the right (restore facing).
    local function stepOut(ctx)
        local ok, err
        ok, err = movement.forward(ctx)
        if not ok then return false, err end
        ok, err = movement.forward(ctx)
        if not ok then return false, err end
        ok, err = movement.turnRight(ctx)
        if not ok then return false, err end
        ok, err = movement.forward(ctx)
        if not ok then return false, err end
        ok, err = movement.forward(ctx)
        if not ok then return false, err end
        -- Restore original facing
        ok, err = movement.turnLeft(ctx)
        if not ok then return false, err end
        return true
    end

    local ok, err = stepOut(ctx)
    if not ok then
        ctx.logger:warn("Initial step-out failed: " .. tostring(err))
    else
        ctx.logger:info("Stepped out to working position (2 forward, 2 right)")
    end

    -- State machine loop
    while ctx.state ~= "EXIT" do
        local currentStateFunc = states[ctx.state]
        if not currentStateFunc then
            ctx.logger:error("Unknown state: " .. tostring(ctx.state))
            break
        end

        ctx.logger:debug("Entering state: " .. ctx.state)
        
        local ok, nextStateOrErr = pcall(currentStateFunc, ctx)
        
        if not ok then
            ctx.logger:error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr))
            ctx.lastError = nextStateOrErr
            ctx.state = "ERROR"
        else
            ctx.state = nextStateOrErr
        end
        
        ---@diagnostic disable-next-line: undefined-global
        sleep(0) -- Yield to avoid "Too long without yielding"
    end

    ctx.logger:info("Agent finished.")
    
    if ctx.lastError then
        print("Agent finished: " .. tostring(ctx.lastError))
    else
        print("Agent finished: success!")
    end
end

local args = { ... }
main(args)
]=])

addEmbeddedFile("factory/schema_modular_factory.txt", [=[
legend:
# = minecraft:stone_bricks
S = minecraft:stone
P = minecraft:oak_planks
L = minecraft:lantern
T = mekanism:basic_logistical_transporter
U = mekanism:basic_universal_cable
. = minecraft:air

layer:0
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSS

layer:1
################
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
################

layer:2
################
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
################

layer:3
################
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
################

layer:4
################
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
################

layer:5
################
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
#..............#
################

layer:6
################
#U............T#
#U............T#
#U............T#
#U............T#
#U............T#
#U............T#
#U............T#
#U......L.....T#
#U............T#
#U............T#
#U............T#
#U............T#
#U............T#
#U............T#
#U............T#
################

layer:7
################
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
#PPPPPPPPPPPPPP#
################
]=])

addEmbeddedFile("factory/state_initialize.lua", [=[
--[[
State: INITIALIZE
Sets up the agent's context, validates schema, and computes build strategy.
--]]

local logger = require("lib_logger")
local schemaUtils = require("lib_schema")
local parser = require("lib_parser")
local movement = require("lib_movement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")

local function INITIALIZE(ctx)
    logger.log(ctx, "info", "Initializing Factory Agent...")
    
    -- 1. Check Fuel
    if not fuelLib.hasFuel(ctx) then
        logger.log(ctx, "warn", "Low fuel on startup.")
        -- We don't block here, check_requirements will handle it
    end

    -- 2. Load Schema (if applicable)
    if ctx.config.mode == "mine" or ctx.config.mode == "tunnel" or ctx.config.mode == "excavate" then
        logger.log(ctx, "info", "Mode: " .. ctx.config.mode)
        ctx.strategy = { type = ctx.config.mode }
        return "CHECK_REQUIREMENTS"
    elseif ctx.config.mode == "treefarm" or ctx.config.mode == "potatofarm" then
        logger.log(ctx, "info", "Mode: " .. ctx.config.mode)
        ctx.strategy = { type = ctx.config.mode }
        
        if ctx.config.mode == "treefarm" then
            ctx.treefarm = {
                state = "SCAN",
                width = ctx.config.width,
                height = ctx.config.height,
                chests = { output = "front", fuel = "up" } -- Default assumptions
            }
            return "TREEFARM"
        elseif ctx.config.mode == "potatofarm" then
            ctx.potatofarm = {
                state = "SCAN",
                width = ctx.config.width,
                height = ctx.config.height,
                chests = { output = "front", fuel = "up" }
            }
            return "POTATOFARM"
        end
        
        return "CHECK_REQUIREMENTS"
    end

    local schemaPath = ctx.config.schemaPath
    if not schemaPath then
        logger.log(ctx, "error", "No schema provided.")
        return "ERROR"
    end

    if not fs.exists(schemaPath) then
        logger.log(ctx, "error", "Schema file not found: " .. schemaPath)
        return "ERROR"
    end

    logger.log(ctx, "info", "Loading schema: " .. schemaPath)
    local ok, schema, meta = parser.parseFile(ctx, schemaPath)
    if not ok then
        logger.log(ctx, "error", "Failed to parse schema: " .. tostring(schema))
        return "ERROR"
    end

    ctx.schema = schema
    ctx.schemaMeta = meta
    
    -- 3. Compute Strategy
    -- For now, simple layer-by-layer
    ctx.strategy = {
        type = "build",
        order = "layer_asc"
    }
    
    -- 4. Scan Inventory
    inventory.scan(ctx)
    
    return "CHECK_REQUIREMENTS"
end

return INITIALIZE
]=])

addEmbeddedFile("factory/state_check_requirements.lua", [=[
--[[
State: CHECK_REQUIREMENTS
Verifies fuel and materials before starting/resuming.
--]]

local logger = require("lib_logger")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")

local function CHECK_REQUIREMENTS(ctx)
    logger.log(ctx, "info", "Checking requirements...")

    -- 1. Fuel
    if not fuelLib.checkFuel(ctx) then
        logger.log(ctx, "warn", "Insufficient fuel.")
        ctx.resumeState = "CHECK_REQUIREMENTS"
        return "REFUEL"
    end

    -- 2. Materials (if building)
    if ctx.strategy.type == "build" and ctx.schema then
        -- Calculate required materials vs inventory
        local required = {}
        for x, xRow in pairs(ctx.schema) do
            for y, yRow in pairs(xRow) do
                for z, block in pairs(yRow) do
                    local mat = block.material
                    required[mat] = (required[mat] or 0) + 1
                end
            end
        end
        
        inventory.scan(ctx)
        local missing = {}
        for mat, count in pairs(required) do
            local has = inventory.count(ctx, mat)
            if has < count then
                missing[mat] = count - has
            end
        end
        
        if next(missing) then
            for mat, count in pairs(missing) do
                logger.log(ctx, "warn", "Missing: " .. mat .. " x" .. count)
            end
            -- For now, just warn and proceed, or switch to RESTOCK
            -- ctx.missingMaterial = next(missing)
            -- return "RESTOCK"
            
            -- Prompt user?
            print("Missing materials. Press Enter to continue anyway (or Ctrl+T to terminate)...")
            read()
        end
    end

    if ctx.strategy.type == "mine" or ctx.strategy.type == "tunnel" or ctx.strategy.type == "excavate" then
        return "MINE"
    elseif ctx.strategy.type == "treefarm" then
        return "TREEFARM"
    elseif ctx.strategy.type == "potatofarm" then
        return "POTATOFARM"
    end

    return "BUILD"
end

return CHECK_REQUIREMENTS
]=])

addEmbeddedFile("factory/state_build.lua", [=[
--[[
State: BUILD
Executes the build plan.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local logger = require("lib_logger")
local world = require("lib_world")

local function BUILD(ctx)
    if not ctx.schema then return "DONE" end
    
    -- Simple iterator over schema
    -- We need a persistent pointer to know where we left off
    -- ctx.pointer is an index into a flattened list of blocks?
    -- Or we iterate and skip completed?
    
    -- Let's flatten the schema into a list of tasks if not done
    if not ctx.buildTasks then
        ctx.buildTasks = {}
        for x, xRow in pairs(ctx.schema) do
            for y, yRow in pairs(xRow) do
                for z, block in pairs(yRow) do
                    table.insert(ctx.buildTasks, { x=x, y=y, z=z, block=block })
                end
            end
        end
        -- Sort by Y, then X, then Z
        table.sort(ctx.buildTasks, function(a, b)
            if a.y ~= b.y then return a.y < b.y end
            if a.x ~= b.x then return a.x < b.x end
            return a.z < b.z
        end)
    end
    
    if ctx.pointer > #ctx.buildTasks then
        return "DONE"
    end
    
    local task = ctx.buildTasks[ctx.pointer]
    local x, y, z = task.x, task.y, task.z
    local block = task.block
    
    -- Move to position
    -- We want to place the block at (x,y,z) relative to origin
    -- So we should move to adjacent?
    -- Ideally move to (x, y+1, z) and place down, or (x, y-1, z) and place up.
    -- Let's try "above" strategy first.
    
    local targetPos = world.localToWorldRelative(ctx.origin, { x = x, y = y + 1, z = z })
    
    if not movement.goTo(ctx, targetPos) then
        logger.log(ctx, "warn", "Failed to reach build position.")
        return "BLOCKED"
    end
    
    -- Select material
    if not inventory.selectMaterial(ctx, block.material) then
        logger.log(ctx, "warn", "Out of material: " .. block.material)
        ctx.missingMaterial = block.material
        ctx.resumeState = "BUILD"
        return "RESTOCK"
    end
    
    -- Place
    if turtle.placeDown() then
        ctx.pointer = ctx.pointer + 1
    else
        -- Check if blocked or already placed
        local hasBlock, data = turtle.inspectDown()
        if hasBlock and data.name == block.material then
            -- Already there
            ctx.pointer = ctx.pointer + 1
        else
            logger.log(ctx, "warn", "Failed to place block.")
            -- Maybe dig?
            if hasBlock then
                turtle.digDown()
            end
        end
    end
    
    return "BUILD"
end

return BUILD
]=])

addEmbeddedFile("factory/state_mine.lua", [=[
--[[
State: MINE
Executes mining/tunneling strategy.
--]]

local movement = require("lib_movement")
local mining = require("lib_mining")
local logger = require("lib_logger")
local inventory = require("lib_inventory")

local function MINE(ctx)
    local mode = ctx.config.mode
    
    if mode == "mine" then
        -- Branch mining logic
        -- Initialize branch mine state if needed
        if not ctx.branchmine then
            ctx.branchmine = {
                state = "SPINE",
                length = ctx.config.length or 60,
                branchInterval = ctx.config.branchInterval or 3,
                branchLength = ctx.config.branchLength or 16,
                torchInterval = ctx.config.torchInterval or 6,
                currentDist = 0,
                chests = { output = "back", fuel = "up" } -- relative to start facing
            }
            return "BRANCHMINE"
        end
        return "BRANCHMINE"
        
    elseif mode == "tunnel" then
        -- Simple tunnel
        local len = ctx.config.length or 16
        local w = ctx.config.width or 1
        local h = ctx.config.height or 2
        
        -- Current progress
        ctx.tunnel = ctx.tunnel or { x=0, y=0, z=0 }
        
        if ctx.tunnel.z >= len then return "DONE" end
        
        -- Dig forward
        if not movement.forward(ctx, { dig=true }) then
            return "BLOCKED"
        end
        ctx.tunnel.z = ctx.tunnel.z + 1
        
        -- Clear cross section
        -- (Simplified: just 1x2 for now)
        if h > 1 then
            turtle.digUp()
        end
        
        -- Place torch?
        if ctx.tunnel.z % (ctx.config.torchInterval or 6) == 0 then
            -- Place torch behind or on wall
            -- ...
        end
        
        return "MINE"
        
    elseif mode == "excavate" then
        -- Excavate chunk
        -- Use built-in excavate logic or custom?
        -- For now, fallback to simple loop
        return "DONE"
    end
    
    return "DONE"
end

return MINE
]=])

addEmbeddedFile("factory/state_treefarm.lua", [=[
--[[
State: TREEFARM
Manages tree farming: scanning, harvesting, replanting.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local logger = require("lib_logger")
local world = require("lib_world")

local function TREEFARM(ctx)
    local state = ctx.treefarm.state -- SCAN, HARVEST, DEPOSIT
    
    if state == "SCAN" then
        -- Scan the farm area for fully grown trees
        -- Simple iteration over the grid
        -- We assume we are at origin or known position
        
        -- For now, just move to next sapling spot
        -- We need to know where saplings are.
        -- Hardcoded 9x9 farm with saplings at (1,1), (1,4), etc?
        -- Let's use the schema if available, or algorithmic
        
        -- Algorithmic: checkerboard or rows?
        -- Let's assume rows of saplings separated by empty rows
        -- S . S . S
        -- . . . . .
        -- S . S . S
        
        local width = ctx.treefarm.width
        local height = ctx.treefarm.height
        
        -- Iterator for sapling spots
        if not ctx.treefarm.nextSpot then
            ctx.treefarm.nextSpot = { x=1, z=1 }
        end
        
        local tx, tz = ctx.treefarm.nextSpot.x, ctx.treefarm.nextSpot.z
        
        -- Move to spot
        local target = { x=tx, y=0, z=tz }
        if not movement.goTo(ctx, target) then
            return "BLOCKED"
        end
        
        -- Check for tree
        local hasBlock, data = turtle.inspect()
        if hasBlock and (data.name:find("log") or data.name:find("wood")) then
            -- Found tree!
            ctx.treefarm.targetTree = { x=tx, z=tz }
            ctx.treefarm.state = "HARVEST"
            return "TREEFARM"
        end
        
        -- Plant if missing
        local hasBlockDown, dataDown = turtle.inspectDown()
        if not hasBlock and (not hasBlockDown or dataDown.name == "minecraft:dirt" or dataDown.name == "minecraft:grass_block") then
             -- Try to plant sapling
             if inventory.selectItem(ctx, "sapling") then
                 turtle.place()
             end
        end
        
        -- Next spot
        -- Pattern: every 3rd block?
        tx = tx + 3
        if tx >= width then
            tx = 1
            tz = tz + 3
        end
        
        if tz >= height then
            -- Finished scan
            ctx.treefarm.nextSpot = { x=1, z=1 }
            ctx.treefarm.state = "DEPOSIT" -- Go dump logs
            return "TREEFARM"
        end
        
        ctx.treefarm.nextSpot = { x=tx, z=tz }
        return "TREEFARM"
        
    elseif state == "HARVEST" then
        -- Cut down tree
        -- Dig up until no more logs
        turtle.dig()
        movement.forward(ctx)
        
        local height = 0
        while turtle.detectUp() do
            local has, data = turtle.inspectUp()
            if has and (data.name:find("log") or data.name:find("wood")) then
                turtle.digUp()
                turtle.up()
                height = height + 1
            else
                break
            end
        end
        
        -- Come down
        while height > 0 do
            turtle.down()
            height = height - 1
        end
        
        -- Back up
        movement.back(ctx)
        
        -- Replant
        if inventory.selectItem(ctx, "sapling") then
            turtle.place()
        end
        
        ctx.treefarm.state = "SCAN"
        return "TREEFARM"
        
    elseif state == "DEPOSIT" then
        -- Go to chest and dump logs/sticks/apples
        local chestPos = { x=0, y=0, z=0 } -- Adjust based on config
        if not movement.goTo(ctx, chestPos) then
            return "BLOCKED"
        end
        
        -- Dump
        for i=1,16 do
            local item = turtle.getItemDetail(i)
            if item then
                if item.name:find("log") or item.name:find("planks") or item.name:find("stick") or item.name:find("apple") then
                    turtle.select(i)
                    turtle.drop() -- Drop front
                end
            end
        end
        
        -- Refuel?
        -- ...
        
        ctx.treefarm.state = "SCAN"
        -- Sleep a bit to let trees grow
        sleep(10)
        return "TREEFARM"
    end
    
    return "DONE"
end

return TREEFARM
]=])

addEmbeddedFile("factory/state_potatofarm.lua", [=[
--[[
State: POTATOFARM
Manages potato farming: scanning, harvesting, replanting.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local logger = require("lib_logger")

local function POTATOFARM(ctx)
    local state = ctx.potatofarm.state or "SCAN"
    
    if state == "SCAN" then
        local width = ctx.potatofarm.width or 9
        local height = ctx.potatofarm.height or 9
        
        -- Iterate all blocks
        if not ctx.potatofarm.nextSpot then
            ctx.potatofarm.nextSpot = { x=1, z=1 }
        end
        
        local tx, tz = ctx.potatofarm.nextSpot.x, ctx.potatofarm.nextSpot.z
        
        -- Move to spot (above crop)
        local target = { x=tx, y=1, z=tz }
        if not movement.goTo(ctx, target) then
            return "BLOCKED"
        end
        
        -- Check crop
        local hasBlock, data = turtle.inspectDown()
        if hasBlock and data.name == "minecraft:potatoes" and data.state.age == 7 then
            -- Fully grown
            turtle.digDown()
            turtle.suckDown() -- Catch drops
            
            -- Replant
            if inventory.selectItem(ctx, "potato") then
                turtle.placeDown()
            end
        elseif not hasBlock then
            -- Empty? Replant
            if inventory.selectItem(ctx, "potato") then
                turtle.placeDown()
            end
        end
        
        -- Next spot
        tx = tx + 1
        if tx >= width then
            tx = 1
            tz = tz + 1
        end
        
        if tz >= height then
            ctx.potatofarm.nextSpot = { x=1, z=1 }
            ctx.potatofarm.state = "DEPOSIT"
            return "POTATOFARM"
        end
        
        ctx.potatofarm.nextSpot = { x=tx, z=tz }
        return "POTATOFARM"
        
    elseif state == "DEPOSIT" then
        -- Go home
        if not movement.goTo(ctx, {x=0, y=0, z=0}) then return "BLOCKED" end
        
        -- Dump extra potatoes (keep some for replanting)
        local keep = 64
        for i=1,16 do
            local item = turtle.getItemDetail(i)
            if item and item.name:find("potato") then
                local count = item.count
                if count > keep then
                    turtle.select(i)
                    turtle.drop(count - keep)
                    keep = 0
                else
                    keep = keep - count
                end
            elseif item and not item.name:find("potato") then
                -- Dump trash
                turtle.select(i)
                turtle.drop()
            end
        end
        
        ctx.potatofarm.state = "SCAN"
        sleep(60) -- Wait for growth
        return "POTATOFARM"
    end
    
    return "DONE"
end

return POTATOFARM
]=])

addEmbeddedFile("factory/state_restock.lua", [=[
--[[
State: RESTOCK
Returns to origin/chests to fetch missing materials.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local logger = require("lib_logger")

local function RESTOCK(ctx)
    logger.log(ctx, "info", "Restocking...")
    
    -- Return to origin
    if not movement.goTo(ctx, { x=0, y=0, z=0, facing="north" }) then
        logger.log(ctx, "error", "Cannot return to origin for restock.")
        return "BLOCKED"
    end
    
    -- Check chests?
    -- Assume input chest is at (0,0,0) front? Or specific location?
    -- For now, prompt user
    
    if ctx.missingMaterial then
        print("Please provide: " .. ctx.missingMaterial)
        print("Put in inventory and press Enter.")
        read()
        
        inventory.scan(ctx)
        if inventory.count(ctx, ctx.missingMaterial) > 0 then
            ctx.missingMaterial = nil
            return ctx.resumeState or "BUILD"
        end
    end
    
    return "ERROR"
end

return RESTOCK
]=])

addEmbeddedFile("factory/state_refuel.lua", [=[
--[[
State: REFUEL
Attempts to refuel from inventory or fuel chest.
--]]

local movement = require("lib_movement")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")

local function REFUEL(ctx)
    logger.log(ctx, "info", "Refueling...")
    
    if fuelLib.refuel(ctx) then
        logger.log(ctx, "info", "Refuel successful.")
        return ctx.resumeState or "CHECK_REQUIREMENTS"
    end
    
    -- Go to fuel chest?
    -- ...
    
    logger.log(ctx, "error", "Out of fuel and no fuel source found.")
    print("Please add fuel and press Enter.")
    read()
    
    if fuelLib.refuel(ctx) then
        return ctx.resumeState or "CHECK_REQUIREMENTS"
    end
    
    return "ERROR"
end

return REFUEL
]=])

addEmbeddedFile("factory/state_blocked.lua", [=[
--[[
State: BLOCKED
Handles navigation failures.
--]]

local logger = require("lib_logger")

local function BLOCKED(ctx)
    logger.log(ctx, "warn", "Movement blocked.")
    
    ctx.retries = (ctx.retries or 0) + 1
    if ctx.retries > 5 then
        logger.log(ctx, "error", "Too many retries. Stuck.")
        return "ERROR"
    end
    
    -- Try to clear obstacle?
    -- If digging enabled...
    
    -- Wait and retry
    sleep(2)
    return ctx.resumeState or "INITIALIZE" -- Fallback?
end

return BLOCKED
]=])

addEmbeddedFile("factory/state_error.lua", [=[
--[[
State: ERROR
Fatal error state.
--]]

local logger = require("lib_logger")

local function ERROR(ctx)
    logger.log(ctx, "error", "Agent stopped due to error: " .. tostring(ctx.lastError))
    return "EXIT"
end

return ERROR
]=])

addEmbeddedFile("factory/state_done.lua", [=[
--[[
State: DONE
Job complete.
--]]

local logger = require("lib_logger")
local movement = require("lib_movement")

local function DONE(ctx)
    logger.log(ctx, "info", "Job complete!")
    
    -- Return home
    movement.goTo(ctx, { x=0, y=0, z=0, facing="north" })
    
    return "EXIT"
end

return DONE
]=])

addEmbeddedFile("factory/state_branchmine.lua", [=[
--[[
State: BRANCHMINE
Implements a standard branch mining strategy.
Spine tunnel with branches every N blocks.
--]]

local movement = require("lib_movement")
local mining = require("lib_mining")
local logger = require("lib_logger")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local trash_config = require("ui.trash_config")

local function BRANCHMINE(ctx)
    local bm = ctx.branchmine
    
    -- Helper to check fuel and inventory
    local function checkStatus()
        if not fuelLib.hasFuel(ctx) then
            -- Mark where we are, go refuel
            bm.resumePos = movement.getPos(ctx)
            bm.resumeState = bm.state
            bm.state = "RETURN_REFUEL"
            return false
        end
        
        if inventory.isFull(ctx) then
             bm.resumePos = movement.getPos(ctx)
             bm.resumeState = bm.state
             bm.state = "RETURN_UNLOAD"
             return false
        end
        return true
    end

    if bm.state == "SPINE" then
        if not checkStatus() then return "BRANCHMINE" end
        
        if bm.currentDist >= bm.length then
            bm.state = "RETURNING"
            return "BRANCHMINE"
        end
        
        -- Dig spine forward
        if not movement.forward(ctx, { dig=true }) then
            return "BLOCKED"
        end
        bm.currentDist = bm.currentDist + 1
        
        -- Dig up (2 high spine)
        turtle.digUp()
        
        -- Check if branch point
        if bm.currentDist % bm.branchInterval == 0 then
            bm.state = "BRANCH_LEFT"
        end
        
        -- Torch?
        if bm.currentDist % bm.torchInterval == 0 then
            -- Place torch
            if inventory.selectItem(ctx, "torch") then
                -- Place on floor or wall?
                -- Move back, place, move forward?
                -- Or place up?
                -- turtle.placeUp() -- if space
            end
        end
        
        return "BRANCHMINE"
        
    elseif bm.state == "BRANCH_LEFT" then
        if not checkStatus() then return "BRANCHMINE" end
        
        -- Turn left
        movement.turnLeft(ctx)
        
        -- Dig branch
        for i=1, bm.branchLength do
            if not movement.forward(ctx, { dig=true }) then
                -- Hit bedrock or unbreakable?
                break
            end
            -- Dig up?
            turtle.digUp()
            
            -- Check ores (up, down, sides?)
            mining.checkVein(ctx)
        end
        
        -- Return to spine
        movement.turnAround(ctx)
        for i=1, bm.branchLength do
            movement.forward(ctx)
        end
        movement.turnLeft(ctx) -- Face forward again
        
        bm.state = "BRANCH_RIGHT"
        return "BRANCHMINE"
        
    elseif bm.state == "BRANCH_RIGHT" then
        if not checkStatus() then return "BRANCHMINE" end
        
        -- Turn right
        movement.turnRight(ctx)
        
        -- Dig branch
        for i=1, bm.branchLength do
            if not movement.forward(ctx, { dig=true }) then
                break
            end
            turtle.digUp()
            mining.checkVein(ctx)
        end
        
        -- Return
        movement.turnAround(ctx)
        for i=1, bm.branchLength do
            movement.forward(ctx)
        end
        movement.turnRight(ctx) -- Face forward
        
        bm.state = "SPINE"
        return "BRANCHMINE"
        
    elseif bm.state == "RETURNING" then
        -- Go back to start
        if not movement.goTo(ctx, {x=0, y=0, z=0, facing="north"}) then
            return "BLOCKED"
        end
        return "DONE"
        
    elseif bm.state == "RETURN_REFUEL" or bm.state == "RETURN_UNLOAD" then
        -- Go home
        if not movement.goTo(ctx, {x=0, y=0, z=0, facing="north"}) then
            return "BLOCKED"
        end
        
        if bm.state == "RETURN_UNLOAD" then
            -- Dump items
            -- Turn to chest (back?)
            movement.turnAround(ctx)
            for i=1,16 do
                local item = turtle.getItemDetail(i)
                if item and not trash_config.isTrash(item.name) then
                    turtle.select(i)
                    turtle.drop()
                else
                    -- Trash?
                    turtle.select(i)
                    turtle.dropUp() -- Trash can up?
                end
            end
            movement.turnAround(ctx)
        end
        
        if bm.state == "RETURN_REFUEL" then
            fuelLib.refuel(ctx)
        end
        
        -- Resume
        if not movement.goTo(ctx, bm.resumePos) then
            return "BLOCKED"
        end
        
        bm.state = bm.resumeState
        return "BRANCHMINE"
    end
    
    return "DONE"
end

return BRANCHMINE
]=])

addEmbeddedFile("lib/lib_logger.lua", [=[
--[[
Logger library for CC:Tweaked turtles.
Provides leveled logging with optional timestamping, history capture, and
custom sinks. Public methods work with either colon or dot syntax.
--]]

---@diagnostic disable: undefined-global

local logger = {}

local diagnostics
local diagnosticsOk, diagnosticsModule = pcall(require, "lib_diagnostics")
if diagnosticsOk then
    diagnostics = diagnosticsModule
end

local DEFAULT_CRASH_FILE = "crashfile"

local DEFAULT_LEVEL = "info"
local DEFAULT_CAPTURE_LIMIT = 200

local LEVEL_VALUE = {
    debug = 10,
    info = 20,
    warn = 30,
    error = 40,
}

local LEVEL_LABEL = {
    debug = "DEBUG",
    info = "INFO",
    warn = "WARN",
    error = "ERROR",
}

local LEVEL_ALIAS = {
    warning = "warn",
    err = "error",
    trace = "debug",
    verbose = "debug",
    fatal = "error",
}

local function isoTimestamp()
    if os and type(os.date) == "function" then
        return os.date("!%Y-%m-%dT%H:%M:%SZ")
    end
    if os and type(os.clock) == "function" then
        return string.format("%.03f", os.clock())
    end
    return nil
end

local function getCrashFilePath(ctx)
    if ctx then
        local config = ctx.config
        if config and type(config.crashFile) == "string" and config.crashFile ~= "" then
            return config.crashFile
        end
        if type(ctx.crashFilePath) == "string" and ctx.crashFilePath ~= "" then
            return ctx.crashFilePath
        end
    end
    return DEFAULT_CRASH_FILE
end

local function buildCrashPayload(ctx, message, metadata)
    local payload = {
        message = message or "Unknown fatal error",
        metadata = metadata,
        timestamp = isoTimestamp(),
    }
    if diagnostics and ctx then
        local ok, snapshot = pcall(diagnostics.snapshot, ctx)
        if ok then
            payload.context = snapshot
        end
    end
    if ctx and ctx.logger and type(ctx.logger.getLastEntry) == "function" then
        local ok, entry = pcall(ctx.logger.getLastEntry, ctx.logger)
        if ok then
            payload.lastLogEntry = entry
        end
    end
    return payload
end

local function serializeCrashPayload(payload)
    if textutils and type(textutils.serializeJSON) == "function" then
        local ok, serialized = pcall(textutils.serializeJSON, payload, { compact = true })
        if ok then
            return serialized
        end
    end
    if textutils and type(textutils.serialize) == "function" then
        local ok, serialized = pcall(textutils.serialize, payload)
        if ok then
            return serialized
        end
    end
    local parts = {}
    for key, value in pairs(payload or {}) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
    end
    table.sort(parts)
    return table.concat(parts, "\n")
end

local function writeFile(path, contents)
    if not fs or type(fs.open) ~= "function" then
        return false, "fs_unavailable"
    end
    local handle, err = fs.open(path, "w")
    if not handle then
        return false, err or "open_failed"
    end
    handle.write(contents)
    handle.close()
    return true
end

local function copyTable(value, depth, seen)
    if type(value) ~= "table" then
        return value
    end
    if depth and depth <= 0 then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return "<recursive>"
    end
    seen[value] = true
    local result = {}
    for k, v in pairs(value) do
        local newKey = copyTable(k, depth and (depth - 1) or nil, seen)
        local newValue = copyTable(v, depth and (depth - 1) or nil, seen)
        result[newKey] = newValue
    end
    seen[value] = nil
    return result
end

local function trySerializers(meta)
    if type(meta) ~= "table" then
        return nil
    end
    if textutils and type(textutils.serialize) == "function" then
        local ok, serialized = pcall(textutils.serialize, meta)
        if ok then
            return serialized
        end
    end
    if textutils and type(textutils.serializeJSON) == "function" then
        local ok, serialized = pcall(textutils.serializeJSON, meta)
        if ok then
            return serialized
        end
    end
    return nil
end

local function formatMetadata(meta)
    if meta == nil then
        return ""
    end
    local metaType = type(meta)
    if metaType == "string" then
        return meta
    elseif metaType == "number" or metaType == "boolean" then
        return tostring(meta)
    elseif metaType == "table" then
        local serialized = trySerializers(meta)
        if serialized then
            return serialized
        end
        local parts = {}
        local count = 0
        for key, value in pairs(meta) do
            parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
            count = count + 1
            if count >= 16 then
                break
            end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(meta)
end

local function formatMessage(message)
    if message == nil then
        return ""
    end
    local msgType = type(message)
    if msgType == "string" then
        return message
    elseif msgType == "number" or msgType == "boolean" then
        return tostring(message)
    elseif msgType == "table" then
        if message.message and type(message.message) == "string" then
            return message.message
        end
        local metaView = formatMetadata(message)
        if metaView ~= "" then
            return metaView
        end
    end
    return tostring(message)
end

local function resolveLevel(level)
    if type(level) == "string" then
        local lowered = level:lower()
        lowered = LEVEL_ALIAS[lowered] or lowered
        if LEVEL_VALUE[lowered] then
            return lowered
        end
        return nil
    elseif type(level) == "number" then
        local closest
        local distance
        for name, value in pairs(LEVEL_VALUE) do
            local diff = math.abs(value - level)
            if not closest or diff < distance then
                closest = name
                distance = diff
            end
        end
        return closest
    end
    return nil
end

local function levelValue(level)
    return LEVEL_VALUE[level] or LEVEL_VALUE[DEFAULT_LEVEL]
end

local function shouldEmit(level, thresholdValue)
    return levelValue(level) >= thresholdValue
end

local function formatTimestamp(state)
    if not state.timestamps then
        return nil, nil
    end
    local fmt = state.timestampFormat or "%H:%M:%S"
    if os and type(os.date) == "function" then
        local timeNumber = os.time and os.time() or nil
        local stamp = os.date(fmt)
        return stamp, timeNumber
    end
    if os and type(os.clock) == "function" then
        local clockValue = os.clock()
        return string.format("%.03f", clockValue), clockValue
    end
    return nil, nil
end

local function cloneEntry(entry)
    return copyTable(entry, 3)
end

local function pushHistory(state, entry)
    local history = state.history
    history[#history + 1] = cloneEntry(entry)
    local limit = state.captureLimit or DEFAULT_CAPTURE_LIMIT
    while #history > limit do
        table.remove(history, 1)
    end
end

local function defaultWriterFactory(state)
    return function(entry)
        local segments = {}
        if entry.timestamp then
            segments[#segments + 1] = entry.timestamp
        elseif state.timestamps and state.lastTimestamp then
            segments[#segments + 1] = state.lastTimestamp
        end
        if entry.tag then
            segments[#segments + 1] = entry.tag
        elseif state.tag then
            segments[#segments + 1] = state.tag
        end
        segments[#segments + 1] = entry.levelLabel or entry.level
        local prefix = "[" .. table.concat(segments, "][") .. "]"
        local line = prefix .. " " .. entry.message
        local metaStr = formatMetadata(entry.metadata)
        if metaStr ~= "" then
            line = line .. " | " .. metaStr
        end
        if print then
            print(line)
        elseif io and io.write then
            io.write(line .. "\n")
        end
    end
end

local function addWriter(state, writer)
    if type(writer) ~= "function" then
        return false, "invalid_writer"
    end
    for _, existing in ipairs(state.writers) do
        if existing == writer then
            return false, "writer_exists"
        end
    end
    state.writers[#state.writers + 1] = writer
    return true
end

local function logInternal(state, level, message, metadata)
    local resolved = resolveLevel(level)
    if not resolved then
        return false, "unknown_level"
    end
    if not shouldEmit(resolved, state.thresholdValue) then
        return false, "level_filtered"
    end

    local timestamp, timeNumber = formatTimestamp(state)
    state.lastTimestamp = timestamp or state.lastTimestamp

    local entry = {
        level = resolved,
        levelLabel = LEVEL_LABEL[resolved],
        message = formatMessage(message),
        metadata = metadata,
        timestamp = timestamp,
        time = timeNumber,
        sequence = state.sequence + 1,
        tag = state.tag,
    }

    state.sequence = entry.sequence
    state.lastEntry = entry

    if state.capture then
        pushHistory(state, entry)
    end

    for _, writer in ipairs(state.writers) do
        local ok, err = pcall(writer, entry)
        if not ok then
            state.lastWriterError = err
        end
    end

    return true, entry
end

function logger.new(opts)
    local state = {
        capture = opts and opts.capture or false,
        captureLimit = (opts and type(opts.captureLimit) == "number" and opts.captureLimit > 0) and opts.captureLimit or DEFAULT_CAPTURE_LIMIT,
        history = {},
        sequence = 0,
        writers = {},
        timestamps = opts and (opts.timestamps or opts.timestamp) or false,
        timestampFormat = opts and opts.timestampFormat or nil,
        tag = opts and (opts.tag or opts.label) or nil,
    }

    local initialLevel = (opts and resolveLevel(opts.level)) or (opts and resolveLevel(opts.minLevel)) or DEFAULT_LEVEL
    state.threshold = initialLevel
    state.thresholdValue = levelValue(initialLevel)

    local instance = {}
    state.instance = instance

    if not (opts and opts.silent) then
        addWriter(state, defaultWriterFactory(state))
    end
    if opts and type(opts.writer) == "function" then
        addWriter(state, opts.writer)
    end
    if opts and type(opts.writers) == "table" then
        for _, writer in ipairs(opts.writers) do
            if type(writer) == "function" then
                addWriter(state, writer)
            end
        end
    end

    function instance:log(level, message, metadata)
        return logInternal(state, level, message, metadata)
    end

    function instance:debug(message, metadata)
        return logInternal(state, "debug", message, metadata)
    end

    function instance:info(message, metadata)
        return logInternal(state, "info", message, metadata)
    end

    function instance:warn(message, metadata)
        return logInternal(state, "warn", message, metadata)
    end

    function instance:error(message, metadata)
        return logInternal(state, "error", message, metadata)
    end

    function instance:setLevel(level)
        local resolved = resolveLevel(level)
        if not resolved then
            return false, "unknown_level"
        end
        state.threshold = resolved
        state.thresholdValue = levelValue(resolved)
        return true, resolved
    end

    function instance:getLevel()
        return state.threshold
    end

    function instance:enableCapture(limit)
        state.capture = true
        if type(limit) == "number" and limit > 0 then
            state.captureLimit = limit
        end
        return true
    end

    function instance:disableCapture()
        state.capture = false
        state.history = {}
        return true
    end

    function instance:getHistory()
        local result = {}
        for index = 1, #state.history do
            result[index] = cloneEntry(state.history[index])
        end
        return result
    end

    function instance:clearHistory()
        state.history = {}
        return true
    end

    function instance:addWriter(writer)
        return addWriter(state, writer)
    end

    function instance:removeWriter(writer)
        if type(writer) ~= "function" then
            return false, "invalid_writer"
        end
        for index, existing in ipairs(state.writers) do
            if existing == writer then
                table.remove(state.writers, index)
                return true
            end
        end
        return false, "writer_missing"
    end

    function instance:setTag(tag)
        state.tag = tag
        return true
    end

    function instance:getTag()
        return state.tag
    end

    function instance:getLastEntry()
        if not state.lastEntry then
            return nil
        end
        return cloneEntry(state.lastEntry)
    end

    function instance:getLastWriterError()
        return state.lastWriterError
    end

    function instance:setTimestamps(enabled, format)
        state.timestamps = not not enabled
        if format then
            state.timestampFormat = format
        end
        return true
    end

    return instance
end

function logger.attach(ctx, opts)
    if type(ctx) ~= "table" then
        error("logger.attach requires a context table", 2)
    end
    local instance = logger.new(opts)
    ctx.logger = instance
    return instance
end

function logger.isLogger(candidate)
    if type(candidate) ~= "table" then
        return false
    end
    return type(candidate.log) == "function"
        and type(candidate.info) == "function"
        and type(candidate.warn) == "function"
        and type(candidate.error) == "function"
end

logger.DEFAULT_LEVEL = DEFAULT_LEVEL
logger.DEFAULT_CAPTURE_LIMIT = DEFAULT_CAPTURE_LIMIT
logger.LEVELS = copyTable(LEVEL_VALUE, 1)
logger.LABELS = copyTable(LEVEL_LABEL, 1)
logger.resolveLevel = resolveLevel
logger.DEFAULT_CRASH_FILE = DEFAULT_CRASH_FILE

function logger.log(ctx, level, message)
    if type(ctx) ~= "table" then
        return
    end
    local logInst = ctx.logger
    if type(logInst) == "table" then
        local fn = logInst[level]
        if type(fn) == "function" then
            fn(logInst, message)
            return
        end
        if type(logInst.log) == "function" then
            logInst.log(logInst, level, message)
            return
        end
    end
    if (level == "warn" or level == "error") and message then
        print(string.format("[%s] %s", level:upper(), message))
    end
end

function logger.writeCrashFile(ctx, message, metadata)
    local path = getCrashFilePath(ctx)
    local payload = buildCrashPayload(ctx, message, metadata)
    local body = serializeCrashPayload(payload)
    if not body or body == "" then
        body = tostring(message or "Unknown fatal error")
    end
    local ok, err = writeFile(path, body .. "\n")
    if not ok then
        return false, err
    end
    if ctx then
        ctx.crashFilePath = path
    end
    return true, path
end

return logger
]=])

addEmbeddedFile("lib/lib_movement.lua", [=[
--[[-
Movement library for CC:Tweaked turtles.
Provides orientation tracking, safe movement primitives, and navigation helpers.
All public functions accept a shared ctx table and return success booleans
with optional error messages.
--]]

---@diagnostic disable: undefined-global, undefined-field

local movement = {}
local logger = require("lib_logger")

local CARDINALS = {"north", "east", "south", "west"}
local DIRECTION_VECTORS = {
    north = { x = 0, y = 0, z = -1 },
    east = { x = 1, y = 0, z = 0 },
    south = { x = 0, y = 0, z = 1 },
    west = { x = -1, y = 0, z = 0 },
}

local AXIS_FACINGS = {
    x = { positive = "east", negative = "west" },
    z = { positive = "south", negative = "north" },
}

local DEFAULT_SOFT_BLOCKS = {
    ["minecraft:snow"] = true,
    ["minecraft:snow_layer"] = true,
    ["minecraft:powder_snow"] = true,
    ["minecraft:tall_grass"] = true,
    ["minecraft:large_fern"] = true,
    ["minecraft:grass"] = true,
    ["minecraft:fern"] = true,
    ["minecraft:cave_vines"] = true,
    ["minecraft:cave_vines_plant"] = true,
    ["minecraft:kelp"] = true,
    ["minecraft:kelp_plant"] = true,
    ["minecraft:sweet_berry_bush"] = true,
}

local DEFAULT_SOFT_TAGS = {
    ["minecraft:snow"] = true,
    ["minecraft:replaceable_plants"] = true,
    ["minecraft:flowers"] = true,
    ["minecraft:saplings"] = true,
    ["minecraft:carpets"] = true,
}

local DEFAULT_SOFT_NAME_HINTS = {
    "sapling",
    "propagule",
    "seedling",
}

local function cloneLookup(source)
    local lookup = {}
    for key, value in pairs(source) do
        if value then
            lookup[key] = true
        end
    end
    return lookup
end

local function extendLookup(lookup, entries)
    if type(entries) ~= "table" then
        return lookup
    end
    if #entries > 0 then
        for _, name in ipairs(entries) do
            if type(name) == "string" then
                lookup[name] = true
            end
        end
    else
        for name, enabled in pairs(entries) do
            if enabled and type(name) == "string" then
                lookup[name] = true
            end
        end
    end
    return lookup
end

local function buildSoftNameHintList(configHints)
    local seen = {}
    local list = {}

    local function append(value)
        if type(value) ~= "string" then
            return
        end
        local normalized = value:lower()
        if normalized == "" or seen[normalized] then
            return
        end
        seen[normalized] = true
        list[#list + 1] = normalized
    end

    for _, hint in ipairs(DEFAULT_SOFT_NAME_HINTS) do
        append(hint)
    end

    if type(configHints) == "table" then
        if #configHints > 0 then
            for _, entry in ipairs(configHints) do
                append(entry)
            end
        else
            for name, enabled in pairs(configHints) do
                if enabled then
                    append(name)
                end
            end
        end
    elseif type(configHints) == "string" then
        append(configHints)
    end

    return list
end

local function matchesSoftNameHint(hints, blockName)
    if type(blockName) ~= "string" then
        return false
    end
    local lowered = blockName:lower()
    for _, hint in ipairs(hints or {}) do
        if lowered:find(hint, 1, true) then
            return true
        end
    end
    return false
end

local function isSoftBlock(state, inspectData)
    if type(state) ~= "table" or type(inspectData) ~= "table" then
        return false
    end
    local name = inspectData.name
    if type(name) == "string" then
        if state.softBlockLookup and state.softBlockLookup[name] then
            return true
        end
        if matchesSoftNameHint(state.softNameHints, name) then
            return true
        end
    end
    local tags = inspectData.tags
    if type(tags) == "table" and state.softTagLookup then
        for tag, value in pairs(tags) do
            if value and state.softTagLookup[tag] then
                return true
            end
        end
    end
    return false
end

local function canonicalFacing(name)
    if type(name) ~= "string" then
        return nil
    end
    name = name:lower()
    if DIRECTION_VECTORS[name] then
        return name
    end
    return nil
end

local function copyPosition(pos)
    if not pos then
        return { x = 0, y = 0, z = 0 }
    end
    return { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
end

local function vecAdd(a, b)
    return { x = (a.x or 0) + (b.x or 0), y = (a.y or 0) + (b.y or 0), z = (a.z or 0) + (b.z or 0) }
end

local function getPlannedMaterial(ctx, pos)
    if type(ctx) ~= "table" or type(pos) ~= "table" then
        return nil
    end

    local plan = ctx.buildPlan
    if type(plan) ~= "table" then
        return nil
    end

    local x = pos.x
    local xLayer = plan[x] or plan[tostring(x)]
    if type(xLayer) ~= "table" then
        return nil
    end

    local y = pos.y
    local yLayer = xLayer[y] or xLayer[tostring(y)]
    if type(yLayer) ~= "table" then
        return nil
    end

    local z = pos.z
    return yLayer[z] or yLayer[tostring(z)]
end

local function tryInspect(inspectFn)
    if type(inspectFn) ~= "function" then
        return nil
    end

    local ok, success, data = pcall(inspectFn)
    if not ok or not success then
        return nil
    end

    if type(data) == "table" then
        return data
    end

    return nil
end

local function ensureMovementState(ctx)
    if type(ctx) ~= "table" then
        error("movement library requires a context table", 2)
    end

    ctx.movement = ctx.movement or {}
    local state = ctx.movement
    local cfg = ctx.config or {}

    if not state.position then
        if ctx.origin then
            state.position = copyPosition(ctx.origin)
        else
            state.position = { x = 0, y = 0, z = 0 }
        end
    end

    if not state.homeFacing then
        state.homeFacing = canonicalFacing(cfg.homeFacing) or canonicalFacing(cfg.initialFacing) or "north"
    end

    if not state.facing then
        state.facing = canonicalFacing(cfg.initialFacing) or state.homeFacing
    end

    state.position = copyPosition(state.position)

    if not state.softBlockLookup then
        state.softBlockLookup = extendLookup(cloneLookup(DEFAULT_SOFT_BLOCKS), cfg.movementSoftBlocks)
    end
    if not state.softTagLookup then
        state.softTagLookup = extendLookup(cloneLookup(DEFAULT_SOFT_TAGS), cfg.movementSoftTags)
    end
    if not state.softNameHints then
        state.softNameHints = buildSoftNameHintList(cfg.movementSoftNameHints)
    end
    state.hasSoftClearRules = (next(state.softBlockLookup) ~= nil)
        or (next(state.softTagLookup) ~= nil)
        or ((state.softNameHints and #state.softNameHints > 0) or false)

    return state
end

function movement.ensureState(ctx)
    return ensureMovementState(ctx)
end

function movement.getPosition(ctx)
    local state = ensureMovementState(ctx)
    return copyPosition(state.position)
end

function movement.setPosition(ctx, pos)
    local state = ensureMovementState(ctx)
    state.position = copyPosition(pos)
    return true
end

function movement.getFacing(ctx)
    local state = ensureMovementState(ctx)
    return state.facing
end

function movement.setFacing(ctx, facing)
    local state = ensureMovementState(ctx)
    local canonical = canonicalFacing(facing)
    if not canonical then
        return false, "unknown facing: " .. tostring(facing)
    end
    state.facing = canonical
    logger.log(ctx, "debug", "Set facing to " .. canonical)
    if ctx.save then ctx.save() end
    return true
end

local function turn(ctx, direction)
    local state = ensureMovementState(ctx)
    if not turtle then
        return false, "turtle API unavailable"
    end

    local rotateFn
    if direction == "left" then
        rotateFn = turtle.turnLeft
    elseif direction == "right" then
        rotateFn = turtle.turnRight
    else
        return false, "invalid turn direction"
    end

    if not rotateFn then
        return false, "turn function missing"
    end

    local ok = rotateFn()
    if not ok then
        return false, "turn " .. direction .. " failed"
    end

    local current = state.facing
    local index
    for i, name in ipairs(CARDINALS) do
        if name == current then
            index = i
            break
        end
    end
    if not index then
        index = 1
        current = CARDINALS[index]
    end

    if direction == "left" then
        index = ((index - 2) % #CARDINALS) + 1
    else
        index = (index % #CARDINALS) + 1
    end

    state.facing = CARDINALS[index]
    logger.log(ctx, "debug", "Turned " .. direction .. ", now facing " .. state.facing)
    if ctx.save then ctx.save() end
    return true
end

function movement.turnLeft(ctx)
    return turn(ctx, "left")
end

function movement.turnRight(ctx)
    return turn(ctx, "right")
end

function movement.turnAround(ctx)
    local ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    return true
end

function movement.faceDirection(ctx, targetFacing)
    local state = ensureMovementState(ctx)
    local canonical = canonicalFacing(targetFacing)
    if not canonical then
        return false, "unknown facing: " .. tostring(targetFacing)
    end

    local currentIndex
    local targetIndex
    for i, name in ipairs(CARDINALS) do
        if name == state.facing then
            currentIndex = i
        end
        if name == canonical then
            targetIndex = i
        end
    end

    if not targetIndex then
        return false, "cannot face unknown cardinal"
    end

    if currentIndex == targetIndex then
        return true
    end

    if not currentIndex then
        state.facing = canonical
        return true
    end

    local diff = (targetIndex - currentIndex) % #CARDINALS
    if diff == 0 then
        return true
    elseif diff == 1 then
        return movement.turnRight(ctx)
    elseif diff == 2 then
        local ok, err = movement.turnRight(ctx)
        if not ok then
            return false, err
        end
        ok, err = movement.turnRight(ctx)
        if not ok then
            return false, err
        end
        return true
    else -- diff == 3
        return movement.turnLeft(ctx)
    end
end

local function getMoveConfig(ctx, opts)
    local cfg = ctx.config or {}
    local maxRetries = (opts and opts.maxRetries) or cfg.maxMoveRetries or 5
    local allowDig = opts and opts.dig
    if allowDig == nil then
        allowDig = cfg.digOnMove
        if allowDig == nil then
            allowDig = true
        end
    end
    local allowAttack = opts and opts.attack
    if allowAttack == nil then
        allowAttack = cfg.attackOnMove
        if allowAttack == nil then
            allowAttack = true
        end
    end
    local delay = (opts and opts.retryDelay) or cfg.moveRetryDelay or 0.5
    return maxRetries, allowDig, allowAttack, delay
end

local function moveWithRetries(ctx, opts, moveFns, delta)
    local state = ensureMovementState(ctx)
    if not turtle then
        return false, "turtle API unavailable"
    end

    local maxRetries, allowDig, allowAttack, delay = getMoveConfig(ctx, opts)
    if type(maxRetries) ~= "number" or maxRetries < 1 then
        maxRetries = 1
    else
        maxRetries = math.floor(maxRetries)
    end
    if (allowDig or state.hasSoftClearRules) and maxRetries < 2 then
        -- Ensure we attempt at least two cycles whenever we might clear obstructions.
        maxRetries = 2
    end
    local attempt = 0

    while attempt < maxRetries do
        attempt = attempt + 1
        local targetPos = vecAdd(state.position, delta)

        if moveFns.move() then
            state.position = targetPos
            logger.log(ctx, "debug", string.format("Moved to x=%d y=%d z=%d", state.position.x, state.position.y, state.position.z))
            if ctx.save then ctx.save() end
            return true
        end

        local handled = false

        if allowAttack and moveFns.attack then
            if moveFns.attack() then
                handled = true
                logger.log(ctx, "debug", "Attacked entity blocking movement")
            end
        end

        local blocked = moveFns.detect and moveFns.detect() or false
        local inspectData
        if blocked then
            inspectData = tryInspect(moveFns.inspect)
        end

        if blocked and moveFns.dig then
            local plannedMaterial
            local canClear = false
            local softBlock = inspectData and isSoftBlock(state, inspectData)

            if softBlock then
                canClear = true
            elseif allowDig then
                plannedMaterial = getPlannedMaterial(ctx, targetPos)
                canClear = true
                
                -- Safety check: Do not dig chests/barrels unless explicitly allowed
                if inspectData and inspectData.name and (inspectData.name:find("chest") or inspectData.name:find("barrel")) then
                    if not opts or not opts.forceDigChests then
                        canClear = false
                        logger.log(ctx, "warn", "Refusing to dig chest/barrel at " .. tostring(inspectData.name))
                    end
                end

                if plannedMaterial then
                    if inspectData and inspectData.name then
                        if inspectData.name == plannedMaterial then
                            canClear = false
                        end
                    else
                        canClear = false
                    end
                end
            end

            if canClear and moveFns.dig() then
                handled = true
                if moveFns.suck then
                    moveFns.suck()
                end
                if softBlock then
                    local foundName = inspectData and inspectData.name or "unknown"
                    logger.log(ctx, "debug", string.format(
                        "Cleared soft obstruction %s at x=%d y=%d z=%d",
                        tostring(foundName),
                        targetPos.x or 0,
                        targetPos.y or 0,
                        targetPos.z or 0
                    ))
                elseif plannedMaterial then
                    local foundName = inspectData and inspectData.name or "unknown"
                    logger.log(ctx, "debug", string.format(
                        "Cleared mismatched block %s (expected %s) at x=%d y=%d z=%d",
                        tostring(foundName),
                        tostring(plannedMaterial),
                        targetPos.x or 0,
                        targetPos.y or 0,
                        targetPos.z or 0
                    ))
                else
                    local foundName = inspectData and inspectData.name
                    if foundName then
                        logger.log(ctx, "debug", string.format(
                            "Dug blocking block %s at x=%d y=%d z=%d",
                            foundName,
                            targetPos.x or 0,
                            targetPos.y or 0,
                            targetPos.z or 0
                        ))
                    else
                        logger.log(ctx, "debug", string.format(
                            "Dug blocking block at x=%d y=%d z=%d",
                            targetPos.x or 0,
                            targetPos.y or 0,
                            targetPos.z or 0
                        ))
                    end
                end
            elseif plannedMaterial and not canClear and allowDig then
                logger.log(ctx, "debug", string.format(
                    "Preserving planned block %s at x=%d y=%d z=%d",
                    tostring(plannedMaterial),
                    targetPos.x or 0,
                    targetPos.y or 0,
                    targetPos.z or 0
                ))
            end
        end

        if attempt < maxRetries then
            if delay and delay > 0 and _G.sleep then
                sleep(delay)
            end
        end
    end

    local axisDelta = string.format("(dx=%d, dy=%d, dz=%d)", delta.x or 0, delta.y or 0, delta.z or 0)
    return false, "unable to move " .. axisDelta .. " after " .. tostring(maxRetries) .. " attempts"
end

function movement.forward(ctx, opts)
    local state = ensureMovementState(ctx)
    local facing = state.facing or "north"
    local delta = copyPosition(DIRECTION_VECTORS[facing])

    local moveFns = {
        move = turtle and turtle.forward or nil,
        detect = turtle and turtle.detect or nil,
        dig = turtle and turtle.dig or nil,
        attack = turtle and turtle.attack or nil,
        inspect = turtle and turtle.inspect or nil,
        suck = turtle and turtle.suck or nil,
    }

    if not moveFns.move then
        return false, "turtle API unavailable"
    end

    return moveWithRetries(ctx, opts, moveFns, delta)
end

function movement.up(ctx, opts)
    local moveFns = {
        move = turtle and turtle.up or nil,
        detect = turtle and turtle.detectUp or nil,
        dig = turtle and turtle.digUp or nil,
        attack = turtle and turtle.attackUp or nil,
        inspect = turtle and turtle.inspectUp or nil,
        suck = turtle and turtle.suckUp or nil,
    }
    if not moveFns.move then
        return false, "turtle API unavailable"
    end
    return moveWithRetries(ctx, opts, moveFns, { x = 0, y = 1, z = 0 })
end

function movement.down(ctx, opts)
    local moveFns = {
        move = turtle and turtle.down or nil,
        detect = turtle and turtle.detectDown or nil,
        dig = turtle and turtle.digDown or nil,
        attack = turtle and turtle.attackDown or nil,
        inspect = turtle and turtle.inspectDown or nil,
        suck = turtle and turtle.suckDown or nil,
    }
    if not moveFns.move then
        return false, "turtle API unavailable"
    end
    return moveWithRetries(ctx, opts, moveFns, { x = 0, y = -1, z = 0 })
end

local function axisFacing(axis, delta)
    if delta > 0 then
        return AXIS_FACINGS[axis].positive
    else
        return AXIS_FACINGS[axis].negative
    end
end

local function moveAxis(ctx, axis, delta, opts)
    if delta == 0 then
        return true
    end

    if axis == "y" then
        local moveFn = delta > 0 and movement.up or movement.down
        for _ = 1, math.abs(delta) do
            local ok, err = moveFn(ctx, opts)
            if not ok then
                return false, err
            end
        end
        return true
    end

    local targetFacing = axisFacing(axis, delta)
    local ok, err = movement.faceDirection(ctx, targetFacing)
    if not ok then
        return false, err
    end

    for step = 1, math.abs(delta) do
        ok, err = movement.forward(ctx, opts)
        if not ok then
            return false, string.format("failed moving along %s on step %d: %s", axis, step, err or "unknown")
        end
    end
    return true
end

function movement.goTo(ctx, targetPos, opts)
    ensureMovementState(ctx)
    if type(targetPos) ~= "table" then
        return false, "target position must be a table"
    end

    local state = ctx.movement
    local axisOrder = (opts and opts.axisOrder) or (ctx.config and ctx.config.movementAxisOrder) or { "x", "z", "y" }

    for _, axis in ipairs(axisOrder) do
        local desired = targetPos[axis]
        if desired == nil then
            return false, "target position missing axis " .. axis
        end
        local delta = desired - (state.position[axis] or 0)
        local ok, err = moveAxis(ctx, axis, delta, opts)
        if not ok then
            return false, err
        end
    end

    return true
end

function movement.stepPath(ctx, pathNodes, opts)
    if type(pathNodes) ~= "table" then
        return false, "pathNodes must be a table"
    end

    for index, node in ipairs(pathNodes) do
        local ok, err = movement.goTo(ctx, node, opts)
        if not ok then
            return false, string.format("failed at path node %d: %s", index, err or "unknown")
        end
    end

    return true
end

function movement.returnToOrigin(ctx, opts)
    ensureMovementState(ctx)
    if not ctx.origin then
        return false, "ctx.origin is required"
    end

    local ok, err = movement.goTo(ctx, ctx.origin, opts)
    if not ok then
        return false, err
    end

    local desiredFacing = (opts and opts.facing) or ctx.movement.homeFacing
    if desiredFacing then
        ok, err = movement.faceDirection(ctx, desiredFacing)
        if not ok then
            return false, err
        end
    end

    return true
end

function movement.turnLeftOf(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return "west"
    elseif facing == "west" then
        return "south"
    elseif facing == "south" then
        return "east"
    else -- east
        return "north"
    end
end

function movement.turnRightOf(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return "east"
    elseif facing == "east" then
        return "south"
    elseif facing == "south" then
        return "west"
    else -- west
        return "north"
    end
end

function movement.turnBackOf(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return "south"
    elseif facing == "south" then
        return "north"
    elseif facing == "east" then
        return "west"
    else -- west
        return "east"
    end
end
function movement.describePosition(ctx)
    local pos = movement.getPosition(ctx)
    local facing = movement.getFacing(ctx)
    return string.format("(x=%d, y=%d, z=%d, facing=%s)", pos.x, pos.y, pos.z, tostring(facing))
end

function movement.face(ctx, targetFacing)
    return movement.faceDirection(ctx, targetFacing)
end

return movement
]=])

addEmbeddedFile("lib/lib_ui.lua", [=[
--[[
UI Library for TurtleOS (Mouse/GUI Edition)
Provides DOS-style windowing and widgets.
--]]

local ui = {}

local colors_bg = colors.blue
local colors_fg = colors.white
local colors_btn = colors.lightGray
local colors_btn_text = colors.black
local colors_input = colors.black
local colors_input_text = colors.white

function ui.clear()
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.clear()
end

function ui.drawBox(x, y, w, h, bg, fg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end
end

function ui.drawFrame(x, y, w, h, title)
    ui.drawBox(x, y, w, h, colors.gray, colors.white)
    ui.drawBox(x + 1, y + 1, w - 2, h - 2, colors_bg, colors_fg)
    
    -- Shadow
    term.setBackgroundColor(colors.black)
    for i = 1, h do
        term.setCursorPos(x + w, y + i)
        term.write(" ")
    end
    for i = 1, w do
        term.setCursorPos(x + i, y + h)
        term.write(" ")
    end

    if title then
        term.setCursorPos(x + 2, y + 1)
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        term.write(" " .. title .. " ")
    end
end

function ui.button(x, y, text, active)
    term.setCursorPos(x, y)
    if active then
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
    else
        term.setBackgroundColor(colors_btn)
        term.setTextColor(colors_btn_text)
    end
    term.write(" " .. text .. " ")
end

function ui.label(x, y, text)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.write(text)
end

function ui.inputText(x, y, width, value, active)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_input)
    term.setTextColor(colors_input_text)
    local display = value or ""
    if #display > width then
        display = display:sub(-width)
    end
    term.write(display .. string.rep(" ", width - #display))
    if active then
        term.setCursorPos(x + #display, y)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
end

function ui.drawPreview(schema, x, y, w, h)
    -- Find bounds
    local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            if nx < minX then minX = nx end
            if nx > maxX then maxX = nx end
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        if nz < minZ then minZ = nz end
                        if nz > maxZ then maxZ = nz end
                    end
                end
            end
        end
    end

    if minX > maxX then return end -- Empty schema

    local scaleX = w / (maxX - minX + 1)
    local scaleZ = h / (maxZ - minZ + 1)
    local scale = math.min(scaleX, scaleZ, 1) -- Keep aspect ratio, max 1:1

    -- Draw background
    term.setBackgroundColor(colors.black)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end

    -- Draw blocks
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        -- Map to screen
                        local scrX = math.floor((nx - minX) * scale) + x
                        local scrY = math.floor((nz - minZ) * scale) + y
                        
                        if scrX >= x and scrX < x + w and scrY >= y and scrY < y + h then
                            term.setCursorPos(scrX, scrY)
                            
                            -- Color mapping
                            local mat = block.material
                            local color = colors.gray
                            local char = " "
                            
                            if mat:find("water") then color = colors.blue
                            elseif mat:find("log") then color = colors.brown
                            elseif mat:find("leaves") then color = colors.green
                            elseif mat:find("sapling") then color = colors.green; char = "T"
                            elseif mat:find("sand") then color = colors.yellow
                            elseif mat:find("dirt") then color = colors.brown
                            elseif mat:find("grass") then color = colors.green
                            elseif mat:find("stone") then color = colors.lightGray
                            elseif mat:find("cane") then color = colors.lime; char = "!"
                            elseif mat:find("potato") then color = colors.orange; char = "."
                            elseif mat:find("torch") then color = colors.orange; char = "i"
                            end
                            
                            term.setBackgroundColor(color)
                            if color == colors.black then term.setTextColor(colors.white) else term.setTextColor(colors.black) end
                            term.write(char)
                        end
                    end
                end
            end
        end
    end
end

-- Simple Event Loop for a Form
-- form = { title = "", elements = { {type="button", x=, y=, text=, id=}, ... } }
function ui.runForm(form)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local running = true
    local result = nil
    local activeInput = nil

    -- Identify focusable elements
    local focusableIndices = {}
    for i, el in ipairs(form.elements) do
        if el.type == "input" or el.type == "button" then
            table.insert(focusableIndices, i)
        end
    end
    local currentFocusIndex = 1
    if #focusableIndices > 0 then
        local el = form.elements[focusableIndices[currentFocusIndex]]
        if el.type == "input" then activeInput = el end
    end

    while running do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, form.title)
        
        -- Custom Draw
        if form.onDraw then
            form.onDraw(fx, fy, fw, fh)
        end

        -- Draw elements
        for i, el in ipairs(form.elements) do
            local ex, ey = fx + el.x, fy + el.y
            local isFocused = false
            if #focusableIndices > 0 and focusableIndices[currentFocusIndex] == i then
                isFocused = true
            end

            if el.type == "button" then
                ui.button(ex, ey, el.text, isFocused)
            elseif el.type == "label" then
                ui.label(ex, ey, el.text)
            elseif el.type == "input" then
                ui.inputText(ex, ey, el.width, el.value, activeInput == el or isFocused)
            end
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            local clickedSomething = false
            
            for i, el in ipairs(form.elements) do
                local ex, ey = fx + el.x, fy + el.y
                if el.type == "button" then
                    if my == ey and mx >= ex and mx < ex + #el.text + 2 then
                        ui.button(ex, ey, el.text, true) -- Flash
                        sleep(0.1)
                        if el.callback then
                            local res = el.callback(form)
                            if res then return res end
                        end
                        clickedSomething = true
                        -- Update focus
                        for fi, idx in ipairs(focusableIndices) do
                            if idx == i then currentFocusIndex = fi; break end
                        end
                        activeInput = nil
                    end
                elseif el.type == "input" then
                    if my == ey and mx >= ex and mx < ex + el.width then
                        activeInput = el
                        clickedSomething = true
                        -- Update focus
                        for fi, idx in ipairs(focusableIndices) do
                            if idx == i then currentFocusIndex = fi; break end
                        end
                    end
                end
            end
            
            if not clickedSomething then
                activeInput = nil
            end
            
        elseif event == "char" and activeInput then
            if not activeInput.stepper then
                activeInput.value = (activeInput.value or "") .. p1
            end
        elseif event == "key" then
            local key = p1
            local focusedEl = (#focusableIndices > 0) and form.elements[focusableIndices[currentFocusIndex]] or nil
            local function adjustStepper(el, delta)
                if not el or not el.stepper then return end
                local step = el.step or 1
                local current = tonumber(el.value) or 0
                local nextVal = current + (delta * step)
                if el.min then nextVal = math.max(el.min, nextVal) end
                if el.max then nextVal = math.min(el.max, nextVal) end
                el.value = tostring(nextVal)
            end

            if key == keys.backspace and activeInput then
                local val = activeInput.value or ""
                if #val > 0 then
                    activeInput.value = val:sub(1, -2)
                end
            elseif (key == keys.left or key == keys.right) and focusedEl and focusedEl.stepper then
                local delta = key == keys.left and -1 or 1
                adjustStepper(focusedEl, delta)
                activeInput = nil
            elseif key == keys.tab or key == keys.down then
                if #focusableIndices > 0 then
                    currentFocusIndex = currentFocusIndex + 1
                    if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
                    local el = form.elements[focusableIndices[currentFocusIndex]]
                    activeInput = (el.type == "input") and el or nil
                end
            elseif key == keys.up then
                if #focusableIndices > 0 then
                    currentFocusIndex = currentFocusIndex - 1
                    if currentFocusIndex < 1 then currentFocusIndex = #focusableIndices end
                    local el = form.elements[focusableIndices[currentFocusIndex]]
                    activeInput = (el.type == "input") and el or nil
                end
            elseif key == keys.enter then
                if activeInput then
                    activeInput = nil
                    -- Move to next
                    if #focusableIndices > 0 then
                        currentFocusIndex = currentFocusIndex + 1
                        if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
                        local el = form.elements[focusableIndices[currentFocusIndex]]
                        activeInput = (el.type == "input") and el or nil
                    end
                else
                    -- Activate button
                    if #focusableIndices > 0 then
                        local el = form.elements[focusableIndices[currentFocusIndex]]
                        if el.type == "button" then
                            ui.button(fx + el.x, fy + el.y, el.text, true) -- Flash
                            sleep(0.1)
                            if el.callback then
                                local res = el.callback(form)
                                if res then return res end
                            end
                        elseif el.type == "input" then
                            activeInput = el
                        end
                    end
                end
            end
        end
    end
end

-- Simple Scrollable Menu
-- items = { { text="Label", callback=function() end }, ... }
function ui.runMenu(title, items)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local scroll = 0
    local maxVisible = fh - 4 -- Title + padding (top/bottom)
    local selectedIndex = 1

    while true do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, title)
        
        -- Draw items
        for i = 1, maxVisible do
            local idx = i + scroll
            if idx <= #items then
                local item = items[idx]
                local isSelected = (idx == selectedIndex)
                ui.button(fx + 2, fy + 1 + i, item.text, isSelected)
            end
        end
        
        -- Scroll indicators
        if scroll > 0 then
            ui.label(fx + fw - 2, fy + 2, "^")
        end
        if scroll + maxVisible < #items then
            ui.label(fx + fw - 2, fy + fh - 2, "v")
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            
            -- Check items
            for i = 1, maxVisible do
                local idx = i + scroll
                if idx <= #items then
                    local item = items[idx]
                    local bx, by = fx + 2, fy + 1 + i
                    -- Button width is text length + 2 spaces
                    if my == by and mx >= bx and mx < bx + #item.text + 2 then
                        ui.button(bx, by, item.text, true) -- Flash
                        sleep(0.1)
                        if item.callback then
                            local res = item.callback()
                            if res then return res end
                        end
                        selectedIndex = idx
                    end
                end
            end
            
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir > 0 then
                if scroll + maxVisible < #items then scroll = scroll + 1 end
            else
                if scroll > 0 then scroll = scroll - 1 end
            end
        elseif event == "key" then
            local key = p1
            if key == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                    if selectedIndex <= scroll then
                        scroll = selectedIndex - 1
                    end
                end
            elseif key == keys.down then
                if selectedIndex < #items then
                    selectedIndex = selectedIndex + 1
                    if selectedIndex > scroll + maxVisible then
                        scroll = selectedIndex - maxVisible
                    end
                end
            elseif key == keys.enter then
                local item = items[selectedIndex]
                if item and item.callback then
                    ui.button(fx + 2, fy + 1 + (selectedIndex - scroll), item.text, true) -- Flash
                    sleep(0.1)
                    local res = item.callback()
                    if res then return res end
                end
            end
        end
    end
end

-- Form Class
function ui.Form(title)
    local self = {
        title = title,
        elements = {},
        _row = 0,
    }
    
    function self:addInput(id, label, value)
        local y = 2 + self._row
        table.insert(self.elements, { type = "label", x = 2, y = y, text = label })
        table.insert(self.elements, { type = "input", x = 15, y = y, width = 20, value = value, id = id })
        self._row = self._row + 1
    end

    function self:addStepper(id, label, value, opts)
        opts = opts or {}
        local y = 2 + self._row
        table.insert(self.elements, { type = "label", x = 2, y = y, text = label })
        table.insert(self.elements, {
            type = "input",
            x = 15,
            y = y,
            width = 12,
            value = tostring(value or 0),
            id = id,
            stepper = true,
            step = opts.step or 1,
            min = opts.min,
            max = opts.max,
        })
        self._row = self._row + 1
    end
    
    function self:addButton(id, label, callback)
         local y = 2 + self._row
         table.insert(self.elements, { type = "button", x = 2, y = y, text = label, id = id, callback = callback })
         self._row = self._row + 1
    end

    function self:run()
        -- Add OK/Cancel buttons
        local y = 2 + self._row + 2
        table.insert(self.elements, { 
            type = "button", x = 2, y = y, text = "OK", 
            callback = function(form) return "ok" end 
        })
        table.insert(self.elements, { 
            type = "button", x = 10, y = y, text = "Cancel", 
            callback = function(form) return "cancel" end 
        })
        
        return ui.runForm(self)
    end
    
    return self
end

function ui.toBlit(color)
    if colors.toBlit then return colors.toBlit(color) end
    local exponent = math.log(color) / math.log(2)
    return string.sub("0123456789abcdef", exponent + 1, exponent + 1)
end

return ui
]=])

addEmbeddedFile("ui/trash_config.lua", [=[
local ui = require("lib_ui")
local mining = require("lib_mining")
local valhelsia_blocks = require("arcade.data.valhelsia_blocks")

local trash_config = {}

function trash_config.run()
    local searchTerm = ""
    local scroll = 0
    local selectedIndex = 1
    local filteredBlocks = {}
    
    -- Helper to update filtered list
    local function updateFilter()
        filteredBlocks = {}
        for _, block in ipairs(valhelsia_blocks) do
            if searchTerm == "" or 
               block.label:lower():find(searchTerm:lower()) or 
               block.id:lower():find(searchTerm:lower()) then
                table.insert(filteredBlocks, block)
            end
        end
    end
    
    updateFilter()
    
    while true do
        ui.clear()
        ui.drawFrame(2, 2, 48, 16, "Trash Configuration")
        
        -- Search Bar
        ui.label(4, 4, "Search: ")
        ui.inputText(12, 4, 30, searchTerm, true)
        
        -- List Header
        ui.label(4, 6, "Name")
        ui.label(35, 6, "Trash?")
        ui.drawBox(4, 7, 44, 1, colors.gray, colors.white)
        
        -- List Items
        local listHeight = 8
        local maxScroll = math.max(0, #filteredBlocks - listHeight)
        if scroll > maxScroll then scroll = maxScroll end
        
        for i = 1, listHeight do
            local idx = i + scroll
            if idx <= #filteredBlocks then
                local block = filteredBlocks[idx]
                local y = 7 + i
                
                local isTrash = mining.TRASH_BLOCKS[block.id]
                local trashLabel = isTrash and "[YES]" or "[NO ]"
                local trashColor = isTrash and colors.red or colors.green
                
                if i == selectedIndex then
                    term.setBackgroundColor(colors.white)
                    term.setTextColor(colors.black)
                else
                    term.setBackgroundColor(colors.blue)
                    term.setTextColor(colors.white)
                end
                
                term.setCursorPos(4, y)
                local label = block.label
                if #label > 30 then label = label:sub(1, 27) .. "..." end
                term.write(label .. string.rep(" ", 31 - #label))
                
                term.setCursorPos(35, y)
                if i == selectedIndex then
                    term.setTextColor(colors.black)
                else
                    term.setTextColor(trashColor)
                end
                term.write(trashLabel)
            end
        end
        
        -- Instructions
        ui.label(4, 17, "Arrows: Move/Scroll  Enter: Toggle  Esc: Save")
        
        local event, p1 = os.pullEvent()
        
        if event == "char" then
            searchTerm = searchTerm .. p1
            updateFilter()
            selectedIndex = 1
            scroll = 0
        elseif event == "key" then
            if p1 == keys.backspace then
                searchTerm = searchTerm:sub(1, -2)
                updateFilter()
                selectedIndex = 1
                scroll = 0
            elseif p1 == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                elseif scroll > 0 then
                    scroll = scroll - 1
                end
            elseif p1 == keys.down then
                if selectedIndex < math.min(listHeight, #filteredBlocks) then
                    selectedIndex = selectedIndex + 1
                elseif scroll < maxScroll then
                    scroll = scroll + 1
                end
            elseif p1 == keys.enter then
                local idx = selectedIndex + scroll
                if filteredBlocks[idx] then
                    local block = filteredBlocks[idx]
                    if mining.TRASH_BLOCKS[block.id] then
                        mining.TRASH_BLOCKS[block.id] = nil -- Remove from trash
                    else
                        mining.TRASH_BLOCKS[block.id] = true -- Add to trash
                    end
                end
            elseif p1 == keys.enter or p1 == keys.escape then
                mining.saveConfig()
                return
            end
        end
    end
end

return trash_config
]=])

addEmbeddedFile("lib/lib_schema.lua", [=[
--[[
Schema library for CC:Tweaked turtles.
Provides helpers for working with build schemas.
--]]

---@diagnostic disable: undefined-global

local schema_utils = {}
local table_utils = require("lib_table")

local function copyTable(tbl)
    if type(tbl) ~= "table" then return {} end
    return table_utils.shallowCopy(tbl)
end

function schema_utils.pushMaterialCount(counts, material)
    counts[material] = (counts[material] or 0) + 1
end

function schema_utils.cloneMeta(meta)
    return copyTable(meta)
end

function schema_utils.newBounds()
    return {
        min = { x = math.huge, y = math.huge, z = math.huge },
        max = { x = -math.huge, y = -math.huge, z = -math.huge },
    }
end

function schema_utils.updateBounds(bounds, x, y, z)
    local minB = bounds.min
    local maxB = bounds.max
    if x < minB.x then minB.x = x end
    if y < minB.y then minB.y = y end
    if z < minB.z then minB.z = z end
    if x > maxB.x then maxB.x = x end
    if y > maxB.y then maxB.y = y end
    if z > maxB.z then maxB.z = z end
end

function schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return false, "invalid_coordinate"
    end
    if type(material) ~= "string" or material == "" then
        return false, "invalid_material"
    end
    meta = schema_utils.cloneMeta(meta)
    schema[x] = schema[x] or {}
    local yLayer = schema[x]
    yLayer[y] = yLayer[y] or {}
    local zLayer = yLayer[y]
    if zLayer[z] ~= nil then
        return false, "duplicate_coordinate"
    end
    zLayer[z] = { material = material, meta = meta }
    schema_utils.updateBounds(bounds, x, y, z)
    schema_utils.pushMaterialCount(counts, material)
    return true
end

function schema_utils.mergeLegend(base, override)
    local result = {}
    if type(base) == "table" then
        for symbol, entry in pairs(base) do
            result[symbol] = entry
        end
    end
    if type(override) == "table" then
        for symbol, entry in pairs(override) do
            result[symbol] = entry
        end
    end
    return result
end

function schema_utils.normaliseLegendEntry(symbol, entry)
    if entry == nil then
        return nil, "unknown_symbol"
    end
    if entry == false or entry == "" then
        return false
    end
    if type(entry) == "string" then
        return { material = entry, meta = {} }
    end
    if type(entry) == "table" then
        if entry.material == nil and entry[1] then
            entry = { material = entry[1], meta = entry[2] }
        end
        local material = entry.material
        if material == nil or material == "" then
            return false
        end
        local meta = entry.meta
        if meta ~= nil and type(meta) ~= "table" then
            return nil, "invalid_meta"
        end
        return { material = material, meta = meta or {} }
    end
    return nil, "invalid_legend_entry"
end

function schema_utils.resolveSymbol(symbol, legend, opts)
    if symbol == "" then
        return nil, "empty_symbol"
    end
    if legend == nil then
        return nil, "missing_legend"
    end
    local entry = legend[symbol]
    if entry == nil then
        if symbol == "." or symbol == " " then
            return false
        end
        if opts and opts.allowImplicitAir and symbol:match("^%p?$") then
            return false
        end
        return nil, "unknown_symbol"
    end
    local normalised, err = schema_utils.normaliseLegendEntry(symbol, entry)
    if err then
        return nil, err
    end
    return normalised
end

function schema_utils.fetchSchemaEntry(schema, pos)
    if type(schema) ~= "table" or type(pos) ~= "table" then
        return nil, "missing_schema"
    end
    local xLayer = schema[pos.x] or schema[tostring(pos.x)]
    if type(xLayer) ~= "table" then
        return nil, "empty"
    end
    local yLayer = xLayer[pos.y] or xLayer[tostring(pos.y)]
    if type(yLayer) ~= "table" then
        return nil, "empty"
    end
    local block = yLayer[pos.z] or yLayer[tostring(pos.z)]
    if block == nil then
        return nil, "empty"
    end
    return block
end

function schema_utils.canonicalToGrid(schema, opts)
    opts = opts or {}
    local grid = {}
    if type(schema) ~= "table" then
        return grid
    end
    for x, xColumn in pairs(schema) do
        if type(xColumn) == "table" then
            for y, yColumn in pairs(xColumn) do
                if type(yColumn) == "table" then
                    for z, block in pairs(yColumn) do
                        if block and type(block) == "table" then
                            local material = block.material
                            if material and material ~= "" then
                                local gx = tostring(x)
                                local gy = tostring(y)
                                local gz = tostring(z)
                                grid[gx] = grid[gx] or {}
                                grid[gx][gy] = grid[gx][gy] or {}
                                grid[gx][gy][gz] = {
                                    material = material,
                                    meta = copyTable(block.meta),
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return grid
end

function schema_utils.canonicalToVoxelDefinition(schema, opts)
    return { grid = schema_utils.canonicalToGrid(schema, opts) }
end

function schema_utils.printMaterials(io, info)
    if not io.print then
        return
    end
    if not info or not info.materials or #info.materials == 0 then
        io.print("Materials: <none>")
        return
    end
    io.print("Materials:")
    for _, entry in ipairs(info.materials) do
        io.print(string.format(" - %s x%d", entry.material, entry.count))
    end
end

function schema_utils.printBounds(io, info)
    if not io.print then
        return
    end
    if not info or not info.bounds or not info.bounds.min then
        io.print("Bounds: <unknown>")
        return
    end
    local minB = info.bounds.min
    local maxB = info.bounds.max
    local dims = {
        x = (maxB.x - minB.x) + 1,
        y = (maxB.y - minB.y) + 1,
        z = (maxB.z - minB.z) + 1,
    }
    io.print(string.format("Bounds: min(%d,%d,%d) max(%d,%d,%d) dims(%d,%d,%d)",
        minB.x, minB.y, minB.z, maxB.x, maxB.y, maxB.z, dims.x, dims.y, dims.z))
end

return schema_utils
]=])

addEmbeddedFile("lib/lib_fs.lua", [=[
local fs_utils = {}

local createdArtifacts = {}

function fs_utils.stageArtifact(path)
    for _, existing in ipairs(createdArtifacts) do
        if existing == path then
            return
        end
    end
    createdArtifacts[#createdArtifacts + 1] = path
end

function fs_utils.writeFile(path, contents)
    if type(path) ~= "string" or path == "" then
        return false, "invalid_path"
    end
    if fs and fs.open then
        local handle = fs.open(path, "w")
        if not handle then
            return false, "open_failed"
        end
        handle.write(contents)
        handle.close()
        return true
    end
    if io and io.open then
        local handle, err = io.open(path, "w")
        if not handle then
            return false, err or "open_failed"
        end
        handle:write(contents)
        handle:close()
        return true
    end
    return false, "fs_unavailable"
end

function fs_utils.deleteFile(path)
    if fs and fs.delete and fs.exists then
        local ok, exists = pcall(fs.exists, path)
        if ok and exists then
            fs.delete(path)
        end
        return true
    end
    if os and os.remove then
        os.remove(path)
        return true
    end
    return false
end

function fs_utils.readFile(path)
    if type(path) ~= "string" or path == "" then
        return nil, "invalid_path"
    end
    if fs and fs.open then
        local handle = fs.open(path, "r")
        if not handle then
            return nil, "open_failed"
        end
        local ok, contents = pcall(handle.readAll)
        handle.close()
        if not ok then
            return nil, "read_failed"
        end
        return contents
    end
    if io and io.open then
        local handle, err = io.open(path, "r")
        if not handle then
            return nil, err or "open_failed"
        end
        local contents = handle:read("*a")
        handle:close()
        return contents
    end
    return nil, "fs_unavailable"
end

function fs_utils.cleanupArtifacts()
    for index = #createdArtifacts, 1, -1 do
        local path = createdArtifacts[index]
        fs_utils.deleteFile(path)
        createdArtifacts[index] = nil
    end
end

return fs_utils
]=])

addEmbeddedFile("lib/lib_parser.lua", [=[
--[[
Parser library for CC:Tweaked turtles.
Normalises schema sources (JSON, text grids, voxel tables) into the canonical
schema[x][y][z] format used by the build states. All public entry points
return success booleans with optional error messages and metadata tables.
--]]

---@diagnostic disable: undefined-global

local parser = {}
local logger = require("lib_logger")
local table_utils = require("lib_table")
local fs_utils = require("lib_fs")
local json_utils = require("lib_json")
local schema_utils = require("lib_schema")

local function parseLayerRows(schema, bounds, counts, layerDef, legend, opts)
    local rows = layerDef.rows
    if type(rows) ~= "table" then
        return false, "invalid_layer"
    end
    local height = #rows
    if height == 0 then
        return true
    end
    local width = nil
    for rowIndex, row in ipairs(rows) do
        if type(row) ~= "string" then
            return false, "invalid_row"
        end
        if width == nil then
            width = #row
            if width == 0 then
                return false, "empty_row"
            end
        elseif width ~= #row then
            return false, "ragged_row"
        end
        for col = 1, #row do
            local symbol = row:sub(col, col)
            local entry, err = schema_utils.resolveSymbol(symbol, legend, opts)
            if err then
                return false, string.format("legend_error:%s", symbol)
            end
            if entry then
                local x = (layerDef.x or 0) + (col - 1)
                local y = layerDef.y or 0
                local z = (layerDef.z or 0) + (rowIndex - 1)
                local ok, addErr = schema_utils.addBlock(schema, bounds, counts, x, y, z, entry.material, entry.meta)
                if not ok then
                    return false, addErr
                end
            end
        end
    end
    return true
end

local function toLayerRows(layer)
    if type(layer) == "string" then
        local rows = {}
        for line in layer:gmatch("([^\r\n]+)") do
            rows[#rows + 1] = line
        end
        return { rows = rows }
    end
    if type(layer) == "table" then
        if layer.rows then
            local rows = {}
            for i = 1, #layer.rows do
                rows[i] = tostring(layer.rows[i])
            end
            return {
                rows = rows,
                y = layer.y or layer.height or layer.level or 0,
                x = layer.x or layer.offsetX or 0,
                z = layer.z or layer.offsetZ or 0,
            }
        end
        local rows = {}
        local count = 0
        for _, value in ipairs(layer) do
            rows[#rows + 1] = tostring(value)
            count = count + 1
        end
        if count > 0 then
            return { rows = rows, y = layer.y or 0, x = layer.x or 0, z = layer.z or 0 }
        end
    end
    return nil
end

local function parseLayers(schema, bounds, counts, def, legend, opts)
    local layers = def.layers
    if type(layers) ~= "table" then
        return false, "invalid_layers"
    end
    local used = 0
    for index, layer in ipairs(layers) do
        local layerRows = toLayerRows(layer)
        if not layerRows then
            return false, "invalid_layer"
        end
        if not layerRows.y then
            layerRows.y = (def.baseY or 0) + (index - 1)
        else
            layerRows.y = layerRows.y + (def.baseY or 0)
        end
        if def.baseX then
            layerRows.x = (layerRows.x or 0) + def.baseX
        end
        if def.baseZ then
            layerRows.z = (layerRows.z or 0) + def.baseZ
        end
        local ok, err = parseLayerRows(schema, bounds, counts, layerRows, legend, opts)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_layers"
    end
    return true
end

local function parseBlockList(schema, bounds, counts, blocks)
    local used = 0
    for _, block in ipairs(blocks) do
        if type(block) ~= "table" then
            return false, "invalid_block"
        end
        local x = block.x or block[1]
        local y = block.y or block[2]
        local z = block.z or block[3]
        local material = block.material or block.name or block.block
        local meta = block.meta or block.data
        if type(meta) ~= "table" then
            meta = {}
        end
        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_blocks"
    end
    return true
end

local function parseVoxelGrid(schema, bounds, counts, grid)
    if type(grid) ~= "table" then
        return false, "invalid_grid"
    end
    local used = 0
    for xKey, xColumn in pairs(grid) do
        local x = tonumber(xKey) or xKey
        if type(x) ~= "number" then
            return false, "invalid_coordinate"
        end
        if type(xColumn) ~= "table" then
            return false, "invalid_grid"
        end
        for yKey, yColumn in pairs(xColumn) do
            local y = tonumber(yKey) or yKey
            if type(y) ~= "number" then
                return false, "invalid_coordinate"
            end
            if type(yColumn) ~= "table" then
                return false, "invalid_grid"
            end
            for zKey, entry in pairs(yColumn) do
                local z = tonumber(zKey) or zKey
                if type(z) ~= "number" then
                    return false, "invalid_coordinate"
                end
                if entry ~= nil then
                    local material
                    local meta = {}
                    if type(entry) == "string" then
                        material = entry
                    elseif type(entry) == "table" then
                        material = entry.material or entry.name or entry.block
                        meta = type(entry.meta) == "table" and entry.meta or {}
                    else
                        return false, "invalid_block"
                    end
                    if material and material ~= "" then
                        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
                        if not ok then
                            return false, err
                        end
                        used = used + 1
                    end
                end
            end
        end
    end
    if used == 0 then
        return false, "empty_grid"
    end
    return true
end

local function summarise(bounds, counts, meta)
    local materials = {}
    for material, count in pairs(counts) do
        materials[#materials + 1] = { material = material, count = count }
    end
    table.sort(materials, function(a, b)
        if a.count == b.count then
            return a.material < b.material
        end
        return a.count > b.count
    end)
    local total = 0
    for _, entry in ipairs(materials) do
        total = total + entry.count
    end
    return {
        bounds = {
            min = table_utils.shallowCopy(bounds.min),
            max = table_utils.shallowCopy(bounds.max),
        },
        materials = materials,
        totalBlocks = total,
        meta = meta
    }
end

local function buildCanonical(def, opts)
    local schema = {}
    local bounds = schema_utils.newBounds()
    local counts = {}
    local ok, err
    if def.blocks then
        ok, err = parseBlockList(schema, bounds, counts, def.blocks)
    elseif def.layers then
        ok, err = parseLayers(schema, bounds, counts, def, def.legend, opts)
    elseif def.grid then
        ok, err = parseVoxelGrid(schema, bounds, counts, def.grid)
    else
        return nil, "unknown_definition"
    end
    if not ok then
        return nil, err
    end
    if bounds.min.x == math.huge then
        return nil, "empty_schema"
    end
    return schema, summarise(bounds, counts, def.meta)
end

local function detectFormatFromExtension(path)
    if type(path) ~= "string" then
        return nil
    end
    local ext = path:match("%.([%w_%-]+)$")
    if not ext then
        return nil
    end
    ext = ext:lower()
    if ext == "json" or ext == "schem" then
        return "json"
    end
    if ext == "txt" or ext == "grid" then
        return "grid"
    end
    if ext == "vox" or ext == "voxel" then
        return "voxel"
    end
    return nil
end

local function detectFormatFromText(text)
    if type(text) ~= "string" then
        return nil
    end
    local trimmed = text:match("^%s*(.-)%s*$") or text
    local firstChar = trimmed:sub(1, 1)
    if firstChar == "{" or firstChar == "[" then
        return "json"
    end
    return "grid"
end

local function parseLegendBlock(lines, index)
    local legend = {}
    local pos = index
    while pos <= #lines do
        local line = lines[pos]
        if line == "" then
            break
        end
        if line:match("^layer") then
            break
        end
        local symbol, rest = line:match("^(%S+)%s*[:=]%s*(.+)$")
        if not symbol then
            symbol, rest = line:match("^(%S+)%s+(.+)$")
        end
        if symbol and rest then
            rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
            local value
            if rest:sub(1, 1) == "{" then
                local parsed = json_utils.decodeJson(rest)
                if parsed then
                    value = parsed
                else
                    value = rest
                end
            else
                value = rest
            end
            legend[symbol] = value
        end
        pos = pos + 1
    end
    return legend, pos
end

local function parseTextGridContent(text, opts)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        lines[#lines + 1] = line
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, nil)
    local layers = {}
    local current = {}
    local currentY = nil
    local lineIndex = 1
    while lineIndex <= #lines do
        local line = lines[lineIndex]
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == "" then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
                currentY = nil
            end
            lineIndex = lineIndex + 1
        elseif trimmed:lower() == "legend:" then
            local legendBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1)
            legend = schema_utils.mergeLegend(legend, legendBlock)
            lineIndex = nextIndex
        elseif trimmed:lower() == "meta:" then
            local metaBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1) -- Reuse parseLegendBlock as format is identical
            if not opts then opts = {} end
            opts.meta = schema_utils.mergeLegend(opts.meta, metaBlock)
            lineIndex = nextIndex
        elseif trimmed:match("^layer") then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
            end
            local yValue = trimmed:match("layer%s*[:=]%s*(-?%d+)")
            currentY = yValue and tonumber(yValue) or (#layers)
            lineIndex = lineIndex + 1
        else
            current[#current + 1] = line
            lineIndex = lineIndex + 1
        end
    end
    if #current > 0 then
        layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
    end
    if not legend or next(legend) == nil then
        return nil, "missing_legend"
    end
    if #layers == 0 then
        return nil, "empty_layers"
    end
    return {
        layers = layers,
        legend = legend,
    }
end

local function parseJsonContent(obj, opts)
    if type(obj) ~= "table" then
        return nil, "invalid_json_root"
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, obj.legend or nil)
    if obj.blocks then
        return {
            blocks = obj.blocks,
            legend = legend,
        }
    end
    if obj.layers then
        return {
            layers = obj.layers,
            legend = legend,
            baseX = obj.baseX,
            baseY = obj.baseY,
            baseZ = obj.baseZ,
        }
    end
    if obj.grid or obj.voxels then
        return {
            grid = obj.grid or obj.voxels,
            legend = legend,
        }
    end
    if #obj > 0 then
        return {
            blocks = obj,
            legend = legend,
        }
    end
    return nil, "unrecognised_json"
end

local function assignToContext(ctx, schema, info)
    if type(ctx) ~= "table" then
        return
    end
    ctx.schema = schema
    ctx.schemaInfo = info
end

local function ensureSpecTable(spec)
    if type(spec) == "table" then
        return table_utils.shallowCopy(spec)
    end
    if type(spec) == "string" then
        return { source = spec }
    end
    return {}
end

function parser.parse(ctx, spec)
    spec = ensureSpecTable(spec)
    local format = spec.format
    local text = spec.text
    local data = spec.data
    local path = spec.path or spec.sourcePath
    local source = spec.source
    if not format and spec.path then
        format = detectFormatFromExtension(spec.path)
    end
    if not format and spec.formatHint then
        format = spec.formatHint
    end
    if not text and not data then
        if spec.textContent then
            text = spec.textContent
        elseif spec.raw then
            text = spec.raw
        elseif spec.sourceText then
            text = spec.sourceText
        end
    end
    if not path and type(source) == "string" and text == nil and data == nil then
        local maybeFormat = detectFormatFromExtension(source)
        if maybeFormat then
            path = source
            format = format or maybeFormat
        else
            text = source
        end
    end
    if text == nil and path then
        local contents, err = fs_utils.readFile(path)
        if not contents then
            return false, err or "read_failed"
        end
        text = contents
        if not format then
            format = detectFormatFromExtension(path) or detectFormatFromText(text)
        end
    end
    if not format then
        if data then
            if data.layers then
                format = "grid"
            elseif data.blocks then
                format = "json"
            elseif data.grid or data.voxels then
                format = "voxel"
            end
        elseif text then
            format = detectFormatFromText(text)
        end
    end
    if not format then
        return false, "unknown_format"
    end
    local definition, err
    if format == "json" then
        if data then
            definition, err = parseJsonContent(data, spec)
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            definition, err = parseJsonContent(obj, spec)
        end
    elseif format == "grid" then
        if data and (data.layers or data.rows) then
            definition = {
                layers = data.layers or { data.rows },
                legend = schema_utils.mergeLegend(spec.legend or nil, data.legend or nil),
                meta = spec.meta or data.meta
            }
        else
            definition, err = parseTextGridContent(text, spec)
            if definition and spec.meta then
                 definition.meta = schema_utils.mergeLegend(definition.meta, spec.meta)
            end
        end
    elseif format == "voxel" then
        if data then
            definition = {
                grid = data.grid or data.voxels or data,
            }
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            if obj.grid or obj.voxels then
                definition = {
                    grid = obj.grid or obj.voxels,
                }
            else
                definition, err = parseJsonContent(obj, spec)
            end
        end
    else
        return false, "unsupported_format"
    end
    if not definition then
        return false, err or "invalid_definition"
    end
    if spec.legend then
        definition.legend = schema_utils.mergeLegend(definition.legend, spec.legend)
    end
    local schema, metadata = buildCanonical(definition, spec)
    if not schema then
        return false, metadata or "parse_failed"
    end
    if type(metadata) ~= "table" then
        metadata = { note = metadata }
    end
    metadata = metadata or {}
    metadata.format = format
    metadata.path = path
    assignToContext(ctx, schema, metadata)
    logger.log(ctx, "debug", string.format("Parsed schema with %d blocks", metadata.totalBlocks or 0))
    return true, schema, metadata
end

function parser.parseFile(ctx, path, opts)
    opts = opts or {}
    opts.path = path
    return parser.parse(ctx, opts)
end

function parser.parseText(ctx, text, opts)
    opts = opts or {}
    opts.text = text
    opts.format = opts.format or "grid"
    return parser.parse(ctx, opts)
end

function parser.parseJson(ctx, data, opts)
    opts = opts or {}
    opts.data = data
    opts.format = "json"
    return parser.parse(ctx, opts)
end

return parser
]=])

addEmbeddedFile("lib/lib_inventory.lua", [=[
--[[
Inventory library for CC:Tweaked turtles.
Tracks slot contents, provides material lookup helpers, and wraps chest
interactions used by higher-level states. All public functions accept a shared
ctx table and follow the project convention of returning success booleans with
optional error messages.
--]]

---@diagnostic disable: undefined-global

local inventory = {}
local movement = require("lib_movement")
local logger = require("lib_logger")

local SIDE_ACTIONS = {
    forward = {
        drop = turtle and turtle.drop or nil,
        suck = turtle and turtle.suck or nil,
    },
    up = {
        drop = turtle and turtle.dropUp or nil,
        suck = turtle and turtle.suckUp or nil,
    },
    down = {
        drop = turtle and turtle.dropDown or nil,
        suck = turtle and turtle.suckDown or nil,
    },
}

local PUSH_TARGETS = {
    "front",
    "back",
    "left",
    "right",
    "top",
    "bottom",
    "north",
    "south",
    "east",
    "west",
    "up",
    "down",
}

local OPPOSITE_FACING = {
    north = "south",
    south = "north",
    east = "west",
    west = "east",
}

local CONTAINER_KEYWORDS = {
    "chest",
    "barrel",
    "shulker",
    "crate",
    "storage",
    "inventory",
}

inventory.DEFAULT_TRASH = {
    ["minecraft:air"] = true,
    ["minecraft:stone"] = true,
    ["minecraft:cobblestone"] = true,
    ["minecraft:deepslate"] = true,
    ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:tuff"] = true,
    ["minecraft:diorite"] = true,
    ["minecraft:granite"] = true,
    ["minecraft:andesite"] = true,
    ["minecraft:calcite"] = true,
    ["minecraft:netherrack"] = true,
    ["minecraft:end_stone"] = true,
    ["minecraft:basalt"] = true,
    ["minecraft:blackstone"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:coarse_dirt"] = true,
    ["minecraft:rooted_dirt"] = true,
    ["minecraft:mycelium"] = true,
    ["minecraft:sand"] = true,
    ["minecraft:red_sand"] = true,
    ["minecraft:sandstone"] = true,
    ["minecraft:red_sandstone"] = true,
    ["minecraft:clay"] = true,
    ["minecraft:dripstone_block"] = true,
    ["minecraft:pointed_dripstone"] = true,
    ["minecraft:bedrock"] = true,
    ["minecraft:lava"] = true,
    ["minecraft:water_bucket"] = true,
}

local function noop()
end

local function normalizeSide(value)
    if type(value) ~= "string" then
        return nil
    end
    local lower = value:lower()
    if lower == "forward" or lower == "front" or lower == "fwd" then
        return "forward"
    end
    if lower == "up" or lower == "top" or lower == "above" then
        return "up"
    end
    if lower == "down" or lower == "bottom" or lower == "below" then
        return "down"
    end
    return nil
end

local function resolveSide(ctx, opts)
    if type(opts) == "string" then
        local direct = normalizeSide(opts)
        return direct or "forward"
    end

    local candidate
    if type(opts) == "table" then
        candidate = opts.side or opts.direction or opts.facing or opts.containerSide or opts.defaultSide
        if not candidate and type(opts.location) == "string" then
            candidate = opts.location
        end
    end

    if not candidate and type(ctx) == "table" then
        local cfg = ctx.config
        if type(cfg) == "table" then
            candidate = cfg.inventorySide or cfg.materialSide or cfg.supplySide or cfg.defaultInventorySide
        end
        if not candidate and type(ctx.inventoryState) == "table" then
            candidate = ctx.inventoryState.defaultSide
        end
    end

    local normalised = normalizeSide(candidate)
    if normalised then
        return normalised
    end

    return "forward"
end

local function tableCount(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function copyArray(list)
    if type(list) ~= "table" then
        return {}
    end
    local result = {}
    for index = 1, #list do
        result[index] = list[index]
    end
    return result
end

local function copySummary(summary)
    if type(summary) ~= "table" then
        return {}
    end
    local result = {}
    for key, value in pairs(summary) do
        result[key] = value
    end
    return result
end

local function copySlots(slots)
    if type(slots) ~= "table" then
        return {}
    end
    local result = {}
    for slot, info in pairs(slots) do
        if type(info) == "table" then
            result[slot] = {
                slot = info.slot,
                count = info.count,
                name = info.name,
                detail = info.detail,
            }
        else
            result[slot] = info
        end
    end
    return result
end

local function hasContainerTag(tags)
    if type(tags) ~= "table" then
        return false
    end
    for key, value in pairs(tags) do
        if value and type(key) == "string" then
            local lower = key:lower()
            for _, keyword in ipairs(CONTAINER_KEYWORDS) do
                if lower:find(keyword, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

local function isContainerBlock(name, tags)
    if type(name) ~= "string" then
        return false
    end
    local lower = name:lower()
    for _, keyword in ipairs(CONTAINER_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true
        end
    end
    return hasContainerTag(tags)
end

local function inspectForwardForContainer()
    if not turtle or type(turtle.inspect) ~= "function" then
        return false
    end
    local ok, data = turtle.inspect()
    if not ok or type(data) ~= "table" then
        return false
    end
    if isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

local function inspectUpForContainer()
    if not turtle or type(turtle.inspectUp) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectUp()
    if not ok or type(data) ~= "table" then
        return false
    end
    if isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

local function inspectDownForContainer()
    if not turtle or type(turtle.inspectDown) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectDown()
    if not ok or type(data) ~= "table" then
        return false
    end
    if isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

local function shouldSearchAllSides(opts)
    if type(opts) ~= "table" then
        return true
    end
    if opts.searchAllSides == false then
        return false
    end
    return true
end

local function peripheralSideForDirection(side)
    if side == "forward" or side == "front" then
        return "front"
    end
    if side == "up" or side == "top" then
        return "top"
    end
    if side == "down" or side == "bottom" then
        return "bottom"
    end
    return side
end

local function computePrimaryPushDirection(ctx, periphSide)
    if periphSide == "front" then
        local facing = movement.getFacing(ctx)
        if facing then
            return OPPOSITE_FACING[facing]
        end
    elseif periphSide == "top" then
        return "down"
    elseif periphSide == "bottom" then
        return "up"
    end
    return nil
end

local function tryPushItems(chest, periphSide, slot, amount, targetSlot, primaryDirection)
    if type(chest) ~= "table" or type(chest.pushItems) ~= "function" then
        return 0
    end

    local tried = {}

    local function attempt(direction)
        if not direction or tried[direction] then
            return 0
        end
        tried[direction] = true
        local ok, moved
        if targetSlot then
            ok, moved = pcall(chest.pushItems, direction, slot, amount, targetSlot)
        else
            ok, moved = pcall(chest.pushItems, direction, slot, amount)
        end
        if ok and type(moved) == "number" and moved > 0 then
            return moved
        end
        return 0
    end

    local moved = attempt(primaryDirection)
    if moved > 0 then
        return moved
    end

    for _, direction in ipairs(PUSH_TARGETS) do
        moved = attempt(direction)
        if moved > 0 then
            return moved
        end
    end

    return 0
end

local function collectStacks(chest, material)
    local stacks = {}
    if type(chest) ~= "table" or not material then
        return stacks
    end

    if type(chest.list) == "function" then
        local ok, list = pcall(chest.list)
        if ok and type(list) == "table" then
            for slot, stack in pairs(list) do
                local numericSlot = tonumber(slot)
                if numericSlot and type(stack) == "table" then
                    local name = stack.name or stack.id
                    local count = stack.count or stack.qty or stack.quantity or 0
                    if name == material and type(count) == "number" and count > 0 then
                        stacks[#stacks + 1] = { slot = numericSlot, count = count }
                    end
                end
            end
        end
    end

    if #stacks == 0 and type(chest.size) == "function" and type(chest.getItemDetail) == "function" then
        local okSize, size = pcall(chest.size)
        if okSize and type(size) == "number" and size > 0 then
            for slot = 1, size do
                local okDetail, detail = pcall(chest.getItemDetail, slot)
                if okDetail and type(detail) == "table" then
                    local name = detail.name
                    local count = detail.count or detail.qty or detail.quantity or 0
                    if name == material and type(count) == "number" and count > 0 then
                        stacks[#stacks + 1] = { slot = slot, count = count }
                    end
                end
            end
        end
    end

    table.sort(stacks, function(a, b)
        return a.slot < b.slot
    end)

    return stacks
end

local function newContainerManifest()
    return {
        totals = {},
        slots = {},
        totalItems = 0,
        orderedSlots = {},
        size = nil,
        metadata = nil,
    }
end

local function addManifestEntry(manifest, slot, stack)
    if type(manifest) ~= "table" or type(slot) ~= "number" then
        return
    end
    if type(stack) ~= "table" then
        return
    end
    local name = stack.name or stack.id
    local count = stack.count or stack.qty or stack.quantity or stack.Count
    if type(name) ~= "string" or type(count) ~= "number" or count <= 0 then
        return
    end
    manifest.slots[slot] = {
        name = name,
        count = count,
        tags = stack.tags,
        nbt = stack.nbt,
        displayName = stack.displayName or stack.label or stack.Name,
        detail = stack,
    }
    manifest.totals[name] = (manifest.totals[name] or 0) + count
    manifest.totalItems = manifest.totalItems + count
end

local function populateManifestSlots(manifest)
    local ordered = {}
    for slot in pairs(manifest.slots) do
        ordered[#ordered + 1] = slot
    end
    table.sort(ordered)
    manifest.orderedSlots = ordered

    local materials = {}
    for material in pairs(manifest.totals) do
        materials[#materials + 1] = material
    end
    table.sort(materials)
    manifest.materials = materials
end

local function attachMetadata(manifest, periphSide)
    if not peripheral then
        return
    end
    local metadata = manifest.metadata or {}
    if type(peripheral.call) == "function" then
        local okMeta, meta = pcall(peripheral.call, periphSide, "getMetadata")
        if okMeta and type(meta) == "table" then
            metadata.name = meta.name or metadata.name
            metadata.displayName = meta.displayName or meta.label or metadata.displayName
            metadata.tags = meta.tags or metadata.tags
        end
    end
    if type(peripheral.getType) == "function" then
        local okType, perType = pcall(peripheral.getType, periphSide)
        if okType then
            if type(perType) == "string" then
                metadata.peripheralType = perType
            elseif type(perType) == "table" and type(perType[1]) == "string" then
                metadata.peripheralType = perType[1]
            end
        end
    end
    if next(metadata) ~= nil then
        manifest.metadata = metadata
    end
end

local function readContainerManifest(periphSide)
    if not peripheral or type(peripheral.wrap) ~= "function" then
        return nil, "peripheral_api_unavailable"
    end

    local wrapOk, chest = pcall(peripheral.wrap, periphSide)
    if not wrapOk or type(chest) ~= "table" then
        return nil, "wrap_failed"
    end

    local manifest = newContainerManifest()

    if type(chest.list) == "function" then
        local okList, list = pcall(chest.list)
        if okList and type(list) == "table" then
            for slot, stack in pairs(list) do
                local numericSlot = tonumber(slot)
                if numericSlot then
                    addManifestEntry(manifest, numericSlot, stack)
                end
            end
        end
    end

    local haveSlots = next(manifest.slots) ~= nil
    if type(chest.size) == "function" then
        local okSize, size = pcall(chest.size)
        if okSize and type(size) == "number" and size >= 0 then
            manifest.size = size
            if not haveSlots and type(chest.getItemDetail) == "function" then
                for slot = 1, size do
                    local okDetail, detail = pcall(chest.getItemDetail, slot)
                    if okDetail then
                        addManifestEntry(manifest, slot, detail)
                    end
                end
            end
        end
    end

    populateManifestSlots(manifest)
    attachMetadata(manifest, periphSide)

    return manifest
end

local function extractFromContainer(ctx, periphSide, material, amount, targetSlot)
    if not material or not peripheral or type(peripheral.wrap) ~= "function" then
        return 0
    end

    local wrapOk, chest = pcall(peripheral.wrap, periphSide)
    if not wrapOk or type(chest) ~= "table" then
        return 0
    end
    if type(chest.pushItems) ~= "function" then
        return 0
    end

    local desired = amount
    if not desired or desired <= 0 then
        desired = 64
    end

    local stacks = collectStacks(chest, material)
    if #stacks == 0 then
        return 0
    end

    local remaining = desired
    local transferred = 0
    local primaryDirection = computePrimaryPushDirection(ctx, periphSide)

    for _, stack in ipairs(stacks) do
        local available = stack.count or 0
        while remaining > 0 and available > 0 do
            local toMove = math.min(available, remaining, 64)
            local moved = tryPushItems(chest, periphSide, stack.slot, toMove, targetSlot, primaryDirection)
            if moved <= 0 then
                break
            end
            transferred = transferred + moved
            remaining = remaining - moved
            available = available - moved
        end
        if remaining <= 0 then
            break
        end
    end

    return transferred
end

local function ensureChestAhead(ctx, opts)
    local frontOk, frontDetail = inspectForwardForContainer()
    if frontOk then
        return true, noop, { side = "forward", detail = frontDetail }
    end

    if not shouldSearchAllSides(opts) then
        return false, nil, nil, "container_not_found"
    end
    if not turtle then
        return false, nil, nil, "turtle_api_unavailable"
    end

    movement.ensureState(ctx)
    local startFacing = movement.getFacing(ctx)

    local function restoreFacing()
        if not startFacing then
            return
        end
        if movement.getFacing(ctx) ~= startFacing then
            local okFace, faceErr = movement.faceDirection(ctx, startFacing)
            if not okFace and faceErr then
                logger.log(ctx, "warn", "Failed to restore facing: " .. tostring(faceErr))
            end
        end
    end

    local function makeRestore()
        if not startFacing then
            return noop
        end
        return function()
            restoreFacing()
        end
    end

    -- Check left
    local ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    local leftOk, leftDetail = inspectForwardForContainer()
    if leftOk then
        logger.log(ctx, "debug", "Found container on left side; using that")
        return true, makeRestore(), { side = "left", detail = leftDetail }
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end

    -- Check right
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    local rightOk, rightDetail = inspectForwardForContainer()
    if rightOk then
        logger.log(ctx, "debug", "Found container on right side; using that")
        return true, makeRestore(), { side = "right", detail = rightDetail }
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end

    -- Check behind
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    local backOk, backDetail = inspectForwardForContainer()
    if backOk then
        logger.log(ctx, "debug", "Found container behind; using that")
        return true, makeRestore(), { side = "back", detail = backDetail }
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end

    restoreFacing()
    return false, nil, nil, "container_not_found"
end

local function ensureInventoryState(ctx)
    if type(ctx) ~= "table" then
        error("inventory library requires a context table", 2)
    end

    if type(ctx.inventoryState) ~= "table" then
        ctx.inventoryState = ctx.inventory or {}
    end
    ctx.inventory = ctx.inventoryState

    local state = ctx.inventoryState
    state.scanVersion = state.scanVersion or 0
    state.slots = state.slots or {}
    state.materialSlots = state.materialSlots or {}
    state.materialTotals = state.materialTotals or {}
    state.emptySlots = state.emptySlots or {}
    state.totalItems = state.totalItems or 0
    if state.dirty == nil then
        state.dirty = true
    end
    return state
end

function inventory.ensureState(ctx)
    return ensureInventoryState(ctx)
end

function inventory.invalidate(ctx)
    local state = ensureInventoryState(ctx)
    state.dirty = true
    return true
end

local function fetchSlotDetail(slot)
    if not turtle then
        return { slot = slot, count = 0 }
    end
    local detail
    if turtle.getItemDetail then
        detail = turtle.getItemDetail(slot)
    end
    local count
    if turtle.getItemCount then
        count = turtle.getItemCount(slot)
    elseif detail then
        count = detail.count
    end
    count = count or 0
    local name = detail and detail.name or nil
    return {
        slot = slot,
        count = count,
        name = name,
        detail = detail,
    }
end

function inventory.scan(ctx, opts)
    local state = ensureInventoryState(ctx)
    if not turtle then
        state.slots = {}
        state.materialSlots = {}
        state.materialTotals = {}
        state.emptySlots = {}
        state.totalItems = 0
        state.dirty = false
        state.scanVersion = state.scanVersion + 1
        return false, "turtle API unavailable"
    end

    local slots = {}
    local materialSlots = {}
    local materialTotals = {}
    local emptySlots = {}
    local totalItems = 0

    for slot = 1, 16 do
        local info = fetchSlotDetail(slot)
        slots[slot] = info
        if info.count > 0 and info.name then
            local list = materialSlots[info.name]
            if not list then
                list = {}
                materialSlots[info.name] = list
            end
            list[#list + 1] = slot
            materialTotals[info.name] = (materialTotals[info.name] or 0) + info.count
            totalItems = totalItems + info.count
        else
            emptySlots[#emptySlots + 1] = slot
        end
    end

    state.slots = slots
    state.materialSlots = materialSlots
    state.materialTotals = materialTotals
    state.emptySlots = emptySlots
    state.totalItems = totalItems
    if os and type(os.clock) == "function" then
        state.lastScanClock = os.clock()
    else
        state.lastScanClock = nil
    end
    local epochFn = os and os["epoch"]
    if type(epochFn) == "function" then
        state.lastScanEpoch = epochFn("utc")
    else
        state.lastScanEpoch = nil
    end
    state.scanVersion = state.scanVersion + 1
    state.dirty = false

    logger.log(ctx, "debug", string.format("Inventory scan complete: %d items across %d materials", totalItems, tableCount(materialSlots)))
    return true
end

local function ensureScanned(ctx, opts)
    local state = ensureInventoryState(ctx)
    if state.dirty or (type(opts) == "table" and opts.force) or not state.slots or next(state.slots) == nil then
        local ok, err = inventory.scan(ctx, opts)
        if not ok and err then
            return nil, err
        end
    end
    return state
end

function inventory.getMaterialSlots(ctx, material, opts)
    if type(material) ~= "string" or material == "" then
        return nil, "invalid_material"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    local slots = state.materialSlots[material]
    if not slots then
        return {}
    end
    return copyArray(slots)
end

function inventory.getSlotForMaterial(ctx, material, opts)
    local slots, err = inventory.getMaterialSlots(ctx, material, opts)
    if slots == nil then
        return nil, err
    end
    if slots[1] then
        return slots[1]
    end
    return nil, "missing_material"
end

function inventory.countMaterial(ctx, material, opts)
    if type(material) ~= "string" or material == "" then
        return 0, "invalid_material"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return 0, err
    end
    return state.materialTotals[material] or 0
end

function inventory.hasMaterial(ctx, material, amount, opts)
    amount = amount or 1
    if amount <= 0 then
        return true
    end
    local total, err = inventory.countMaterial(ctx, material, opts)
    if err then
        return false, err
    end
    return total >= amount
end

function inventory.findEmptySlot(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    local empty = state.emptySlots
    if empty and empty[1] then
        return empty[1]
    end
    return nil, "no_empty_slot"
end

function inventory.isEmpty(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return false, err
    end
    return state.totalItems == 0
end

function inventory.totalItemCount(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return 0, err
    end
    return state.totalItems
end

function inventory.getTotals(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    return copySummary(state.materialTotals)
end

function inventory.snapshot(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    return {
        slots = copySlots(state.slots),
        totals = copySummary(state.materialTotals),
        emptySlots = copyArray(state.emptySlots),
        totalItems = state.totalItems,
        scanVersion = state.scanVersion,
        lastScanClock = state.lastScanClock,
        lastScanEpoch = state.lastScanEpoch,
    }
end

function inventory.detectContainer(ctx, opts)
    opts = opts or {}
    local side = resolveSide(ctx, opts)
    if side == "forward" then
        local chestOk, restoreFn, info, err = ensureChestAhead(ctx, opts)
        if not chestOk then
            return nil, err or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFn()
        end
        local result = info or { side = "forward" }
        result.peripheralSide = "front"
        return result
    elseif side == "up" then
        local okUp, detail = inspectUpForContainer()
        if okUp then
            return { side = "up", detail = detail, peripheralSide = "top" }
        end
        return nil, "container_not_found"
    elseif side == "down" then
        local okDown, detail = inspectDownForContainer()
        if okDown then
            return { side = "down", detail = detail, peripheralSide = "bottom" }
        end
        return nil, "container_not_found"
    end
    return nil, "unsupported_side"
end

function inventory.getContainerManifest(ctx, opts)
    if not turtle then
        return nil, "turtle API unavailable"
    end
    opts = opts or {}
    local side = resolveSide(ctx, opts)
    local periphSide = peripheralSideForDirection(side)
    local restoreFacing = noop
    local info

    if side == "forward" then
        local chestOk, restoreFn, chestInfo, err = ensureChestAhead(ctx, opts)
        if not chestOk then
            return nil, err or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFacing = restoreFn
        end
        info = chestInfo or { side = "forward" }
        periphSide = "front"
    elseif side == "up" then
        local okUp, detail = inspectUpForContainer()
        if not okUp then
            return nil, "container_not_found"
        end
        info = { side = "up", detail = detail }
        periphSide = "top"
    elseif side == "down" then
        local okDown, detail = inspectDownForContainer()
        if not okDown then
            return nil, "container_not_found"
        end
        info = { side = "down", detail = detail }
        periphSide = "bottom"
    else
        return nil, "unsupported_side"
    end

    local manifest, manifestErr = readContainerManifest(periphSide)
    restoreFacing()
    if not manifest then
        return nil, manifestErr or "wrap_failed"
    end

    manifest.peripheralSide = periphSide
    if info then
        manifest.relativeSide = info.side
        manifest.inspectDetail = info.detail
        if not manifest.metadata and info.detail then
            manifest.metadata = {
                name = info.detail.name,
                displayName = info.detail.displayName or info.detail.label,
                tags = info.detail.tags,
            }
        elseif manifest.metadata and info.detail then
            manifest.metadata.name = manifest.metadata.name or info.detail.name
            manifest.metadata.displayName = manifest.metadata.displayName or info.detail.displayName or info.detail.label
            manifest.metadata.tags = manifest.metadata.tags or info.detail.tags
        end
    end

    return manifest
end

function inventory.selectMaterial(ctx, material, opts)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local slot, err = inventory.getSlotForMaterial(ctx, material, opts)
    if not slot then
        return false, err or "missing_material"
    end
    if turtle.select(slot) then
        return true
    end
    return false, "select_failed"
end

local function selectSlot(slot)
    if not turtle then
        return false
    end
    if turtle.getSelectedSlot() == slot then
        return true
    end
    return turtle.select(slot)
end

function inventory.dropMaterial(ctx, material, amount, opts)
    opts = opts or {}
    local side = resolveSide(ctx, opts)
    local periphSide = peripheralSideForDirection(side)
    local slots = inventory.getMaterialSlots(ctx, material, opts)
    if not slots or #slots == 0 then
        return 0, "material_not_found"
    end

    local dropped = 0
    local remaining = amount or 64
    local action = SIDE_ACTIONS[side] and SIDE_ACTIONS[side].drop

    if not action then
        return 0, "invalid_side"
    end

    for _, slotInfo in ipairs(slots) do
        if remaining <= 0 then
            break
        end
        local count = slotInfo.count
        local toDrop = math.min(count, remaining)
        if selectSlot(slotInfo.slot) then
            if action(toDrop) then
                dropped = dropped + toDrop
                remaining = remaining - toDrop
                inventory.invalidate(ctx)
            else
                return dropped, "drop_failed"
            end
        else
            return dropped, "select_failed"
        end
    end
    return dropped
end

function inventory.suckMaterial(ctx, material, amount, opts)
    opts = opts or {}
    local side = resolveSide(ctx, opts)
    local periphSide = peripheralSideForDirection(side)
    
    -- If specific material requested, try to use peripheral push if available
    if material and peripheral.isPresent(periphSide) then
        local extracted = extractFromContainer(ctx, periphSide, material, amount)
        if extracted > 0 then
            inventory.invalidate(ctx)
            return extracted
        end
    end

    -- Fallback to suck
    local action = SIDE_ACTIONS[side] and SIDE_ACTIONS[side].suck
    if not action then
        return 0, "invalid_side"
    end

    if action(amount) then
        inventory.invalidate(ctx)
        -- We don't know exactly what we sucked or how much without scanning, 
        -- but we know the action succeeded.
        -- To be accurate, we should scan and check difference, but for now return success.
        return amount or 1 
    end
    return 0, "suck_failed"
end

function inventory.condense(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return false, err
    end

    local moves = 0
    local slots = state.slots
    
    -- Simple condense: find partial stacks and merge them
    -- This is O(N^2) over 16 slots, which is fine.
    for i = 1, 15 do
        local slotI = slots[i]
        if slotI.count > 0 and slotI.count < 64 and slotI.name then
            for j = i + 1, 16 do
                local slotJ = slots[j]
                if slotJ.count > 0 and slotJ.name == slotI.name then
                    -- Can merge J into I
                    local space = 64 - slotI.count
                    local toMove = math.min(space, slotJ.count)
                    if toMove > 0 then
                        if selectSlot(j) then
                            if turtle.transferTo(i, toMove) then
                                slotI.count = slotI.count + toMove
                                slotJ.count = slotJ.count - toMove
                                moves = moves + 1
                                inventory.invalidate(ctx)
                            end
                        end
                    end
                    if slotI.count >= 64 then
                        break
                    end
                end
            end
        end
    end
    
    return true, moves
end

function inventory.trash(ctx, opts)
    opts = opts or {}
    local trashList = opts.trash or inventory.DEFAULT_TRASH
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return false, err
    end

    local trashed = 0
    for i = 1, 16 do
        local slot = state.slots[i]
        if slot.count > 0 and slot.name and trashList[slot.name] then
            if selectSlot(i) then
                if turtle.drop() then -- Drop forward? or down? Usually trash is dropped wherever.
                    trashed = trashed + slot.count
                    inventory.invalidate(ctx)
                elseif turtle.dropDown() then
                     trashed = trashed + slot.count
                     inventory.invalidate(ctx)
                elseif turtle.dropUp() then
                     trashed = trashed + slot.count
                     inventory.invalidate(ctx)
                end
            end
        end
    end
    return true, trashed
end

function inventory.restock(ctx, requirements, opts)
    -- requirements: { ["minecraft:log"] = 16, ... }
    opts = opts or {}
    local missing = {}
    local state = ensureScanned(ctx, opts)
    
    for mat, count in pairs(requirements) do
        local current = inventory.countMaterial(ctx, mat)
        if current < count then
            missing[mat] = count - current
        end
    end
    
    if next(missing) == nil then
        return true
    end
    
    -- Try to pull from connected inventories
    -- This logic needs to be robust.
    -- For now, simple check forward/up/down
    
    local sides = {"front", "top", "bottom"}
    local pulledAny = false
    
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) then
            for mat, amount in pairs(missing) do
                if amount > 0 then
                    local pulled = extractFromContainer(ctx, side, mat, amount)
                    if pulled > 0 then
                        missing[mat] = missing[mat] - pulled
                        pulledAny = true
                        inventory.invalidate(ctx)
                    end
                end
            end
        end
    end
    
    -- Check if satisfied
    for mat, amount in pairs(missing) do
        if amount > 0 then
            return false, "missing_resources", missing
        end
    end
    
    return true
end

function inventory.dump(ctx, opts)
    -- Dump everything except kept items
    opts = opts or {}
    local keep = opts.keep or {}
    local side = resolveSide(ctx, opts)
    local action = SIDE_ACTIONS[side] and SIDE_ACTIONS[side].drop
    if not action then return false, "invalid_side" end
    
    local state = ensureScanned(ctx, opts)
    local dumped = 0
    
    for i = 1, 16 do
        local slot = state.slots[i]
        if slot.count > 0 and slot.name then
            local keepCount = keep[slot.name] or 0
            if keepCount < slot.count then
                -- Need to dump some
                local toDump = slot.count - keepCount
                if selectSlot(i) then
                    if action(toDump) then
                        dumped = dumped + toDump
                        inventory.invalidate(ctx)
                    end
                end
            end
        end
    end
    return true, dumped
end

function inventory.hasSpace(ctx, opts)
    local state = ensureScanned(ctx, opts)
    if not state then return false end
    if #state.emptySlots > 0 then return true end
    -- Check if any stack is not full?
    -- Actually, usually we just care about empty slots for new items
    return false
end

function inventory.compact(ctx)
    return inventory.condense(ctx)
end

function inventory.transfer(ctx, toSlot, fromSlot, amount)
    if not turtle then return false end
    if fromSlot == toSlot then return true end
    if selectSlot(fromSlot) then
        if amount then
            return turtle.transferTo(toSlot, amount)
        else
            return turtle.transferTo(toSlot)
        end
    end
    return false
end

function inventory.equip(ctx, side, material)
    -- side: "left" or "right"
    if not turtle then return false end
    local slot, err = inventory.getSlotForMaterial(ctx, material)
    if not slot then return false, err end
    
    if selectSlot(slot.slot) then
        if side == "left" then
            return turtle.equipLeft()
        else
            return turtle.equipRight()
        end
    end
    return false
end

function inventory.pullMaterial(ctx, material, amount, opts)
    -- High level pull: find container with material and pull it
    -- This relies on ensureChestAhead or similar logic being available/configured
    -- For now, just a wrapper around extractFromContainer if side is known
    opts = opts or {}
    local side = resolveSide(ctx, opts)
    local periphSide = peripheralSideForDirection(side)
    
    if peripheral.isPresent(periphSide) then
        local count = extractFromContainer(ctx, periphSide, material, amount)
        if count > 0 then
            inventory.invalidate(ctx)
            return true, count
        end
    end
    return false, "not_found"
end

function inventory.pushMaterial(ctx, material, amount, opts)
    return inventory.dropMaterial(ctx, material, amount, opts)
end

function inventory.getSlotDetail(ctx, slot)
    local state = ensureScanned(ctx)
    if state and state.slots then
        return state.slots[slot]
    end
    return fetchSlotDetail(slot)
end

function inventory.refresh(ctx)
    return inventory.scan(ctx, { force = true })
end

function inventory.checkRequirements(ctx, requirements)
    local missing = {}
    local hasMissing = false
    for mat, count in pairs(requirements) do
        local avail = inventory.countMaterial(ctx, mat)
        if avail < count then
            missing[mat] = count - avail
            hasMissing = true
        end
    end
    if hasMissing then
        return false, missing
    end
    return true
end

function inventory.consume(ctx, material, amount)
    -- "Consume" means ensure we have it, and then assume it's used (e.g. for building)
    -- This doesn't actually remove it from inventory, just checks presence.
    -- The actual removal happens when turtle.place() is called.
    return inventory.hasMaterial(ctx, material, amount)
end

function inventory.ensureSelected(ctx, material)
    return inventory.selectMaterial(ctx, material)
end

function inventory.findItem(ctx, material)
    local slot = inventory.getSlotForMaterial(ctx, material)
    if slot then return slot.slot end
    return nil
end

-- Advanced inventory management

function inventory.sort(ctx)
    -- Sort inventory by name
    local state = ensureScanned(ctx)
    local slots = copySlots(state.slots)
    local sorted = {}
    for i=1,16 do sorted[i] = slots[i] end
    
    table.sort(sorted, function(a,b)
        if a.name and not b.name then return true end
        if not a.name and b.name then return false end
        if not a.name and not b.name then return false end
        if a.name == b.name then return a.count > b.count end
        return a.name < b.name
    end)
    
    -- Apply sort... this is complex to execute efficiently.
    -- Skipping for now as it's not critical.
    return false, "not_implemented"
end

function inventory.dumpTrash(ctx)
    return inventory.trash(ctx)
end

function inventory.getInventory(ctx)
    local state = ensureScanned(ctx)
    return state.slots
end

function inventory.inspect(ctx, slot)
    return inventory.getSlotDetail(ctx, slot)
end

function inventory.getItemCount(ctx, slot)
    local detail = inventory.getSlotDetail(ctx, slot)
    return detail and detail.count or 0
end

function inventory.getItemName(ctx, slot)
    local detail = inventory.getSlotDetail(ctx, slot)
    return detail and detail.name
end

function inventory.getFreeSpace(ctx, slot)
    local detail = inventory.getSlotDetail(ctx, slot)
    if not detail or not detail.name then return 64 end
    local limit = 64 -- Assume 64 for now, could check maxStackSize if available
    return limit - detail.count
end

function inventory.isFull(ctx)
    local state = ensureScanned(ctx)
    return #state.emptySlots == 0
end

function inventory.merge(ctx)
    return inventory.condense(ctx)
end

-- Helper to check if we have enough fuel items
function inventory.hasFuel(ctx, threshold)
    -- This requires knowing which items are fuel.
    -- We can check turtle.refuel(0) on items?
    -- Or use a known fuel list.
    -- For now, assume coal/charcoal/lava
    local fuels = {
        ["minecraft:coal"] = 80,
        ["minecraft:charcoal"] = 80,
        ["minecraft:lava_bucket"] = 1000,
        ["minecraft:blaze_rod"] = 120,
    }
    
    local total = 0
    for mat, value in pairs(fuels) do
        local count = inventory.countMaterial(ctx, mat)
        total = total + (count * value)
    end
    return total >= (threshold or 0)
end

function inventory.refuel(ctx, amount)
    -- Try to refuel 'amount' levels
    -- Scan for fuel items and consume them
    local needed = amount or (turtle.getFuelLimit() - turtle.getFuelLevel())
    if needed <= 0 then return true end
    
    local fuels = {
        "minecraft:coal",
        "minecraft:charcoal",
        "minecraft:lava_bucket",
        "minecraft:blaze_rod",
        "minecraft:stick",
        "minecraft:planks",
        "minecraft:log",
    }
    
    for _, fuel in ipairs(fuels) do
        local slots = inventory.getMaterialSlots(ctx, fuel)
        if slots then
            for _, slot in ipairs(slots) do
                if selectSlot(slot.slot) then
                    if turtle.refuel(0) then -- Check if it is fuel
                         -- Refuel one by one or all?
                         turtle.refuel() -- Refuel all in stack
                         inventory.invalidate(ctx)
                         if turtle.getFuelLevel() >= (turtle.getFuelLimit() - 100) then
                             return true
                         end
                    end
                end
            end
        end
    end
    return true
end

function inventory.ensureState(ctx)
    if not ctx.inventory then
        ctx.inventory = {}
    end
    
    -- Check if we need to rescan
    local changes = false
    if not ctx.inventory.slots then
        changes = true
    end
    
    if changes then
        inventory.scan(ctx)
    end
    return true
end

function inventory.getCounts(ctx)
    local counts = {}
    -- Scan all slots
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then
            counts[item.name] = (counts[item.name] or 0) + item.count
        end
    end
    return counts
end

function inventory.retrieveFromNearby(ctx, missing)
    local sides = {"front", "top", "bottom", "left", "right", "back"}
    local pulledAny = false
    
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) then
            local types = { peripheral.getType(side) }
            local isInventory = false
            for _, t in ipairs(types) do
                if t == "inventory" then isInventory = true break end
            end
            
            if isInventory then
                local p = peripheral.wrap(side)
                if p and p.list then
                    local list = p.list()
                    local neededFromChest = {}
                    for slot, item in pairs(list) do
                        if item and missing[item.name] and missing[item.name] > 0 then
                            neededFromChest[item.name] = true
                        end
                    end
                    
                    -- Check if we need anything from this chest
                    local hasNeeds = false
                    for k,v in pairs(neededFromChest) do hasNeeds = true break end
                    
                    if hasNeeds then
                        local pullSide = "forward"
                        local turned = false
                        
                        -- Turn to face the chest if needed
                        if side == "top" then pullSide = "up"
                        elseif side == "bottom" then pullSide = "down"
                        elseif side == "front" then pullSide = "forward"
                        elseif side == "left" then
                            movement.turnLeft(ctx)
                            turned = true
                            pullSide = "forward"
                        elseif side == "right" then
                            movement.turnRight(ctx)
                            turned = true
                            pullSide = "forward"
                        elseif side == "back" then
                            movement.turnRight(ctx)
                            movement.turnRight(ctx)
                            turned = true
                            pullSide = "forward"
                        end
                        
                        -- Pull all needed items
                        for mat, _ in pairs(neededFromChest) do
                            local amount = missing[mat]
                            if amount > 0 then
                                print(string.format("Attempting to pull %s from %s...", mat, side))
                                -- If inventory is full, try condensing to free space before pulling
                                local empty = inventory.findEmptySlot(ctx)
                                if not empty then
                                    pcall(inventory.condense, ctx)
                                    empty = inventory.findEmptySlot(ctx)
                                end
                                if not empty then
                                    logger.log(ctx, "warn", string.format("No empty slot available to pull %s; skipping pull", mat))
                                else
                                local success, err = inventory.pullMaterial(ctx, mat, amount, { side = pullSide })
                                if success then
                                    pulledAny = true
                                    missing[mat] = math.max(0, missing[mat] - amount)
                                else
                                     logger.log(ctx, "warn", "Failed to pull " .. mat .. ": " .. tostring(err))
                                end
                                end
                            end
                        end
                        
                        -- Restore facing
                        if turned then
                            if side == "left" then movement.turnRight(ctx)
                            elseif side == "right" then movement.turnLeft(ctx)
                            elseif side == "back" then 
                                movement.turnRight(ctx)
                                movement.turnRight(ctx)
                            end
                        end
                    end
                end
            end
        end
    end
    return pulledAny
end

function inventory.checkNearby(ctx, missing)
    local found = {}
    local sides = {"front", "top", "bottom", "left", "right", "back"}
    
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) then
            local types = { peripheral.getType(side) }
            local isInventory = false
            for _, t in ipairs(types) do
                if t == "inventory" then isInventory = true break end
            end
            
            if isInventory then
                local p = peripheral.wrap(side)
                if p and p.list then
                    local list = p.list()
                    for slot, item in pairs(list) do
                        if item and missing[item.name] then
                            found[item.name] = (found[item.name] or 0) + item.count
                        end
                    end
                end
            end
        end
    end
    return found
end

return inventory
]=])

addEmbeddedFile("lib/lib_table.lua", [=[
local table_utils = {}

function table_utils.copy(source)
    if type(source) ~= "table" then
        return {}
    end
    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for k, v in pairs(value) do
        result[k] = deepCopy(v)
    end
    return result
end

table_utils.deepCopy = deepCopy

function table_utils.merge(base, overrides)
    if type(base) ~= "table" and type(overrides) ~= "table" then
        return overrides or base
    end

    local result = {}

    if type(base) == "table" then
        for k, v in pairs(base) do
            result[k] = deepCopy(v)
        end
    end

    if type(overrides) == "table" then
        for k, v in pairs(overrides) do
            if type(v) == "table" and type(result[k]) == "table" then
                result[k] = table_utils.merge(result[k], v)
            else
                result[k] = deepCopy(v)
            end
        end
    elseif overrides ~= nil then
        return deepCopy(overrides)
    end

    return result
end

function table_utils.copyArray(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for i = 1, #source do
        result[i] = source[i]
    end
    return result
end

function table_utils.sumValues(tbl)
    local total = 0
    if type(tbl) ~= "table" then
        return total
    end
    for _, value in pairs(tbl) do
        if type(value) == "number" then
            total = total + value
        end
    end
    return total
end

function table_utils.copyTotals(totals)
    local result = {}
    for material, count in pairs(totals or {}) do
        result[material] = count
    end
    return result
end

function table_utils.mergeTotals(target, source)
    for material, count in pairs(source or {}) do
        target[material] = (target[material] or 0) + count
    end
end

function table_utils.tableCount(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function table_utils.copyArray(list)
    if type(list) ~= "table" then
        return {}
    end
    local result = {}
    for index = 1, #list do
        result[index] = list[index]
    end
    return result
end

function table_utils.copySummary(summary)
    if type(summary) ~= "table" then
        return {}
    end
    local result = {}
    for key, value in pairs(summary) do
        result[key] = value
    end
    return result
end

function table_utils.copySlots(slots)
    if type(slots) ~= "table" then
        return {}
    end
    local result = {}
    for slot, info in pairs(slots) do
        if type(info) == "table" then
            result[slot] = {
                slot = info.slot,
                count = info.count,
                name = info.name,
                detail = info.detail,
            }
        else
            result[slot] = info
        end
    end
    return result
end

function table_utils.copyValue(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for k, v in pairs(value) do
        result[k] = table_utils.copyValue(v, seen)
    end
    return result
end

function table_utils.shallowCopy(tbl)
    local result = {}
    for k, v in pairs(tbl) do
        result[k] = v
    end
    return result
end

return table_utils
]=])

addEmbeddedFile("lib/lib_string.lua", [=[
local string_utils = {}

function string_utils.trim(text)
    if type(text) ~= "string" then
        return text
    end
    return text:match("^%s*(.-)%s*$")
end

function string_utils.detailToString(value, depth)
    depth = (depth or 0) + 1
    if depth > 4 then
        return "..."
    end
    if type(value) ~= "table" then
        return tostring(value)
    end
    if textutils and textutils.serialize then
        return textutils.serialize(value)
    end
    local parts = {}
    for k, v in pairs(value) do
        parts[#parts + 1] = tostring(k) .. "=" .. string_utils.detailToString(v, depth)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

return string_utils
]=])

addEmbeddedFile("lib/version.lua", [=[
--[[
Version and build counter for Arcadesys TurtleOS.
Build counter increments on each bundle/rebuild.
]]

local version = {}

version.MAJOR = 2
version.MINOR = 1
version.PATCH = 1
version.BUILD = 47

--- Format version string (e.g., "v2.1.1 (build 42)")
function version.toString()
    return string.format("v%d.%d.%d (build %d)", 
        version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end

--- Format short display (e.g., "TurtleOS v2.1.1 #42")
function version.display()
    return string.format("TurtleOS v%d.%d.%d #%d", 
        version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end

return version
]=])

addEmbeddedFile("lib/lib_world.lua", [=[
local world = {}

function world.getInspect(side)
    if side == "forward" then
        return turtle.inspect
    elseif side == "up" then
        return turtle.inspectUp
    elseif side == "down" then
        return turtle.inspectDown
    end
    return nil
end

local SIDE_ALIASES = {
    forward = "forward",
    front = "forward",
    down = "down",
    bottom = "down",
    up = "up",
    top = "up",
    left = "left",
    right = "right",
    back = "back",
    behind = "back",
}

function world.normaliseSide(side)
    if type(side) ~= "string" then
        return nil
    end
    return SIDE_ALIASES[string.lower(side)]
end

function world.toPeripheralSide(side)
    local normalised = world.normaliseSide(side) or side
    if normalised == "forward" then
        return "front"
    elseif normalised == "up" then
        return "top"
    elseif normalised == "down" then
        return "bottom"
    elseif normalised == "back" then
        return "back"
    elseif normalised == "left" then
        return "left"
    elseif normalised == "right" then
        return "right"
    end
    return normalised
end

function world.inspectSide(side)
    local normalised = world.normaliseSide(side)
    if normalised == "forward" then
        return turtle and turtle.inspect and turtle.inspect()
    elseif normalised == "up" then
        return turtle and turtle.inspectUp and turtle.inspectUp()
    elseif normalised == "down" then
        return turtle and turtle.inspectDown and turtle.inspectDown()
    end
    return false
end

function world.isContainer(detail)
    if type(detail) ~= "table" then
        return false
    end
    local name = string.lower(detail.name or "")
    if name:find("chest", 1, true) or name:find("barrel", 1, true) or name:find("drawer", 1, true) then
        return true
    end
    if type(detail.tags) == "table" then
        for tag in pairs(detail.tags) do
            local lowered = string.lower(tag)
            if lowered:find("inventory", 1, true) or lowered:find("chest", 1, true) or lowered:find("barrel", 1, true) then
                return true
            end
        end
    end
    return false
end

function world.normalizeSide(value)
    if type(value) ~= "string" then
        return nil
    end
    local lower = value:lower()
    if lower == "forward" or lower == "front" or lower == "fwd" then
        return "forward"
    end
    if lower == "up" or lower == "top" or lower == "above" then
        return "up"
    end
    if lower == "down" or lower == "bottom" or lower == "below" then
        return "down"
    end
    return nil
end

function world.resolveSide(ctx, opts)
    if type(opts) == "string" then
        local direct = world.normalizeSide(opts)
        return direct or "forward"
    end

    local candidate
    if type(opts) == "table" then
        candidate = opts.side or opts.direction or opts.facing or opts.containerSide or opts.defaultSide
        if not candidate and type(opts.location) == "string" then
            candidate = opts.location
        end
    end

    if not candidate and type(ctx) == "table" then
        local cfg = ctx.config
        if type(cfg) == "table" then
            candidate = cfg.inventorySide or cfg.materialSide or cfg.supplySide or cfg.defaultInventorySide
        end
        if not candidate and type(ctx.inventoryState) == "table" then
            candidate = ctx.inventoryState.defaultSide
        end
    end

    local normalised = world.normalizeSide(candidate)
    if normalised then
        return normalised
    end

    return "forward"
end

function world.isContainerBlock(name, tags)
    if type(name) ~= "string" then
        return false
    end
    local lower = name:lower()
    for _, keyword in ipairs(CONTAINER_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true
        end
    end
    return world.hasContainerTag(tags)
end

function world.inspectForwardForContainer()
    if not turtle or type(turtle.inspect) ~= "function" then
        return false
    end
    local ok, data = turtle.inspect()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectUpForContainer()
    if not turtle or type(turtle.inspectUp) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectUp()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectDownForContainer()
    if not turtle or type(turtle.inspectDown) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectDown()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.peripheralSideForDirection(side)
    if side == "forward" or side == "front" then
        return "front"
    end
    if side == "up" or side == "top" then
        return "top"
    end
    if side == "down" or side == "bottom" then
        return "bottom"
    end
    return side
end

function world.computePrimaryPushDirection(ctx, periphSide)
    if periphSide == "front" then
        local facing = movement.getFacing(ctx)
        if facing then
            return OPPOSITE_FACING[facing]
        end
    elseif periphSide == "top" then
        return "down"
    elseif periphSide == "bottom" then
        return "up"
    end
    return nil
end

function world.normaliseCoordinate(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    if number >= 0 then
        return math.floor(number + 0.5)
    end
    return math.ceil(number - 0.5)
end

function world.normalisePosition(pos)
    if type(pos) ~= "table" then
        return nil, "invalid_position"
    end
    local xRaw = pos.x
    if xRaw == nil then
        xRaw = pos[1]
    end
    local yRaw = pos.y
    if yRaw == nil then
        yRaw = pos[2]
    end
    local zRaw = pos.z
    if zRaw == nil then
        zRaw = pos[3]
    end
    local x = world.normaliseCoordinate(xRaw)
    local y = world.normaliseCoordinate(yRaw)
    local z = world.normaliseCoordinate(zRaw)
    if not x or not y or not z then
        return nil, "invalid_position"
    end
    return { x = x, y = y, z = z }
end

function world.normaliseFacing(facing)
    facing = type(facing) == "string" and facing:lower() or "north"
    if facing ~= "north" and facing ~= "east" and facing ~= "south" and facing ~= "west" then
        return "north"
    end
    return facing
end

function world.facingVectors(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return { forward = { x = 0, z = -1 }, right = { x = 1, z = 0 } }
    elseif facing == "east" then
        return { forward = { x = 1, z = 0 }, right = { x = 0, z = 1 } }
    elseif facing == "south" then
        return { forward = { x = 0, z = 1 }, right = { x = -1, z = 0 } }
    else -- west
        return { forward = { x = -1, z = 0 }, right = { x = 0, z = -1 } }
    end
end

function world.rotateLocalOffset(localOffset, facing)
    local vectors = world.facingVectors(facing)
    local dx = localOffset.x or 0
    local dz = localOffset.z or 0
    local right = vectors.right
    local forward = vectors.forward
    return {
        x = (right.x * dx) + (forward.x * dz),
        z = (right.z * dx) + (forward.z * dz),
    }
end

function world.localToWorld(localOffset, facing)
    facing = world.normaliseFacing(facing)
    local dx = localOffset and localOffset.x or 0
    local dz = localOffset and localOffset.z or 0
    local rotated = world.rotateLocalOffset({ x = dx, z = dz }, facing)
    return {
        x = rotated.x,
        y = localOffset and localOffset.y or 0,
        z = rotated.z,
    }
end

function world.localToWorldRelative(origin, localPos)
    local rotated = world.localToWorld(localPos, origin.facing)
    return {
        x = origin.x + rotated.x,
        y = origin.y + rotated.y,
        z = origin.z + rotated.z
    }
end

function world.copyPosition(pos)
    if type(pos) ~= "table" then
        return nil
    end
    return {
        x = pos.x or 0,
        y = pos.y or 0,
        z = pos.z or 0,
    }
end

function world.detectContainers(io)
    local found = {}
    local sides = { "forward", "down", "up" }
    local labels = {
        forward = "front",
        down = "below",
        up = "above",
    }
    for _, side in ipairs(sides) do
        local inspect
        if side == "forward" then
            inspect = turtle.inspect
        elseif side == "up" then
            inspect = turtle.inspectUp
        else
            inspect = turtle.inspectDown
        end
        if type(inspect) == "function" then
            local ok, detail = inspect()
            if ok then
                local name = type(detail.name) == "string" and detail.name or "unknown"
                found[#found + 1] = string.format(" %s: %s", labels[side] or side, name)
            end
        end
    end
    if io.print then
        if #found == 0 then
            io.print("Detected containers: <none>")
        else
            io.print("Detected containers:")
            for _, line in ipairs(found) do
                io.print(" -" .. line)
            end
        end
    end
end

return world
]=])

addEmbeddedFile("lib/lib_fuel.lua", [=[
--[[
Fuel management helpers for CC:Tweaked turtles.
Tracks thresholds, detects low fuel conditions, and provides a simple
SERVICE routine that returns the turtle to origin and attempts to refuel
from configured sources.
--]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local table_utils = require("lib_table")
local logger = require("lib_logger")
local copyTable = table_utils.copy or table_utils.shallowCopy or function(tbl)
    local result = {}
    if type(tbl) ~= "table" then
        return result
    end
    for k, v in pairs(tbl) do
        result[k] = v
    end
    return result
end

local fuel = {}

local DEFAULT_THRESHOLD = 80
local DEFAULT_RESERVE = 160
local DEFAULT_SIDES = { "forward", "down", "up" }
local DEFAULT_FUEL_ITEMS = {
    "minecraft:coal",
    "minecraft:charcoal",
    "minecraft:coal_block",
    "minecraft:lava_bucket",
    "minecraft:blaze_rod",
    "minecraft:dried_kelp_block",
}

local function ensureFuelState(ctx)
    if type(ctx) ~= "table" then
        error("fuel library requires a context table", 2)
    end
    ctx.fuelState = ctx.fuelState or {}
    local state = ctx.fuelState
    local cfg = ctx.config or {}

    state.threshold = state.threshold or cfg.fuelThreshold or cfg.minFuel or DEFAULT_THRESHOLD
    state.reserve = state.reserve or cfg.fuelReserve or math.max(DEFAULT_RESERVE, state.threshold * 2)
    state.fuelItems = state.fuelItems or (cfg.fuelItems and #cfg.fuelItems > 0 and table_utils.copyArray(cfg.fuelItems)) or table_utils.copyArray(DEFAULT_FUEL_ITEMS)
    state.sides = state.sides or (cfg.fuelChestSides and #cfg.fuelChestSides > 0 and table_utils.copyArray(cfg.fuelChestSides)) or table_utils.copyArray(DEFAULT_SIDES)
    state.cycleLimit = state.cycleLimit or cfg.fuelCycleLimit or cfg.inventoryCycleLimit or 192
    state.history = state.history or {}
    state.serviceActive = state.serviceActive or false
    state.lastLevel = state.lastLevel or nil
    return state
end

function fuel.ensureState(ctx)
    return ensureFuelState(ctx)
end

local function readFuel()
    if not turtle or not turtle.getFuelLevel then
        return nil, nil, false
    end
    local level = turtle.getFuelLevel()
    local limit = turtle.getFuelLimit and turtle.getFuelLimit() or nil
    if level == "unlimited" or limit == "unlimited" then
        return nil, nil, true
    end
    if level == math.huge or limit == math.huge then
        return nil, nil, true
    end
    if type(level) ~= "number" then
        return nil, nil, false
    end
    if type(limit) ~= "number" then
        limit = nil
    end
    return level, limit, false
end

local function resolveTarget(state, opts)
    opts = opts or {}
    local target = opts.target or 0
    if type(target) ~= "number" or target <= 0 then
        target = 0
    end
    local threshold = opts.threshold or state.threshold or 0
    local reserve = opts.reserve or state.reserve or 0
    if threshold > target then
        target = threshold
    end
    if reserve > target then
        target = reserve
    end
    if target <= 0 then
        target = threshold > 0 and threshold or DEFAULT_THRESHOLD
    end
    return target
end
    
local function resolveSides(state, opts)
    opts = opts or {}
    if type(opts.sides) == "table" and #opts.sides > 0 then
        return table_utils.copyArray(opts.sides)
    end
    return table_utils.copyArray(state.sides)
end

local function resolveFuelItems(state, opts)
    opts = opts or {}
    if type(opts.fuelItems) == "table" and #opts.fuelItems > 0 then
        return table_utils.copyArray(opts.fuelItems)
    end
    return table_utils.copyArray(state.fuelItems)
end

local function recordHistory(state, entry)
    state.history = state.history or {}
    state.history[#state.history + 1] = entry
    local limit = 20
    while #state.history > limit do
        table.remove(state.history, 1)
    end
end

local function consumeFromInventory(ctx, target, opts)
    if not turtle or type(turtle.refuel) ~= "function" then
        return false, { error = "turtle API unavailable" }
    end
    local before = select(1, readFuel())
    if before == nil then
        return false, { error = "fuel unreadable" }
    end
    target = target or 0
    if target <= 0 then
        return false, {
            consumed = {},
            startLevel = before,
            endLevel = before,
            note = "no_target",
        }
    end

    local level = before
    local consumed = {}
    for slot = 1, 16 do
        if target > 0 and level >= target then
            break
        end

        local item = turtle.getItemDetail(slot)
        local shouldSkip = false
        if item and opts and opts.excludeItems then
            for _, pattern in ipairs(opts.excludeItems) do
                if item.name:find(pattern) then
                    shouldSkip = true
                    break
                end
            end
        end

        if not shouldSkip then
            turtle.select(slot)
            local count = turtle.getItemCount(slot)
            local canRefuel = count and count > 0 and turtle.refuel(0)
            if canRefuel then
                while (target <= 0 or level < target) and turtle.getItemCount(slot) > 0 do
                    if not turtle.refuel(1) then
                        break
                    end
                    consumed[slot] = (consumed[slot] or 0) + 1
                    level = select(1, readFuel()) or level
                    if target > 0 and level >= target then
                        break
                    end
                end
            end
        end
    end
    local after = select(1, readFuel()) or level
    if inventory.invalidate then
        inventory.invalidate(ctx)
    end
    return (after > before), {
        consumed = consumed,
        startLevel = before,
        endLevel = after,
    }
end

local function pullFromSources(ctx, state, opts, target)
    if not turtle then
        return false, { error = "turtle API unavailable" }
    end
    inventory.ensureState(ctx)
    local sides = resolveSides(state, opts)
    local items = resolveFuelItems(state, opts)
    local pullAmount = opts and opts.pullAmount
    local pulled = {}
    local errors = {}
    local refueled = {}
    local attempts = 0
    local maxAttempts = opts and opts.maxPullAttempts or (#sides * #items)
    if maxAttempts < 1 then
        maxAttempts = #sides * #items
    end
    local cycleLimit = (opts and opts.inventoryCycleLimit) or state.cycleLimit or 192
    for _, side in ipairs(sides) do
        for _, material in ipairs(items) do
            if attempts >= maxAttempts then
                break
            end
            attempts = attempts + 1
            local ok, err = inventory.pullMaterial(ctx, material, pullAmount, {
                side = side,
                deferScan = true,
                cycleLimit = cycleLimit,
            })
            if ok then
                pulled[#pulled + 1] = { side = side, material = material }
                logger.log(ctx, "debug", string.format("Pulled %s from %s", material, side))
                -- Immediately refresh inventory and attempt to use pulled items as fuel
                if turtle and type(turtle.refuel) == "function" then
                    -- force a fresh scan so we can locate the pulled stacks
                    inventory.ensureState(ctx)
                    inventory.scan(ctx)
                    local slots, _err = inventory.getMaterialSlots(ctx, material)
                    if slots and #slots > 0 then
                        for _, slot in ipairs(slots) do
                            local detail = turtle.getItemDetail and turtle.getItemDetail(slot) or nil
                            local shouldSkip = false
                            if detail and opts and opts.excludeItems then
                                for _, pattern in ipairs(opts.excludeItems) do
                                    if detail.name and detail.name:find(pattern) then
                                        shouldSkip = true
                                        break
                                    end
                                end
                            end
                            if shouldSkip then
                                logger.log(ctx, "debug", string.format("Skipping refuel from %s (slot %d) due to excludeItems", material, slot))
                            else
                                local beforeLevel = select(1, readFuel()) or 0
                                if turtle.refuel(0) then
                                    turtle.select(slot)
                                    local consumedCount = 0
                                    while turtle.getItemCount and turtle.getItemCount(slot) > 0 do
                                        -- stop if we reached target (if provided)
                                        local current = select(1, readFuel()) or beforeLevel
                                        if target and target > 0 and current >= target then
                                            break
                                        end
                                        if not turtle.refuel(1) then
                                            break
                                        end
                                        consumedCount = consumedCount + 1
                                    end
                                    if consumedCount > 0 then
                                        refueled[#refueled + 1] = { slot = slot, material = material, consumed = consumedCount }
                                        logger.log(ctx, "debug", string.format("Refueled using %d of %s from slot %d", consumedCount, material, slot))
                                    end
                                end
                            end
                        end
                        if #refueled > 0 then
                            inventory.invalidate(ctx)
                            inventory.scan(ctx)
                        end
                    end
                end
            elseif err ~= "missing_material" then
                errors[#errors + 1] = { side = side, material = material, error = err }
                logger.log(ctx, "warn", string.format("Pull %s from %s failed: %s", material, side, tostring(err)))
            end
        end
        if attempts >= maxAttempts then
            break
        end
    end
    if #pulled > 0 then
        inventory.invalidate(ctx)
    end
    return #pulled > 0, { pulled = pulled, errors = errors, refueled = refueled }
end

local function refuelRound(ctx, state, opts, target, report)
    local consumed, info = consumeFromInventory(ctx, target, opts)
    report.steps[#report.steps + 1] = {
        type = "inventory",
        round = report.round,
        success = consumed,
        info = info,
    }
    if consumed then
        logger.log(ctx, "debug", string.format("Consumed %d fuel items from inventory", table_utils.sumValues(info and info.consumed)))
    end
    local level = select(1, readFuel())
    if level and level >= target and target > 0 then
        report.finalLevel = level
        report.reachedTarget = true
        return true, report
    end

    local pullOpts = opts and copyTable(opts) or {}
    local missing = target - (level or 0)
    if missing > 0 then
        -- Avoid over-pulling unstackable fuels (e.g., lava buckets). Assume a conservative 1000 fuel per item.
        pullOpts.pullAmount = pullOpts.pullAmount or math.max(1, math.ceil(missing / 1000))
    end

    local pulled, pullInfo = pullFromSources(ctx, state, pullOpts, target)
    report.steps[#report.steps + 1] = {
        type = "pull",
        round = report.round,
        success = pulled,
        info = pullInfo,
    }

    if pulled then
        local consumedAfterPull, postInfo = consumeFromInventory(ctx, target, opts)
        report.steps[#report.steps + 1] = {
            type = "inventory",
            stage = "post_pull",
            round = report.round,
            success = consumedAfterPull,
            info = postInfo,
        }
        if consumedAfterPull then
            logger.log(ctx, "debug", string.format("Post-pull consumption used %d fuel items", table_utils.sumValues(postInfo and postInfo.consumed)))
            local postLevel = select(1, readFuel())
            if postLevel and postLevel >= target and target > 0 then
                report.finalLevel = postLevel
                report.reachedTarget = true
                return true, report
            end
        end
    end

    return (pulled or consumed), report
end

local function refuelInternal(ctx, state, opts)
    local startLevel, limit, unlimited = readFuel()
    if unlimited then
        return true, {
            startLevel = startLevel,
            limit = limit,
            finalLevel = startLevel,
            unlimited = true,
        }
    end
    if not startLevel then
        return true, {
            startLevel = nil,
            limit = limit,
            finalLevel = nil,
            message = "fuel level unavailable",
        }
    end

    local target = resolveTarget(state, opts)
    local report = {
        startLevel = startLevel,
        limit = limit,
        target = target,
        steps = {},
    }

    local rounds = opts and opts.rounds or 3
    if rounds < 1 then
        rounds = 1
    end

    for i = 1, rounds do
        report.round = i
        local ok, roundReport = refuelRound(ctx, state, opts, target, report)
        report = roundReport
        if report.reachedTarget then
            return true, report
        end
        if not ok then
            break
        end
    end

    report.finalLevel = select(1, readFuel()) or startLevel
    if report.finalLevel and report.finalLevel >= target and target > 0 then
        report.reachedTarget = true
        return true, report
    end
    report.reachedTarget = target <= 0
    return report.reachedTarget, report
end

function fuel.check(ctx, opts)
    local state = ensureFuelState(ctx)
    local level, limit, unlimited = readFuel()
    state.lastLevel = level or state.lastLevel

    local report = {
        level = level,
        limit = limit,
        unlimited = unlimited,
        threshold = state.threshold,
        reserve = state.reserve,
        history = state.history,
    }

    if unlimited then
        report.ok = true
        return true, report
    end
    if not level then
        report.ok = true
        report.note = "fuel level unavailable"
        return true, report
    end

    local threshold = opts and opts.threshold or state.threshold or 0
    report.threshold = threshold
    report.reserve = opts and opts.reserve or state.reserve
    report.ok = level >= threshold
    report.needsService = not report.ok
    report.depleted = level <= 0
    return report.ok, report
end

function fuel.refuel(ctx, opts)
    local state = ensureFuelState(ctx)
    local ok, report = refuelInternal(ctx, state, opts)
    recordHistory(state, {
        type = "refuel",
        timestamp = os and os.time and os.time() or nil,
        success = ok,
        report = report,
    })
    if ok then
        logger.log(ctx, "info", string.format("Refuel complete (fuel=%s)", tostring(report.finalLevel or "unknown")))
    else
        logger.log(ctx, "warn", "Refuel attempt did not reach target level")
    end
    return ok, report
end

function fuel.ensure(ctx, opts)
    local state = ensureFuelState(ctx)
    local ok, report = fuel.check(ctx, opts)
    if ok then
        return true, report
    end
    if opts and opts.nonInteractive then
        return false, report
    end
    local serviceOk, serviceReport = fuel.service(ctx, opts)
    if not serviceOk then
        report.service = serviceReport
        return false, report
    end
    return fuel.check(ctx, opts)
end

local function bootstrapFuel(ctx, state, opts, report)
    logger.log(ctx, "warn", "Fuel depleted; attempting to consume onboard fuel before navigating")
    local minimumMove = opts and opts.minimumMoveFuel or math.max(10, state.threshold or 0)
    if minimumMove <= 0 then
        minimumMove = 10
    end
    local consumed, info = consumeFromInventory(ctx, minimumMove, opts)
    report.steps[#report.steps + 1] = {
        type = "inventory",
        stage = "bootstrap",
        success = consumed,
        info = info,
    }
    local level = select(1, readFuel()) or (info and info.endLevel) or report.startLevel
    report.bootstrapLevel = level
    if level <= 0 then
        logger.log(ctx, "error", "Fuel depleted; cannot move to origin")
        report.error = "out_of_fuel"
        report.finalLevel = level
        return false, report
    end
    return true, report
end

local function runService(ctx, state, opts, report)
    state.serviceActive = true
    logger.log(ctx, "info", "Entering SERVICE mode: returning to origin for refuel")

    local ok, err = movement.returnToOrigin(ctx, opts and opts.navigation)
    if not ok then
        state.serviceActive = false
        logger.log(ctx, "error", "SERVICE return failed: " .. tostring(err))
        report.returnError = err
        return false, report
    end
    report.steps[#report.steps + 1] = { type = "return", success = true }

    local refuelOk, refuelReport = refuelInternal(ctx, state, opts)
    report.steps[#report.steps + 1] = {
        type = "refuel",
        success = refuelOk,
        report = refuelReport,
    }

    state.serviceActive = false
    recordHistory(state, {
        type = "service",
        timestamp = os and os.time and os.time() or nil,
        success = refuelOk,
        report = report,
    })

    if not refuelOk then
        logger.log(ctx, "warn", "SERVICE refuel did not reach target level")
        report.finalLevel = select(1, readFuel()) or (refuelReport and refuelReport.finalLevel) or report.startLevel
        return false, report
    end

    local finalLevel = select(1, readFuel()) or refuelReport.finalLevel
    report.finalLevel = finalLevel
    logger.log(ctx, "info", string.format("SERVICE complete (fuel=%s)", tostring(finalLevel or "unknown")))
    return true, report
end

function fuel.service(ctx, opts)
    local state = ensureFuelState(ctx)
    if state.serviceActive then
        return false, { error = "service_already_active" }
    end

    inventory.ensureState(ctx)
    movement.ensureState(ctx)

    local level, limit, unlimited = readFuel()
    local report = {
        startLevel = level,
        limit = limit,
        steps = {},
    }

    if unlimited then
        report.note = "fuel is unlimited"
        return true, report
    end

    if not level then
        logger.log(ctx, "warn", "Fuel level unavailable; skipping service")
        report.error = "fuel_unreadable"
        return false, report
    end

    if level <= 0 then
        local ok, bootstrapReport = bootstrapFuel(ctx, state, opts, report)
        if not ok then
            return false, bootstrapReport
        end
        report = bootstrapReport
    end

    return runService(ctx, state, opts, report)
end

function fuel.resolveFuelThreshold(ctx)
    local threshold = 0
    local function consider(value)
        if type(value) == "number" and value > threshold then
            threshold = value
        end
    end
    if type(ctx.fuelState) == "table" then
        local fuel = ctx.fuelState
        consider(fuel.threshold)
        consider(fuel.reserve)
        consider(fuel.min)
        consider(fuel.minFuel)
        consider(fuel.low)
    end
    if type(ctx.config) == "table" then
        local cfg = ctx.config
        consider(cfg.fuelThreshold)
        consider(cfg.fuelReserve)
        consider(cfg.minFuel)
    end
    return threshold
end

function fuel.isFuelLow(ctx)
    if not turtle or not turtle.getFuelLevel then
        return false
    end
    local level = turtle.getFuelLevel()
    if level == "unlimited" then
        return false
    end
    if type(level) ~= "number" then
        return false
    end
    local threshold = fuel.resolveFuelThreshold(ctx)
    if threshold <= 0 then
        return false
    end
    return level <= threshold

    end

    function fuel.describeFuel(io, report)
    if not io.print then
        return
    end
    if report.unlimited then
        io.print("Fuel: unlimited")
        return
    end
    local levelText = report.level and tostring(report.level) or "unknown"
    local limitText = report.limit and ("/" .. tostring(report.limit)) or ""
    io.print(string.format("Fuel level: %s%s", levelText, limitText))
    if report.threshold then
        io.print(string.format("Threshold: %d", report.threshold))
    end
    if report.reserve then
        io.print(string.format("Reserve target: %d", report.reserve))
    end
    if report.needsService then
        io.print("Status: below threshold (service required)")
    else
        io.print("Status: sufficient for now")
    end
end

function fuel.describeService(io, report)
    if not io.print then
        return
    end
    if not report then
        io.print("No service report available.")
        return
    end
    if report.returnError then
        io.print("Return-to-origin failed: " .. tostring(report.returnError))
    end
    if report.steps then
        for _, step in ipairs(report.steps) do
            if step.type == "return" then
                io.print("Return to origin: " .. (step.success and "OK" or "FAIL"))
            elseif step.type == "refuel" then
                local info = step.report or {}
                local final = info.finalLevel ~= nil and info.finalLevel or (info.endLevel or "unknown")
                io.print(string.format("Refuel step: %s (final=%s)", step.success and "OK" or "FAIL", tostring(final)))
            end
        end
    end
    if report.finalLevel then
        io.print("Service final fuel level: " .. tostring(report.finalLevel))
    end
end

return fuel
]=])

addEmbeddedFile("lib/lib_mining.lua", [=[
--[[
Mining library for CC:Tweaked turtles.
Handles ore detection, extraction, and hole filling.
]]

---@diagnostic disable: undefined-global

local mining = {}
local inventory = require("lib_inventory")
local movement = require("lib_movement")
local logger = require("lib_logger")
local json = require("lib_json")

local CONFIG_FILE = "data/trash_config.json"

-- Blocks that are considered "trash" and should be ignored during ore scanning.
-- Also used to determine what blocks can be used to fill holes.
mining.TRASH_BLOCKS = inventory.DEFAULT_TRASH
mining.TRASH_BLOCKS["minecraft:chest"] = true
mining.TRASH_BLOCKS["minecraft:barrel"] = true
mining.TRASH_BLOCKS["minecraft:trapped_chest"] = true
mining.TRASH_BLOCKS["minecraft:torch"] = true

function mining.loadConfig()
    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")
        if f then
            local data = f.readAll()
            f.close()
            local config = json.decodeJson(data)
            if config and config.trash then
                for k, v in pairs(config.trash) do
                    mining.TRASH_BLOCKS[k] = v
                end
            end
        end
    end
end

function mining.saveConfig()
    local config = { trash = mining.TRASH_BLOCKS }
    local data = json.encode(config)
    -- Ensure data directory exists
    if not fs.exists("data") then
        fs.makeDir("data")
    end
    local f = fs.open(CONFIG_FILE, "w")
    if f then
        f.write(data)
        f.close()
    end
end

-- Load config on startup
mining.loadConfig()

-- Blocks that should NEVER be placed to fill holes (liquids, gravity blocks, etc)
mining.FILL_BLACKLIST = {
    ["minecraft:air"] = true,
    ["minecraft:water_bucket"] = true,
    ["minecraft:lava"] = true,
    ["minecraft:sand"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:torch"] = true,
    ["minecraft:bedrock"] = true,
    ["minecraft:chest"] = true,
    ["minecraft:barrel"] = true,
    ["minecraft:trapped_chest"] = true,
}

--- Check if a block is considered "ore" (valuable)
function mining.isOre(name)
    if not name then return false end
    return not mining.TRASH_BLOCKS[name]
end

--- Find a suitable trash block in inventory to use for filling
local function findFillMaterial(ctx)
    inventory.scan(ctx)
    local state = inventory.ensureState(ctx)
    if not state or not state.slots then return nil end
    for slot, item in pairs(state.slots) do
        if mining.TRASH_BLOCKS[item.name] and not mining.FILL_BLACKLIST[item.name] then
            return slot, item.name
        end
    end
    return nil
end

--- Mine a block in a specific direction if it's valuable, then fill the hole
-- @param dir "front", "up", "down"
function mining.mineAndFill(ctx, dir)
    local inspect, dig, place, suck
    if dir == "front" then
        inspect = turtle.inspect
        dig = turtle.dig
        place = turtle.place
        suck = turtle.suck
    elseif dir == "up" then
        inspect = turtle.inspectUp
        dig = turtle.digUp
        place = turtle.placeUp
        suck = turtle.suckUp
    elseif dir == "down" then
        inspect = turtle.inspectDown
        dig = turtle.digDown
        place = turtle.placeDown
        suck = turtle.suckDown
    else
        return false, "Invalid direction"
    end

    local hasBlock, data = inspect()
    if hasBlock and mining.isOre(data.name) then
        logger.log(ctx, "info", "Mining valuable: " .. data.name)
        if dig() then
            sleep(0.2)
            while suck() do sleep(0.1) end

            -- Attempt to fill the hole
            local slot = findFillMaterial(ctx)
            if slot then
                turtle.select(slot)
                place()
            else
                logger.log(ctx, "warn", "No trash blocks available to fill hole")
            end
            return true
        else
            logger.log(ctx, "warn", "Failed to dig " .. data.name)
        end
    end
    return false
end

--- Scan all 6 directions around the turtle, mine ores, and fill holes.
-- The turtle will return to its original facing.
function mining.scanAndMineNeighbors(ctx)
    -- Check Up
    mining.mineAndFill(ctx, "up")
    
    -- Check Down
    mining.mineAndFill(ctx, "down")

    -- Check 4 horizontal directions
    for i = 1, 4 do
        mining.mineAndFill(ctx, "front")
        movement.turnRight(ctx)
    end
end

return mining
]=])

addEmbeddedFile("lib/lib_json.lua", [=[
local json_utils = {}

function json_utils.encode(data)
    if textutils and textutils.serializeJSON then
        return textutils.serializeJSON(data)
    end
    return nil, "json_encoder_unavailable"
end

function json_utils.decodeJson(text)
    if type(text) ~= "string" then
        return nil, "invalid_json"
    end
    if textutils and textutils.unserializeJSON then
        local ok, result = pcall(textutils.unserializeJSON, text)
        if ok and result ~= nil then
            return result
        end
        return nil, "json_parse_failed"
    end
    local ok, json = pcall(require, "json")
    if ok and type(json) == "table" and type(json.decode) == "function" then
        local okDecode, result = pcall(json.decode, text)
        if okDecode then
            return result
        end
        return nil, "json_parse_failed"
    end
    return nil, "json_decoder_unavailable"
end

function json_utils.decode(text)
    return json_utils.decodeJson(text)
end

return json_utils
]=])

addEmbeddedFile("lib/lib_diagnostics.lua", [=[
local diagnostics = {}

local function safeOrigin(origin)
    if type(origin) ~= "table" then
        return nil
    end
    return {
        x = origin.x,
        y = origin.y,
        z = origin.z,
        facing = origin.facing
    }
end

local function normalizeStrategy(strategy)
    if type(strategy) == "table" then
        return strategy
    end
    return nil
end

local function snapshot(ctx)
    if type(ctx) ~= "table" then
        return { error = "missing context" }
    end
    local config = type(ctx.config) == "table" and ctx.config or {}
    local origin = safeOrigin(ctx.origin)
    local strategyLen = 0
    if type(ctx.strategy) == "table" then
        strategyLen = #ctx.strategy
    end
    local stamp
    if os and type(os.time) == "function" then
        stamp = os.time()
    end

    return {
        state = ctx.state,
        mode = config.mode,
        pointer = ctx.pointer,
        strategySize = strategyLen,
        retries = ctx.retries,
        missingMaterial = ctx.missingMaterial,
        lastError = ctx.lastError,
        origin = origin,
        timestamp = stamp
    }
end

local function requireStrategy(ctx)
    local strategy = normalizeStrategy(ctx.strategy)
    if strategy then
        return strategy
    end

    local message = "Build strategy unavailable"
    if ctx and ctx.logger then
        ctx.logger:error(message, { context = snapshot(ctx) })
    end
    ctx.lastError = ctx.lastError or message
    return nil, message
end

diagnostics.snapshot = snapshot
diagnostics.requireStrategy = requireStrategy

return diagnostics
]=])

addEmbeddedFile("lib/lib_persistence.lua", [=[
local json = require("lib_json")
local logger = require("lib_logger")

local persistence = {}
local STATE_FILE = "state.json"

function persistence.load(ctx, config)
    local path = (config and config.path) or STATE_FILE
    
    if not fs.exists(path) then
        logger.log(ctx, "info", "No previous state found at " .. path)
        return nil
    end

    local f = fs.open(path, "r")
    if not f then
        logger.log(ctx, "error", "Failed to open state file for reading: " .. path)
        return nil
    end

    local content = f.readAll()
    f.close()

    if not content or content == "" then
        logger.log(ctx, "warn", "State file was empty")
        return nil
    end

    local state = json.decode(content)
    if not state then
        logger.log(ctx, "error", "Failed to decode state JSON")
        return nil
    end

    logger.log(ctx, "info", "State loaded from " .. path)
    return state
end

function persistence.save(ctx, config)
    local path = (config and config.path) or STATE_FILE
    
    local snapshot = {
        state = ctx.state,
        config = ctx.config,
        origin = ctx.origin,
        movement = ctx.movement,
        chests = ctx.chests,
        potatofarm = ctx.potatofarm,
        treefarm = ctx.treefarm,
        mine = ctx.mine,
    }

    local content = json.encode(snapshot)
    if not content then
        logger.log(ctx, "error", "Failed to encode state to JSON")
        return false
    end

    local f = fs.open(path, "w")
    if not f then
        logger.log(ctx, "error", "Failed to open state file for writing: " .. path)
        return false
    end

    f.write(content)
    f.close()

    return true
end

function persistence.clear(ctx, config)
    local path = (config and config.path) or STATE_FILE
    if fs.exists(path) then
        fs.delete(path)
        logger.log(ctx, "info", "Cleared state file: " .. path)
    end
end

return persistence
]=])

addEmbeddedFile("factory/factory.lua", [=[
local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")
local debug = debug

if type(package) ~= "table" then package = { path = "" } end
if type(package.path) ~= "string" then package.path = package.path or "" end
package.loaded = package.loaded or {}

local function requireForce(name)
    package.loaded[name] = nil
    return require(name)
end

local states = {
    INITIALIZE = requireForce("state_initialize"),
    CHECK_REQUIREMENTS = requireForce("state_check_requirements"),
    BUILD = requireForce("state_build"),
    MINE = requireForce("state_mine"),
    TREEFARM = requireForce("state_treefarm"),
    POTATOFARM = requireForce("state_potatofarm"),
    RESTOCK = requireForce("state_restock"),
    REFUEL = requireForce("state_refuel"),
    BLOCKED = requireForce("state_blocked"),
    ERROR = requireForce("state_error"),
    DONE = requireForce("state_done"),
}

local function mergeTables(base, extra)
    if type(base) ~= "table" then
        base = {}
    end
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            base[key] = value
        end
    end
    return base
end

local function buildPayload(ctx, extra)
    local payload = { context = diagnostics.snapshot(ctx) }
    if extra then
        mergeTables(payload, extra)
    end
    return payload
end

local function run(args)
    local ctx = {
        state = "INITIALIZE",
        config = {
            verbose = false,
            schemaPath = nil,
        },
        origin = { x = 0, y = 0, z = 0, facing = "north" },
        pointer = 1,
        schema = nil,
        strategy = nil,
        inventoryState = {},
        fuelState = {},
        retries = 0,
    }

    local index = 1
    while index <= #args do
        local value = args[index]
        if value == "--verbose" then
            ctx.config.verbose = true
        elseif value == "mine" then
            ctx.config.mode = "mine"
        elseif value == "tunnel" then
            ctx.config.mode = "tunnel"
        elseif value == "excavate" then
            ctx.config.mode = "excavate"
        elseif value == "treefarm" then
            ctx.config.mode = "treefarm"
        elseif value == "potatofarm" then
            ctx.config.mode = "potatofarm"
        elseif value == "farm" then
            ctx.config.mode = "farm"
        elseif value == "--farm-type" then
            index = index + 1
            ctx.config.farmType = args[index]
        elseif value == "--width" then
            index = index + 1
            ctx.config.width = tonumber(args[index])
        elseif value == "--height" then
            index = index + 1
            ctx.config.height = tonumber(args[index])
        elseif value == "--depth" then
            index = index + 1
            ctx.config.depth = tonumber(args[index])
        elseif value == "--length" then
            index = index + 1
            ctx.config.length = tonumber(args[index])
        elseif value == "--branch-interval" then
            index = index + 1
            ctx.config.branchInterval = tonumber(args[index])
        elseif value == "--branch-length" then
            index = index + 1
            ctx.config.branchLength = tonumber(args[index])
        elseif value == "--torch-interval" then
            index = index + 1
            ctx.config.torchInterval = tonumber(args[index])
        elseif not value:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
            ctx.config.schemaPath = value
        end
        index = index + 1
    end

    if not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
        ctx.config.schemaPath = "schema.json"
    end

    local logOpts = {
        level = ctx.config.verbose and "debug" or "info",
        timestamps = true
    }
    logger.attach(ctx, logOpts)
    
    ctx.logger:info("Agent starting...")

    local persistence = require("lib_persistence")
    local savedState = persistence.load(ctx)
    if savedState then
        ctx.logger:info("Resuming from saved state...")
        mergeTables(ctx, savedState)
        
        if ctx.movement then
            local movement = require("lib_movement")
            movement.ensureState(ctx)
        end
    end

    if turtle and turtle.getFuelLevel then
        local level = turtle.getFuelLevel()
        local limit = turtle.getFuelLimit()
        ctx.logger:info(string.format("Fuel: %s / %s", tostring(level), tostring(limit)))
        if level ~= "unlimited" and type(level) == "number" and level < 100 then
             ctx.logger:warn("Fuel is very low on startup!")
             local fuelLib = require("lib_fuel")
             fuelLib.refuel(ctx, { target = 2000 })
        end
    end

    ctx.save = function()
        persistence.save(ctx)
    end

    while ctx.state ~= "EXIT" do
        ctx.save()

        local stateHandler = states[ctx.state]
        if not stateHandler then
            ctx.logger:error("Unknown state: " .. tostring(ctx.state), buildPayload(ctx))
            break
        end

        ctx.logger:debug("Entering state: " .. ctx.state)
        local ok, nextStateOrErr = pcall(stateHandler, ctx)
        if not ok then
            local trace = debug and debug.traceback and debug.traceback() or nil
            ctx.logger:error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr),
                buildPayload(ctx, { error = tostring(nextStateOrErr), traceback = trace }))
            ctx.lastError = nextStateOrErr
            ctx.state = "ERROR"
        else
            if type(nextStateOrErr) ~= "string" or nextStateOrErr == "" then
                ctx.logger:error("State returned invalid transition", buildPayload(ctx, { result = tostring(nextStateOrErr) }))
                ctx.lastError = nextStateOrErr
                ctx.state = "ERROR"
            elseif not states[nextStateOrErr] and nextStateOrErr ~= "EXIT" then
                ctx.logger:error("Transitioned to unknown state: " .. tostring(nextStateOrErr), buildPayload(ctx))
                ctx.state = "ERROR"
            else
                ctx.state = nextStateOrErr
            end
        end

        sleep(0)
    end
    
    persistence.clear(ctx)

    ctx.logger:info("Agent finished.")
end

local module = { run = run }

if not _G.__FACTORY_EMBED__ then
    local argv = { ... }
    run(argv)
end

return module
]=])

addEmbeddedFile("factory/main.lua", [=[
if not string.find(package.path, "/lib/?.lua") then
    package.path = package.path .. ";/?.lua;/lib/?.lua;/arcade/?.lua;/factory/?.lua"
end

local logger = require("lib_logger")
local movement = require("lib_movement")
local ui = require("lib_ui")
local trash_config = require("ui.trash_config")

local function interactiveSetup(ctx)
    local mode = "treefarm"
    local width = 9
    local height = 9
    local length = 60
    local branchInterval = 3
    local branchLength = 16
    local torchInterval = 6
    
    local selected = 1 
    
    while true do
        ui.clear()
        ui.drawFrame(2, 2, 30, 16, "Factory Setup")
        
        ui.label(4, 4, "Mode: ")
        local modeLabel = "Tree"
        if mode == "potatofarm" then modeLabel = "Potato" end
        if mode == "mine" then modeLabel = "Mine" end
        
        if selected == 1 then
            if term.isColor() then term.setTextColor(colors.yellow) end
            term.write("< " .. modeLabel .. " >")
        else
            if term.isColor() then term.setTextColor(colors.white) end
            term.write("  " .. modeLabel .. "  ")
        end

        local startIdx = 4
        
        if mode == "treefarm" or mode == "potatofarm" then
            startIdx = 4
            ui.label(4, 6, "Width: ")
            if selected == 2 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. width .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. width .. "  ")
            end
            
            ui.label(4, 8, "Height:")
            if selected == 3 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. height .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. height .. "  ")
            end
        elseif mode == "mine" then
            startIdx = 7
            ui.label(4, 6, "Length: ")
            if selected == 2 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. length .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. length .. "  ")
            end

            ui.label(4, 7, "Br. Int:")
            if selected == 3 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. branchInterval .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. branchInterval .. "  ")
            end

            ui.label(4, 8, "Br. Len:")
            if selected == 4 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. branchLength .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. branchLength .. "  ")
            end

            ui.label(4, 9, "Torch Int:")
            if selected == 5 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write("< " .. torchInterval .. " >")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("  " .. torchInterval .. "  ")
            end

            ui.label(4, 10, "Trash:")
            if selected == 6 then
                if term.isColor() then term.setTextColor(colors.yellow) end
                term.write(" < EDIT > ")
            else
                if term.isColor() then term.setTextColor(colors.white) end
                term.write("   EDIT   ")
            end
        end
        
        ui.button(8, 12, "START", selected == startIdx)
        
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = selected - 1
            if selected < 1 then selected = startIdx end
        elseif key == keys.down then
            selected = selected + 1
            if selected > startIdx then selected = 1 end
        elseif key == keys.left then
            if selected == 1 then 
                if mode == "treefarm" then mode = "potatofarm"
                elseif mode == "potatofarm" then mode = "mine"
                else mode = "treefarm" end
                selected = 1
            end
            if mode == "treefarm" or mode == "potatofarm" then
                if selected == 2 then width = math.max(1, width - 1) end
                if selected == 3 then height = math.max(1, height - 1) end
            elseif mode == "mine" then
                if selected == 2 then length = math.max(10, length - 10) end
                if selected == 3 then branchInterval = math.max(1, branchInterval - 1) end
                if selected == 4 then branchLength = math.max(1, branchLength - 1) end
                if selected == 5 then torchInterval = math.max(1, torchInterval - 1) end
            end
        elseif key == keys.right then
            if selected == 1 then 
                if mode == "treefarm" then mode = "mine"
                elseif mode == "mine" then mode = "potatofarm"
                else mode = "treefarm" end
                selected = 1
            end
            if mode == "treefarm" or mode == "potatofarm" then
                if selected == 2 then width = width + 1 end
                if selected == 3 then height = height + 1 end
            elseif mode == "mine" then
                if selected == 2 then length = length + 10 end
                if selected == 3 then branchInterval = branchInterval + 1 end
                if selected == 4 then branchLength = branchLength + 1 end
                if selected == 5 then torchInterval = torchInterval + 1 end
            end
        elseif key == keys.enter then
            if selected == startIdx then
                return { 
                    mode = mode, 
                    width = width, 
                    height = height, 
                    length = length, 
                    branchInterval = branchInterval, 
                    branchLength = branchLength, 
                    torchInterval = torchInterval 
                }
            elseif mode == "mine" and selected == 6 then
                trash_config.run()
            end
        end
    end
end

local states = {
    INITIALIZE = require("state_initialize"),
    BUILD = require("state_build"),
    MINE = require("state_mine"),
    RESTOCK = require("state_restock"),
    REFUEL = require("state_refuel"),
    BLOCKED = require("state_blocked"),
    ERROR = require("state_error"),
    DONE = require("state_done"),
    CHECK_REQUIREMENTS = require("state_check_requirements"),
    TREEFARM = require("state_treefarm"),
    POTATOFARM = require("state_potatofarm"),
    BRANCHMINE = require("state_branchmine")
}

local function main(args)
    local ctx = {
        state = "INITIALIZE",
        config = {
            verbose = false,
            schemaPath = nil
        },
        origin = { x=0, y=0, z=0, facing="north" },
        pointer = 1,
        schema = nil,
        strategy = nil,
        inventoryState = {},
        fuelState = {},
        retries = 0
    }

    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "--verbose" then
            ctx.config.verbose = true
        elseif arg == "mine" then
            ctx.config.mode = "mine"
        elseif arg == "treefarm" then
            ctx.config.mode = "treefarm"
        elseif arg == "potatofarm" then
            ctx.config.mode = "potatofarm"
        elseif arg == "--length" then
            i = i + 1
            ctx.config.length = tonumber(args[i])
        elseif arg == "--width" then
            i = i + 1
            ctx.config.width = tonumber(args[i])
        elseif arg == "--height" then
            i = i + 1
            ctx.config.height = tonumber(args[i])
        elseif arg == "--branch-interval" then
            i = i + 1
            ctx.config.branchInterval = tonumber(args[i])
        elseif arg == "--branch-length" then
            i = i + 1
            ctx.config.branchLength = tonumber(args[i])
        elseif arg == "--torch-interval" then
            i = i + 1
            ctx.config.torchInterval = tonumber(args[i])
        elseif not arg:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
             ctx.config.schemaPath = arg
        end
        i = i + 1
    end
    
    if #args == 0 then
        local setupConfig = interactiveSetup(ctx)
        for k, v in pairs(setupConfig) do
            ctx.config[k] = v
        end
    end
    
    if not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
        ctx.config.schemaPath = "schema.json"
    end

    ctx.logger = logger.new({
        level = ctx.config.verbose and "debug" or "info"
    })
    ctx.logger:info("Agent starting...")

    local function stepOut(ctx)
        local ok, err
        ok, err = movement.forward(ctx)
        if not ok then return false, err end
        ok, err = movement.forward(ctx)
        if not ok then return false, err end
        ok, err = movement.turnRight(ctx)
        if not ok then return false, err end
        ok, err = movement.forward(ctx)
        if not ok then return false, err end
        ok, err = movement.forward(ctx)
        if not ok then return false, err end
        ok, err = movement.turnLeft(ctx)
        if not ok then return false, err end
        return true
    end

    local ok, err = stepOut(ctx)
    if not ok then
        ctx.logger:warn("Initial step-out failed: " .. tostring(err))
    else
        ctx.logger:info("Stepped out to working position (2 forward, 2 right)")
    end

    while ctx.state ~= "EXIT" do
        local currentStateFunc = states[ctx.state]
        if not currentStateFunc then
            ctx.logger:error("Unknown state: " .. tostring(ctx.state))
            break
        end

        ctx.logger:debug("Entering state: " .. ctx.state)
        
        local ok, nextStateOrErr = pcall(currentStateFunc, ctx)
        
        if not ok then
            ctx.logger:error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr))
            ctx.lastError = nextStateOrErr
            ctx.state = "ERROR"
        else
            ctx.state = nextStateOrErr
        end
        
        sleep(0)
    end

    ctx.logger:info("Agent finished.")
    
    if ctx.lastError then
        print("Agent finished: " .. tostring(ctx.lastError))
    else
        print("Agent finished: success!")
    end
end

local args = { ... }
main(args)
]=])

addEmbeddedFile("factory/turtle_os.lua", [=[
--[[
TurtleOS v2.0
Graphical launcher for the factory agent.
--]]

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

_G.__FACTORY_EMBED__ = true
local factory = require("factory")
_G.__FACTORY_EMBED__ = nil

local function pauseAndReturn(retVal)
    print("\nOperation finished.")
    print("Press Enter to continue...")
    read()
    return retVal
end

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

local function main()
    while true do
        ui.clear()
        print("TurtleOS v2.0")
        print("-------------")
        
        local options = {
            { text = "Tree Farm", action = runTreeFarm },
            { text = "Potato Farm", action = runPotatoFarm },
            { text = "Excavate", action = runExcavate },
            { text = "Tunnel", action = runTunnel },
            { text = "Mine", action = runMining },
            { text = "Farm Designer", action = function()
                local sub = ui.Menu("Farm Designer")
                sub:addOption("Tree Farm Design", function()
                    ui.clear()
                    shell.run("factory_planner.lua", "--farm", "tree")
                end)
                sub:addOption("Potato Farm Design", function()
                    ui.clear()
                    shell.run("factory_planner.lua", "--farm", "potato")
                end)
                sub:addOption("Back", function() return "back" end)
                sub:run()
            end },
            { text = "Exit", action = function() return "exit" end }
        }
        
        local menu = ui.Menu("Main Menu")
        for _, opt in ipairs(options) do
            menu:addOption(opt.text, opt.action)
        end
        
        local result = menu:run()
        if result == "exit" then break end
    end
end

main()
]=])

addEmbeddedFile("arcadesys_os.lua", [=[
--[[
Arcadesys launcher
]]

local VERSION = "2.0.2"

if type(package) ~= "table" then package = { path = "" } end
if type(package.path) ~= "string" then package.path = package.path or "" end
package.loaded = package.loaded or {}

local upstreamRequire = _G.require

local function requireCompat(name)
    if package.loaded[name] ~= nil then return package.loaded[name] end
    if upstreamRequire and upstreamRequire ~= requireCompat then
        local result = upstreamRequire(name)
        package.loaded[name] = result
        return result
    end

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

_G.require = _G.require or requireCompat

local function ensurePackagePaths(baseDir)
    local root = baseDir == "" and "/" or baseDir
    local paths = {
        "/?.lua",
        "/lib/?.lua",
        fs.combine(root, "?.lua"),
        fs.combine(root, "lib/?.lua"),
        fs.combine(root, "arcade/?.lua"),
        fs.combine(root, "arcade/ui/?.lua"),
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

local function runProgram(path, ui, ...)
    local args = { ... }
    local function go()
        local fn, loadErr = loadfile(path)
        if not fn then
            error("Unable to load " .. path .. ": " .. tostring(loadErr))
        end
        _G.arg = args
        return fn(table.unpack(args))
    end

    local ok, err = pcall(go)
    if not ok then
        local msg = "Failed to run " .. path .. ": " .. tostring(err)
        print(msg)
        if _G.read then
            print("(Press Enter to continue)")
            pcall(read)
        elseif _G.sleep then
            sleep(2)
        end
    end
end

local baseDir = detectBaseDir()
ensurePackagePaths(baseDir == "" and "/" or baseDir)

print(string.format("Arcadesys %s - launching Turtle UI", VERSION))

local function launchTurtleUi()
    if fs.exists("factory/turtle_os.lua") then
        runProgram("factory/turtle_os.lua")
    elseif fs.exists("/factory/turtle_os.lua") then
        runProgram("/factory/turtle_os.lua")
    else
        print("Turtle UI missing.")
        if _G.read then
            print("(Press Enter to continue)")
            pcall(read)
        elseif _G.sleep then
            sleep(2)
        end
    end
end

launchTurtleUi()
]=])

addEmbeddedFile("factory/schema_farm_tree.txt", [[legend:
. = minecraft:air
D = minecraft:dirt
S = minecraft:oak_sapling
# = minecraft:stone_bricks

meta:
mode = treefarm

layer:0
#####
#DDD#
#DDD#
#DDD#
#####

layer:1
.....
.S.S.
.....
.S.S.
.....
]])

addEmbeddedFile("factory/schema_farm_potato.txt", [[legend:
. = minecraft:air
D = minecraft:dirt
W = minecraft:water_bucket
P = minecraft:potatoes
# = minecraft:stone_bricks

meta:
mode = potatofarm

layer:0
#####
#DDD#
#DWD#
#DDD#
#####

layer:1
.....
.PPP.
.P.P.
.PPP.
.....
]])

addEmbeddedFile("factory/schema_printer_sample.txt", [[legend:
# = minecraft:stone_bricks
G = minecraft:glass
L = minecraft:lantern
T = minecraft:torch
. = minecraft:air

layer:0
.....
.###.
.###.
.###.
.....

layer:1
.....
.#G#.
.#L#.
.#G#.
.....

layer:2
.....
..#..
..#..
..#..
.....

layer:3
.....
.....
..T..
.....
.....
]])







addEmbeddedFile("arcade/data/valhelsia_blocks.lua", [=[
return {
    { id = "minecraft:stone", label = "Stone" },
    { id = "minecraft:dirt", label = "Dirt" },
    { id = "minecraft:cobblestone", label = "Cobblestone" },
    { id = "minecraft:planks", label = "Planks" },
    { id = "minecraft:sand", label = "Sand" },
    { id = "minecraft:gravel", label = "Gravel" },
    { id = "minecraft:log", label = "Log" },
    { id = "minecraft:glass", label = "Glass" },
    { id = "minecraft:chest", label = "Chest" },
    { id = "minecraft:furnace", label = "Furnace" },
    { id = "minecraft:crafting_table", label = "Crafting Table" },
    { id = "minecraft:iron_block", label = "Iron Block" },
    { id = "minecraft:gold_block", label = "Gold Block" },
    { id = "minecraft:diamond_block", label = "Diamond Block" },
    { id = "minecraft:torch", label = "Torch" },
    { id = "minecraft:hopper", label = "Hopper" },
    { id = "minecraft:dropper", label = "Dropper" },
    { id = "minecraft:dispenser", label = "Dispenser" },
    { id = "minecraft:observer", label = "Observer" },
    { id = "minecraft:piston", label = "Piston" },
    { id = "minecraft:sticky_piston", label = "Sticky Piston" },
    { id = "minecraft:lever", label = "Lever" },
    { id = "minecraft:redstone_block", label = "Redstone Block" },
    
    { id = "storagedrawers:controller", label = "Drawer Controller" },
    { id = "storagedrawers:oak_full_drawers_1", label = "Oak Drawer" },
    { id = "storagedrawers:compacting_drawers_3", label = "Compacting Drawer" },
    
    { id = "create:andesite_casing", label = "Andesite Casing" },
    { id = "create:brass_casing", label = "Brass Casing" },
    { id = "create:copper_casing", label = "Copper Casing" },
    { id = "create:shaft", label = "Shaft" },
    { id = "create:cogwheel", label = "Cogwheel" },
    { id = "create:large_cogwheel", label = "Large Cogwheel" },
    { id = "create:gearbox", label = "Gearbox" },
    { id = "create:clutch", label = "Clutch" },
    { id = "create:gearshift", label = "Gearshift" },
    { id = "create:encased_chain_drive", label = "Chain Drive" },
    { id = "create:belt", label = "Mechanical Belt" },
    { id = "create:chute", label = "Chute" },
    { id = "create:smart_chute", label = "Smart Chute" },
    { id = "create:fluid_pipe", label = "Fluid Pipe" },
    { id = "create:mechanical_pump", label = "Mech Pump" },
    { id = "create:fluid_tank", label = "Fluid Tank" },
    { id = "create:mechanical_press", label = "Mech Press" },
    { id = "create:mechanical_mixer", label = "Mech Mixer" },
    { id = "create:basin", label = "Basin" },
    { id = "create:blaze_burner", label = "Blaze Burner" },
    { id = "create:millstone", label = "Millstone" },
    { id = "create:crushing_wheel", label = "Crushing Wheel" },
    { id = "create:mechanical_drill", label = "Mech Drill" },
    { id = "create:mechanical_saw", label = "Mech Saw" },
    { id = "create:deployer", label = "Deployer" },
    { id = "create:portable_storage_interface", label = "Portable Storage" },
    { id = "create:redstone_link", label = "Redstone Link" },
    
    { id = "mekanism:steel_casing", label = "Steel Casing" },
    { id = "mekanism:metallurgic_infuser", label = "Met. Infuser" },
    { id = "mekanism:enrichment_chamber", label = "Enrich. Chamber" },
    { id = "mekanism:crusher", label = "Crusher" },
    { id = "mekanism:osmium_compressor", label = "Osmium Comp." },
    { id = "mekanism:combiner", label = "Combiner" },
    { id = "mekanism:purification_chamber", label = "Purif. Chamber" },
    { id = "mekanism:pressurized_reaction_chamber", label = "PRC" },
    { id = "mekanism:chemical_injection_chamber", label = "Chem. Inj." },
    { id = "mekanism:chemical_crystallizer", label = "Crystallizer" },
    { id = "mekanism:chemical_dissolution_chamber", label = "Dissolution" },
    { id = "mekanism:chemical_washer", label = "Washer" },
    { id = "mekanism:digital_miner", label = "Digital Miner" },
    { id = "mekanism:basic_universal_cable", label = "Univ. Cable" },
    { id = "mekanism:basic_mechanical_pipe", label = "Mech. Pipe" },
    { id = "mekanism:basic_pressurized_tube", label = "Press. Tube" },
    { id = "mekanism:basic_logistical_transporter", label = "Log. Transp." },
    
    { id = "immersiveengineering:coke_oven", label = "Coke Oven" },
    { id = "immersiveengineering:blast_furnace", label = "Blast Furnace" },
    { id = "immersiveengineering:windmill", label = "Windmill" },
    { id = "immersiveengineering:watermill", label = "Watermill" },
    { id = "immersiveengineering:dynamo", label = "Dynamo" },
    { id = "immersiveengineering:hv_capacitor", label = "HV Capacitor" },
    { id = "immersiveengineering:mv_capacitor", label = "MV Capacitor" },
    { id = "immersiveengineering:lv_capacitor", label = "LV Capacitor" },
    { id = "immersiveengineering:conveyor_basic", label = "Conveyor" },
    
    { id = "ae2:controller", label = "ME Controller" },
    { id = "ae2:drive", label = "ME Drive" },
    { id = "ae2:terminal", label = "ME Terminal" },
    { id = "ae2:crafting_terminal", label = "Crafting Term" },
    { id = "ae2:pattern_terminal", label = "Pattern Term" },
    { id = "ae2:interface", label = "ME Interface" },
    { id = "ae2:molecular_assembler", label = "Mol. Assembler" },
    { id = "ae2:cable_glass", label = "Glass Cable" },
    { id = "ae2:cable_smart", label = "Smart Cable" },
    
    { id = "computercraft:computer_normal", label = "Computer" },
    { id = "computercraft:computer_advanced", label = "Adv Computer" },
    { id = "computercraft:turtle_normal", label = "Turtle" },
    { id = "computercraft:turtle_advanced", label = "Adv Turtle" },
    { id = "computercraft:monitor_normal", label = "Monitor" },
    { id = "computercraft:monitor_advanced", label = "Adv Monitor" },
    { id = "computercraft:disk_drive", label = "Disk Drive" },
    { id = "computercraft:printer", label = "Printer" },
    { id = "computercraft:speaker", label = "Speaker" },
    { id = "computercraft:wired_modem", label = "Wired Modem" },
    { id = "computercraft:wireless_modem_normal", label = "Wireless Modem" },
}
]=])

addEmbeddedFile("factory_planner.lua", [=[---@diagnostic disable: undefined-global, undefined-field

-- Factory Designer Launcher
-- Thin wrapper around lib_designer so players always get the full feature set.

local function ensurePackagePath()
    if not package or type(package.path) ~= "string" then
        package = package or {}
        package.path = package.path or ""
    end

    if not string.find(package.path, "/lib/?.lua", 1, true) then
        package.path = package.path .. ";/?.lua;/lib/?.lua;/factory/?.lua;/arcade/?.lua"
    end
end

ensurePackagePath()

local designer = require("lib_designer")
local parser = require("lib_parser")

local args = { ... }

local function printUsage()
    print([[Factory Designer
Usage: factory_planner.lua [--load <schema-file>] [--farm <tree|potato>] [--help]

Controls are available inside the designer (press M for menu).]])
end

local function resolveSchemaPath(rawPath)
    if fs.exists(rawPath) then
        return rawPath
    end
    if fs.exists(rawPath .. ".json") then
        return rawPath .. ".json"
    end
    if fs.exists(rawPath .. ".txt") then
        return rawPath .. ".txt"
    end
    return rawPath
end

local function loadInitialSchema(path)
    local resolved = resolveSchemaPath(path)
    if not fs.exists(resolved) then
        print("Warning: schema file not found: " .. resolved)
        return nil
    end

    local ok, schema, metadata = parser.parseFile(nil, resolved)
    if not ok then
        print("Failed to load schema: " .. tostring(schema))
        return nil
    end

    print("Loaded schema: " .. resolved)
    return {
        schema = schema,
        metadata = metadata,
    }
end

local function main()
    local config, handled = parseArgs()
    if handled then return end

    local runOpts = {}
    if config and config.loadPath then
        local initial = loadInitialSchema(config.loadPath)
        if initial then
            runOpts.schema = initial.schema
            runOpts.metadata = initial.metadata
        end
    end

    if config and config.farmType then
        if config.farmType == "tree" then
            runOpts.meta = { mode = "treefarm" }
            runOpts.palette = {
                { id = "minecraft:stone_bricks", color = colors.gray, sym = "#" },
                { id = "minecraft:dirt", color = colors.brown, sym = "D" },
                { id = "minecraft:oak_sapling", color = colors.green, sym = "S" },
                { id = "minecraft:torch", color = colors.yellow, sym = "i" },
                { id = "minecraft:chest", color = colors.orange, sym = "C" },
            }
        elseif config.farmType == "potato" then
            runOpts.meta = { mode = "potatofarm" }
            runOpts.palette = {
                { id = "minecraft:stone_bricks", color = colors.gray, sym = "#" },
                { id = "minecraft:dirt", color = colors.brown, sym = "D" },
                { id = "minecraft:water_bucket", color = colors.blue, sym = "W" },
                { id = "minecraft:potato", color = colors.yellow, sym = "P" },
                { id = "minecraft:chest", color = colors.orange, sym = "C" },
            }
        else
            print("Unknown farm type: " .. config.farmType)
            return
        end
    end

    local ok, err = pcall(designer.run, runOpts)
    if not ok then
        print("Designer crashed: " .. tostring(err))
    end
end

main()
]=])

addEmbeddedFile("lib/version.lua", [=[--[[
Version and build counter for Arcadesys TurtleOS.
Build counter increments on each bundle/rebuild.
]]

local version = {}

version.MAJOR = 2
version.MINOR = 1
version.PATCH = 1
version.BUILD = 47

--- Format version string (e.g., "v2.1.1 (build 42)")
function version.toString()
    return string.format("v%d.%d.%d (build %d)", 
        version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end

--- Format short display (e.g., "TurtleOS v2.1.1 #42")
function version.display()
    return string.format("TurtleOS v%d.%d.%d #%d", 
        version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end

return version
]=])

addEmbeddedFile("lib/lib_json.lua", [=[--[[
JSON library for CC:Tweaked turtles.
Provides helpers for encoding and decoding JSON.
--]]

---@diagnostic disable: undefined-global

local json_utils = {}

function json_utils.encode(data)
    if textutils and textutils.serializeJSON then
        return textutils.serializeJSON(data)
    end
    return nil, "json_encoder_unavailable"
end

function json_utils.decodeJson(text)
    if type(text) ~= "string" then
        return nil, "invalid_json"
    end
    if textutils and textutils.unserializeJSON then
        local ok, result = pcall(textutils.unserializeJSON, text)
        if ok and result ~= nil then
            return result
        end
        return nil, "json_parse_failed"
    end
    local ok, json = pcall(require, "json")
    if ok and type(json) == "table" and type(json.decode) == "function" then
        local okDecode, result = pcall(json.decode, text)
        if okDecode then
            return result
        end
        return nil, "json_parse_failed"
    end
    return nil, "json_decoder_unavailable"
end

return json_utils
]=])

addEmbeddedFile("lib/lib_ui.lua", [=[--[[
UI Library for TurtleOS (Mouse/GUI Edition)
Provides DOS-style windowing and widgets.
--]]

local ui = {}

local colors_bg = colors.blue
local colors_fg = colors.white
local colors_btn = colors.lightGray
local colors_btn_text = colors.black
local colors_input = colors.black
local colors_input_text = colors.white

function ui.clear()
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.clear()
end

function ui.drawBox(x, y, w, h, bg, fg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end
end

function ui.drawFrame(x, y, w, h, title)
    ui.drawBox(x, y, w, h, colors.gray, colors.white)
    ui.drawBox(x + 1, y + 1, w - 2, h - 2, colors_bg, colors_fg)
    
    -- Shadow
    term.setBackgroundColor(colors.black)
    for i = 1, h do
        term.setCursorPos(x + w, y + i)
        term.write(" ")
    end
    for i = 1, w do
        term.setCursorPos(x + i, y + h)
        term.write(" ")
    end

    if title then
        term.setCursorPos(x + 2, y + 1)
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        term.write(" " .. title .. " ")
    end
end

function ui.button(x, y, text, active)
    term.setCursorPos(x, y)
    if active then
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
    else
        term.setBackgroundColor(colors_btn)
        term.setTextColor(colors_btn_text)
    end
    term.write(" " .. text .. " ")
end

function ui.label(x, y, text)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.write(text)
end

function ui.inputText(x, y, width, value, active)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_input)
    term.setTextColor(colors_input_text)
    local display = value or ""
    if #display > width then
        display = display:sub(-width)
    end
    term.write(display .. string.rep(" ", width - #display))
    if active then
        term.setCursorPos(x + #display, y)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
end

function ui.drawPreview(schema, x, y, w, h)
    -- Find bounds
    local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            if nx < minX then minX = nx end
            if nx > maxX then maxX = nx end
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        if nz < minZ then minZ = nz end
                        if nz > maxZ then maxZ = nz end
                    end
                end
            end
        end
    end

    if minX > maxX then return end -- Empty schema

    local scaleX = w / (maxX - minX + 1)
    local scaleZ = h / (maxZ - minZ + 1)
    local scale = math.min(scaleX, scaleZ, 1) -- Keep aspect ratio, max 1:1

    -- Draw background
    term.setBackgroundColor(colors.black)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end

    -- Draw blocks
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        -- Map to screen
                        local scrX = math.floor((nx - minX) * scale) + x
                        local scrY = math.floor((nz - minZ) * scale) + y
                        
                        if scrX >= x and scrX < x + w and scrY >= y and scrY < y + h then
                            term.setCursorPos(scrX, scrY)
                            
                            -- Color mapping
                            local mat = block.material
                            local color = colors.gray
                            local char = " "
                            
                            if mat:find("water") then color = colors.blue
                            elseif mat:find("log") then color = colors.brown
                            elseif mat:find("leaves") then color = colors.green
                            elseif mat:find("sapling") then color = colors.green; char = "T"
                            elseif mat:find("sand") then color = colors.yellow
                            elseif mat:find("dirt") then color = colors.brown
                            elseif mat:find("grass") then color = colors.green
                            elseif mat:find("stone") then color = colors.lightGray
                            elseif mat:find("cane") then color = colors.lime; char = "!"
                            elseif mat:find("potato") then color = colors.orange; char = "."
                            elseif mat:find("torch") then color = colors.orange; char = "i"
                            end
                            
                            term.setBackgroundColor(color)
                            if color == colors.black then term.setTextColor(colors.white) else term.setTextColor(colors.black) end
                            term.write(char)
                        end
                    end
                end
            end
        end
    end
end

-- Simple Event Loop for a Form
-- form = { title = "", elements = { {type="button", x=, y=, text=, id=}, ... } }
function ui.runForm(form)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local running = true
    local result = nil
    local activeInput = nil

    -- Identify focusable elements
    local focusableIndices = {}
    for i, el in ipairs(form.elements) do
        if el.type == "input" or el.type == "button" then
            table.insert(focusableIndices, i)
        end
    end
    local currentFocusIndex = 1
    if #focusableIndices > 0 then
        local el = form.elements[focusableIndices[currentFocusIndex]]
        if el.type == "input" then activeInput = el end
    end

    while running do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, form.title)
        
        -- Custom Draw
        if form.onDraw then
            form.onDraw(fx, fy, fw, fh)
        end

        -- Draw elements
        for i, el in ipairs(form.elements) do
            local ex, ey = fx + el.x, fy + el.y
            local isFocused = false
            if #focusableIndices > 0 and focusableIndices[currentFocusIndex] == i then
                isFocused = true
            end

            if el.type == "button" then
                ui.button(ex, ey, el.text, isFocused)
            elseif el.type == "label" then
                ui.label(ex, ey, el.text)
            elseif el.type == "input" then
                ui.inputText(ex, ey, el.width, el.value, activeInput == el or isFocused)
            end
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            local clickedSomething = false
            
            for i, el in ipairs(form.elements) do
                local ex, ey = fx + el.x, fy + el.y
                if el.type == "button" then
                    if my == ey and mx >= ex and mx < ex + #el.text + 2 then
                        ui.button(ex, ey, el.text, true) -- Flash
                        sleep(0.1)
                        if el.callback then
                            local res = el.callback(form)
                            if res then return res end
                        end
                        clickedSomething = true
                        -- Update focus
                        for fi, idx in ipairs(focusableIndices) do
                            if idx == i then currentFocusIndex = fi; break end
                        end
                        activeInput = nil
                    end
                elseif el.type == "input" then
                    if my == ey and mx >= ex and mx < ex + el.width then
                        activeInput = el
                        clickedSomething = true
                        -- Update focus
                        for fi, idx in ipairs(focusableIndices) do
                            if idx == i then currentFocusIndex = fi; break end
                        end
                    end
                end
            end
            
            if not clickedSomething then
                activeInput = nil
            end
            
        elseif event == "char" and activeInput then
            if not activeInput.stepper then
                activeInput.value = (activeInput.value or "") .. p1
            end
        elseif event == "key" then
            local key = p1
            local focusedEl = (#focusableIndices > 0) and form.elements[focusableIndices[currentFocusIndex]] or nil
            local function adjustStepper(el, delta)
                if not el or not el.stepper then return end
                local step = el.step or 1
                local current = tonumber(el.value) or 0
                local nextVal = current + (delta * step)
                if el.min then nextVal = math.max(el.min, nextVal) end
                if el.max then nextVal = math.min(el.max, nextVal) end
                el.value = tostring(nextVal)
            end

            if key == keys.backspace and activeInput then
                local val = activeInput.value or ""
                if #val > 0 then
                    activeInput.value = val:sub(1, -2)
                end
            elseif (key == keys.left or key == keys.right) and focusedEl and focusedEl.stepper then
                local delta = key == keys.left and -1 or 1
                adjustStepper(focusedEl, delta)
                activeInput = nil
            elseif key == keys.tab or key == keys.down then
                if #focusableIndices > 0 then
                    currentFocusIndex = currentFocusIndex + 1
                    if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
                    local el = form.elements[focusableIndices[currentFocusIndex]]
                    activeInput = (el.type == "input") and el or nil
                end
            elseif key == keys.up then
                if #focusableIndices > 0 then
                    currentFocusIndex = currentFocusIndex - 1
                    if currentFocusIndex < 1 then currentFocusIndex = #focusableIndices end
                    local el = form.elements[focusableIndices[currentFocusIndex]]
                    activeInput = (el.type == "input") and el or nil
                end
            elseif key == keys.enter then
                if activeInput then
                    activeInput = nil
                    -- Move to next
                    if #focusableIndices > 0 then
                        currentFocusIndex = currentFocusIndex + 1
                        if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
                        local el = form.elements[focusableIndices[currentFocusIndex]]
                        activeInput = (el.type == "input") and el or nil
                    end
                else
                    -- Activate button
                    if #focusableIndices > 0 then
                        local el = form.elements[focusableIndices[currentFocusIndex]]
                        if el.type == "button" then
                            ui.button(fx + el.x, fy + el.y, el.text, true) -- Flash
                            sleep(0.1)
                            if el.callback then
                                local res = el.callback(form)
                                if res then return res end
                            end
                        elseif el.type == "input" then
                            activeInput = el
                        end
                    end
                end
            end
        end
    end
end

-- Simple Scrollable Menu
-- items = { { text="Label", callback=function() end }, ... }
function ui.runMenu(title, items)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local scroll = 0
    local maxVisible = fh - 4 -- Title + padding (top/bottom)
    local selectedIndex = 1

    while true do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, title)
        
        -- Draw items
        for i = 1, maxVisible do
            local idx = i + scroll
            if idx <= #items then
                local item = items[idx]
                local isSelected = (idx == selectedIndex)
                ui.button(fx + 2, fy + 1 + i, item.text, isSelected)
            end
        end
        
        -- Scroll indicators
        if scroll > 0 then
            ui.label(fx + fw - 2, fy + 2, "^")
        end
        if scroll + maxVisible < #items then
            ui.label(fx + fw - 2, fy + fh - 2, "v")
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            
            -- Check items
            for i = 1, maxVisible do
                local idx = i + scroll
                if idx <= #items then
                    local item = items[idx]
                    local bx, by = fx + 2, fy + 1 + i
                    -- Button width is text length + 2 spaces
                    if my == by and mx >= bx and mx < bx + #item.text + 2 then
                        ui.button(bx, by, item.text, true) -- Flash
                        sleep(0.1)
                        if item.callback then
                            local res = item.callback()
                            if res then return res end
                        end
                        selectedIndex = idx
                    end
                end
            end
            
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir > 0 then
                if scroll + maxVisible < #items then scroll = scroll + 1 end
            else
                if scroll > 0 then scroll = scroll - 1 end
            end
        elseif event == "key" then
            local key = p1
            if key == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                    if selectedIndex <= scroll then
                        scroll = selectedIndex - 1
                    end
                end
            elseif key == keys.down then
                if selectedIndex < #items then
                    selectedIndex = selectedIndex + 1
                    if selectedIndex > scroll + maxVisible then
                        scroll = selectedIndex - maxVisible
                    end
                end
            elseif key == keys.enter then
                local item = items[selectedIndex]
                if item and item.callback then
                    ui.button(fx + 2, fy + 1 + (selectedIndex - scroll), item.text, true) -- Flash
                    sleep(0.1)
                    local res = item.callback()
                    if res then return res end
                end
            end
        end
    end
end

-- Form Class
function ui.Form(title)
    local self = {
        title = title,
        elements = {},
        _row = 0,
    }
    
    function self:addInput(id, label, value)
        local y = 2 + self._row
        table.insert(self.elements, { type = "label", x = 2, y = y, text = label })
        table.insert(self.elements, { type = "input", x = 15, y = y, width = 20, value = value, id = id })
        self._row = self._row + 1
    end

    function self:addStepper(id, label, value, opts)
        opts = opts or {}
        local y = 2 + self._row
        table.insert(self.elements, { type = "label", x = 2, y = y, text = label })
        table.insert(self.elements, {
            type = "input",
            x = 15,
            y = y,
            width = 12,
            value = tostring(value or 0),
            id = id,
            stepper = true,
            step = opts.step or 1,
            min = opts.min,
            max = opts.max,
        })
        self._row = self._row + 1
    end
    
    function self:addButton(id, label, callback)
         local y = 2 + self._row
         table.insert(self.elements, { type = "button", x = 2, y = y, text = label, id = id, callback = callback })
         self._row = self._row + 1
    end

    function self:run()
        -- Add OK/Cancel buttons
        local y = 2 + self._row + 2
        table.insert(self.elements, { 
            type = "button", x = 2, y = y, text = "OK", 
            callback = function(form) return "ok" end 
        })
        table.insert(self.elements, { 
            type = "button", x = 10, y = y, text = "Cancel", 
            callback = function(form) return "cancel" end 
        })
        
        return ui.runForm(self)
    end
    
    return self
end

function ui.toBlit(color)
    if colors.toBlit then return colors.toBlit(color) end
    local exponent = math.log(color) / math.log(2)
    return string.sub("0123456789abcdef", exponent + 1, exponent + 1)
end

return ui
]=])

addEmbeddedFile("lib/lib_parser.lua", [=[--[[
Parser library for CC:Tweaked turtles.
Normalises schema sources (JSON, text grids, voxel tables) into the canonical
schema[x][y][z] format used by the build states. All public entry points
return success booleans with optional error messages and metadata tables.
--]]

---@diagnostic disable: undefined-global

local parser = {}
local logger = require("lib_logger")
local table_utils = require("lib_table")
local fs_utils = require("lib_fs")
local json_utils = require("lib_json")
local schema_utils = require("lib_schema")

local function parseLayerRows(schema, bounds, counts, layerDef, legend, opts)
    local rows = layerDef.rows
    if type(rows) ~= "table" then
        return false, "invalid_layer"
    end
    local height = #rows
    if height == 0 then
        return true
    end
    local width = nil
    for rowIndex, row in ipairs(rows) do
        if type(row) ~= "string" then
            return false, "invalid_row"
        end
        if width == nil then
            width = #row
            if width == 0 then
                return false, "empty_row"
            end
        elseif width ~= #row then
            return false, "ragged_row"
        end
        for col = 1, #row do
            local symbol = row:sub(col, col)
            local entry, err = schema_utils.resolveSymbol(symbol, legend, opts)
            if err then
                return false, string.format("legend_error:%s", symbol)
            end
            if entry then
                local x = (layerDef.x or 0) + (col - 1)
                local y = layerDef.y or 0
                local z = (layerDef.z or 0) + (rowIndex - 1)
                local ok, addErr = schema_utils.addBlock(schema, bounds, counts, x, y, z, entry.material, entry.meta)
                if not ok then
                    return false, addErr
                end
            end
        end
    end
    return true
end

local function toLayerRows(layer)
    if type(layer) == "string" then
        local rows = {}
        for line in layer:gmatch("([^\r\n]+)") do
            rows[#rows + 1] = line
        end
        return { rows = rows }
    end
    if type(layer) == "table" then
        if layer.rows then
            local rows = {}
            for i = 1, #layer.rows do
                rows[i] = tostring(layer.rows[i])
            end
            return {
                rows = rows,
                y = layer.y or layer.height or layer.level or 0,
                x = layer.x or layer.offsetX or 0,
                z = layer.z or layer.offsetZ or 0,
            }
        end
        local rows = {}
        local count = 0
        for _, value in ipairs(layer) do
            rows[#rows + 1] = tostring(value)
            count = count + 1
        end
        if count > 0 then
            return { rows = rows, y = layer.y or 0, x = layer.x or 0, z = layer.z or 0 }
        end
    end
    return nil
end

local function parseLayers(schema, bounds, counts, def, legend, opts)
    local layers = def.layers
    if type(layers) ~= "table" then
        return false, "invalid_layers"
    end
    local used = 0
    for index, layer in ipairs(layers) do
        local layerRows = toLayerRows(layer)
        if not layerRows then
            return false, "invalid_layer"
        end
        if not layerRows.y then
            layerRows.y = (def.baseY or 0) + (index - 1)
        else
            layerRows.y = layerRows.y + (def.baseY or 0)
        end
        if def.baseX then
            layerRows.x = (layerRows.x or 0) + def.baseX
        end
        if def.baseZ then
            layerRows.z = (layerRows.z or 0) + def.baseZ
        end
        local ok, err = parseLayerRows(schema, bounds, counts, layerRows, legend, opts)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_layers"
    end
    return true
end

local function parseBlockList(schema, bounds, counts, blocks)
    local used = 0
    for _, block in ipairs(blocks) do
        if type(block) ~= "table" then
            return false, "invalid_block"
        end
        local x = block.x or block[1]
        local y = block.y or block[2]
        local z = block.z or block[3]
        local material = block.material or block.name or block.block
        local meta = block.meta or block.data
        if type(meta) ~= "table" then
            meta = {}
        end
        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_blocks"
    end
    return true
end

local function parseVoxelGrid(schema, bounds, counts, grid)
    if type(grid) ~= "table" then
        return false, "invalid_grid"
    end
    local used = 0
    for xKey, xColumn in pairs(grid) do
        local x = tonumber(xKey) or xKey
        if type(x) ~= "number" then
            return false, "invalid_coordinate"
        end
        if type(xColumn) ~= "table" then
            return false, "invalid_grid"
        end
        for yKey, yColumn in pairs(xColumn) do
            local y = tonumber(yKey) or yKey
            if type(y) ~= "number" then
                return false, "invalid_coordinate"
            end
            if type(yColumn) ~= "table" then
                return false, "invalid_grid"
            end
            for zKey, entry in pairs(yColumn) do
                local z = tonumber(zKey) or zKey
                if type(z) ~= "number" then
                    return false, "invalid_coordinate"
                end
                if entry ~= nil then
                    local material
                    local meta = {}
                    if type(entry) == "string" then
                        material = entry
                    elseif type(entry) == "table" then
                        material = entry.material or entry.name or entry.block
                        meta = type(entry.meta) == "table" and entry.meta or {}
                    else
                        return false, "invalid_block"
                    end
                    if material and material ~= "" then
                        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
                        if not ok then
                            return false, err
                        end
                        used = used + 1
                    end
                end
            end
        end
    end
    if used == 0 then
        return false, "empty_grid"
    end
    return true
end

local function summarise(bounds, counts, meta)
    local materials = {}
    for material, count in pairs(counts) do
        materials[#materials + 1] = { material = material, count = count }
    end
    table.sort(materials, function(a, b)
        if a.count == b.count then
            return a.material < b.material
        end
        return a.count > b.count
    end)
    local total = 0
    for _, entry in ipairs(materials) do
        total = total + entry.count
    end
    return {
        bounds = {
            min = table_utils.shallowCopy(bounds.min),
            max = table_utils.shallowCopy(bounds.max),
        },
        materials = materials,
        totalBlocks = total,
        meta = meta
    }
end

local function buildCanonical(def, opts)
    local schema = {}
    local bounds = schema_utils.newBounds()
    local counts = {}
    local ok, err
    if def.blocks then
        ok, err = parseBlockList(schema, bounds, counts, def.blocks)
    elseif def.layers then
        ok, err = parseLayers(schema, bounds, counts, def, def.legend, opts)
    elseif def.grid then
        ok, err = parseVoxelGrid(schema, bounds, counts, def.grid)
    else
        return nil, "unknown_definition"
    end
    if not ok then
        return nil, err
    end
    if bounds.min.x == math.huge then
        return nil, "empty_schema"
    end
    return schema, summarise(bounds, counts, def.meta)
end

local function detectFormatFromExtension(path)
    if type(path) ~= "string" then
        return nil
    end
    local ext = path:match("%.([%w_%-]+)$")
    if not ext then
        return nil
    end
    ext = ext:lower()
    if ext == "json" or ext == "schem" then
        return "json"
    end
    if ext == "txt" or ext == "grid" then
        return "grid"
    end
    if ext == "vox" or ext == "voxel" then
        return "voxel"
    end
    return nil
end

local function detectFormatFromText(text)
    if type(text) ~= "string" then
        return nil
    end
    local trimmed = text:match("^%s*(.-)%s*$") or text
    local firstChar = trimmed:sub(1, 1)
    if firstChar == "{" or firstChar == "[" then
        return "json"
    end
    return "grid"
end

local function parseLegendBlock(lines, index)
    local legend = {}
    local pos = index
    while pos <= #lines do
        local line = lines[pos]
        if line == "" then
            break
        end
        if line:match("^layer") then
            break
        end
        local symbol, rest = line:match("^(%S+)%s*[:=]%s*(.+)$")
        if not symbol then
            symbol, rest = line:match("^(%S+)%s+(.+)$")
        end
        if symbol and rest then
            rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
            local value
            if rest:sub(1, 1) == "{" then
                local parsed = json_utils.decodeJson(rest)
                if parsed then
                    value = parsed
                else
                    value = rest
                end
            else
                value = rest
            end
            legend[symbol] = value
        end
        pos = pos + 1
    end
    return legend, pos
end

local function parseTextGridContent(text, opts)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        lines[#lines + 1] = line
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, nil)
    local layers = {}
    local current = {}
    local currentY = nil
    local lineIndex = 1
    while lineIndex <= #lines do
        local line = lines[lineIndex]
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == "" then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
                currentY = nil
            end
            lineIndex = lineIndex + 1
        elseif trimmed:lower() == "legend:" then
            local legendBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1)
            legend = schema_utils.mergeLegend(legend, legendBlock)
            lineIndex = nextIndex
        elseif trimmed:lower() == "meta:" then
            local metaBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1) -- Reuse parseLegendBlock as format is identical
            if not opts then opts = {} end
            opts.meta = schema_utils.mergeLegend(opts.meta, metaBlock)
            lineIndex = nextIndex
        elseif trimmed:match("^layer") then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
            end
            local yValue = trimmed:match("layer%s*[:=]%s*(-?%d+)")
            currentY = yValue and tonumber(yValue) or (#layers)
            lineIndex = lineIndex + 1
        else
            current[#current + 1] = line
            lineIndex = lineIndex + 1
        end
    end
    if #current > 0 then
        layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
    end
    if not legend or next(legend) == nil then
        return nil, "missing_legend"
    end
    if #layers == 0 then
        return nil, "empty_layers"
    end
    return {
        layers = layers,
        legend = legend,
    }
end

local function parseJsonContent(obj, opts)
    if type(obj) ~= "table" then
        return nil, "invalid_json_root"
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, obj.legend or nil)
    if obj.blocks then
        return {
            blocks = obj.blocks,
            legend = legend,
        }
    end
    if obj.layers then
        return {
            layers = obj.layers,
            legend = legend,
            baseX = obj.baseX,
            baseY = obj.baseY,
            baseZ = obj.baseZ,
        }
    end
    if obj.grid or obj.voxels then
        return {
            grid = obj.grid or obj.voxels,
            legend = legend,
        }
    end
    if #obj > 0 then
        return {
            blocks = obj,
            legend = legend,
        }
    end
    return nil, "unrecognised_json"
end

local function assignToContext(ctx, schema, info)
    if type(ctx) ~= "table" then
        return
    end
    ctx.schema = schema
    ctx.schemaInfo = info
end

local function ensureSpecTable(spec)
    if type(spec) == "table" then
        return table_utils.shallowCopy(spec)
    end
    if type(spec) == "string" then
        return { source = spec }
    end
    return {}
end

function parser.parse(ctx, spec)
    spec = ensureSpecTable(spec)
    local format = spec.format
    local text = spec.text
    local data = spec.data
    local path = spec.path or spec.sourcePath
    local source = spec.source
    if not format and spec.path then
        format = detectFormatFromExtension(spec.path)
    end
    if not format and spec.formatHint then
        format = spec.formatHint
    end
    if not text and not data then
        if spec.textContent then
            text = spec.textContent
        elseif spec.raw then
            text = spec.raw
        elseif spec.sourceText then
            text = spec.sourceText
        end
    end
    if not path and type(source) == "string" and text == nil and data == nil then
        local maybeFormat = detectFormatFromExtension(source)
        if maybeFormat then
            path = source
            format = format or maybeFormat
        else
            text = source
        end
    end
    if text == nil and path then
        local contents, err = fs_utils.readFile(path)
        if not contents then
            return false, err or "read_failed"
        end
        text = contents
        if not format then
            format = detectFormatFromExtension(path) or detectFormatFromText(text)
        end
    end
    if not format then
        if data then
            if data.layers then
                format = "grid"
            elseif data.blocks then
                format = "json"
            elseif data.grid or data.voxels then
                format = "voxel"
            end
        elseif text then
            format = detectFormatFromText(text)
        end
    end
    if not format then
        return false, "unknown_format"
    end
    local definition, err
    if format == "json" then
        if data then
            definition, err = parseJsonContent(data, spec)
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            definition, err = parseJsonContent(obj, spec)
        end
    elseif format == "grid" then
        if data and (data.layers or data.rows) then
            definition = {
                layers = data.layers or { data.rows },
                legend = schema_utils.mergeLegend(spec.legend or nil, data.legend or nil),
                meta = spec.meta or data.meta
            }
        else
            definition, err = parseTextGridContent(text, spec)
            if definition and spec.meta then
                 definition.meta = schema_utils.mergeLegend(definition.meta, spec.meta)
            end
        end
    elseif format == "voxel" then
        if data then
            definition = {
                grid = data.grid or data.voxels or data,
            }
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            if obj.grid or obj.voxels then
                definition = {
                    grid = obj.grid or obj.voxels,
                }
            else
                definition, err = parseJsonContent(obj, spec)
            end
        end
    else
        return false, "unsupported_format"
    end
    if not definition then
        return false, err or "invalid_definition"
    end
    if spec.legend then
        definition.legend = schema_utils.mergeLegend(definition.legend, spec.legend)
    end
    local schema, metadata = buildCanonical(definition, spec)
    if not schema then
        return false, metadata or "parse_failed"
    end
    if type(metadata) ~= "table" then
        metadata = { note = metadata }
    end
    metadata = metadata or {}
    metadata.format = format
    metadata.path = path
    assignToContext(ctx, schema, metadata)
    logger.log(ctx, "debug", string.format("Parsed schema with %d blocks", metadata.totalBlocks or 0))
    return true, schema, metadata
end

function parser.parseFile(ctx, path, opts)
    opts = opts or {}
    opts.path = path
    return parser.parse(ctx, opts)
end

function parser.parseText(ctx, text, opts)
    opts = opts or {}
    opts.text = text
    opts.format = opts.format or "grid"
    return parser.parse(ctx, opts)
end

function parser.parseJson(ctx, data, opts)
    opts = opts or {}
    opts.data = data
    opts.format = "json"
    return parser.parse(ctx, opts)
end

return parser
]=])

addEmbeddedFile("lib/lib_items.lua", [=[--[[
Item definitions and properties.
Maps Minecraft item IDs to symbols, colors, and other metadata.
--]]

local items = {
    { id = "minecraft:stone", sym = "#", color = colors.lightGray },
    { id = "minecraft:cobblestone", sym = "c", color = colors.gray },
    { id = "minecraft:dirt", sym = "d", color = colors.brown },
    { id = "minecraft:grass_block", sym = "g", color = colors.green },
    { id = "minecraft:planks", sym = "p", color = colors.orange },
    { id = "minecraft:log", sym = "L", color = colors.brown },
    { id = "minecraft:leaves", sym = "l", color = colors.green },
    { id = "minecraft:glass", sym = "G", color = colors.lightBlue },
    { id = "minecraft:sand", sym = "s", color = colors.yellow },
    { id = "minecraft:gravel", sym = "v", color = colors.gray },
    { id = "minecraft:coal_ore", sym = "C", color = colors.black },
    { id = "minecraft:iron_ore", sym = "I", color = colors.white },
    { id = "minecraft:gold_ore", sym = "O", color = colors.yellow },
    { id = "minecraft:diamond_ore", sym = "D", color = colors.cyan },
    { id = "minecraft:redstone_ore", sym = "R", color = colors.red },
    { id = "minecraft:lapis_ore", sym = "B", color = colors.blue },
    { id = "minecraft:chest", sym = "H", color = colors.orange },
    { id = "minecraft:furnace", sym = "F", color = colors.gray },
    { id = "minecraft:crafting_table", sym = "T", color = colors.brown },
    { id = "minecraft:torch", sym = "i", color = colors.yellow },
    { id = "minecraft:water_bucket", sym = "W", color = colors.blue },
    { id = "minecraft:lava_bucket", sym = "A", color = colors.orange },
    { id = "minecraft:bucket", sym = "u", color = colors.lightGray },
    { id = "minecraft:wheat_seeds", sym = ".", color = colors.green },
    { id = "minecraft:wheat", sym = "w", color = colors.yellow },
    { id = "minecraft:carrot", sym = "r", color = colors.orange },
    { id = "minecraft:potato", sym = "o", color = colors.yellow },
    { id = "minecraft:sugar_cane", sym = "|", color = colors.lime },
    { id = "minecraft:oak_sapling", sym = "S", color = colors.green },
    { id = "minecraft:spruce_sapling", sym = "S", color = colors.green },
    { id = "minecraft:birch_sapling", sym = "S", color = colors.green },
    { id = "minecraft:jungle_sapling", sym = "S", color = colors.green },
    { id = "minecraft:acacia_sapling", sym = "S", color = colors.green },
    { id = "minecraft:dark_oak_sapling", sym = "S", color = colors.green },
    { id = "minecraft:stone_bricks", sym = "#", color = colors.gray },
}

return items
]=])

addEmbeddedFile("lib/lib_schema.lua", [=[--[[
Schema utilities.
Helpers for resolving symbols, managing bounds, and manipulating schema data.
--]]

local schema_utils = {}
local items = require("lib_items")
local table_utils = require("lib_table")

function schema_utils.newBounds()
    return {
        min = { x = math.huge, y = math.huge, z = math.huge },
        max = { x = -math.huge, y = -math.huge, z = -math.huge },
    }
end

function schema_utils.updateBounds(bounds, x, y, z)
    if x < bounds.min.x then bounds.min.x = x end
    if y < bounds.min.y then bounds.min.y = y end
    if z < bounds.min.z then bounds.min.z = z end
    if x > bounds.max.x then bounds.max.x = x end
    if y > bounds.max.y then bounds.max.y = y end
    if z > bounds.max.z then bounds.max.z = z end
end

function schema_utils.resolveSymbol(symbol, legend, opts)
    local entry = legend and legend[symbol]
    if not entry then
        -- Default fallbacks
        if symbol == "." then return nil end -- Air
        return nil, "unknown_symbol"
    end

    local material, meta
    if type(entry) == "table" then
        material = entry.material or entry.block or entry.name
        meta = entry.meta or entry.data or {}
    else
        material = entry
        meta = {}
    end

    if material == "minecraft:air" or material == "air" then
        return nil
    end

    -- Apply global meta overrides if present
    if opts and opts.meta then
        meta = table_utils.merge(meta, opts.meta)
    end

    return { material = material, meta = meta }
end

function schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
    if not material then return true end -- Skip air/nil

    if not schema[x] then schema[x] = {} end
    if not schema[x][y] then schema[x][y] = {} end
    
    -- Check for conflict? For now, overwrite.
    schema[x][y][z] = {
        material = material,
        meta = meta
    }

    schema_utils.updateBounds(bounds, x, y, z)
    counts[material] = (counts[material] or 0) + 1
    return true
end

function schema_utils.mergeLegend(base, override)
    if not base and not override then return {} end
    if not base then return override end
    if not override then return base end
    
    local merged = table_utils.shallowCopy(base)
    for k, v in pairs(override) do
        merged[k] = v
    end
    return merged
end

function schema_utils.cloneMeta(meta)
    if not meta then return {} end
    return table_utils.deepCopy(meta)
end

function schema_utils.canonicalToVoxelDefinition(schema)
    -- Convert canonical [x][y][z] format back to a voxel grid format suitable for JSON export
    -- This is essentially just the schema table itself, but we might want to ensure keys are strings for JSON
    -- However, CC's textutils.serializeJSON handles number keys as array indices if contiguous, or object keys if strings.
    -- To be safe and consistent with "grid" format, we can keep it as is, or convert to a list of blocks.
    -- Let's stick to the grid format as it's more compact for dense structures.
    
    -- Actually, to ensure JSON compatibility (string keys for sparse arrays), we might need to be careful.
    -- But for now, let's just return the schema structure.
    return { grid = schema }
end

return schema_utils
]=])

local lib_designer_part1 = [=[--[[
Graphical Schema Designer (Paint-style)
]]

local ui = require("lib_ui")
local json = require("lib_json")
local items = require("lib_items")
local schema_utils = require("lib_schema")
local parser = require("lib_parser")
local version = require("version")

local designer = {}

-- --- Constants & Config ---

local COLORS = {
    bg = colors.gray,
    canvas_bg = colors.black,
    grid = colors.lightGray,
    text = colors.white,
    btn_active = colors.blue,
    btn_inactive = colors.lightGray,
    btn_text = colors.black,
}

local DEFAULT_MATERIALS = {
    { id = "minecraft:stone", color = colors.lightGray, sym = "#" },
    { id = "minecraft:dirt", color = colors.brown, sym = "d" },
    { id = "minecraft:cobblestone", color = colors.gray, sym = "c" },
    { id = "minecraft:planks", color = colors.orange, sym = "p" },
    { id = "minecraft:glass", color = colors.lightBlue, sym = "g" },
    { id = "minecraft:log", color = colors.brown, sym = "L" },
    { id = "minecraft:torch", color = colors.yellow, sym = "i" },
    { id = "minecraft:iron_block", color = colors.white, sym = "I" },
    { id = "minecraft:gold_block", color = colors.yellow, sym = "G" },
    { id = "minecraft:diamond_block", color = colors.cyan, sym = "D" },
}

local TOOLS = {
    PENCIL = "Pencil",
    LINE = "Line",
    RECT = "Rect",
    RECT_FILL = "FillRect",
    CIRCLE = "Circle",
    CIRCLE_FILL = "FillCircle",
    BUCKET = "Bucket",
    PICKER = "Picker"
}

-- --- State ---

local state = {}

local function resetState()
    state.running = true
    state.w = 14
    state.h = 14
    state.d = 5
    state.data = {} -- [x][y][z] = material_index (0 or nil for air)
    state.meta = {} -- [x][y][z] = meta table
    state.fileMeta = nil -- Global file metadata
    state.palette = {}
    state.paletteEditMode = false
    state.offset = { x = 0, y = 0, z = 0 }

    state.view = {
        layer = 0, -- Current Y level
        offsetX = 4, -- Screen X offset of canvas
        offsetY = 3, -- Screen Y offset of canvas
        scrollX = 0,
        scrollY = 0,
        cursorX = 0,
        cursorY = 0,
    }

    state.menuOpen = false
    state.inventoryOpen = false
    state.searchOpen = false
    state.searchQuery = ""
    state.searchResults = {}
    state.searchScroll = 0
    state.dragItem = nil -- { id, sym, color }

    state.tool = TOOLS.PENCIL
    state.primaryColor = 1 -- Index in palette
    state.secondaryColor = 0 -- 0 = Air/Eraser

    state.mouse = {
        down = false,
        drag = false,
        startX = 0, startY = 0, -- Canvas coords
        currX = 0, currY = 0,   -- Canvas coords
        btn = 1
    }

    state.status = "Ready"

    for i, m in ipairs(DEFAULT_MATERIALS) do
        state.palette[i] = { id = m.id, color = m.color, sym = m.sym }
    end
end

resetState()

-- --- Helpers ---

local function getMaterial(idx)
    if idx == 0 or not idx then return nil end
    return state.palette[idx]
end

local function getBlock(x, y, z)
    if not state.data[x] then return 0 end
    if not state.data[x][y] then return 0 end
    return state.data[x][y][z] or 0
end

local function setBlock(x, y, z, matIdx, meta)
    if x < 0 or x >= state.w or z < 0 or z >= state.h or y < 0 or y >= state.d then return end

    if not state.data[x] then state.data[x] = {} end
    if not state.data[x][y] then state.data[x][y] = {} end
    if not state.meta[x] then state.meta[x] = {} end
    if not state.meta[x][y] then state.meta[x][y] = {} end

    if matIdx == 0 then
        state.data[x][y][z] = nil
        if state.meta[x] and state.meta[x][y] then
            state.meta[x][y][z] = nil
        end
    else
        state.data[x][y][z] = matIdx
        state.meta[x][y][z] = meta or {}
    end
end

local function getBlockMeta(x, y, z)
    if not state.meta[x] or not state.meta[x][y] then return {} end
    return schema_utils.cloneMeta(state.meta[x][y][z])
end

local function findItemDef(id)
    for _, item in ipairs(items) do
        if item.id == id then
            return item
        end
    end
    return nil
end

local function ensurePaletteMaterial(material)
    for idx, mat in ipairs(state.palette) do
        if mat.id == material then
            return idx
        end
    end

    local fallback = findItemDef(material)
    local entry = {
        id = material,
        color = fallback and fallback.color or colors.white,
        sym = fallback and fallback.sym or "?",
    }

    table.insert(state.palette, entry)
    return #state.palette
end

local function clearCanvas()
    state.data = {}
    state.meta = {}
end

local function loadCanonical(schema, metadata)
    if type(schema) ~= "table" then
        return false, "invalid_schema"
    end

    clearCanvas()

    local bounds = schema_utils.newBounds()
    local blockCount = 0

    for xKey, xColumn in pairs(schema) do
        if type(xColumn) == "table" then
            local x = tonumber(xKey) or xKey
            if type(x) ~= "number" then return false, "invalid_coordinate" end
            for yKey, yColumn in pairs(xColumn) do
                if type(yColumn) == "table" then
                    local y = tonumber(yKey) or yKey
                    if type(y) ~= "number" then return false, "invalid_coordinate" end
                    for zKey, block in pairs(yColumn) do
                        if type(block) == "table" and block.material then
                            local z = tonumber(zKey) or zKey
                            if type(z) ~= "number" then return false, "invalid_coordinate" end
                            schema_utils.updateBounds(bounds, x, y, z)
                            blockCount = blockCount + 1
                        end
                    end
                end
            end
        end
    end

    if blockCount == 0 then
        state.status = "Loaded empty schema"
        return true
    end

    state.offset = {
        x = bounds.min.x,
        y = bounds.min.y,
        z = bounds.min.z,
    }

    state.w = math.max(1, (bounds.max.x - bounds.min.x) + 1)
    state.d = math.max(1, (bounds.max.y - bounds.min.y) + 1)
    state.h = math.max(1, (bounds.max.z - bounds.min.z) + 1)

    for xKey, xColumn in pairs(schema) do
        if type(xColumn) == "table" then
            local x = tonumber(xKey) or xKey
            if type(x) ~= "number" then return false, "invalid_coordinate" end
            for yKey, yColumn in pairs(xColumn) do
                if type(yColumn) == "table" then
                    local y = tonumber(yKey) or yKey
                    if type(y) ~= "number" then return false, "invalid_coordinate" end
                    for zKey, block in pairs(yColumn) do
                        if type(block) == "table" and block.material then
                            local z = tonumber(zKey) or zKey
                            if type(z) ~= "number" then return false, "invalid_coordinate" end
                            local matIdx = ensurePaletteMaterial(block.material)
                            local localX = x - state.offset.x
                            local localY = y - state.offset.y
                            local localZ = z - state.offset.z
                            setBlock(localX, localY, localZ, matIdx, schema_utils.cloneMeta(block.meta))
                        end
                    end
                end
            end
        end
    end

    state.status = string.format("Loaded %d blocks", blockCount)
    if metadata and metadata.path then
        state.status = state.status .. " from " .. metadata.path
    end

    if metadata and metadata.meta then
        state.fileMeta = metadata.meta
    end

    return true
end

local function exportCanonical()
    local schema = {}
    local bounds = schema_utils.newBounds()
    local total = 0

    for x, xColumn in pairs(state.data) do
        for y, yColumn in pairs(xColumn) do
            for z, matIdx in pairs(yColumn) do
                local mat = getMaterial(matIdx)
                if mat then
                    local worldX = x + state.offset.x
                    local worldY = y + state.offset.y
                    local worldZ = z + state.offset.z
                    schema[worldX] = schema[worldX] or {}
                    schema[worldX][worldY] = schema[worldX][worldY] or {}
                    schema[worldX][worldY][worldZ] = {
                        material = mat.id,
                        meta = getBlockMeta(x, y, z),
                    }
                    schema_utils.updateBounds(bounds, worldX, worldY, worldZ)
                    total = total + 1
                end
            end
        end
    end

    local info = { totalBlocks = total }
    if total > 0 then
        info.bounds = bounds
    end

    return schema, info
end

local function exportVoxelDefinition()
    local canonical, info = exportCanonical()
    return schema_utils.canonicalToVoxelDefinition(canonical), info
end

-- --- Algorithms ---

local function drawLine(x0, y0, x1, y1, callback)
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy

    while true do
        callback(x0, y0)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x0 = x0 + sx
        end
        if e2 < dx then
            err = err + dx
            y0 = y0 + sy
        end
    end
end

local function drawRect(x0, y0, x1, y1, filled, callback)
    local minX, maxX = math.min(x0, x1), math.max(x0, x1)
    local minY, maxY = math.min(y0, y1), math.max(y0, y1)
    
    for x = minX, maxX do
        for y = minY, maxY do
            if filled or (x == minX or x == maxX or y == minY or y == maxY) then
                callback(x, y)
            end
        end
    end
end

local function drawCircle(x0, y0, x1, y1, filled, callback)
    -- Midpoint circle algorithm adapted for ellipse/bounds
    local r = math.floor(math.min(math.abs(x1 - x0), math.abs(y1 - y0)) / 2)
    local cx = math.floor((x0 + x1) / 2)
    local cy = math.floor((y0 + y1) / 2)
    
    local x = r
    local y = 0
    local err = 0

    while x >= y do
        if filled then
            for i = cx - x, cx + x do callback(i, cy + y); callback(i, cy - y) end
            for i = cx - y, cx + y do callback(i, cy + x); callback(i, cy - x) end
        else
            callback(cx + x, cy + y)
            callback(cx + y, cy + x)
            callback(cx - y, cy + x)
            callback(cx - x, cy + y)
            callback(cx - x, cy - y)
            callback(cx - y, cy - x)
            callback(cx + y, cy - x)
            callback(cx + x, cy - y)
        end

        if err <= 0 then
            y = y + 1
            err = err + 2 * y + 1
        end
        if err > 0 then
            x = x - 1
            err = err - 2 * x + 1
        end
    end
end

local function floodFill(startX, startY, targetColor, replaceColor)
    if targetColor == replaceColor then return end
    
    local queue = { {x = startX, y = startY} }
    local visited = {}
    
    local function key(x, y) return x .. "," .. y end
    
    while #queue > 0 do
        local p = table.remove(queue, 1)
        local k = key(p.x, p.y)
        
        if not visited[k] then
            visited[k] = true
            local curr = getBlock(p.x, state.view.layer, p.y)
            
            if curr == targetColor then
                setBlock(p.x, state.view.layer, p.y, replaceColor)
                
                local neighbors = {
                    {x = p.x + 1, y = p.y},
                    {x = p.x - 1, y = p.y},
                    {x = p.x, y = p.y + 1},
                    {x = p.x, y = p.y - 1}
                }
                
                for _, n in ipairs(neighbors) do
                    if n.x >= 0 and n.x < state.w and n.y >= 0 and n.y < state.h then
                        table.insert(queue, n)
                    end
                end
            end
        end
    end
end

-- --- Rendering ---

local drawSearch

local function drawMenu()
    if not state.menuOpen then return end
    
    local w, h = term.getSize()
    local mx, my = w - 12, 2
    local mw, mh = 12, 8
    
    ui.drawFrame(mx, my, mw, mh, "Menu")
    
    local options = { "Resize", "Save", "Load", "Clear", "Inventory", "Quit" }
    for i, opt in ipairs(options) do
        term.setCursorPos(mx + 1, my + i)
        term.setBackgroundColor(COLORS.bg)
        term.setTextColor(COLORS.text)
        if opt == "Inventory" and state.inventoryOpen then
            term.setTextColor(colors.yellow)
        end
        term.write(opt)
    end
end

local function drawInventory()
    if not state.inventoryOpen then return end
    
    local w, h = term.getSize()
    local iw, ih = 18, 6 -- 4x4 grid + border
    local ix, iy = math.floor((w - iw)/2), math.floor((h - ih)/2)
    
    ui.drawFrame(ix, iy, iw, ih, "Inventory")
    
    -- Draw 4x4 grid
    for row = 0, 3 do
        for col = 0, 3 do
            local slot = row * 4 + col + 1
            local item = turtle.getItemDetail(slot)
            
            term.setCursorPos(ix + 1 + (col * 4), iy + 1 + row)
            
            local sym = "."
            local color = colors.gray
            
            if item then
                sym = item.name:sub(11, 11):upper() -- First char of name after minecraft:
                color = colors.white
            end
            
            term.setBackgroundColor(colors.black)
            term.setTextColor(color)
            term.write(" " .. sym .. " ")
        end
    end
    
    term.setCursorPos(ix + 1, iy + ih)
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.text)
    term.write("Drag to Palette")
end

local function drawDragItem()
    if state.dragItem and state.mouse.screenX then
        term.setCursorPos(state.mouse.screenX, state.mouse.screenY)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.write(state.dragItem.sym)
    end
end

local function drawUI()
    ui.clear()
    
    -- Toolbar (Top)
    term.setBackgroundColor(COLORS.bg)
    term.setCursorPos(1, 1)
    term.clearLine()
    
    -- [M] Button
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.write(" M ")
    
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.text)
    term.write(string.format(" Designer [%d,%d,%d] Layer: %d/%d", state.w, state.h, state.d, state.view.layer, state.d - 1))
    
    -- Tools (Left Side)
    local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
    for i, t in ipairs(toolsList) do
        term.setCursorPos(1, 2 + i)
        if state.tool == t then
            term.setBackgroundColor(COLORS.btn_active)
            term.setTextColor(colors.white)
            term.write(" " .. t:sub(1,1) .. " ")
        else
            term.setBackgroundColor(COLORS.btn_inactive)
            term.setTextColor(COLORS.btn_text)
            term.write(" " .. t:sub(1,1) .. " ")
        end
    end
    
    -- Palette (Right Side)
    local palX = 2 + state.w + 2
    term.setCursorPos(palX, 2)
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.text)
    
    local editLabel = state.paletteEditMode and "[EDITING]" or "[Edit]"
    if state.paletteEditMode then term.setTextColor(colors.red) end
    term.write("Pal " .. editLabel)
    
    -- Search Button
    term.setCursorPos(palX + 14, 2)
    term.setBackgroundColor(COLORS.btn_inactive)
    term.setTextColor(COLORS.btn_text)
    term.write("Find")
    
    for i, mat in ipairs(state.palette) do
        term.setCursorPos(palX, 3 + i)
        
        -- Indicator for selection
        local indicator = " "
        if state.primaryColor == i then indicator = "L" end
        if state.secondaryColor == i then indicator = "R" end
        if state.primaryColor == i and state.secondaryColor == i then indicator = "B" end
        
        term.setBackgroundColor(COLORS.bg)
        term.setTextColor(COLORS.text)
        term.write(indicator)
        
        term.setBackgroundColor(mat.color)
        term.setTextColor(colors.black)
        term.write(" " .. mat.sym .. " ")
        
        term.setBackgroundColor(COLORS.bg)
        term.setTextColor(COLORS.text)
        local name = mat.id:match(":(.+)") or mat.id
        term.write(" " .. name)
    end
    
    -- Status Bar (Bottom)
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(COLORS.bg)
    term.clearLine()
    term.write(state.status)
    
    -- Display version in bottom right corner
    local versionText = version.display()
    term.setCursorPos(w - #versionText + 1, h)
    term.setTextColor(colors.lightGray)
    term.write(versionText)
    term.setTextColor(COLORS.text)
    
    -- Instructions
    term.setCursorPos(1, h-1)
    term.write("S:Save L:Load F:Find R:Resize C:Clear Q:Quit PgUp/Dn:Layer")
    
    drawMenu()
    drawInventory()
    drawSearch()
    drawDragItem()
end

local function drawCanvas()
    local ox, oy = state.view.offsetX, state.view.offsetY
    local sx, sy = state.view.scrollX, state.view.scrollY
    
    -- Draw Border
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(colors.white)
    ui.drawBox(ox - 1, oy - 1, state.w + 2, state.h + 2, COLORS.bg, colors.white)
    
    -- Draw Pixels
    for x = 0, state.w - 1 do
        for z = 0, state.h - 1 do
            -- Apply scroll
            local screenX = ox + x - sx
            local screenY = oy + z - sy
            
            -- Only draw if within canvas view area (roughly)
            -- Actually, we should clip to the border box
            -- For simplicity, let's just draw if it fits on screen
            local w, h = term.getSize()
            if screenX >= ox and screenX < w and screenY >= oy and screenY < h - 2 then
                local matIdx = getBlock(x, state.view.layer, z)
                local mat = getMaterial(matIdx)
                
                local bg = COLORS.canvas_bg
                local char = "."
                local fg = COLORS.grid
                
                if mat then
]=]

local lib_designer_part2 = [=[                    bg = mat.color
                    char = mat.sym
                    fg = colors.black
                    if bg == colors.black then fg = colors.white end
                end
                
                -- Ghost drawing
                if state.mouse.down and state.mouse.drag then
                    local isGhost = false
                    local ghostColor = (state.mouse.btn == 1) and state.primaryColor or state.secondaryColor
                    
                    local function checkGhost(gx, gy)
                        if gx == x and gy == z then isGhost = true end
                    end
                    
                    if state.tool == TOOLS.PENCIL then
                        checkGhost(state.mouse.currX, state.mouse.currY)
                    elseif state.tool == TOOLS.LINE then
                        drawLine(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, checkGhost)
                    elseif state.tool == TOOLS.RECT then
                        drawRect(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, false, checkGhost)
                    elseif state.tool == TOOLS.RECT_FILL then
                        drawRect(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, true, checkGhost)
                    elseif state.tool == TOOLS.CIRCLE then
                        drawCircle(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, false, checkGhost)
                    elseif state.tool == TOOLS.CIRCLE_FILL then
                        drawCircle(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, true, checkGhost)
                    end
                    
                    if isGhost then
                        local gMat = getMaterial(ghostColor)
                        if gMat then
                            bg = gMat.color
                            char = gMat.sym
                            fg = colors.black
                        else
                            bg = COLORS.canvas_bg
                            char = "x"
                            fg = colors.red
                        end
                    end
                end
                
                term.setCursorPos(screenX, screenY)
                term.setBackgroundColor(bg)
                term.setTextColor(fg)
                term.write(char)
            end
        end
    end

    -- Draw Cursor
    local cx, cy = state.view.cursorX, state.view.cursorY
    local screenX = ox + cx - sx
    local screenY = oy + cy - sy
    local w, h = term.getSize()
    
    if screenX >= ox and screenX < w and screenY >= oy and screenY < h - 2 then
        term.setCursorPos(screenX, screenY)
        if os.clock() % 0.8 < 0.4 then
            term.setBackgroundColor(colors.white)
            term.setTextColor(colors.black)
        else
            local matIdx = getBlock(cx, state.view.layer, cy)
            local mat = getMaterial(matIdx)
            if mat then
                term.setBackgroundColor(mat.color == colors.white and colors.black or colors.white)
                term.setTextColor(mat.color)
            else
                term.setBackgroundColor(colors.white)
                term.setTextColor(colors.black)
            end
        end
        local matIdx = getBlock(cx, state.view.layer, cy)
        local mat = getMaterial(matIdx)
        term.write(mat and mat.sym or "+")
    end
end



-- --- Logic ---

local function applyTool(x, y, btn)
    local color = (btn == 1) and state.primaryColor or state.secondaryColor
    
    if state.tool == TOOLS.PENCIL then
        setBlock(x, state.view.layer, y, color)
    elseif state.tool == TOOLS.BUCKET then
        local target = getBlock(x, state.view.layer, y)
        floodFill(x, y, target, color)
    elseif state.tool == TOOLS.PICKER then
        local picked = getBlock(x, state.view.layer, y)
        if btn == 1 then state.primaryColor = picked else state.secondaryColor = picked end
        state.tool = TOOLS.PENCIL -- Auto switch back
    end
end

local function applyShape(x0, y0, x1, y1, btn)
    local color = (btn == 1) and state.primaryColor or state.secondaryColor
    
    local function plot(x, y)
        setBlock(x, state.view.layer, y, color)
    end
    
    if state.tool == TOOLS.LINE then
        drawLine(x0, y0, x1, y1, plot)
    elseif state.tool == TOOLS.RECT then
        drawRect(x0, y0, x1, y1, false, plot)
    elseif state.tool == TOOLS.RECT_FILL then
        drawRect(x0, y0, x1, y1, true, plot)
    elseif state.tool == TOOLS.CIRCLE then
        drawCircle(x0, y0, x1, y1, false, plot)
    elseif state.tool == TOOLS.CIRCLE_FILL then
        drawCircle(x0, y0, x1, y1, true, plot)
    end
end

local function loadSchema()
    ui.clear()
    term.setCursorPos(1, 1)
    print("Load Schema")
    term.write("Filename: ")
    local name = read()
    if name == "" then return end
    
    -- Try to load file
    if not fs.exists(name) then
        if fs.exists(name .. ".json") then name = name .. ".json"
        elseif fs.exists(name .. ".txt") then name = name .. ".txt"
        else
            state.status = "File not found"
            return
        end
    end
    
    local ok, schema, meta = parser.parseFile(nil, name)
    
    if ok then
        local ok2, err = loadCanonical(schema, meta)
        if ok2 then
            state.status = "Loaded " .. name
        else
            state.status = "Error loading: " .. err
        end
    else
        state.status = "Parse error: " .. schema
    end
end

local function saveSchema()
    ui.clear()
    term.setCursorPos(1, 1)
    print("Save Schema")
    term.write("Filename: ")
    local name = read()
    if name == "" then return end
    if not name:find("%.json$") then name = name .. ".json" end
    
    local exportDef, info = exportVoxelDefinition()
    
    -- Inject file metadata if present
    if state.fileMeta then
        exportDef.meta = state.fileMeta
    end

    local f = fs.open(name, "w")
    f.write(json.encode(exportDef))
    f.close()
    state.status = "Saved to " .. name
end

local function resizeCanvas()
    ui.clear()
    print("Resize Canvas")
    term.write("Width (" .. state.w .. "): ")
    local w = tonumber(read()) or state.w
    term.write("Height/Depth (" .. state.h .. "): ")
    local h = tonumber(read()) or state.h
    term.write("Layers (" .. state.d .. "): ")
    local d = tonumber(read()) or state.d
    
    state.w = w
    state.h = h
    state.d = d
end

local function editPaletteItem(idx)
    ui.clear()
    term.setCursorPos(1, 1)
    print("Edit Palette Item #" .. idx)
    
    local current = state.palette[idx]
    
    term.write("ID (" .. current.id .. "): ")
    local newId = read()
    if newId == "" then newId = current.id end
    
    term.write("Symbol (" .. current.sym .. "): ")
    local newSym = read()
    if newSym == "" then newSym = current.sym end
    newSym = newSym:sub(1, 1)
    
    -- Color selection is tricky in text mode, let's skip for now or cycle
    -- For now, keep color
    
    state.palette[idx].id = newId
    state.palette[idx].sym = newSym
    state.status = "Updated Item #" .. idx
end

local function updateSearchResults()
    state.searchResults = {}
    local query = state.searchQuery:lower()
    for _, item in ipairs(items) do
        if item.name:lower():find(query, 1, true) or item.id:lower():find(query, 1, true) then
            table.insert(state.searchResults, item)
        end
    end
    state.searchScroll = 0
end

drawSearch = function()
    if not state.searchOpen then return end
    
    local w, h = term.getSize()
    local sw, sh = 24, 14
    local sx, sy = math.floor((w - sw)/2), math.floor((h - sh)/2)
    
    ui.drawFrame(sx, sy, sw, sh, "Item Search")
    
    -- Search Box
    term.setCursorPos(sx + 1, sy + 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(state.searchQuery .. "_")
    local padding = sw - 2 - #state.searchQuery - 1
    if padding > 0 then term.write(string.rep(" ", padding)) end
    
    -- Results List
    local maxLines = sh - 3
    for i = 1, maxLines do
        local idx = state.searchScroll + i
        local item = state.searchResults[idx]
        
        term.setCursorPos(sx + 1, sy + 2 + i)
        if item then
            term.setBackgroundColor(colors.black)
            term.setTextColor(item.color or colors.white)
            local label = item.name or item.id
            if #label > sw - 4 then label = label:sub(1, sw - 4) end
            term.write(" " .. item.sym .. " " .. label)
            local pad = sw - 2 - 3 - #label
            if pad > 0 then term.write(string.rep(" ", pad)) end
        else
            term.setBackgroundColor(COLORS.bg)
            term.write(string.rep(" ", sw - 2))
        end
    end
end

-- --- Main ---

function designer.run(opts)
    opts = opts or {}
    resetState()

    if opts.palette then
        state.palette = {}
        for i, item in ipairs(opts.palette) do
            table.insert(state.palette, {
                id = item.id,
                color = item.color,
                sym = item.sym
            })
        end
    end

    if opts.meta then
        state.fileMeta = opts.meta
    end

    if opts.schema then
        local ok, err = loadCanonical(opts.schema, opts.metadata)
        if not ok then
            return false, err
        end
    end

    state.running = true

    while state.running do
        drawUI()
        drawCanvas()
        drawMenu()
        drawInventory()
        drawSearch()
        drawDragItem()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "char" and state.searchOpen then
            state.searchQuery = state.searchQuery .. p1
            updateSearchResults()

        elseif event == "mouse_scroll" and state.searchOpen then
            local dir = p1
            state.searchScroll = math.max(0, state.searchScroll + dir)

        elseif event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            state.mouse.screenX = mx
            state.mouse.screenY = my
            local handled = false

            -- 0. Check Search (Topmost)
            if state.searchOpen then
                local w, h = term.getSize()
                local sw, sh = 24, 14
                local sx, sy = math.floor((w - sw)/2), math.floor((h - sh)/2)

                if mx >= sx and mx < sx + sw and my >= sy and my < sy + sh then
                    -- Inside Search Window
                    if my >= sy + 3 then
                        local idx = state.searchScroll + (my - (sy + 2))
                        local item = state.searchResults[idx]
                        if item then
                            state.dragItem = { id = item.id, sym = item.sym, color = item.color }
                            state.searchOpen = false
                        end
                    end
                    handled = true
                else
                    state.searchOpen = false
                    handled = true
                end
            end

            -- 1. Check Menu (Topmost)
            if not handled and state.menuOpen then
                local w, h = term.getSize()
                local menuX, menuY = w - 12, 2
                if mx >= menuX and mx < menuX + 12 and my >= menuY and my < menuY + 8 then
                    local idx = my - menuY
                    local options = { "Resize", "Save", "Load", "Clear", "Inventory", "Quit" }
                    if options[idx] then
                        if options[idx] == "Quit" then state.running = false
                        elseif options[idx] == "Inventory" then state.inventoryOpen = not state.inventoryOpen
                        elseif options[idx] == "Resize" then resizeCanvas()
                        elseif options[idx] == "Save" then saveSchema()
                        elseif options[idx] == "Clear" then clearCanvas()
                        elseif options[idx] == "Load" then loadSchema()
                        end
                        if options[idx] ~= "Inventory" then state.menuOpen = false end
                    end
                    handled = true
                else
                    -- Click outside menu closes it
                    state.menuOpen = false
                    handled = true -- Consume click
                end
            end

            -- 2. Check Inventory (Topmost)
            if not handled and state.inventoryOpen then
                local w, h = term.getSize()
                local iw, ih = 18, 6
                local ix, iy = math.floor((w - iw)/2), math.floor((h - ih)/2)

                if mx >= ix and mx < ix + iw and my >= iy and my < iy + ih then
                    -- Check slot click
                    local relX, relY = mx - ix - 1, my - iy - 1
                    if relX >= 0 and relY >= 0 then
                        local col = math.floor(relX / 4)
                        local row = relY
                        if col >= 0 and col <= 3 and row >= 0 and row <= 3 then
                            local slot = row * 4 + col + 1
                            local item = turtle.getItemDetail(slot)
                            if item then
                                state.dragItem = {
                                    id = item.name,
                                    sym = item.name:sub(11, 11):upper(),
                                    color = colors.white
                                }
                            end
                        end
                    end
                    handled = true
                end
            end

            -- 3. Check [M] Button
            if not handled and mx >= 1 and mx <= 3 and my == 1 then
                state.menuOpen = not state.menuOpen
                handled = true
            end

            -- 4. Check Palette (Drop Target & Selection)
            local palX = 2 + state.w + 2
            if not handled and mx >= palX and mx <= palX + 18 then -- Expanded for Search button
                if my == 2 then
                    -- Check Edit vs Search
                    if mx >= palX + 14 and mx <= palX + 17 then
                        state.searchOpen = not state.searchOpen
                        if state.searchOpen then
                            state.searchQuery = ""
                            updateSearchResults()
                        end
                    elseif mx <= palX + 13 then
                        state.paletteEditMode = not state.paletteEditMode
                    end
                    handled = true
                elseif my >= 4 and my < 4 + #state.palette then
                    local idx = my - 3
                    if state.paletteEditMode then
                        editPaletteItem(idx)
                    else
                        if btn == 1 then state.primaryColor = idx
                        elseif btn == 2 then state.secondaryColor = idx end
                    end
                    handled = true
                end
            end

            -- 5. Check Tools
            if not handled and mx >= 1 and mx <= 3 and my >= 3 and my < 3 + 8 then
                local idx = my - 2
                local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
                if toolsList[idx] then state.tool = toolsList[idx] end
                handled = true
            end

            -- 6. Check Canvas
            if not handled then
                local cx = mx - state.view.offsetX
                local cy = my - state.view.offsetY

                if cx >= 0 and cx < state.w and cy >= 0 and cy < state.h then
                    state.mouse.down = true
                    state.mouse.btn = btn
                    state.mouse.startX = cx
                    state.mouse.startY = cy
                    state.mouse.currX = cx
                    state.mouse.currY = cy

                    if state.tool == TOOLS.PENCIL or state.tool == TOOLS.BUCKET or state.tool == TOOLS.PICKER then
                        applyTool(cx, cy, btn)
                    end
                end
            end

        elseif event == "mouse_drag" then
            local btn, mx, my = p1, p2, p3
            state.mouse.screenX = mx
            state.mouse.screenY = my
            local cx = mx - state.view.offsetX
            local cy = my - state.view.offsetY

            if state.mouse.down then
                -- Clamp to canvas
                cx = math.max(0, math.min(state.w - 1, cx))
                cy = math.max(0, math.min(state.h - 1, cy))

                state.mouse.currX = cx
                state.mouse.currY = cy
                state.mouse.drag = true

                if state.tool == TOOLS.PENCIL then
                    applyTool(cx, cy, state.mouse.btn)
                end
            end

        elseif event == "mouse_up" then
            local btn, mx, my = p1, p2, p3

            -- Handle Drag Drop to Palette
            if state.dragItem then
                local palX = 2 + state.w + 2
                if mx >= palX and mx <= palX + 15 and my >= 4 and my < 4 + #state.palette then
                    local idx = my - 3
                    state.palette[idx].id = state.dragItem.id
                    state.palette[idx].sym = state.dragItem.sym
                    state.status = "Assigned " .. state.dragItem.id .. " to slot " .. idx
                end
                state.dragItem = nil
            end

            if state.mouse.down and state.mouse.drag then
                -- Commit shape
                if state.tool == TOOLS.LINE or state.tool == TOOLS.RECT or state.tool == TOOLS.RECT_FILL or state.tool == TOOLS.CIRCLE then
                    applyShape(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, state.mouse.btn)
                end
            end
            state.mouse.down = false
            state.mouse.drag = false

        elseif event == "key" then
            local key = p1

            if state.searchOpen then
                if key == keys.backspace then
                    state.searchQuery = state.searchQuery:sub(1, -2)
                    updateSearchResults()
                elseif key == keys.enter then
                    if #state.searchResults > 0 then
                        local item = state.searchResults[1]
                        state.dragItem = { id = item.id, sym = item.sym, color = item.color }
                        state.searchOpen = false
                    end
                elseif key == keys.up then
                    state.searchScroll = math.max(0, state.searchScroll - 1)
                elseif key == keys.down then
                    state.searchScroll = state.searchScroll + 1
                end
            else
                -- Cursor Movement
                if key == keys.up then
                    state.view.cursorY = math.max(0, state.view.cursorY - 1)
                    if state.view.cursorY < state.view.scrollY then state.view.scrollY = state.view.cursorY end
                    if state.mouse.drag then state.mouse.currY = state.view.cursorY end
                elseif key == keys.down then
                    state.view.cursorY = math.min(state.h - 1, state.view.cursorY + 1)
                    local h = term.getSize()
                    local viewH = h - 2 - state.view.offsetY
                    if state.view.cursorY >= state.view.scrollY + viewH then state.view.scrollY = state.view.cursorY - viewH + 1 end
                    if state.mouse.drag then state.mouse.currY = state.view.cursorY end
                elseif key == keys.left then
                    state.view.cursorX = math.max(0, state.view.cursorX - 1)
                    if state.view.cursorX < state.view.scrollX then state.view.scrollX = state.view.cursorX end
                    if state.mouse.drag then state.mouse.currX = state.view.cursorX end
                elseif key == keys.right then
                    state.view.cursorX = math.min(state.w - 1, state.view.cursorX + 1)
                    local w = term.getSize()
                    local viewW = w - state.view.offsetX
                    if state.view.cursorX >= state.view.scrollX + viewW then state.view.scrollX = state.view.cursorX - viewW + 1 end
                    if state.mouse.drag then state.mouse.currX = state.view.cursorX end
                
                -- Actions
                elseif key == keys.space or key == keys.enter then
                    if state.tool == TOOLS.PENCIL or state.tool == TOOLS.BUCKET or state.tool == TOOLS.PICKER then
                        applyTool(state.view.cursorX, state.view.cursorY, 1)
                    else
                        -- Shape tools: Toggle drag
                        if not state.mouse.drag then
                            state.mouse.startX = state.view.cursorX
                            state.mouse.startY = state.view.cursorY
                            state.mouse.currX = state.view.cursorX
                            state.mouse.currY = state.view.cursorY
                            state.mouse.drag = true
                            state.mouse.down = true
                            state.mouse.btn = 1
                        else
                            state.mouse.currX = state.view.cursorX
                            state.mouse.currY = state.view.cursorY
                            applyShape(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, 1)
                            state.mouse.drag = false
                            state.mouse.down = false
                        end
                    end
                
                -- Palette
                elseif key == keys.leftBracket then
                    state.primaryColor = math.max(1, state.primaryColor - 1)
                elseif key == keys.rightBracket then
                    state.primaryColor = math.min(#state.palette, state.primaryColor + 1)
                
                -- Tools (Number keys 1-8)
                elseif key >= keys.one and key <= keys.eight then
                    local idx = key - keys.one + 1
                    local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
                    if toolsList[idx] then state.tool = toolsList[idx] end
                end

                if key == keys.q then state.running = false end
                if key == keys.f then 
                    state.searchOpen = not state.searchOpen 
                    if state.searchOpen then 
                        state.searchQuery = "" 
                        updateSearchResults()
                    end
                end
                if key == keys.s then saveSchema() end
                if key == keys.r then resizeCanvas() end
                if key == keys.c then clearCanvas() end -- Clear all
                if key == keys.pageUp then state.view.layer = math.min(state.d - 1, state.view.layer + 1) end
                if key == keys.pageDown then state.view.layer = math.max(0, state.view.layer - 1) end
            end
        end
    end

    if opts.returnSchema then
        return exportCanonical()
    end
end

designer.loadCanonical = loadCanonical
designer.exportCanonical = exportCanonical
designer.exportVoxelDefinition = exportVoxelDefinition

return designer
]=]

addEmbeddedFile("lib/lib_designer.lua", lib_designer_part1 .. lib_designer_part2)

addEmbeddedFile("factory/turtle_os.lua", [=[--[[
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

local function main()
    while true do
        ui.clear()
        print("TurtleOS v2.0")
        print("-------------")
        
        local options = {
            { text = "Tree Farm", action = runTreeFarm },
            { text = "Potato Farm", action = runPotatoFarm },
            { text = "Excavate", action = runExcavate },
            { text = "Tunnel", action = runTunnel },
            { text = "Mine", action = runMining },
            { text = "Farm Designer", action = function()
                local sub = ui.Menu("Farm Designer")
                sub:addOption("Tree Farm Design", function()
                    ui.clear()
                    shell.run("factory_planner.lua", "--farm", "tree")
                end)
                sub:addOption("Potato Farm Design", function()
                    ui.clear()
                    shell.run("factory_planner.lua", "--farm", "potato")
                end)
                sub:addOption("Back", function() return "back" end)
                sub:run()
            end },
            { text = "Exit", action = function() return "exit" end }
        }
        
        local menu = ui.Menu("Main Menu")
        for _, opt in ipairs(options) do
            menu:addOption(opt.text, opt.action)
        end
        
        local result = menu:run()
        if result == "exit" then break end
    end
end

main()
]=])

addEmbeddedFile("factory/factory.lua", [=[--[[
Factory entry point for the modular agent system.
Exposes a `run(args)` helper so it can be required/bundled while remaining
runnable as a stand-alone turtle program.
]]

local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")
local debug = debug

-- Force reload of state modules to ensure updates are applied
local function requireForce(name)
    package.loaded[name] = nil
    return require(name)
end

local states = {
    INITIALIZE = requireForce("state_initialize"),
    CHECK_REQUIREMENTS = requireForce("state_check_requirements"),
    BUILD = requireForce("state_build"),
    MINE = requireForce("state_mine"),
    TREEFARM = requireForce("state_treefarm"),
    POTATOFARM = requireForce("state_potatofarm"),
    RESTOCK = requireForce("state_restock"),
    REFUEL = requireForce("state_refuel"),
    BLOCKED = requireForce("state_blocked"),
    ERROR = requireForce("state_error"),
    DONE = requireForce("state_done"),
}

local function mergeTables(base, extra)
    if type(base) ~= "table" then
        base = {}
    end
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            base[key] = value
        end
    end
    return base
end

local function buildPayload(ctx, extra)
    local payload = { context = diagnostics.snapshot(ctx) }
    if extra then
        mergeTables(payload, extra)
    end
    return payload
end

local function run(args)
    local ctx = {
        state = "INITIALIZE",
        config = {
            verbose = false,
            schemaPath = nil,
        },
        origin = { x = 0, y = 0, z = 0, facing = "north" },
        pointer = 1,
        schema = nil,
        strategy = nil,
        inventoryState = {},
        fuelState = {},
        retries = 0,
    }

    local index = 1
    while index <= #args do
        local value = args[index]
        if value == "--verbose" then
            ctx.config.verbose = true
        elseif value == "mine" then
            ctx.config.mode = "mine"
        elseif value == "tunnel" then
            ctx.config.mode = "tunnel"
        elseif value == "excavate" then
            ctx.config.mode = "excavate"
        elseif value == "treefarm" then
            ctx.config.mode = "treefarm"
            -- ctx.state = "TREEFARM" -- Let INITIALIZE handle setup
        elseif value == "potatofarm" then
            ctx.config.mode = "potatofarm"
        elseif value == "farm" then
            ctx.config.mode = "farm"
        elseif value == "--farm-type" then
            index = index + 1
            ctx.config.farmType = args[index]
        elseif value == "--width" then
            index = index + 1
            ctx.config.width = tonumber(args[index])
        elseif value == "--height" then
            index = index + 1
            ctx.config.height = tonumber(args[index])
        elseif value == "--depth" then
            index = index + 1
            ctx.config.depth = tonumber(args[index])
        elseif value == "--length" then
            index = index + 1
            ctx.config.length = tonumber(args[index])
        elseif value == "--branch-interval" then
            index = index + 1
            ctx.config.branchInterval = tonumber(args[index])
        elseif value == "--branch-length" then
            index = index + 1
            ctx.config.branchLength = tonumber(args[index])
        elseif value == "--torch-interval" then
            index = index + 1
            ctx.config.torchInterval = tonumber(args[index])
        elseif not value:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
            ctx.config.schemaPath = value
        end
        index = index + 1
    end

    if not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
        ctx.config.schemaPath = "schema.json"
    end

    -- Initialize logger
    local logOpts = {
        level = ctx.config.verbose and "debug" or "info",
        timestamps = true
    }
    logger.attach(ctx, logOpts)
    
    ctx.logger:info("Agent starting...")

    -- Load previous state if available
    local persistence = require("lib_persistence")
    local savedState = persistence.load(ctx)
    if savedState then
        ctx.logger:info("Resuming from saved state...")
        -- Merge saved state into context
        mergeTables(ctx, savedState)
        
        -- Restore movement state explicitly if needed
        if ctx.movement then
            local movement = require("lib_movement")
            movement.ensureState(ctx)
            -- Force the library to recognize the loaded position/facing
            -- (ensureState does this by checking ctx.movement, which we just loaded)
        end
    end

    -- Initial fuel check
    if turtle and turtle.getFuelLevel then
        local level = turtle.getFuelLevel()
        local limit = turtle.getFuelLimit()
        ctx.logger:info(string.format("Fuel: %s / %s", tostring(level), tostring(limit)))
        if level ~= "unlimited" and type(level) == "number" and level < 100 then
             ctx.logger:warn("Fuel is very low on startup!")
             -- Attempt emergency refuel
             local fuelLib = require("lib_fuel")
             fuelLib.refuel(ctx, { target = 2000 })
        end
    end

    -- Helper to save state
    ctx.save = function()
        persistence.save(ctx)
    end

    while ctx.state ~= "EXIT" do
        -- Save state before executing the next step
        ctx.save()

        local stateHandler = states[ctx.state]
        if not stateHandler then
            ctx.logger:error("Unknown state: " .. tostring(ctx.state), buildPayload(ctx))
            break
        end

        ctx.logger:debug("Entering state: " .. ctx.state)
        local ok, nextStateOrErr = pcall(stateHandler, ctx)
        if not ok then
            local trace = debug and debug.traceback and debug.traceback() or nil
            ctx.logger:error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr),
                buildPayload(ctx, { error = tostring(nextStateOrErr), traceback = trace }))
            ctx.lastError = nextStateOrErr
            ctx.state = "ERROR"
        else
            if type(nextStateOrErr) ~= "string" or nextStateOrErr == "" then
                ctx.logger:error("State returned invalid transition", buildPayload(ctx, { result = tostring(nextStateOrErr) }))
                ctx.lastError = nextStateOrErr
                ctx.state = "ERROR"
            elseif not states[nextStateOrErr] and nextStateOrErr ~= "EXIT" then
                ctx.logger:error("Transitioned to unknown state: " .. tostring(nextStateOrErr), buildPayload(ctx))
                ctx.state = "ERROR"
            else
                ctx.state = nextStateOrErr
            end
        end

        ---@diagnostic disable-next-line: undefined-global
        sleep(0)
    end
    
    -- Clear state on clean exit
    persistence.clear(ctx)

    ctx.logger:info("Agent finished.")
end

local module = { run = run }

---@diagnostic disable-next-line: undefined-field
if not _G.__FACTORY_EMBED__ then
    local argv = { ... }
    run(argv)
end

return module
]=])

addEmbeddedFile("factory/state_initialize.lua", [=[---@diagnostic disable: undefined-global
--[[
State: INITIALIZE
Loads schema, parses it, and computes the build strategy.
--]]

local parser = require("lib_parser")
local orientation = require("lib_orientation")
local logger = require("lib_logger")
local strategyTunnel = require("lib_strategy_tunnel")
local strategyExcavate = require("lib_strategy_excavate")
local strategyFarm = require("lib_strategy_farm")
local ui = require("lib_ui")
local startup = require("lib_startup")
local inventory = require("lib_inventory")

local function validateSchema(schema)
    if type(schema) ~= "table" then return false, "Schema is not a table" end
    local count = 0
    for _ in pairs(schema) do count = count + 1 end
    if count == 0 then return false, "Schema is empty" end
    return true
end

local function getBlock(schema, x, y, z)
    local xLayer = schema[x] or schema[tostring(x)]
    if not xLayer then return nil end
    local yLayer = xLayer[y] or xLayer[tostring(y)]
    if not yLayer then return nil end
    return yLayer[z] or yLayer[tostring(z)]
end

local function isPlaceable(block)
    if not block then return false end
    local name = block.material
    if not name or name == "" then return false end
    if name == "minecraft:air" or name == "air" then return false end
    return true
end

local function computeApproachLocal(localPos, side)
    side = side or "down"
    if side == "up" then
        return { x = localPos.x, y = localPos.y - 1, z = localPos.z }, side
    elseif side == "down" then
        return { x = localPos.x, y = localPos.y + 1, z = localPos.z }, side
    else
        return { x = localPos.x, y = localPos.y, z = localPos.z }, side
    end
end

local function computeLocalXZ(bounds, x, z, orientationKey)
    local orient = orientation.resolveOrientationKey(orientationKey)
    local relativeX = x - bounds.minX
    local relativeZ = z - bounds.minZ
    local localZ = - (relativeZ + 1)
    local localX
    if orient == "forward_right" then
        localX = relativeX + 1
    else
        localX = - (relativeX + 1)
    end
    return localX, localZ
end

local function normaliseBounds(info)
    if not info or not info.bounds then return nil, "missing_bounds" end
    local minB = info.bounds.min
    local maxB = info.bounds.max
    if not (minB and maxB) then return nil, "missing_bounds" end
    
    local function norm(t, k) return tonumber(t[k]) end
    
    return {
        minX = norm(minB, "x") or 0,
        minY = norm(minB, "y") or 0,
        minZ = norm(minB, "z") or 0,
        maxX = norm(maxB, "x") or 0,
        maxY = norm(maxB, "y") or 0,
        maxZ = norm(maxB, "z") or 0,
    }
end

local function buildOrder(schema, info, opts)
    local bounds, err = normaliseBounds(info)
    if not bounds then return nil, err or "missing_bounds" end
    
    opts = opts or {}
    local offsetLocal = opts.offsetLocal or { x = 0, y = 0, z = 0 }
    local offsetXLocal = offsetLocal.x or 0
    local offsetYLocal = offsetLocal.y or 0
    local offsetZLocal = offsetLocal.z or 0
    
    -- Default to forward_left if not specified
    local orientKey = opts.orientation or "forward_left"

    local order = {}
    for y = bounds.minY, bounds.maxY do
        for row = 0, bounds.maxZ - bounds.minZ do
            local z = bounds.minZ + row
            local forward = (row % 2) == 0
            local xStart = forward and bounds.minX or bounds.maxX
            local xEnd = forward and bounds.maxX or bounds.minX
            local step = forward and 1 or -1
            local x = xStart
            while true do
                local block = getBlock(schema, x, y, z)
                if isPlaceable(block) then
                    local baseX, baseZ = computeLocalXZ(bounds, x, z, orientKey)
                    local localPos = {
                        x = baseX + offsetXLocal,
                        y = y + offsetYLocal,
                        z = baseZ + offsetZLocal,
                    }
                    local meta = (block and type(block.meta) == "table") and block.meta or nil
                    local side = (meta and meta.side) or "down"
                    local approach, resolvedSide = computeApproachLocal(localPos, side)
                    order[#order + 1] = {
                        schemaPos = { x = x, y = y, z = z },
                        localPos = localPos,
                        approachLocal = approach,
                        block = block,
                        side = resolvedSide,
                    }
                end
                if x == xEnd then break end
                x = x + step
            end
        end
    end
    return order, bounds
end

local function INITIALIZE(ctx)
    logger.log(ctx, "info", "Initializing...")
    
    -- Startup Logic (Fuel & Chests)
    if not ctx.chests then
        ctx.chests = startup.runChestSetup(ctx)
    end
    
    if not startup.runFuelCheck(ctx, ctx.chests) then
        return "INITIALIZE"
    end
    
    if ctx.config.mode == "mine" then
        logger.log(ctx, "info", "Starting Branch Mine mode...")
        ctx.branchmine = {
            length = tonumber(ctx.config.length) or 60,
            branchInterval = tonumber(ctx.config.branchInterval) or 3,
            branchLength = tonumber(ctx.config.branchLength) or 16,
            torchInterval = tonumber(ctx.config.torchInterval) or 6,
            currentDist = 0,
            state = "SPINE",
            spineY = 0, -- Assuming we start at 0 relative to start
            chests = ctx.chests
        }
        ctx.nextState = "BRANCHMINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "tunnel" then
        logger.log(ctx, "info", "Generating tunnel strategy...")
        local length = tonumber(ctx.config.length) or 16
        local width = tonumber(ctx.config.width) or 1
        local height = tonumber(ctx.config.height) or 2
        local torchInterval = tonumber(ctx.config.torchInterval) or 6
        
        ctx.strategy = strategyTunnel.generate(length, width, height, torchInterval)
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Tunnel Plan: %d steps.", #ctx.strategy))
        ctx.nextState = "MINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "excavate" then
        logger.log(ctx, "info", "Generating excavation strategy...")
        local length = tonumber(ctx.config.length) or 8
        local width = tonumber(ctx.config.width) or 8
        local depth = tonumber(ctx.config.depth) or 3
        
        ctx.strategy = strategyExcavate.generate(length, width, depth)
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Excavation Plan: %d steps.", #ctx.strategy))
        ctx.nextState = "MINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "treefarm" then
        logger.log(ctx, "info", "Starting Tree Farm mode...")
        ctx.treefarm = {
            width = tonumber(ctx.config.width) or 9,
            height = tonumber(ctx.config.height) or 9,
            currentX = 0,
            currentZ = 0, -- Using Z for the second dimension to match Minecraft coordinates usually
            state = "SCAN",
            chests = ctx.chests
        }
        return "TREEFARM"
    end

    if ctx.config.mode == "potatofarm" then
        logger.log(ctx, "info", "Starting Potato Farm mode...")
        ctx.potatofarm = {
            width = tonumber(ctx.config.width) or 9,
            height = tonumber(ctx.config.height) or 9,
            currentX = 0,
            currentZ = 0,
            nextX = 0,
            nextZ = 0,
            state = "SCAN",
            chests = ctx.chests
        }
        return "POTATOFARM"
    end

    if ctx.config.mode == "farm" then
        logger.log(ctx, "info", "Generating farm strategy...")
        local farmType = ctx.config.farmType or "tree"
        local width = tonumber(ctx.config.width) or 9
        local length = tonumber(ctx.config.length) or 9
        
        local schema = strategyFarm.generate(farmType, width, length)
        
        local valid, err = validateSchema(schema)
        if not valid then
            ctx.lastError = "Generated schema invalid: " .. tostring(err)
            return "ERROR"
        end

        -- Preview
        ui.clear()
        ui.drawPreview(schema, 2, 2, 30, 15)
        term.setCursorPos(1, 18)
        print("Previewing " .. farmType .. " farm.")
        print("Press Enter to confirm, 'q' to quit.")
        local input = read()
        if input == "q" or input == "Q" then
            return "DONE"
        end
        
        -- Normalize schema for buildOrder
        -- We need to calculate bounds manually since we don't have parser info
        local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
        local minY, maxY = 0, 1 -- Assuming 2 layers for now
        
        for sx, row in pairs(schema) do
            local nx = tonumber(sx)
            if nx then
                if nx < minX then minX = nx end
                if nx > maxX then maxX = nx end
                for sy, col in pairs(row) do
                    for sz, block in pairs(col) do
                        local nz = tonumber(sz)
                        if nz then
                            if nz < minZ then minZ = nz end
                            if nz > maxZ then maxZ = nz end
                        end
                    end
                end
            end
        end
        
        ctx.schema = schema
        ctx.schemaInfo = {
            bounds = {
                min = { x = minX, y = minY, z = minZ },
                max = { x = maxX, y = maxY, z = maxZ }
            }
        }
        
        logger.log(ctx, "info", "Computing build strategy...")
        local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
        if not order then
            ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
            return "ERROR"
        end

        ctx.strategy = order
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Plan: %d steps.", #order))
        ctx.nextState = "BUILD"
        return "CHECK_REQUIREMENTS"
    end
    
    if not ctx.config.schemaPath then
        ctx.lastError = "No schema path provided"
        return "ERROR"
    end

    logger.log(ctx, "info", "Loading schema: " .. ctx.config.schemaPath)
    local ok, schemaOrErr, info = parser.parseFile(ctx, ctx.config.schemaPath, { formatHint = nil })
    if not ok then
        ctx.lastError = "Failed to parse schema: " .. tostring(schemaOrErr)
        return "ERROR"
    end

    ctx.schema = schemaOrErr
    ctx.schemaInfo = info

    local valid, err = validateSchema(ctx.schema)
    if not valid then
        ctx.lastError = "Loaded schema invalid: " .. tostring(err)
        return "ERROR"
    end

    logger.log(ctx, "info", "Computing build strategy...")
    local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
    if not order then
        ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
        return "ERROR"
    end

    ctx.strategy = order
    ctx.pointer = 1
    
    logger.log(ctx, "info", string.format("Plan: %d steps.", #order))

    -- Check for schema metadata to trigger next state
    if ctx.schemaInfo and ctx.schemaInfo.meta then
        local meta = ctx.schemaInfo.meta
        if meta.mode == "treefarm" then
            logger.log(ctx, "info", "Schema defines a Tree Farm. Will transition to TREEFARM after build.")
            ctx.onBuildComplete = "TREEFARM"
            
            -- Calculate dimensions from bounds
            local bounds = ctx.schemaInfo.bounds
            local width = (bounds.max.x - bounds.min.x) + 1
            local height = (bounds.max.z - bounds.min.z) + 1
            
            ctx.treefarm = {
                width = width,
                height = height,
                currentX = 0,
                currentZ = 0,
                state = "SCAN",
                chests = ctx.chests,
                useSchema = true -- Flag to tell TREEFARM to use schema locations
            }
        elseif meta.mode == "potatofarm" then
            logger.log(ctx, "info", "Schema defines a Potato Farm. Will transition to POTATOFARM after build.")
            ctx.onBuildComplete = "POTATOFARM"
            
            local bounds = ctx.schemaInfo.bounds
            local width = (bounds.max.x - bounds.min.x) + 1
            local height = (bounds.max.z - bounds.min.z) + 1
            
            ctx.potatofarm = {
                width = width,
                height = height,
                currentX = 0,
                currentZ = 0,
                nextX = 0,
                nextZ = 0,
                state = "SCAN",
                chests = ctx.chests,
                useSchema = true
            }
        end
    end

    ctx.nextState = "BUILD"
    return "CHECK_REQUIREMENTS"
end

return INITIALIZE
]=])

addEmbeddedFile("factory/state_check_requirements.lua", [=[---@diagnostic disable: undefined-global
--[[
State: CHECK_REQUIREMENTS
Verifies that the turtle has enough fuel and materials to complete the task.
Prompts the user if items are missing.
--]]

local inventory = require("lib_inventory")
local logger = require("lib_logger")
local fuel = require("lib_fuel")
local diagnostics = require("lib_diagnostics")
local movement = require("lib_movement")

local MATERIAL_ALIASES = {
    ["minecraft:potatoes"] = { "minecraft:potato" }, -- Blocks vs. item name
    ["minecraft:water_bucket"] = { "minecraft:water_bucket_bucket" }, -- Allow buckets to satisfy water needs
}

local function countWithAliases(invCounts, material)
    local total = invCounts[material] or 0
    local aliases = MATERIAL_ALIASES[material]
    if aliases then
        for _, alias in ipairs(aliases) do
            total = total + (invCounts[alias] or 0)
        end
    end
    return total
end

local function buildPullList(missing)
    local pull = {}
    for mat, count in pairs(missing) do
        local aliases = MATERIAL_ALIASES[mat]
        if aliases then
            for _, alias in ipairs(aliases) do
                pull[alias] = math.max(pull[alias] or 0, count)
            end
        else
            pull[mat] = count
        end
    end
    return pull
end

local function calculateRequirements(ctx, strategy)
    -- Potatofarm: assume soil is prepped at y=0; only require fuel and potatoes for replanting.
    if ctx.potatofarm then
        local width = tonumber(ctx.potatofarm.width) or tonumber(ctx.config.width) or 9
        local height = tonumber(ctx.potatofarm.height) or tonumber(ctx.config.height) or 9
        -- Rough fuel budget: sweep the inner grid twice plus margin.
        local inner = math.max(1, (width - 2)) * math.max(1, (height - 2))
        local fuelNeeded = math.ceil(inner * 2.0) + 100
        local potatoesNeeded = inner -- enough to replant every spot once
        return {
            fuel = fuelNeeded,
            materials = { ["minecraft:potato"] = potatoesNeeded }
        }
    end

    local reqs = {
        fuel = 0,
        materials = {}
    }

    -- Estimate fuel
    -- A simple heuristic: 1 fuel per step.
    if strategy then
        reqs.fuel = #strategy
    end
    
    -- Add a safety margin for fuel (e.g. 10% + 100)
    reqs.fuel = math.ceil(reqs.fuel * 1.1) + 100

    -- Calculate materials
    if ctx.config.mode == "mine" then
        -- Mining mode
        -- Check for torches if strategy has place_torch
        for _, step in ipairs(strategy) do
            if step.type == "place_torch" then
                reqs.materials["minecraft:torch"] = (reqs.materials["minecraft:torch"] or 0) + 1
            elseif step.type == "place_chest" then
                reqs.materials["minecraft:chest"] = (reqs.materials["minecraft:chest"] or 0) + 1
            end
        end
    else
        -- Build mode
        for _, step in ipairs(strategy) do
            if step.block and step.block.material then
                local mat = step.block.material
                reqs.materials[mat] = (reqs.materials[mat] or 0) + 1
            end
        end
    end

    return reqs
end

local function calculateBranchmineRequirements(ctx)
    local bm = ctx.branchmine or {}
    local length = tonumber(bm.length or ctx.config.length) or 60
    local branchInterval = tonumber(bm.branchInterval or ctx.config.branchInterval) or 3
    local branchLength = tonumber(bm.branchLength or ctx.config.branchLength) or 16
    local torchInterval = tonumber(bm.torchInterval or ctx.config.torchInterval) or 6

    branchInterval = math.max(branchInterval, 1)
    torchInterval = math.max(torchInterval, 1)
    branchLength = math.max(branchLength, 1)

    local branchPairs = math.floor(length / branchInterval)
    local branchTravel = branchPairs * (4 * branchLength + 4)
    local totalTravel = length + branchTravel

    local reqs = {
        fuel = math.ceil(totalTravel * 1.1) + 100,
        materials = {}
    }

    local torchItem = ctx.config.torchItem or "minecraft:torch"
    local torchCount = math.max(1, math.floor(length / torchInterval))
    reqs.materials[torchItem] = torchCount

    return reqs
end

local function CHECK_REQUIREMENTS(ctx)
    logger.log(ctx, "info", "Checking requirements...")

    local reqs
    if ctx.branchmine then
        reqs = calculateBranchmineRequirements(ctx)
    else
        if ctx.config.mode == "mine" then
            logger.log(ctx, "warn", "Branchmine context missing, re-initializing...")
            ctx.branchmine = {
                length = tonumber(ctx.config.length) or 60,
                branchInterval = tonumber(ctx.config.branchInterval) or 3,
                branchLength = tonumber(ctx.config.branchLength) or 16,
                torchInterval = tonumber(ctx.config.torchInterval) or 6,
                currentDist = 0,
                state = "SPINE",
                spineY = 0,
                chests = ctx.chests
            }
            ctx.nextState = "BRANCHMINE"
            reqs = calculateBranchmineRequirements(ctx)
        else
            local strategy, errMsg = diagnostics.requireStrategy(ctx)
            if not strategy then
                ctx.lastError = errMsg or "Strategy missing"
                return "ERROR"
            end
            reqs = calculateRequirements(ctx, strategy)
        end
    end
    -- Assume dirt is already placed in the world; do not require the turtle to carry dirt.
    if reqs and reqs.materials then
        reqs.materials["minecraft:dirt"] = nil
        -- Do not require water buckets for farm strategies; assume water is pre-placed in the world.
        reqs.materials["minecraft:water_bucket"] = nil
    end

    local invCounts = inventory.getCounts(ctx)
    local currentFuel = turtle.getFuelLevel()
    if currentFuel == "unlimited" then currentFuel = 999999 end
    if type(currentFuel) ~= "number" then currentFuel = 0 end

    local missing = {
        fuel = 0,
        materials = {}
    }
    local hasMissing = false

    -- Check fuel
    if currentFuel < reqs.fuel then
        -- Attempt to refuel from inventory or nearby sources
        print("Attempting to refuel to meet requirements...")
        logger.log(ctx, "info", "Attempting to refuel to meet requirements...")
        fuel.refuel(ctx, { target = reqs.fuel, excludeItems = { "minecraft:torch" } })
        
        currentFuel = turtle.getFuelLevel()
        if currentFuel == "unlimited" then currentFuel = 999999 end
        if type(currentFuel) ~= "number" then currentFuel = 0 end
    end

    if currentFuel < reqs.fuel then
        missing.fuel = reqs.fuel - currentFuel
        hasMissing = true
    end

    -- Check materials
    for mat, count in pairs(reqs.materials) do
        -- Assume water is pre-placed; treat requirement as satisfied.
        if mat == "minecraft:water_bucket" then
            invCounts[mat] = count
        end
        -- Assume dirt is already available in the world (don't require the turtle to carry it).
        if mat == "minecraft:dirt" then
            invCounts[mat] = count
        end

        local have = countWithAliases(invCounts, mat)
        
        -- Special handling for chests: allow any chest/barrel if "minecraft:chest" is requested
        if mat == "minecraft:chest" and have < count then
            local totalChests = 0
            for invMat, invCount in pairs(invCounts) do
                if invMat:find("chest") or invMat:find("barrel") or invMat:find("shulker") then
                    totalChests = totalChests + invCount
                end
            end
            if totalChests >= count then
                have = count -- Satisfied
            end
        end

        if have < count then
            missing.materials[mat] = count - have
            hasMissing = true
        end
    end

    if hasMissing then
        print("Checking nearby chests for missing items...")
        local pullList = buildPullList(missing.materials)
        if inventory.retrieveFromNearby(ctx, pullList) then
             -- Re-check inventory
             invCounts = inventory.getCounts(ctx)
             -- Re-apply assumptions (water/dirt) after re-check
             for mat, count in pairs(reqs.materials) do
                if mat == "minecraft:water_bucket" or mat == "minecraft:dirt" then
                    invCounts[mat] = count
                end
             end
             hasMissing = false
             missing.materials = {}
             for mat, count in pairs(reqs.materials) do
                local have = countWithAliases(invCounts, mat)
                if have < count then
                    missing.materials[mat] = count - have
                    hasMissing = true
                end
             end
        end
    end

    -- If we're still missing items, check whether nearby chests have enough
    -- even if we can't hold them all at once (e.g., lots of water buckets).
    local nearby = nil
    if hasMissing then
        nearby = inventory.checkNearby(ctx, buildPullList(missing.materials))
        for mat, deficit in pairs(missing.materials) do
            local total = countWithAliases(invCounts, mat)
            total = total + (nearby[mat] or 0)
            local aliases = MATERIAL_ALIASES[mat]
            if aliases then
                for _, alias in ipairs(aliases) do
                    total = total + (nearby[alias] or 0)
                end
            end

            -- If the material is dirt, assume it's available in-world and treat as satisfied.
            if mat == "minecraft:dirt" then
                total = reqs.materials[mat] or total
            end

            if total >= (reqs.materials[mat] or 0) then
                missing.materials[mat] = nil
            end
        end

        -- Recompute hasMissing after relaxing for nearby stock
        hasMissing = missing.fuel > 0
        for _ in pairs(missing.materials) do
            hasMissing = true
            break
        end
    end

    if not hasMissing then
        logger.log(ctx, "info", "All requirements met.")
        return ctx.nextState or "DONE"
    end

    -- Report missing
    print("\n=== MISSING REQUIREMENTS ===")
    if missing.fuel > 0 then
        print(string.format("- Fuel: %d (Have %d, Need %d)", missing.fuel, currentFuel, reqs.fuel))
    end
    for mat, count in pairs(missing.materials) do
        print(string.format("- %s: %d", mat, count))
    end

    -- Check nearby
    nearby = nearby or inventory.checkNearby(ctx, missing.materials)
    local foundNearby = false
    for mat, count in pairs(nearby) do
        if not foundNearby then
            print("\n=== FOUND IN NEARBY CHESTS ===")
            foundNearby = true
        end
        print(string.format("- %s: %d", mat, count))
    end

    print("\nPress Enter to re-check, or type 'q' then Enter to quit.")
    local input = read()
    if input == "q" or input == "Q" then
        return "DONE"
    end
    
    return "CHECK_REQUIREMENTS"
end

return CHECK_REQUIREMENTS
]=])

addEmbeddedFile("lib/lib_world.lua", [=[local world = {}

function world.getInspect(side)
    if side == "forward" then
        return turtle.inspect
    elseif side == "up" then
        return turtle.inspectUp
    elseif side == "down" then
        return turtle.inspectDown
    end
    return nil
end

local SIDE_ALIASES = {
    forward = "forward",
    front = "forward",
    down = "down",
    bottom = "down",
    up = "up",
    top = "up",
    left = "left",
    right = "right",
    back = "back",
    behind = "back",
}

function world.normaliseSide(side)
    if type(side) ~= "string" then
        return nil
    end
    return SIDE_ALIASES[string.lower(side)]
end

function world.toPeripheralSide(side)
    local normalised = world.normaliseSide(side) or side
    if normalised == "forward" then
        return "front"
    elseif normalised == "up" then
        return "top"
    elseif normalised == "down" then
        return "bottom"
    elseif normalised == "back" then
        return "back"
    elseif normalised == "left" then
        return "left"
    elseif normalised == "right" then
        return "right"
    end
    return normalised
end

function world.inspectSide(side)
    local normalised = world.normaliseSide(side)
    if normalised == "forward" then
        return turtle and turtle.inspect and turtle.inspect()
    elseif normalised == "up" then
        return turtle and turtle.inspectUp and turtle.inspectUp()
    elseif normalised == "down" then
        return turtle and turtle.inspectDown and turtle.inspectDown()
    end
    return false
end

function world.isContainer(detail)
    if type(detail) ~= "table" then
        return false
    end
    local name = string.lower(detail.name or "")
    if name:find("chest", 1, true) or name:find("barrel", 1, true) or name:find("drawer", 1, true) then
        return true
    end
    if type(detail.tags) == "table" then
        for tag in pairs(detail.tags) do
            local lowered = string.lower(tag)
            if lowered:find("inventory", 1, true) or lowered:find("chest", 1, true) or lowered:find("barrel", 1, true) then
                return true
            end
        end
    end
    return false
end

function world.normalizeSide(value)
    if type(value) ~= "string" then
        return nil
    end
    local lower = value:lower()
    if lower == "forward" or lower == "front" or lower == "fwd" then
        return "forward"
    end
    if lower == "up" or lower == "top" or lower == "above" then
        return "up"
    end
    if lower == "down" or lower == "bottom" or lower == "below" then
        return "down"
    end
    return nil
end

function world.resolveSide(ctx, opts)
    if type(opts) == "string" then
        local direct = world.normalizeSide(opts)
        return direct or "forward"
    end

    local candidate
    if type(opts) == "table" then
        candidate = opts.side or opts.direction or opts.facing or opts.containerSide or opts.defaultSide
        if not candidate and type(opts.location) == "string" then
            candidate = opts.location
        end
    end

    if not candidate and type(ctx) == "table" then
        local cfg = ctx.config
        if type(cfg) == "table" then
            candidate = cfg.inventorySide or cfg.materialSide or cfg.supplySide or cfg.defaultInventorySide
        end
        if not candidate and type(ctx.inventoryState) == "table" then
            candidate = ctx.inventoryState.defaultSide
        end
    end

    local normalised = world.normalizeSide(candidate)
    if normalised then
        return normalised
    end

    return "forward"
end

function world.isContainerBlock(name, tags)
    if type(name) ~= "string" then
        return false
    end
    local lower = name:lower()
    for _, keyword in ipairs(CONTAINER_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true
        end
    end
    return world.hasContainerTag(tags)
end

function world.inspectForwardForContainer()
    if not turtle or type(turtle.inspect) ~= "function" then
        return false
    end
    local ok, data = turtle.inspect()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectUpForContainer()
    if not turtle or type(turtle.inspectUp) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectUp()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectDownForContainer()
    if not turtle or type(turtle.inspectDown) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectDown()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.peripheralSideForDirection(side)
    if side == "forward" or side == "front" then
        return "front"
    end
    if side == "up" or side == "top" then
        return "top"
    end
    if side == "down" or side == "bottom" then
        return "bottom"
    end
    return side
end

function world.computePrimaryPushDirection(ctx, periphSide)
    if periphSide == "front" then
        local facing = movement.getFacing(ctx)
        if facing then
            return OPPOSITE_FACING[facing]
        end
    elseif periphSide == "top" then
        return "down"
    elseif periphSide == "bottom" then
        return "up"
    end
    return nil
end

function world.normaliseCoordinate(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    if number >= 0 then
        return math.floor(number + 0.5)
    end
    return math.ceil(number - 0.5)
end

function world.normalisePosition(pos)
    if type(pos) ~= "table" then
        return nil, "invalid_position"
    end
    local xRaw = pos.x
    if xRaw == nil then
        xRaw = pos[1]
    end
    local yRaw = pos.y
    if yRaw == nil then
        yRaw = pos[2]
    end
    local zRaw = pos.z
    if zRaw == nil then
        zRaw = pos[3]
    end
    local x = world.normaliseCoordinate(xRaw)
    local y = world.normaliseCoordinate(yRaw)
    local z = world.normaliseCoordinate(zRaw)
    if not x or not y or not z then
        return nil, "invalid_position"
    end
    return { x = x, y = y, z = z }
end

function world.normaliseFacing(facing)
    facing = type(facing) == "string" and facing:lower() or "north"
    if facing ~= "north" and facing ~= "east" and facing ~= "south" and facing ~= "west" then
        return "north"
    end
    return facing
end

function world.facingVectors(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return { forward = { x = 0, z = -1 }, right = { x = 1, z = 0 } }
    elseif facing == "east" then
        return { forward = { x = 1, z = 0 }, right = { x = 0, z = 1 } }
    elseif facing == "south" then
        return { forward = { x = 0, z = 1 }, right = { x = -1, z = 0 } }
    else -- west
        return { forward = { x = -1, z = 0 }, right = { x = 0, z = -1 } }
    end
end

function world.rotateLocalOffset(localOffset, facing)
    local vectors = world.facingVectors(facing)
    local dx = localOffset.x or 0
    local dz = localOffset.z or 0
    local right = vectors.right
    local forward = vectors.forward
    return {
        x = (right.x * dx) + (forward.x * dz),
        z = (right.z * dx) + (forward.z * dz),
    }
end

function world.localToWorld(localOffset, facing)
    facing = world.normaliseFacing(facing)
    local dx = localOffset and localOffset.x or 0
    local dz = localOffset and localOffset.z or 0
    local rotated = world.rotateLocalOffset({ x = dx, z = dz }, facing)
    return {
        x = rotated.x,
        y = localOffset and localOffset.y or 0,
        z = rotated.z,
    }
end

function world.localToWorldRelative(origin, localPos)
    local rotated = world.localToWorld(localPos, origin.facing)
    return {
        x = origin.x + rotated.x,
        y = origin.y + rotated.y,
        z = origin.z + rotated.z
    }
end

function world.copyPosition(pos)
    if type(pos) ~= "table" then
        return nil
    end
    return {
        x = pos.x or 0,
        y = pos.y or 0,
        z = pos.z or 0,
    }
end

function world.detectContainers(io)
    local found = {}
    local sides = { "forward", "down", "up" }
    local labels = {
        forward = "front",
        down = "below",
        up = "above",
    }
    for _, side in ipairs(sides) do
        local inspect
        if side == "forward" then
            inspect = turtle.inspect
        elseif side == "up" then
            inspect = turtle.inspectUp
        else
            inspect = turtle.inspectDown
        end
        if type(inspect) == "function" then
            local ok, detail = inspect()
            if ok then
                local name = type(detail.name) == "string" and detail.name or "unknown"
                found[#found + 1] = string.format(" %s: %s", labels[side] or side, name)
            end
        end
    end
    if io.print then
        if #found == 0 then
            io.print("Detected containers: <none>")
        else
            io.print("Detected containers:")
            for _, line in ipairs(found) do
                io.print(" -" .. line)
            end
        end
    end
end

return world
]=])

addEmbeddedFile("lib/lib_gps.lua", [=[--[[
GPS library for CC:Tweaked turtles.
Provides helpers for using the GPS API.
--]]

---@diagnostic disable: undefined-global

local gps_utils = {}

function gps_utils.detectFacingWithGps(logger)
    if not gps or type(gps.locate) ~= "function" then
        return nil, "gps_unavailable"
    end
    if not turtle or type(turtle.forward) ~= "function" or type(turtle.back) ~= "function" then
        return nil, "turtle_api_unavailable"
    end

    local function locate(timeout)
        local ok, x, y, z = pcall(gps.locate, timeout)
        if ok and x then
            return x, y, z
        end
        return nil, nil, nil
    end

    local x1, _, z1 = locate(0.5)
    if not x1 then
        x1, _, z1 = locate(1)
        if not x1 then
            return nil, "gps_initial_failed"
        end
    end

    if not turtle.forward() then
        return nil, "forward_blocked"
    end

    local x2, _, z2 = locate(0.5)
    if not x2 then
        x2, _, z2 = locate(1)
    end

    local returned = turtle.back()
    if not returned then
        local attempts = 0
        while attempts < 5 and not returned do
            returned = turtle.back()
            attempts = attempts + 1
            if not returned and sleep then
                sleep(0)
            end
        end
        if not returned then
            if logger then
                logger:warn("Facing detection failed to restore the turtle's start position; adjust the turtle manually and rerun.")
            end
            return nil, "return_failed"
        end
    end

    if not x2 then
        return nil, "gps_second_failed"
    end

    local dx = x2 - x1
    local dz = z2 - z1
    local threshold = 0.2

    if math.abs(dx) < threshold and math.abs(dz) < threshold then
        return nil, "gps_delta_small"
    end

    if math.abs(dx) >= math.abs(dz) then
        if dx > threshold then
            return "east"
        elseif dx < -threshold then
            return "west"
        end
    else
        if dz > threshold then
            return "south"
        elseif dz < -threshold then
            return "north"
        end
    end

    return nil, "gps_delta_small"
end

return gps_utils
]=])

addEmbeddedFile("lib/lib_orientation.lua", [=[--[[
Orientation library for CC:Tweaked turtles.
Provides helpers for facing, orientation, and coordinate transformations.
--]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local world = require("lib_world")
local gps_utils = require("lib_gps")

local orientation = {}

local START_ORIENTATIONS = {
    [1] = { label = "Forward + Left", key = "forward_left" },
    [2] = { label = "Forward + Right", key = "forward_right" },
}
local DEFAULT_ORIENTATION = 1

function orientation.resolveOrientationKey(raw)
    if type(raw) == "string" then
        local key = raw:lower()
        if key == "forward_left" or key == "forward-left" or key == "left" or key == "l" then
            return "forward_left"
        elseif key == "forward_right" or key == "forward-right" or key == "right" or key == "r" then
            return "forward_right"
        end
    elseif type(raw) == "number" and START_ORIENTATIONS[raw] then
        return START_ORIENTATIONS[raw].key
    end
    return START_ORIENTATIONS[DEFAULT_ORIENTATION].key
end

function orientation.orientationLabel(key)
    local resolved = orientation.resolveOrientationKey(key)
    for _, entry in pairs(START_ORIENTATIONS) do
        if entry.key == resolved then
            return entry.label
        end
    end
    return START_ORIENTATIONS[DEFAULT_ORIENTATION].label
end

function orientation.normaliseFacing(facing)
    return world.normaliseFacing(facing)
end

function orientation.facingVectors(facing)
    return world.facingVectors(facing)
end

function orientation.rotateLocalOffset(localOffset, facing)
    return world.rotateLocalOffset(localOffset, facing)
end

function orientation.localToWorld(localOffset, facing)
    return world.localToWorld(localOffset, facing)
end

function orientation.detectFacingWithGps(logger)
    return gps_utils.detectFacingWithGps(logger)
end

function orientation.turnLeftOf(facing)
    return movement.turnLeftOf(facing)
end

function orientation.turnRightOf(facing)
    return movement.turnRightOf(facing)
end

function orientation.turnBackOf(facing)
    return movement.turnBackOf(facing)
end

return orientation
]=])

addEmbeddedFile("lib/lib_parser.lua", [=[--[[
Parser library for CC:Tweaked turtles.
Normalises schema sources (JSON, text grids, voxel tables) into the canonical
schema[x][y][z] format used by the build states. All public entry points
return success booleans with optional error messages and metadata tables.
--]]

---@diagnostic disable: undefined-global

local parser = {}
local logger = require("lib_logger")
local table_utils = require("lib_table")
local fs_utils = require("lib_fs")
local json_utils = require("lib_json")
local schema_utils = require("lib_schema")

local function parseLayerRows(schema, bounds, counts, layerDef, legend, opts)
    local rows = layerDef.rows
    if type(rows) ~= "table" then
        return false, "invalid_layer"
    end
    local height = #rows
    if height == 0 then
        return true
    end
    local width = nil
    for rowIndex, row in ipairs(rows) do
        if type(row) ~= "string" then
            return false, "invalid_row"
        end
        if width == nil then
            width = #row
            if width == 0 then
                return false, "empty_row"
            end
        elseif width ~= #row then
            return false, "ragged_row"
        end
        for col = 1, #row do
            local symbol = row:sub(col, col)
            local entry, err = schema_utils.resolveSymbol(symbol, legend, opts)
            if err then
                return false, string.format("legend_error:%s", symbol)
            end
            if entry then
                local x = (layerDef.x or 0) + (col - 1)
                local y = layerDef.y or 0
                local z = (layerDef.z or 0) + (rowIndex - 1)
                local ok, addErr = schema_utils.addBlock(schema, bounds, counts, x, y, z, entry.material, entry.meta)
                if not ok then
                    return false, addErr
                end
            end
        end
    end
    return true
end

local function toLayerRows(layer)
    if type(layer) == "string" then
        local rows = {}
        for line in layer:gmatch("([^\r\n]+)") do
            rows[#rows + 1] = line
        end
        return { rows = rows }
    end
    if type(layer) == "table" then
        if layer.rows then
            local rows = {}
            for i = 1, #layer.rows do
                rows[i] = tostring(layer.rows[i])
            end
            return {
                rows = rows,
                y = layer.y or layer.height or layer.level or 0,
                x = layer.x or layer.offsetX or 0,
                z = layer.z or layer.offsetZ or 0,
            }
        end
        local rows = {}
        local count = 0
        for _, value in ipairs(layer) do
            rows[#rows + 1] = tostring(value)
            count = count + 1
        end
        if count > 0 then
            return { rows = rows, y = layer.y or 0, x = layer.x or 0, z = layer.z or 0 }
        end
    end
    return nil
end

local function parseLayers(schema, bounds, counts, def, legend, opts)
    local layers = def.layers
    if type(layers) ~= "table" then
        return false, "invalid_layers"
    end
    local used = 0
    for index, layer in ipairs(layers) do
        local layerRows = toLayerRows(layer)
        if not layerRows then
            return false, "invalid_layer"
        end
        if not layerRows.y then
            layerRows.y = (def.baseY or 0) + (index - 1)
        else
            layerRows.y = layerRows.y + (def.baseY or 0)
        end
        if def.baseX then
            layerRows.x = (layerRows.x or 0) + def.baseX
        end
        if def.baseZ then
            layerRows.z = (layerRows.z or 0) + def.baseZ
        end
        local ok, err = parseLayerRows(schema, bounds, counts, layerRows, legend, opts)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_layers"
    end
    return true
end

local function parseBlockList(schema, bounds, counts, blocks)
    local used = 0
    for _, block in ipairs(blocks) do
        if type(block) ~= "table" then
            return false, "invalid_block"
        end
        local x = block.x or block[1]
        local y = block.y or block[2]
        local z = block.z or block[3]
        local material = block.material or block.name or block.block
        local meta = block.meta or block.data
        if type(meta) ~= "table" then
            meta = {}
        end
        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_blocks"
    end
    return true
end

local function parseVoxelGrid(schema, bounds, counts, grid)
    if type(grid) ~= "table" then
        return false, "invalid_grid"
    end
    local used = 0
    for xKey, xColumn in pairs(grid) do
        local x = tonumber(xKey) or xKey
        if type(x) ~= "number" then
            return false, "invalid_coordinate"
        end
        if type(xColumn) ~= "table" then
            return false, "invalid_grid"
        end
        for yKey, yColumn in pairs(xColumn) do
            local y = tonumber(yKey) or yKey
            if type(y) ~= "number" then
                return false, "invalid_coordinate"
            end
            if type(yColumn) ~= "table" then
                return false, "invalid_grid"
            end
            for zKey, entry in pairs(yColumn) do
                local z = tonumber(zKey) or zKey
                if type(z) ~= "number" then
                    return false, "invalid_coordinate"
                end
                if entry ~= nil then
                    local material
                    local meta = {}
                    if type(entry) == "string" then
                        material = entry
                    elseif type(entry) == "table" then
                        material = entry.material or entry.name or entry.block
                        meta = type(entry.meta) == "table" and entry.meta or {}
                    else
                        return false, "invalid_block"
                    end
                    if material and material ~= "" then
                        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
                        if not ok then
                            return false, err
                        end
                        used = used + 1
                    end
                end
            end
        end
    end
    if used == 0 then
        return false, "empty_grid"
    end
    return true
end

local function summarise(bounds, counts, meta)
    local materials = {}
    for material, count in pairs(counts) do
        materials[#materials + 1] = { material = material, count = count }
    end
    table.sort(materials, function(a, b)
        if a.count == b.count then
            return a.material < b.material
        end
        return a.count > b.count
    end)
    local total = 0
    for _, entry in ipairs(materials) do
        total = total + entry.count
    end
    return {
        bounds = {
            min = table_utils.shallowCopy(bounds.min),
            max = table_utils.shallowCopy(bounds.max),
        },
        materials = materials,
        totalBlocks = total,
        meta = meta
    }
end

local function buildCanonical(def, opts)
    local schema = {}
    local bounds = schema_utils.newBounds()
    local counts = {}
    local ok, err
    if def.blocks then
        ok, err = parseBlockList(schema, bounds, counts, def.blocks)
    elseif def.layers then
        ok, err = parseLayers(schema, bounds, counts, def, def.legend, opts)
    elseif def.grid then
        ok, err = parseVoxelGrid(schema, bounds, counts, def.grid)
    else
        return nil, "unknown_definition"
    end
    if not ok then
        return nil, err
    end
    if bounds.min.x == math.huge then
        return nil, "empty_schema"
    end
    return schema, summarise(bounds, counts, def.meta)
end

local function detectFormatFromExtension(path)
    if type(path) ~= "string" then
        return nil
    end
    local ext = path:match("%.([%w_%-]+)$")
    if not ext then
        return nil
    end
    ext = ext:lower()
    if ext == "json" or ext == "schem" then
        return "json"
    end
    if ext == "txt" or ext == "grid" then
        return "grid"
    end
    if ext == "vox" or ext == "voxel" then
        return "voxel"
    end
    return nil
end

local function detectFormatFromText(text)
    if type(text) ~= "string" then
        return nil
    end
    local trimmed = text:match("^%s*(.-)%s*$") or text
    local firstChar = trimmed:sub(1, 1)
    if firstChar == "{" or firstChar == "[" then
        return "json"
    end
    return "grid"
end

local function parseLegendBlock(lines, index)
    local legend = {}
    local pos = index
    while pos <= #lines do
        local line = lines[pos]
        if line == "" then
            break
        end
        if line:match("^layer") then
            break
        end
        local symbol, rest = line:match("^(%S+)%s*[:=]%s*(.+)$")
        if not symbol then
            symbol, rest = line:match("^(%S+)%s+(.+)$")
        end
        if symbol and rest then
            rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
            local value
            if rest:sub(1, 1) == "{" then
                local parsed = json_utils.decodeJson(rest)
                if parsed then
                    value = parsed
                else
                    value = rest
                end
            else
                value = rest
            end
            legend[symbol] = value
        end
        pos = pos + 1
    end
    return legend, pos
end

local function parseTextGridContent(text, opts)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        lines[#lines + 1] = line
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, nil)
    local layers = {}
    local current = {}
    local currentY = nil
    local lineIndex = 1
    while lineIndex <= #lines do
        local line = lines[lineIndex]
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == "" then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
                currentY = nil
            end
            lineIndex = lineIndex + 1
        elseif trimmed:lower() == "legend:" then
            local legendBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1)
            legend = schema_utils.mergeLegend(legend, legendBlock)
            lineIndex = nextIndex
        elseif trimmed:lower() == "meta:" then
            local metaBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1) -- Reuse parseLegendBlock as format is identical
            if not opts then opts = {} end
            opts.meta = schema_utils.mergeLegend(opts.meta, metaBlock)
            lineIndex = nextIndex
        elseif trimmed:match("^layer") then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
            end
            local yValue = trimmed:match("layer%s*[:=]%s*(-?%d+)")
            currentY = yValue and tonumber(yValue) or (#layers)
            lineIndex = lineIndex + 1
        else
            current[#current + 1] = line
            lineIndex = lineIndex + 1
        end
    end
    if #current > 0 then
        layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
    end
    if not legend or next(legend) == nil then
        return nil, "missing_legend"
    end
    if #layers == 0 then
        return nil, "empty_layers"
    end
    return {
        layers = layers,
        legend = legend,
    }
end

local function parseJsonContent(obj, opts)
    if type(obj) ~= "table" then
        return nil, "invalid_json_root"
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, obj.legend or nil)
    if obj.blocks then
        return {
            blocks = obj.blocks,
            legend = legend,
        }
    end
    if obj.layers then
        return {
            layers = obj.layers,
            legend = legend,
            baseX = obj.baseX,
            baseY = obj.baseY,
            baseZ = obj.baseZ,
        }
    end
    if obj.grid or obj.voxels then
        return {
            grid = obj.grid or obj.voxels,
            legend = legend,
        }
    end
    if #obj > 0 then
        return {
            blocks = obj,
            legend = legend,
        }
    end
    return nil, "unrecognised_json"
end

local function assignToContext(ctx, schema, info)
    if type(ctx) ~= "table" then
        return
    end
    ctx.schema = schema
    ctx.schemaInfo = info
end

local function ensureSpecTable(spec)
    if type(spec) == "table" then
        return table_utils.shallowCopy(spec)
    end
    if type(spec) == "string" then
        return { source = spec }
    end
    return {}
end

function parser.parse(ctx, spec)
    spec = ensureSpecTable(spec)
    local format = spec.format
    local text = spec.text
    local data = spec.data
    local path = spec.path or spec.sourcePath
    local source = spec.source
    if not format and spec.path then
        format = detectFormatFromExtension(spec.path)
    end
    if not format and spec.formatHint then
        format = spec.formatHint
    end
    if not text and not data then
        if spec.textContent then
            text = spec.textContent
        elseif spec.raw then
            text = spec.raw
        elseif spec.sourceText then
            text = spec.sourceText
        end
    end
    if not path and type(source) == "string" and text == nil and data == nil then
        local maybeFormat = detectFormatFromExtension(source)
        if maybeFormat then
            path = source
            format = format or maybeFormat
        else
            text = source
        end
    end
    if text == nil and path then
        local contents, err = fs_utils.readFile(path)
        if not contents then
            return false, err or "read_failed"
        end
        text = contents
        if not format then
            format = detectFormatFromExtension(path) or detectFormatFromText(text)
        end
    end
    if not format then
        if data then
            if data.layers then
                format = "grid"
            elseif data.blocks then
                format = "json"
            elseif data.grid or data.voxels then
                format = "voxel"
            end
        elseif text then
            format = detectFormatFromText(text)
        end
    end
    if not format then
        return false, "unknown_format"
    end
    local definition, err
    if format == "json" then
        if data then
            definition, err = parseJsonContent(data, spec)
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            definition, err = parseJsonContent(obj, spec)
        end
    elseif format == "grid" then
        if data and (data.layers or data.rows) then
            definition = {
                layers = data.layers or { data.rows },
                legend = schema_utils.mergeLegend(spec.legend or nil, data.legend or nil),
                meta = spec.meta or data.meta
            }
        else
            definition, err = parseTextGridContent(text, spec)
            if definition and spec.meta then
                 definition.meta = schema_utils.mergeLegend(definition.meta, spec.meta)
            end
        end
    elseif format == "voxel" then
        if data then
            definition = {
                grid = data.grid or data.voxels or data,
            }
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            if obj.grid or obj.voxels then
                definition = {
                    grid = obj.grid or obj.voxels,
                }
            else
                definition, err = parseJsonContent(obj, spec)
            end
        end
    else
        return false, "unsupported_format"
    end
    if not definition then
        return false, err or "invalid_definition"
    end
    if spec.legend then
        definition.legend = schema_utils.mergeLegend(definition.legend, spec.legend)
    end
    local schema, metadata = buildCanonical(definition, spec)
    if not schema then
        return false, metadata or "parse_failed"
    end
    if type(metadata) ~= "table" then
        metadata = { note = metadata }
    end
    metadata = metadata or {}
    metadata.format = format
    metadata.path = path
    assignToContext(ctx, schema, metadata)
    logger.log(ctx, "debug", string.format("Parsed schema with %d blocks", metadata.totalBlocks or 0))
    return true, schema, metadata
end

function parser.parseFile(ctx, path, opts)
    opts = opts or {}
    opts.path = path
    return parser.parse(ctx, opts)
end

function parser.parseText(ctx, text, opts)
    opts = opts or {}
    opts.text = text
    opts.format = opts.format or "grid"
    return parser.parse(ctx, opts)
end

function parser.parseJson(ctx, data, opts)
    opts = opts or {}
    opts.data = data
    opts.format = "json"
    return parser.parse(ctx, opts)
end

return parser
]=])

addEmbeddedFile("lib/lib_ui.lua", [=[--[[
UI Library for TurtleOS (Mouse/GUI Edition)
Provides DOS-style windowing and widgets.
--]]

local ui = {}

local colors_bg = colors.blue
local colors_fg = colors.white
local colors_btn = colors.lightGray
local colors_btn_text = colors.black
local colors_input = colors.black
local colors_input_text = colors.white

function ui.clear()
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.clear()
end

function ui.drawBox(x, y, w, h, bg, fg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end
end

function ui.drawFrame(x, y, w, h, title)
    ui.drawBox(x, y, w, h, colors.gray, colors.white)
    ui.drawBox(x + 1, y + 1, w - 2, h - 2, colors_bg, colors_fg)
    
    -- Shadow
    term.setBackgroundColor(colors.black)
    for i = 1, h do
        term.setCursorPos(x + w, y + i)
        term.write(" ")
    end
    for i = 1, w do
        term.setCursorPos(x + i, y + h)
        term.write(" ")
    end

    if title then
        term.setCursorPos(x + 2, y + 1)
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        term.write(" " .. title .. " ")
    end
end

function ui.button(x, y, text, active)
    term.setCursorPos(x, y)
    if active then
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
    else
        term.setBackgroundColor(colors_btn)
        term.setTextColor(colors_btn_text)
    end
    term.write(" " .. text .. " ")
end

function ui.label(x, y, text)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.write(text)
end

function ui.inputText(x, y, width, value, active)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_input)
    term.setTextColor(colors_input_text)
    local display = value or ""
    if #display > width then
        display = display:sub(-width)
    end
    term.write(display .. string.rep(" ", width - #display))
    if active then
        term.setCursorPos(x + #display, y)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
end

function ui.drawPreview(schema, x, y, w, h)
    -- Find bounds
    local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            if nx < minX then minX = nx end
            if nx > maxX then maxX = nx end
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        if nz < minZ then minZ = nz end
                        if nz > maxZ then maxZ = nz end
                    end
                end
            end
        end
    end

    if minX > maxX then return end -- Empty schema

    local scaleX = w / (maxX - minX + 1)
    local scaleZ = h / (maxZ - minZ + 1)
    local scale = math.min(scaleX, scaleZ, 1) -- Keep aspect ratio, max 1:1

    -- Draw background
    term.setBackgroundColor(colors.black)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end

    -- Draw blocks
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        -- Map to screen
                        local scrX = math.floor((nx - minX) * scale) + x
                        local scrY = math.floor((nz - minZ) * scale) + y
                        
                        if scrX >= x and scrX < x + w and scrY >= y and scrY < y + h then
                            term.setCursorPos(scrX, scrY)
                            
                            -- Color mapping
                            local mat = block.material
                            local color = colors.gray
                            local char = " "
                            
                            if mat:find("water") then color = colors.blue
                            elseif mat:find("log") then color = colors.brown
                            elseif mat:find("leaves") then color = colors.green
                            elseif mat:find("sapling") then color = colors.green; char = "T"
                            elseif mat:find("sand") then color = colors.yellow
                            elseif mat:find("dirt") then color = colors.brown
                            elseif mat:find("grass") then color = colors.green
                            elseif mat:find("stone") then color = colors.lightGray
                            elseif mat:find("cane") then color = colors.lime; char = "!"
                            elseif mat:find("potato") then color = colors.orange; char = "."
                            elseif mat:find("torch") then color = colors.orange; char = "i"
                            end
                            
                            term.setBackgroundColor(color)
                            if color == colors.black then term.setTextColor(colors.white) else term.setTextColor(colors.black) end
                            term.write(char)
                        end
                    end
                end
            end
        end
    end
end

-- Simple Event Loop for a Form
-- form = { title = "", elements = { {type="button", x=, y=, text=, id=}, ... } }
function ui.runForm(form)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local running = true
    local result = nil
    local activeInput = nil

    -- Identify focusable elements
    local focusableIndices = {}
    for i, el in ipairs(form.elements) do
        if el.type == "input" or el.type == "button" then
            table.insert(focusableIndices, i)
        end
    end
    local currentFocusIndex = 1
    if #focusableIndices > 0 then
        local el = form.elements[focusableIndices[currentFocusIndex]]
        if el.type == "input" then activeInput = el end
    end

    while running do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, form.title)
        
        -- Custom Draw
        if form.onDraw then
            form.onDraw(fx, fy, fw, fh)
        end

        -- Draw elements
        for i, el in ipairs(form.elements) do
            local ex, ey = fx + el.x, fy + el.y
            local isFocused = false
            if #focusableIndices > 0 and focusableIndices[currentFocusIndex] == i then
                isFocused = true
            end

            if el.type == "button" then
                ui.button(ex, ey, el.text, isFocused)
            elseif el.type == "label" then
                ui.label(ex, ey, el.text)
            elseif el.type == "input" then
                ui.inputText(ex, ey, el.width, el.value, activeInput == el or isFocused)
            end
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            local clickedSomething = false
            
            for i, el in ipairs(form.elements) do
                local ex, ey = fx + el.x, fy + el.y
                if el.type == "button" then
                    if my == ey and mx >= ex and mx < ex + #el.text + 2 then
                        ui.button(ex, ey, el.text, true) -- Flash
                        sleep(0.1)
                        if el.callback then
                            local res = el.callback(form)
                            if res then return res end
                        end
                        clickedSomething = true
                        -- Update focus
                        for fi, idx in ipairs(focusableIndices) do
                            if idx == i then currentFocusIndex = fi; break end
                        end
                        activeInput = nil
                    end
                elseif el.type == "input" then
                    if my == ey and mx >= ex and mx < ex + el.width then
                        activeInput = el
                        clickedSomething = true
                        -- Update focus
                        for fi, idx in ipairs(focusableIndices) do
                            if idx == i then currentFocusIndex = fi; break end
                        end
                    end
                end
            end
            
            if not clickedSomething then
                activeInput = nil
            end
            
        elseif event == "char" and activeInput then
            if not activeInput.stepper then
                activeInput.value = (activeInput.value or "") .. p1
            end
        elseif event == "key" then
            local key = p1
            local focusedEl = (#focusableIndices > 0) and form.elements[focusableIndices[currentFocusIndex]] or nil
            local function adjustStepper(el, delta)
                if not el or not el.stepper then return end
                local step = el.step or 1
                local current = tonumber(el.value) or 0
                local nextVal = current + (delta * step)
                if el.min then nextVal = math.max(el.min, nextVal) end
                if el.max then nextVal = math.min(el.max, nextVal) end
                el.value = tostring(nextVal)
            end

            if key == keys.backspace and activeInput then
                local val = activeInput.value or ""
                if #val > 0 then
                    activeInput.value = val:sub(1, -2)
                end
            elseif (key == keys.left or key == keys.right) and focusedEl and focusedEl.stepper then
                local delta = key == keys.left and -1 or 1
                adjustStepper(focusedEl, delta)
                activeInput = nil
            elseif key == keys.tab or key == keys.down then
                if #focusableIndices > 0 then
                    currentFocusIndex = currentFocusIndex + 1
                    if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
                    local el = form.elements[focusableIndices[currentFocusIndex]]
                    activeInput = (el.type == "input") and el or nil
                end
            elseif key == keys.up then
                if #focusableIndices > 0 then
                    currentFocusIndex = currentFocusIndex - 1
                    if currentFocusIndex < 1 then currentFocusIndex = #focusableIndices end
                    local el = form.elements[focusableIndices[currentFocusIndex]]
                    activeInput = (el.type == "input") and el or nil
                end
            elseif key == keys.enter then
                if activeInput then
                    activeInput = nil
                    -- Move to next
                    if #focusableIndices > 0 then
                        currentFocusIndex = currentFocusIndex + 1
                        if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
                        local el = form.elements[focusableIndices[currentFocusIndex]]
                        activeInput = (el.type == "input") and el or nil
                    end
                else
                    -- Activate button
                    if #focusableIndices > 0 then
                        local el = form.elements[focusableIndices[currentFocusIndex]]
                        if el.type == "button" then
                            ui.button(fx + el.x, fy + el.y, el.text, true) -- Flash
                            sleep(0.1)
                            if el.callback then
                                local res = el.callback(form)
                                if res then return res end
                            end
                        elseif el.type == "input" then
                            activeInput = el
                        end
                    end
                end
            end
        end
    end
end

-- Simple Scrollable Menu
-- items = { { text="Label", callback=function() end }, ... }
function ui.runMenu(title, items)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local scroll = 0
    local maxVisible = fh - 4 -- Title + padding (top/bottom)
    local selectedIndex = 1

    while true do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, title)
        
        -- Draw items
        for i = 1, maxVisible do
            local idx = i + scroll
            if idx <= #items then
                local item = items[idx]
                local isSelected = (idx == selectedIndex)
                ui.button(fx + 2, fy + 1 + i, item.text, isSelected)
            end
        end
        
        -- Scroll indicators
        if scroll > 0 then
            ui.label(fx + fw - 2, fy + 2, "^")
        end
        if scroll + maxVisible < #items then
            ui.label(fx + fw - 2, fy + fh - 2, "v")
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            
            -- Check items
            for i = 1, maxVisible do
                local idx = i + scroll
                if idx <= #items then
                    local item = items[idx]
                    local bx, by = fx + 2, fy + 1 + i
                    -- Button width is text length + 2 spaces
                    if my == by and mx >= bx and mx < bx + #item.text + 2 then
                        ui.button(bx, by, item.text, true) -- Flash
                        sleep(0.1)
                        if item.callback then
                            local res = item.callback()
                            if res then return res end
                        end
                        selectedIndex = idx
                    end
                end
            end
            
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir > 0 then
                if scroll + maxVisible < #items then scroll = scroll + 1 end
            else
                if scroll > 0 then scroll = scroll - 1 end
            end
        elseif event == "key" then
            local key = p1
            if key == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                    if selectedIndex <= scroll then
                        scroll = selectedIndex - 1
                    end
                end
            elseif key == keys.down then
                if selectedIndex < #items then
                    selectedIndex = selectedIndex + 1
                    if selectedIndex > scroll + maxVisible then
                        scroll = selectedIndex - maxVisible
                    end
                end
            elseif key == keys.enter then
                local item = items[selectedIndex]
                if item and item.callback then
                    ui.button(fx + 2, fy + 1 + (selectedIndex - scroll), item.text, true) -- Flash
                    sleep(0.1)
                    local res = item.callback()
                    if res then return res end
                end
            end
        end
    end
end

-- Form Class
function ui.Form(title)
    local self = {
        title = title,
        elements = {},
        _row = 0,
    }
    
    function self:addInput(id, label, value)
        local y = 2 + self._row
        table.insert(self.elements, { type = "label", x = 2, y = y, text = label })
        table.insert(self.elements, { type = "input", x = 15, y = y, width = 20, value = value, id = id })
        self._row = self._row + 1
    end

    function self:addStepper(id, label, value, opts)
        opts = opts or {}
        local y = 2 + self._row
        table.insert(self.elements, { type = "label", x = 2, y = y, text = label })
        table.insert(self.elements, {
            type = "input",
            x = 15,
            y = y,
            width = 12,
            value = tostring(value or 0),
            id = id,
            stepper = true,
            step = opts.step or 1,
            min = opts.min,
            max = opts.max,
        })
        self._row = self._row + 1
    end
    
    function self:addButton(id, label, callback)
         local y = 2 + self._row
         table.insert(self.elements, { type = "button", x = 2, y = y, text = label, id = id, callback = callback })
         self._row = self._row + 1
    end

    function self:run()
        -- Add OK/Cancel buttons
        local y = 2 + self._row + 2
        table.insert(self.elements, { 
            type = "button", x = 2, y = y, text = "OK", 
            callback = function(form) return "ok" end 
        })
        table.insert(self.elements, { 
            type = "button", x = 10, y = y, text = "Cancel", 
            callback = function(form) return "cancel" end 
        })
        
        return ui.runForm(self)
    end
    
    return self
end

function ui.toBlit(color)
    if colors.toBlit then return colors.toBlit(color) end
    local exponent = math.log(color) / math.log(2)
    return string.sub("0123456789abcdef", exponent + 1, exponent + 1)
end

return ui
]=])

addEmbeddedFile("lib/lib_strategy_tunnel.lua", [=[--[[
Strategy generator for tunneling.
Produces a linear list of steps for the turtle to excavate a tunnel of given dimensions.
]]

local strategy = {}

local function normalizePositiveInt(value, default)
    local numberValue = tonumber(value)
    if not numberValue or numberValue < 1 then
        return default
    end
    return math.floor(numberValue)
end

local function pushStep(steps, x, y, z, facing, stepType, data)
    steps[#steps + 1] = {
        type = stepType,
        x = x,
        y = y,
        z = z,
        facing = facing,
        data = data,
    }
end

local function forward(x, z, facing)
    if facing == 0 then
        z = z + 1
    elseif facing == 1 then
        x = x + 1
    elseif facing == 2 then
        z = z - 1
    else
        x = x - 1
    end
    return x, z
end

local function turnLeft(facing)
    return (facing + 3) % 4
end

local function turnRight(facing)
    return (facing + 1) % 4
end

--- Generate a tunnel strategy
---@param length number Length of the tunnel
---@param width number Width of the tunnel
---@param height number Height of the tunnel
---@param torchInterval number Distance between torches
---@return table
function strategy.generate(length, width, height, torchInterval)
    length = normalizePositiveInt(length, 16)
    width = normalizePositiveInt(width, 1)
    height = normalizePositiveInt(height, 2)
    torchInterval = normalizePositiveInt(torchInterval, 6)

    local steps = {}
    local x, y, z = 0, 0, 0
    local facing = 0 -- 0: forward (z+), 1: right (x+), 2: back (z-), 3: left (x-)

    -- We assume the turtle starts at bottom-left of the tunnel face, facing into the tunnel.
    -- Actually, let's assume turtle starts at (0,0,0) and that is the bottom-center or bottom-left?
    -- Let's assume standard behavior: Turtle is at start of tunnel.
    -- It will mine forward `length` blocks.
    -- If width > 1, it needs to strafe or turn.
    
    -- Simple implementation: Layer by layer, row by row.
    -- But for a tunnel, we usually want to move forward, clearing the cross-section.
    
    for l = 1, length do
        -- Clear the cross-section at current depth
        -- We are at some (x, y) in the cross section.
        -- Let's say we start at bottom-left (0,0) of the cross section relative to the tunnel axis.
        
        -- Actually, simpler: Just iterate x, y, z loops.
        -- But we want to minimize movement.
        -- Serpentine pattern for the cross section?
        
        -- Let's stick to the `state_mine` logic which expects "move" steps.
        -- `state_mine` is designed for branch mining where it moves forward and mines neighbors.
        -- It might not be suitable for clearing a large room.
        -- `state_mine` supports: move, turn, mine_neighbors, place_torch.
        -- `mine_neighbors` mines up, down, left, right, front.
        
        -- If we use `state_mine`, we are limited to its capabilities.
        -- Maybe we should use `state_build` logic but with "dig" enabled?
        -- Or extend `state_mine`?
        
        -- `state_mine` logic:
        -- if step.type == "move" then movement.goTo(dest, {dig=true})
        
        -- So if we generate a path that covers every block in the tunnel volume, `movement.goTo` with `dig=true` will clear it.
        -- We just need to generate the path.
        
        -- Let's generate a path that visits every block in the volume (0..width-1, 0..height-1, 1..length)
        -- Wait, 1..length because 0 is start?
        -- Let's say turtle starts at 0,0,0.
        -- It needs to clear 0,0,1 to width-1, height-1, length.
        
        -- Actually, let's just do a simple serpentine.
        
        -- Current pos
        -- x, y, z are relative to start.
        
        -- We are at (x,y,z). We want to clear the block at (x,y,z) if it's not 0,0,0?
        -- No, `goTo` moves TO the block.
        
        -- Let's iterate length first (depth), then width/height?
        -- No, usually you want to clear the face then move forward.
        -- But `goTo` is absolute coords.
        
        -- Let's do:
        -- For each slice z = 1 to length:
        --   For each y = 0 to height-1:
        --     For each x = 0 to width-1:
        --       visit(x, y, z)
        
        -- Optimization: Serpentine x and y.
    end
    
    -- Re-thinking: `state_mine` uses `localToWorld` which interprets x,y,z relative to turtle start.
    -- So we just need to generate a list of coordinates to visit.
    
    local currentX, currentY, currentZ = 0, 0, 0
    
    for d = 1, length do
        -- Move forward to next slice
        -- We are at z = d-1. We want to clear z = d.
        -- But we also need to clear x=0..width-1, y=0..height-1 at z=d.
        
        -- Let's assume we are at (currentX, currentY, d-1).
        -- We move to (currentX, currentY, d).
        
        -- Serpentine logic for the face
        -- We are at some x,y.
        -- We want to cover all x in [0, width-1] and y in [0, height-1].
        
        -- If we are just moving forward, we are carving a 1x1 tunnel.
        -- If width/height > 1, we need to visit others.
        
        -- Let's generate points.
        local slicePoints = {}
        for y = 0, height - 1 do
            for x = 0, width - 1 do
                table.insert(slicePoints, {x=x, y=y})
            end
        end
        
        -- Sort slicePoints to be nearest neighbor or serpentine
        -- Simple serpentine:
        -- If y is even, x goes 0 -> width-1
        -- If y is odd, x goes width-1 -> 0
        -- But we also need to minimize y movement.
        
        -- Actually, let's just generate the path directly.
        
        -- We are at z=d.
        -- We iterate y from 0 to height-1.
        -- If y is even: x from 0 to width-1
        -- If y is odd: x from width-1 to 0
        
        -- But wait, between slices, we want to connect the end of slice d to start of slice d+1.
        -- End of slice d is (endX, endY, d).
        -- Start of slice d+1 should be (endX, endY, d+1).
        -- So we should reverse the traversal order for the next slice?
        -- Or just continue?
        
        -- Let's try to keep it simple.
        -- Slice 1:
        --   y=0: x=0->W
        --   y=1: x=W->0
        --   ...
        --   End at (LastX, LastY, 1)
        
        -- Slice 2:
        --   Start at (LastX, LastY, 2)
        --   We should traverse in reverse of Slice 1 to minimize movement?
        --   Or just continue the pattern?
        
        -- Let's just do standard serpentine for every slice, but reverse the whole slice order if d is even?
        
        local yStart, yEnd, yStep
        if d % 2 == 1 then
            yStart, yEnd, yStep = 0, height - 1, 1
        else
            yStart, yEnd, yStep = height - 1, 0, -1
        end
        
        for y = yStart, yEnd, yStep do
            local xStart, xEnd, xStep
            -- If we are on an "even" row relative to the start of this slice...
            -- Let's just say: if y is even, go right. If y is odd, go left.
            -- But we need to match the previous position.
            
            -- If we came from z-1, we are at (currentX, currentY, d-1).
            -- We move to (currentX, currentY, d).
            -- So we should start this slice at currentX, currentY.
            
            -- This implies we shouldn't hardcode loops, but rather "fill" the slice starting from current pos.
            -- But that's pathfinding.
            
            -- Let's stick to a fixed pattern that aligns.
            -- If width=1, height=2.
            -- d=1: (0,0,1) -> (0,1,1). End at (0,1,1).
            -- d=2: (0,1,2) -> (0,0,2). End at (0,0,2).
            -- d=3: (0,0,3) -> (0,1,3).
            -- This works perfectly.
            
            -- So:
            -- If d is odd: y goes 0 -> height-1.
            -- If d is even: y goes height-1 -> 0.
            
            -- Inside y loop:
            -- We need to decide x direction.
            -- If y is even (0, 2...): x goes 0 -> width-1?
            -- Let's trace d=1 (odd). y=0. x=0->W. End x=W-1.
            -- y=1. We are at x=W-1. So x should go W-1 -> 0.
            -- So if y is odd: x goes W-1 -> 0.
            
            -- Now d=2 (even). Start y=height-1.
            -- If height=2. Start y=1.
            -- We ended d=1 at (0, 1, 1).
            -- So we start d=2 at (0, 1, 2).
            -- y=1 is odd. So x goes W-1 -> 0?
            -- Wait, we are at x=0.
            -- So if y is odd, we should go 0 -> W-1?
            -- This depends on where we ended.
            
            -- Let's generalize.
            -- We are at (currentX, currentY, d).
            -- We want to visit all x in row y.
            -- If currentX is 0, go to W-1.
            -- If currentX is W-1, go to 0.
            
            if currentX == 0 then
                xStart, xEnd, xStep = 0, width - 1, 1
            else
                xStart, xEnd, xStep = width - 1, 0, -1
            end
            
            for x = xStart, xEnd, xStep do
                -- We are visiting (x, y, d)
                -- But wait, we need to actually MOVE there.
                -- The loop generates the target coordinates.
                
                -- If this is the very first point (0,0,1), we are at (0,0,0).
                -- We just push the step.
                
                pushStep(steps, x, y, d, 0, "move")
                currentX, currentY, currentZ = x, y, d
                
                -- Place torch?
                -- Only on the floor (y=0) and maybe centered x?
                -- And at interval.
                if y == 0 and x == math.floor((width-1)/2) and d % torchInterval == 0 then
                     pushStep(steps, x, y, d, 0, "place_torch")
                end
            end
        end
    end

    return steps
end

return strategy
]=])

addEmbeddedFile("lib/lib_strategy_excavate.lua", [=[--[[
Strategy generator for excavation (quarry).
Produces a linear list of steps for the turtle to excavate a hole of given dimensions.
]]

local strategy = {}

local function normalizePositiveInt(value, default)
    local numberValue = tonumber(value)
    if not numberValue or numberValue < 1 then
        return default
    end
    return math.floor(numberValue)
end

local function pushStep(steps, x, y, z, facing, stepType, data)
    steps[#steps + 1] = {
        type = stepType,
        x = x,
        y = y,
        z = z,
        facing = facing,
        data = data,
    }
end

--- Generate an excavation strategy
---@param length number Length (z-axis)
---@param width number Width (x-axis)
---@param depth number Depth (y-axis, downwards)
---@return table
function strategy.generate(length, width, depth)
    length = normalizePositiveInt(length, 8)
    width = normalizePositiveInt(width, 8)
    depth = normalizePositiveInt(depth, 3)

    local steps = {}
    local x, y, z = 0, 0, 0
    local facing = 0 -- 0: forward (z+), 1: right (x+), 2: back (z-), 3: left (x-)

    -- We assume turtle starts at (0,0,0) which is the top-left corner of the hole.
    -- It will excavate x=[0, width-1], z=[0, length-1], y=[0, -depth+1].
    
    for d = 0, depth - 1 do
        local currentY = -d
        
        -- Serpentine pattern for the layer
        -- If d is even: start at (0,0), end at (W-1, L-1) or (0, L-1) depending on W.
        -- If d is odd: we should probably reverse to minimize travel.
        
        -- Actually, standard excavate usually returns to start to dump items?
        -- My system handles restocking/refueling via state machine interrupts.
        -- So I just need to generate the path.
        
        -- Layer logic:
        -- Iterate z from 0 to length-1.
        -- For each z, iterate x.
        
        -- To optimize, we alternate x direction every z row.
        -- And we alternate z direction every layer?
        
        -- Let's keep it simple.
        -- Layer 0: z=0..L-1.
        --   z=0: x=0..W-1
        --   z=1: x=W-1..0
        --   ...
        
        -- End of Layer 0 is at z=L-1, x=(depends).
        -- Layer 1 starts at z=L-1, x=(same).
        -- So Layer 1 should go z=L-1..0.
        
        local zStart, zEnd, zStep
        if d % 2 == 0 then
            zStart, zEnd, zStep = 0, length - 1, 1
        else
            zStart, zEnd, zStep = length - 1, 0, -1
        end
        
        for z = zStart, zEnd, zStep do
            local xStart, xEnd, xStep
            -- Determine x direction based on z and layer parity?
            -- If d is even (0):
            --   z=0: x=0..W-1
            --   z=1: x=W-1..0
            --   So if z is even, x=0..W-1.
            
            -- If d is odd (1):
            --   We start at z=L-1.
            --   We want to match the x from previous layer.
            --   Previous layer ended at z=L-1.
            --   If (L-1) was even, it ended at W-1.
            --   If (L-1) was odd, it ended at 0.
            
            -- Let's just use currentX to decide.
            -- But we are generating steps, we don't track currentX easily unless we simulate.
            -- Let's simulate.
            
            -- Wait, I can just use the same logic as tunnel.
            -- If we are at x=0, go to W-1.
            -- If we are at x=W-1, go to 0.
            
            -- But I need to know where I am at the start of the z-loop.
            -- At start of d=0, I am at (0,0,0).
            
            -- Let's track currentX, currentZ.
            if d == 0 and z == zStart then
                x = 0
            end
            
            if x == 0 then
                xStart, xEnd, xStep = 0, width - 1, 1
            else
                xStart, xEnd, xStep = width - 1, 0, -1
            end
            
            for ix = xStart, xEnd, xStep do
                x = ix
                pushStep(steps, x, currentY, z, 0, "move")
            end
        end
    end

    return steps
end

return strategy
]=])

addEmbeddedFile("lib/lib_strategy_farm.lua", [=[--[[
Strategy generator for farms.
Generates 3D schemas for Tree, Sugarcane, and Potato farms.
]]

local strategy = {}

local MATERIALS = {
    dirt = "minecraft:dirt",
    sand = "minecraft:sand",
    water = "minecraft:water_bucket",
    log = "minecraft:oak_log",
    sapling = "minecraft:oak_sapling",
    cane = "minecraft:sugar_cane",
    potato = "minecraft:potatoes",
    carrot = "minecraft:carrots",
    wheat = "minecraft:wheat",
    beetroot = "minecraft:beetroots",
    nether_wart = "minecraft:nether_wart",
    soul_sand = "minecraft:soul_sand",
    farmland = "minecraft:farmland",
    stone = "minecraft:stone_bricks", -- Border
    torch = "minecraft:torch",
    furnace = "minecraft:furnace",
    chest = "minecraft:chest"
}

local function createBlock(mat)
    return { material = mat }
end

function strategy.generate(farmType, width, length)
    width = tonumber(width) or 9
    length = tonumber(length) or 9
    
    local schema = {}
    
    -- Helper to set block
    local function set(x, y, z, mat)
        schema[x] = schema[x] or {}
        schema[x][y] = schema[x][y] or {}
        schema[x][y][z] = createBlock(mat)
    end

    if farmType == "tree" then
        -- Simple grid of saplings with 2 block spacing
        -- Layer 0: Dirt
        -- Layer 1: Saplings
        for x = 0, width - 1 do
            for z = 0, length - 1 do
                set(x, 0, z, MATERIALS.dirt)
                
                -- Border
                if x == 0 or x == width - 1 or z == 0 or z == length - 1 then
                    set(x, 0, z, MATERIALS.stone)
                else
                    -- Checkerboard or spacing
                    if x % 3 == 1 and z % 3 == 1 then
                        set(x, 1, z, MATERIALS.sapling)
                    elseif (x % 3 == 1 and z % 3 == 0) or (x % 3 == 0 and z % 3 == 1) then
                         -- Space around sapling
                    elseif x % 5 == 0 and z % 5 == 0 then
                        set(x, 1, z, MATERIALS.torch)
                    end
                end
            end
        end

        -- Add charcoal maker essentials (Furnace + Chest) on the border
        set(0, 1, 1, MATERIALS.furnace)
        set(0, 1, 2, MATERIALS.chest)

    elseif farmType == "cane" then
        -- Rows: Water, Sand, Sand, Water
        for x = 0, width - 1 do
            for z = 0, length - 1 do
                -- Border
                if z == 0 or z == length - 1 then
                    set(x, 0, z, MATERIALS.stone)
                else
                    local pattern = x % 3
                    if pattern == 0 then
                        set(x, 0, z, MATERIALS.water)
                    else
                        set(x, 0, z, MATERIALS.sand)
                        set(x, 1, z, MATERIALS.cane)
                    end
                end
            end
        end

    elseif farmType == "potato" or farmType == "carrot" or farmType == "wheat" or farmType == "beetroot" then
        -- Standard crop farm
        -- Rows of water every 4 blocks?
        -- Hydration is 4 blocks.
        -- Pattern: W D D D D D D D D W (9 blocks)
        -- Let's do: W D D D W D D D W
        for x = 0, width - 1 do
            for z = 0, length - 1 do
                -- Only lay ground (dirt/water) at y=0; no border blocks or crops.
                if x % 4 == 0 then
                    set(x, 0, z, MATERIALS.water)
                else
                    set(x, 0, z, MATERIALS.dirt) -- turtle tills/handles crops later
                end
            end
        end
    elseif farmType == "nether_wart" then
        -- Soul sand field
        for x = 0, width - 1 do
            for z = 0, length - 1 do
                if z == 0 or z == length - 1 or x == 0 or x == width - 1 then
                    set(x, 0, z, MATERIALS.stone)
                else
                    set(x, 0, z, MATERIALS.soul_sand)
                    set(x, 1, z, MATERIALS.nether_wart)
                end
            end
        end
    end

    return schema
end

return strategy
]=])

addEmbeddedFile("ui/trash_config.lua", [=[local ui = require("lib_ui")
local mining = require("lib_mining")
local valhelsia_blocks = require("arcade.data.valhelsia_blocks")

local trash_config = {}

function trash_config.run()
    local searchTerm = ""
    local scroll = 0
    local selectedIndex = 1
    local filteredBlocks = {}
    
    -- Helper to update filtered list
    local function updateFilter()
        filteredBlocks = {}
        for _, block in ipairs(valhelsia_blocks) do
            if searchTerm == "" or 
               block.label:lower():find(searchTerm:lower()) or 
               block.id:lower():find(searchTerm:lower()) then
                table.insert(filteredBlocks, block)
            end
        end
    end
    
    updateFilter()
    
    while true do
        ui.clear()
        ui.drawFrame(2, 2, 48, 16, "Trash Configuration")
        
        -- Search Bar
        ui.label(4, 4, "Search: ")
        ui.inputText(12, 4, 30, searchTerm, true)
        
        -- List Header
        ui.label(4, 6, "Name")
        ui.label(35, 6, "Trash?")
        ui.drawBox(4, 7, 44, 1, colors.gray, colors.white)
        
        -- List Items
        local listHeight = 8
        local maxScroll = math.max(0, #filteredBlocks - listHeight)
        if scroll > maxScroll then scroll = maxScroll end
        
        for i = 1, listHeight do
            local idx = i + scroll
            if idx <= #filteredBlocks then
                local block = filteredBlocks[idx]
                local y = 7 + i
                
                local isTrash = mining.TRASH_BLOCKS[block.id]
                local trashLabel = isTrash and "[YES]" or "[NO ]"
                local trashColor = isTrash and colors.red or colors.green
                
                if i == selectedIndex then
                    term.setBackgroundColor(colors.white)
                    term.setTextColor(colors.black)
                else
                    term.setBackgroundColor(colors.blue)
                    term.setTextColor(colors.white)
                end
                
                term.setCursorPos(4, y)
                local label = block.label
                if #label > 30 then label = label:sub(1, 27) .. "..." end
                term.write(label .. string.rep(" ", 31 - #label))
                
                term.setCursorPos(35, y)
                if i == selectedIndex then
                    term.setTextColor(colors.black)
                else
                    term.setTextColor(trashColor)
                end
                term.write(trashLabel)
            end
        end
        
        -- Instructions
        ui.label(4, 17, "Arrows: Move/Scroll  Enter: Toggle  Esc: Save")
        
        local event, p1 = os.pullEvent()
        
        if event == "char" then
            searchTerm = searchTerm .. p1
            updateFilter()
            selectedIndex = 1
            scroll = 0
        elseif event == "key" then
            if p1 == keys.backspace then
                searchTerm = searchTerm:sub(1, -2)
                updateFilter()
                selectedIndex = 1
                scroll = 0
            elseif p1 == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                elseif scroll > 0 then
                    scroll = scroll - 1
                end
            elseif p1 == keys.down then
                if selectedIndex < math.min(listHeight, #filteredBlocks) then
                    selectedIndex = selectedIndex + 1
                elseif scroll < maxScroll then
                    scroll = scroll + 1
                end
            elseif p1 == keys.enter then
                local idx = selectedIndex + scroll
                if filteredBlocks[idx] then
                    local block = filteredBlocks[idx]
                    if mining.TRASH_BLOCKS[block.id] then
                        mining.TRASH_BLOCKS[block.id] = nil -- Remove from trash
                    else
                        mining.TRASH_BLOCKS[block.id] = true -- Add to trash
                    end
                end
            elseif p1 == keys.enter or p1 == keys.escape then
                mining.saveConfig()
                return
            end
        end
    end
end

return trash_config
]=])

addEmbeddedFile("lib/lib_persistence.lua", [=[--[[
Persistence library for TurtleOS.
Handles saving and loading the agent's state to a JSON file.
]]

local json = require("lib_json")
local logger = require("lib_logger")

local persistence = {}
local STATE_FILE = "state.json"

---@class PersistenceConfig
---@field path string|nil Path to the state file (default: "state.json")

---Load state from disk.
---@param ctx table Context table for logging
---@param config PersistenceConfig|nil Configuration options
---@return table|nil state The loaded state table, or nil if not found/error
function persistence.load(ctx, config)
    local path = (config and config.path) or STATE_FILE
    
    if not fs.exists(path) then
        logger.log(ctx, "info", "No previous state found at " .. path)
        return nil
    end

    local f = fs.open(path, "r")
    if not f then
        logger.log(ctx, "error", "Failed to open state file for reading: " .. path)
        return nil
    end

    local content = f.readAll()
    f.close()

    if not content or content == "" then
        logger.log(ctx, "warn", "State file was empty")
        return nil
    end

    local state = json.decode(content)
    if not state then
        logger.log(ctx, "error", "Failed to decode state JSON")
        return nil
    end

    logger.log(ctx, "info", "State loaded from " .. path)
    return state
end

---Save state to disk.
---@param ctx table Context table containing the state to save
---@param config PersistenceConfig|nil Configuration options
---@return boolean success
function persistence.save(ctx, config)
    local path = (config and config.path) or STATE_FILE
    
    -- Construct a serializable snapshot of the context
    -- We don't want to save everything (like functions or the logger itself)
    local snapshot = {
        state = ctx.state,
        config = ctx.config,
        origin = ctx.origin,
        movement = ctx.movement, -- Contains position and facing
        chests = ctx.chests,     -- Save chest locations
        -- Save specific state data if it exists
        potatofarm = ctx.potatofarm,
        treefarm = ctx.treefarm,
        mine = ctx.mine,
        -- Add other state-specific tables here as needed
    }

    local content = json.encode(snapshot)
    if not content then
        logger.log(ctx, "error", "Failed to encode state to JSON")
        return false
    end

    local f = fs.open(path, "w")
    if not f then
        logger.log(ctx, "error", "Failed to open state file for writing: " .. path)
        return false
    end

    f.write(content)
    f.close()

    return true
end

---Clear the saved state file.
---@param ctx table Context table
---@param config PersistenceConfig|nil
function persistence.clear(ctx, config)
    local path = (config and config.path) or STATE_FILE
    if fs.exists(path) then
        fs.delete(path)
        logger.log(ctx, "info", "Cleared state file: " .. path)
    end
end

return persistence
]=])

addEmbeddedFile("lib/lib_wizard.lua", [=[--[[
Wizard library for CC:Tweaked turtles.
Dummy implementation to satisfy dependencies.
]]

local wizard = {}

function wizard.run(ctx)
    return true
end

return wizard
]=])

-- END_EMBEDDED_FILES

local function log(msg)
  print("[install] " .. msg)
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

local function promptConfirm()
  term.write("This will ERASE everything except the ROM. Continue? (y/N) ")
  local reply = string.lower(read() or "")
  return reply == "y" or reply == "yes"
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

  log("Fetching manifest from " .. url)
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
    name = manifest.name or "Workstation",
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
      log("Downloading " .. file.path)
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

local function formatDisk()
  log("Formatting computer...")
  for _, entry in ipairs(fs.list("/")) do
    if entry ~= "rom" then
      fs.delete(entry)
    end
  end
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

  handle.write(content)
  handle.close()
end

local function installImage(image)
  log("Installing " .. (image.name or "Workstation") .. " (" .. (image.version or "unknown") .. ")")
  for _, file in ipairs(image.files) do
    writeFile(file.path, file.content or "")
  end
end

local function summarizeInstall(image)
  local files = image.files or {}
  print("")
  print("Install summary:")
  print(string.format(" - Name: %s", image.name or "Workstation"))
  print(string.format(" - Version: %s", image.version or "unknown"))
  print(string.format(" - Files installed: %d", #files))
  for _, file in ipairs(files) do
    if file.path then
      print("   * " .. file.path)
    end
  end
end

local function main()
  local manifestUrl = tArgs[1] or DEFAULT_MANIFEST_URL

  if manifestUrl == "embedded" then
    log("Using embedded Workstation image only.")
  elseif not http then
    log("HTTP is disabled; falling back to embedded image.")
    manifestUrl = "embedded"
  end

  local image
  if manifestUrl ~= "embedded" then
    local manifest, err = loadManifest(manifestUrl)
    if not manifest then
      log("Manifest error: " .. err)
      log("Falling back to embedded image.")
    else
      local bundle, downloadErr = downloadFiles(manifest)
      if not bundle then
        log("Download error: " .. downloadErr)
        log("Falling back to embedded image.")
      else
        image = bundle
      end
    end
  end

  if not image then
    image = EMBEDDED_IMAGE
  end

  if not promptConfirm() then
    log("Installation cancelled.")
    return
  end

  -- Ensure we have data before wiping the disk.
  formatDisk()
  installImage(image)
  -- Persist the installed manifest/image so users can verify what was applied.
  pcall(function()
    if type(textutils) == "table" and textutils.serializeJSON then
      writeFile("/arcadesys_installed_manifest.json", textutils.serializeJSON(image))
    else
      writeFile("/arcadesys_installed_manifest.json", "{ \"name\": \"" .. tostring(image.name) .. "\", \"version\": \"" .. tostring(image.version) .. "\" }")
    end
  end)
  log("Installation complete.")
  summarizeInstall(image)
  print("")
  term.write("Press Enter to reboot (or type 'cancel' to stay): ")
  local resp = string.lower(read() or "")
  if resp == "cancel" or resp == "c" or resp == "no" then
    log("Reboot skipped by user.")
    return
  end
  log("Rebooting...")
  sleep(1)
  os.reboot()
end

main()
