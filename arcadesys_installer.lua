-- Arcadesys Installer Launcher
-- Lets you install or update any Arcadesys OS profile from GitHub.

local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/"

local PROFILES = {
    { name = "Essentials (AE2 Monitor + Factory Planner)", script = "workstation_install.lua" },
}

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function header()
    clear()
    print("========================================")
    print("         Arcadesys OS Installer         ")
    print("========================================")
    print("")
end

local function pause(msg)
    print("")
    print(msg or "Press Enter to continue...")
    read()
end

local function download(url, dest)
    local res, err = http.get(url)
    if not res then
        return false, err or "HTTP get failed"
    end
    local headers = res.getResponseHeaders() or {}
    local expectedSize = tonumber(headers["Content-Length"] or headers["content-length"] or 0)
    local free = fs.getFreeSpace(fs.getDir(dest) or "/") or 0

    -- Bail out early if we already know there is not enough space.
    if expectedSize > 0 and expectedSize > free then
        res.close()
        return false, string.format("Not enough space (%d needed, %d free)", expectedSize, free)
    end

    local handle = fs.open(dest, "w")
    if not handle then
        res.close()
        return false, "Cannot write " .. dest
    end

    -- Stream the body to disk to avoid holding it all in memory and to detect space errors early.
    while true do
        local chunk = res.read(8192)
        if not chunk then break end

        -- Check free space periodically to fail fast if the disk is filling up mid-download.
        free = fs.getFreeSpace(fs.getDir(dest) or "/") or 0
        if #chunk > free then
            handle.close()
            res.close()
            fs.delete(dest)
            return false, "Not enough space while writing (disk full)"
        end

        handle.write(chunk)
    end

    handle.close()
    res.close()
    return true
end

local function runScript(path)
    local ok, err = pcall(function()
        shell.run(path)
    end)
    if not ok then
        print("Installer error: " .. tostring(err))
        pause()
    end
end

local function perform(profile, mode)
    header()
    print(mode .. " " .. profile.name)
    print("Fetching latest installer from GitHub...")

    local temp = "__arcadesys_installer_tmp.lua"
    fs.delete(temp)

    local ok, err = download(BASE_URL .. profile.script, temp)
    if not ok then
        print("Download failed: " .. tostring(err))
        pause("Press Enter to return to menu...")
        return
    end

    print("Running installer...")
    runScript(temp)
    fs.delete(temp)
end

local function pickProfile()
    while true do
        header()
        print("Select a profile:")
        for i, profile in ipairs(PROFILES) do
            print(string.format("  %d) %s", i, profile.name))
        end
        print(string.format("  %d) Exit", #PROFILES + 1))
        print("")
        io.write("> ")
        local choice = tonumber(read()) or 0
        if choice == #PROFILES + 1 then
            return nil
        end
        if PROFILES[choice] then
            return PROFILES[choice]
        end
    end
end

local function pickAction(profile)
    while true do
        header()
        print(profile.name)
        print("")
        print("  1) Install (fresh setup)")
        print("  2) Update (pull latest from GitHub)")
        print("  3) Back")
        print("")
        io.write("> ")
        local choice = tonumber(read()) or 0
        if choice == 1 then
            return "Install"
        elseif choice == 2 then
            return "Update"
        elseif choice == 3 then
            return nil
        end
    end
end

local function main()
    if not http then
        header()
        print("HTTP API is disabled. Enable it in ComputerCraft settings.")
        return
    end

    while true do
        local profile = pickProfile()
        if not profile then
            break
        end
        local action = pickAction(profile)
        if action then
            perform(profile, action)
        end
    end

    header()
    print("Goodbye!")
end

local function runWithMonitor(fn)
    local ok, monitorUtil = pcall(require, "lib_monitor")
    if ok and monitorUtil and monitorUtil.runOnMonitor then
        return monitorUtil.runOnMonitor(fn, { textScale = 0.5 })
    end
    return fn()
end

runWithMonitor(main)
