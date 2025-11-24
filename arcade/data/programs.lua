local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/arcade/"

-- Pricing Configuration
-- Adjust prices here. Set to 0 for free downloads.
local PRICING = {
    blackjack = 0,
    slots = 0,
    cantstop = 0,
    idlecraft = 0,
    artillery = 0,
    factory_planner = 0,
    inv_manager = 0,
    store = 0,
    themes = 0
}

local programs = {
  {
    id = "blackjack",
    name = "Blackjack",
    path = "games/blackjack.lua",
    price = PRICING.blackjack,
    description = "Beat the dealer in a race to 21.",
    category = "games",
    url = BASE_URL .. "games/blackjack.lua"
  },
  {
    id = "slots",
    name = "Slots",
    path = "games/slots.lua",
    price = PRICING.slots,
    description = "Spin reels for quick wins.",
    category = "games",
    url = BASE_URL .. "games/slots.lua"
  },
  {
    id = "cantstop",
    name = "Can't Stop",
    path = "games/cantstop.lua",
    price = PRICING.cantstop,
    description = "Push your luck dice classic.",
    category = "games",
    url = BASE_URL .. "games/cantstop.lua"
  },
  {
    id = "idlecraft",
    name = "IdleCraft",
    path = "games/idlecraft.lua",
    price = PRICING.idlecraft,
    description = "AFK-friendly cobble empire.",
    category = "games",
    url = BASE_URL .. "games/idlecraft.lua"
  },
  {
    id = "artillery",
    name = "Artillery",
    path = "games/artillery.lua",
    price = PRICING.artillery,
    description = "2-player tank battle.",
    category = "games",
    url = BASE_URL .. "games/artillery.lua"
  },
  {
    id = "factory_planner",
    name = "Factory Planner",
    path = "factory_planner.lua",
    price = PRICING.factory_planner,
    description = "Design factory layouts for turtles.",
    category = "actions",
    url = BASE_URL .. "factory_planner.lua"
  },
  {
    id = "inv_manager",
    name = "Inventory Manager",
    path = "inv_manager.lua",
    price = PRICING.inv_manager,
    description = "Manage inventory (Coming Soon).",
    category = "actions",
    prodReady = false,
    url = BASE_URL .. "inv_manager.lua"
  },
  {
    id = "store",
    name = "App Store",
    path = "store.lua",
    price = PRICING.store,
    description = "Download new games.",
    category = "system",
    url = BASE_URL .. "store.lua"
  },
  {
    id = "themes",
    name = "Themes",
    path = "games/themes.lua",
    price = PRICING.themes,
    description = "Change system theme.",
    category = "system",
    url = BASE_URL .. "games/themes.lua"
  },
}

return programs
