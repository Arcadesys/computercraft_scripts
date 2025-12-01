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
