-- installer.lua
-- Bootstrapper that always pulls the latest Arcadesys installer from GitHub,
-- then launches it so you can install or update any profile.

local REMOTE_INSTALLER = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/arcadesys_installer.lua"
local LOCAL_INSTALLER = "arcadesys_installer.lua"

local function bail(msg)
    print(msg or "Install aborted.")
    return
end

if not http then
    bail("HTTP API is disabled. Enable it in ComputerCraft settings.")
    return
end

local function download(url, dest)
    local res, err = http.get(url)
    if not res then
        return false, err or "HTTP request failed"
    end

    local handle = fs.open(dest, "w")
    if not handle then
        res.close()
        return false, "Cannot open " .. dest .. " for writing"
    end

    while true do
        local chunk = res.read(8192)
        if not chunk then break end
        handle.write(chunk)
    end

    handle.close()
    res.close()
    return true
end

print("Fetching latest Arcadesys installer...")
fs.delete(LOCAL_INSTALLER)
local ok, err = download(REMOTE_INSTALLER, LOCAL_INSTALLER)
if not ok then
    bail("Download failed: " .. tostring(err))
    return
end

print("Running installer menu...")
local okRun, runErr = pcall(function()
    shell.run(LOCAL_INSTALLER)
end)

if not okRun then
    bail("Installer error: " .. tostring(runErr))
end
