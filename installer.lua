-- installer.lua
-- Arcadesys Unified Installer
-- Downloads packaged files from a configurable HTTP endpoint, verifies checksums,
-- installs them into /lib, /arcade, and /factory, and regenerates startup.lua.

local DEFAULT_ENDPOINT = "https://arcadesys.invalid/latest"
local MANIFEST_NAME = "manifest.json"
local METADATA_PATH = "/.arcadesys_install.json"

local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

local function printHeader()
    clear()
    print("========================================")
    print("       ARCADESYS UNIFIED INSTALLER      ")
    print("========================================")
    print("")
end

local function detectPlatform()
    if turtle then
        return "turtle"
    else
        return "computer"
    end
end

local function parseArgs()
    local args = {...}
    local opts = {
        endpoint = DEFAULT_ENDPOINT,
        update = false,
    }

    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "--endpoint" then
            opts.endpoint = args[i + 1]
            i = i + 1
        elseif arg == "--update" then
            opts.update = true
        end
        i = i + 1
    end

    return opts
end

local function httpAvailable()
    return http and http.get and http.request
end

local function readHttpResponse(handle)
    if not handle then return nil end
    local content = handle.readAll()
    handle.close()
    return content
end

local function fetchUrl(url)
    local handle = http.get(url)
    if not handle then
        error("HTTP GET failed: " .. url)
    end

    local body = readHttpResponse(handle)
    if not body then
        error("Empty response from: " .. url)
    end

    return body
end

local function loadManifest(endpoint)
    local manifestUrl = endpoint
    if string.sub(manifestUrl, -1) ~= "/" then
        manifestUrl = manifestUrl .. "/"
    end
    manifestUrl = manifestUrl .. MANIFEST_NAME

    print("Downloading manifest from " .. manifestUrl)
    local raw = fetchUrl(manifestUrl)

    local ok, manifest = pcall(textutils.unserialiseJSON, raw)
    if not ok or not manifest then
        error("Failed to parse manifest JSON")
    end

    if type(manifest.files) ~= "table" then
        error("Manifest missing files list")
    end

    manifest.version = manifest.version or "unknown"
    return manifest
end

local function loadMetadata()
    if not fs.exists(METADATA_PATH) then
        return nil
    end

    local handle = fs.open(METADATA_PATH, "r")
    local content = handle.readAll()
    handle.close()

    local ok, data = pcall(textutils.unserialiseJSON, content)
    if ok then
        return data
    end

    return nil
end

local function saveMetadata(metadata)
    local handle = fs.open(METADATA_PATH, "w")
    handle.write(textutils.serialiseJSON(metadata))
    handle.close()
end

local function ensureAllowedPath(path)
    if string.sub(path, 1, 1) ~= "/" then
        path = "/" .. path
    end

    local root = string.match(path, "^/([^/]+)")
    if root ~= "lib" and root ~= "arcade" and root ~= "factory" then
        error("Manifest tried to write outside allowed paths: " .. path)
    end

    return path
end

local function shouldInstallForPlatform(fileEntry, platform)
    if type(fileEntry.targets) ~= "table" or #fileEntry.targets == 0 then
        return true
    end

    for _, target in ipairs(fileEntry.targets) do
        if target == platform then
            return true
        end
    end

    return false
end

local function validateChecksum(content, checksum)
    if not checksum then
        return true
    end

    local digest = textutils.sha256(content)
    return digest == checksum
end

local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir and dir ~= "" then
        fs.makeDir(dir)
    end

    local handle = fs.open(path, "w")
    handle.write(content)
    handle.close()
end

local function buildFileUrl(baseEndpoint, fileEntry)
    if fileEntry.url and string.match(fileEntry.url, "^https?://") then
        return fileEntry.url
    end

    local base = baseEndpoint
    if string.sub(base, -1) ~= "/" then
        base = base .. "/"
    end

    if fileEntry.url then
        return base .. fileEntry.url
    end

    return base .. fileEntry.path
end

local function installFiles(manifest, endpoint, platform)
    for _, fileEntry in ipairs(manifest.files) do
        if shouldInstallForPlatform(fileEntry, platform) then
            if not fileEntry.path or not fileEntry.checksum then
                error("Manifest entry missing required fields")
            end

            local destination = ensureAllowedPath(fileEntry.path)
            local fileUrl = buildFileUrl(endpoint, fileEntry)

            print("Downloading " .. destination .. " from " .. fileUrl)
            local content = fetchUrl(fileUrl)

            if not validateChecksum(content, fileEntry.checksum) then
                error("Checksum validation failed for " .. destination)
            end

            writeFile(destination, content)
            print("Installed " .. destination)
        end
    end
end

local function regenerateStartup()
    print("Regenerating startup.lua...")
    local startupContent = [[
-- startup.lua
-- Auto-generated by Arcadesys Installer

local platform = turtle and "turtle" or "computer"

-- Add lib and arcade to package path
package.path = package.path .. ";/lib/?.lua;/arcade/?.lua;/factory/?.lua"

if platform == "turtle" then
    if fs.exists("/factory/factory.lua") then
        shell.run("/factory/factory.lua")
    else
        print("Factory agent not found.")
    end
else
    if fs.exists("/arcade/arcade_shell.lua") then
        shell.run("/arcade/arcade_shell.lua")
    else
        print("ArcadeOS not found.")
    end
end
]]

    writeFile("/startup.lua", startupContent)
end

local function install()
    if not httpAvailable() then
        error("HTTP API is not available. Please enable it in ComputerCraft settings.")
    end

    local opts = parseArgs()
    printHeader()

    local platform = detectPlatform()
    print("Detected Platform: " .. string.upper(platform))
    print("")

    print("Using endpoint: " .. opts.endpoint)
    print("")

    local manifest = loadManifest(opts.endpoint)
    local metadata = loadMetadata()

    if metadata and metadata.version == manifest.version and metadata.endpoint == opts.endpoint and not opts.update then
        print("Already up to date (version " .. manifest.version .. ")")
        print("Use --update to force reinstallation.")
        return
    end

    installFiles(manifest, opts.endpoint, platform)

    regenerateStartup()

    saveMetadata({
        version = manifest.version,
        endpoint = opts.endpoint,
        installedAt = os.epoch("utc"),
    })

    print("")
    print("Installation Complete!")
    print("Rebooting in 3 seconds...")
    os.sleep(3)
    os.reboot()
end

install()
