-- arcadesys_installer.lua
-- Pocket-focused ArcadeOS installer with a built-in music screamer helper

local VARIANT = "pocket"
local EXPERIENCE = "arcade" -- What we persist so startup.lua boots into the arcade shell
local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/"
local MUSIC_HELPER_PATH = "/music_screamer.lua"
local ROOTS = { "arcade", "lib", "games", "kiosk.lua" }

local files = {
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
    "startup.lua",
}

local function persistExperience()
    local h = fs.open("experience.settings", "w")
    if h then
        h.write(textutils.serialize({ experience = EXPERIENCE }))
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

local function writeMusicHelper()
    local helper = [[
-- music_screamer.lua
-- Tiny speaker stress-test for pocket installs. Press Ctrl+T to stop.

local speaker = peripheral and peripheral.find and peripheral.find("speaker") or nil
if not speaker then
    print("No speaker found. Place/attach one, then re-run.")
    return
end

local tones = {
    { inst = "pling", pitch = 4 },
    { inst = "bell", pitch = 6 },
    { inst = "hat", pitch = 3 },
    { inst = "bd", pitch = 2 },
    { inst = "snare", pitch = 5 },
}

print("Screaming music... Ctrl+T to quiet it down.")
while true do
    for _, tone in ipairs(tones) do
        speaker.playNote(tone.inst, 3, tone.pitch)
        sleep(0.05)
    end
end
]]

    local h = fs.open(MUSIC_HELPER_PATH, "w")
    if not h then
        printError("Could not write " .. MUSIC_HELPER_PATH)
        return
    end
    h.write(helper)
    h.close()
end

local function celebrate()
    local speaker = peripheral and peripheral.find and peripheral.find("speaker") or nil
    if not speaker or not speaker.playNote then
        return
    end

    local sequence = {
        { "pling", 3, 6 },
        { "pling", 3, 8 },
        { "bell", 2, 10 },
    }

    for _, item in ipairs(sequence) do
        speaker.playNote(item[1], item[2], item[3])
        sleep(0.08)
    end
end

print("Arcadesys Pocket installer (music screaming edition)")
print("This will refresh /arcade and /lib, then drop a music_screamer helper.")

persistExperience()
local existing = fs.exists("/arcade") and fs.exists("/lib")
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

writeMusicHelper()

print(string.format("Done. Success: %d, Failed: %d", success, fail))
if fail == 0 then
    print("music_screamer.lua ready. Attach a speaker and run it to let the pocket yell.")
    celebrate()
end

print("Rebooting in 2 seconds...")
sleep(2)
os.reboot()
