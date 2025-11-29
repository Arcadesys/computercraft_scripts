-- Arcadesys Installer Launcher
-- Lets you install or update any Arcadesys OS profile from GitHub.

local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/"

local PROFILES = {
    { name = "Arcade OS (PC)", script = "arcade_os_install.lua" },
    { name = "Workstation OS", script = "workstation_install.lua" },
    { name = "Turtle/Factory OS", script = "turtle_os_install.lua" },
    { name = "Pocket Arcade OS", script = "pocket_os_installer.lua" },
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
    local body = res.readAll()
    res.close()

    local handle = fs.open(dest, "w")
    if not handle then
        return false, "Cannot write " .. dest
    end
    handle.write(body)
    handle.close()
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

main()
