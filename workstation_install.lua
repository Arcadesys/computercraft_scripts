-- Arcadesys Essentials Installer (Computer)
-- Installs AE2 monitor + Factory Planner
local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/"
local ROOTS = { "arcade", "factory", "lib", "tools", "ui", "kiosk.lua", "games" }
local files = {
    "ae2_me_bridge_monitor.lua",
    "factory_planner.lua",
    "lib/lib_cards.lua",
    "lib/lib_designer.lua",
    "lib/lib_diagnostics.lua",
    "lib/lib_farming.lua",
    "lib/lib_fs.lua",
    "lib/lib_fuel.lua",
    "lib/lib_games.lua",
    "lib/lib_gps.lua",
    "lib/lib_initialize.lua",
    "lib/lib_inventory.lua",
    "lib/lib_items.lua",
    "lib/lib_json.lua",
    "lib/lib_license.lua",
    "lib/lib_logger.lua",
    "lib/lib_menu.lua",
    "lib/lib_mining.lua",
    "lib/lib_monitor.lua",
    "lib/lib_movement.lua",
    "lib/lib_navigation.lua",
    "lib/lib_network.lua",
    "lib/lib_orientation.lua",
    "lib/lib_parser.lua",
    "lib/lib_placement.lua",
    "lib/lib_reporter.lua",
    "lib/lib_schema.lua",
    "lib/lib_startup.lua",
    "lib/lib_strategy_branchmine.lua",
    "lib/lib_strategy_excavate.lua",
    "lib/lib_strategy_farm.lua",
    "lib/lib_strategy_tunnel.lua",
    "lib/lib_strategy.lua",
    "lib/lib_string.lua",
    "lib/lib_table.lua",
    "lib/lib_ui.lua",
    "lib/lib_wizard.lua",
    "lib/lib_world.lua",
    "lib/lib_worldstate.lua",
    "lib/log.lua",
    "lib/version.lua",
    "installer.lua",
    "startup.lua",
    "arcadesys_installer.lua",
    "pocket_os_install.lua",
    "pocket_menu.lua",
    "workstation_menu.lua",
}

local function cleanup()
    for _, root in ipairs(ROOTS) do
        if fs.exists("/" .. root) then
            fs.delete("/" .. root)
        end
    end
end

local function download(path)
    local url = BASE_URL .. path
    local response = http.get(url)
    if not response then
        printError("Failed to download " .. path)
        return false
    end
    local content = response.readAll()
    response.close()
    local installPath = "/" .. path
    local dir = fs.getDir(installPath)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local file = fs.open(installPath, "w")
    if not file then
        printError("Cannot write " .. installPath)
        return false
    end
    file.write(content)
    file.close()
    return true
end

print("Arcadesys Essentials installer (Computer)")
local existing = fs.exists("/arcade") or fs.exists("/factory")
if existing then
    print("Existing install detected. Refreshing...")
else
    print("Fresh install.")
end
cleanup()
local success, fail = 0, 0
for _, file in ipairs(files) do
    if download(file) then
        success = success + 1
    else
        fail = fail + 1
    end
    sleep(0.05)
end
print(string.format("Done. Success: %d, Failed: %d", success, fail))
print("Rebooting in 2 seconds...")
sleep(2)
os.reboot()
