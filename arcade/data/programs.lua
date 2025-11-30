local REPO_ROOT = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/"
local EXPERIENCE_FILE = "experience.settings"
local DEFAULT_EXPERIENCE = "arcade"

local function loadExperience()
    if not fs or type(fs.exists) ~= "function" or type(fs.open) ~= "function" then
        return nil
    end

    if not fs.exists(EXPERIENCE_FILE) then
        return nil
    end

    local handle = fs.open(EXPERIENCE_FILE, "r")
    if not handle then
        return nil
    end

    local ok, data = pcall(function()
        local contents = handle.readAll()
        handle.close()
        return textutils.unserialize(contents)
    end)

    if ok and type(data) == "table" and type(data.experience) == "string" then
        return data.experience
    end

    return nil
end

local experience = loadExperience() or DEFAULT_EXPERIENCE

-- Pricing Configuration
-- Adjust prices here. Set to 0 for free downloads.
local PRICING = {
    blackjack = 0,
    slots = 0,
    videopoker = 0,
    cantstop = 0,
    idlecraft = 0,
    artillery = 0,
    factory_planner = 0,
    inv_manager = 0,
    store = 0,
    themes = 0,
    video_player = 0
}

local function configureProgram(def)
    if def.remotePath == false then
        def.url = nil
    else
        local remotePath = def.remotePath
        if not remotePath or remotePath == "" then
            local localPath = def.path or ""
            if localPath:sub(1, 1) == "/" then
                localPath = localPath:sub(2)
            end
            remotePath = "arcade/" .. localPath
        end
        if remotePath:sub(1, 1) == "/" then
            remotePath = remotePath:sub(2)
        end
        def.url = REPO_ROOT .. remotePath
    end
    def.remotePath = nil
    return def
end

local programs = {
  configureProgram({
    id = "blackjack",
    name = "Blackjack",
    path = "games/blackjack.lua",
    price = PRICING.blackjack,
    description = "Beat the dealer in a race to 21.",
    category = "games",
    remotePath = "arcade/games/blackjack.lua"
  }),
  configureProgram({
    id = "slots",
    name = "Slots",
    path = "games/slots.lua",
    price = PRICING.slots,
    description = "Spin reels for quick wins.",
    category = "games",
  }),
  configureProgram({
    id = "videopoker",
    name = "Video Poker",
    path = "games/videopoker.lua",
    price = PRICING.videopoker,
    description = "Jacks or Better poker.",
    category = "games",
  }),
  configureProgram({
    id = "cantstop",
    name = "Can't Stop",
    path = "games/cantstop.lua",
    price = PRICING.cantstop,
    description = "Push your luck dice classic.",
    category = "games",
  }),
  configureProgram({
    id = "idlecraft",
    name = "IdleCraft",
    path = "games/idlecraft.lua",
    price = PRICING.idlecraft,
    description = "AFK-friendly cobble empire.",
    category = "games",
  }),
  configureProgram({
    id = "artillery",
    name = "Artillery",
    path = "games/artillery.lua",
    price = PRICING.artillery,
    description = "2-player tank battle.",
    category = "games",
    remotePath = "arcade/games/artillery.lua"
  }),
  configureProgram({
    id = "factory_planner",
    name = "Factory Planner",
    path = "factory_planner.lua",
    price = PRICING.factory_planner,
    description = "Design factory layouts for turtles.",
    category = "actions",
    remotePath = "factory_planner.lua"
  }),
  configureProgram({
    id = "inv_manager",
    name = "Inventory Manager",
    path = "inv_manager.lua",
    price = PRICING.inv_manager,
    description = "Manage inventory (Coming Soon).",
    category = "actions",
    prodReady = false,
    remotePath = false
  }),
  configureProgram({
    id = "store",
    name = "App Store",
    path = "store.lua",
    price = PRICING.store,
    description = "Download and update apps.",
    category = "system",
  }),
  configureProgram({
    id = "themes",
    name = "Themes",
    path = "games/themes.lua",
    price = PRICING.themes,
    description = "Change system theme.",
    category = "system",
  }),
  configureProgram({
    id = "video_player",
    name = "Video Player",
    path = "video_player.lua",
    price = PRICING.store,
    description = "Stream NFP videos from a manifest URL.",
    category = "tools",
    remotePath = "arcade/video_player.lua"
  }),
}

local function shouldInclude(program)
  if experience == "workstation" and program.category == "games" then
    return false
  end
  return true
end

local filtered = {}
for _, program in ipairs(programs) do
  if shouldInclude(program) then
    table.insert(filtered, program)
  end
end

return filtered
