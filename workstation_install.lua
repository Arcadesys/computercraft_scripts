-- Arcadesys Workstation Installer
-- Auto-generated at 2025-11-29T04:37:05.587Z
-- Refreshes or installs the workstation experience (computer)

local VARIANT = "workstation"
local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/"
local ROOTS = { "arcade", "factory", "lib", "tools", "ui", "kiosk.lua", "games" }
local files = {
    "ae2_drive_monitor.lua",
    "arcade/arcade_arcade.lua",
    "arcade/arcade_shell.lua",
    "arcade/arcade.lua",
    "arcade/arcadeos.lua",
    "arcade/boot.lua",
    "arcade/data/programs.lua",
    "arcade/data/valhelsia_blocks.lua",
    "arcade/games/artillery.lua",
    "arcade/games/blackjack.lua",
    "arcade/games/cantstop.lua",
    "arcade/games/idlecraft.lua",
    "arcade/games/slots.lua",
    "arcade/games/themes.lua",
    "arcade/games/videopoker.lua",
    "arcade/games/warlords.lua",
    "arcade/license_store.lua",
    "arcade/store.lua",
    "arcade/ui/renderer.lua",
    "arcade/video_player.lua",
    "factory_planner.lua",
    "factory/factory.lua",
    "factory/main.lua",
    "factory/state_blocked.lua",
    "factory/state_branchmine.lua",
    "factory/state_build.lua",
    "factory/state_check_requirements.lua",
    "factory/state_done.lua",
    "factory/state_error.lua",
    "factory/state_initialize.lua",
    "factory/state_mine.lua",
    "factory/state_potatofarm.lua",
    "factory/state_refuel.lua",
    "factory/state_restock.lua",
    "factory/state_treefarm.lua",
    "factory/turtle_os.lua",
    "games/arcade.lua",
    "kiosk.lua",
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
    "printer.lua",
    "startup.lua",
    "tools/install_sender.lua",
    "tools/receive_schema.lua",
    "ui/trash_config.lua",
}

local function persistExperience()
    local h = fs.open("experience.settings", "w")
    if h then
        h.write(textutils.serialize({ experience = VARIANT }))
        h.close()
    end
end

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

print("Arcadesys Workstation installer")
persistExperience()
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
