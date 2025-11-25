-- Arcadesys Network Installer
-- Auto-generated at 2025-11-24T23:11:52.899Z
-- Downloads files from GitHub to bypass file size limits

local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/appify/"
local files = {
    "arcade/arcade_shell.lua",
    "arcade/arcade.lua",
    "arcade/arcadeos.lua",
    "arcade/data/programs.lua",
    "arcade/data/valhelsia_blocks.lua",
    "arcade/games/cantstop.lua",
    "arcade/games/idlecraft.lua",
    "arcade/games/slots.lua",
    "arcade/games/themes.lua",
    "arcade/license_store.lua",
    "arcade/store.lua",
    "arcade/ui/renderer.lua",
    "factory/factory.lua",
    "factory/harness_common.lua",
    "factory/harness_fuel.lua",
    "factory/harness_initialize.lua",
    "factory/harness_inventory.lua",
    "factory/harness_logger.lua",
    "factory/harness_movement.lua",
    "factory/harness_navigation_steps.lua",
    "factory/harness_navigation.lua",
    "factory/harness_parser_data.lua",
    "factory/harness_parser.lua",
    "factory/harness_placement_data.lua",
    "factory/harness_placement.lua",
    "factory/harness_worldstate.lua",
    "factory/main.lua",
    "factory/state_blocked.lua",
    "factory/state_build.lua",
    "factory/state_check_requirements.lua",
    "factory/state_done.lua",
    "factory/state_error.lua",
    "factory/state_initialize.lua",
    "factory/state_mine.lua",
    "factory/state_refuel.lua",
    "factory/state_restock.lua",
    "factory/state_treefarm.lua",
    "factory/turtle_os.lua",
    "games/arcade.lua",
    "installer.lua",
    "lib/lib_designer.lua",
    "lib/lib_diagnostics.lua",
    "lib/lib_fs.lua",
    "lib/lib_fuel.lua",
    "lib/lib_games.lua",
    "lib/lib_gps.lua",
    "lib/lib_initialize.lua",
    "lib/lib_inventory_utils.lua",
    "lib/lib_inventory.lua",
    "lib/lib_items.lua",
    "lib/lib_json.lua",
    "lib/lib_logger.lua",
    "lib/lib_mining.lua",
    "lib/lib_movement.lua",
    "lib/lib_navigation.lua",
    "lib/lib_orientation.lua",
    "lib/lib_parser.lua",
    "lib/lib_placement.lua",
    "lib/lib_reporter.lua",
    "lib/lib_schema.lua",
    "lib/lib_strategy_branchmine.lua",
    "lib/lib_strategy_excavate.lua",
    "lib/lib_strategy_farm.lua",
    "lib/lib_strategy_tunnel.lua",
    "lib/lib_strategy.lua",
    "lib/lib_string.lua",
    "lib/lib_table.lua",
    "lib/lib_ui.lua",
    "lib/lib_world.lua",
    "lib/lib_worldstate.lua",
    "lib/log.lua",
    "startup.lua",
}

print("Starting Network Install...")
print("Source: " .. BASE_URL)

local function download(path)
    local url = BASE_URL .. path
    print("Downloading " .. path .. "...")
    local response = http.get(url)
    if not response then
        printError("Failed to download " .. path)
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    local file = fs.open(path, "w")
    if not file then
        printError("Failed to write " .. path)
        return false
    end
    
    file.write(content)
    file.close()
    return true
end

local successCount = 0
local failCount = 0

for _, file in ipairs(files) do
    if download(file) then
        successCount = successCount + 1
    else
        failCount = failCount + 1
    end
    sleep(0.1)
end

print("")
print("Install Complete!")
print("Downloaded: " .. successCount)
print("Failed: " .. failCount)

print("Verifying installation...")
local errors = 0
for _, file in ipairs(files) do
    if not fs.exists(file) then
        printError("Missing: " .. file)
        errors = errors + 1
    end
end
if failCount == 0 and errors == 0 then
    print("Verification successful.")
    print("Reboot or run startup to launch.")
else
    print("Installation issues detected.")
    if failCount > 0 then print("Failed downloads: " .. failCount) end
    if errors > 0 then print("Missing files: " .. errors) end
end
