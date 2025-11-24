local BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/arcade/"

local programs = {
  {
    id = "blackjack",
    name = "Blackjack",
    path = "games/blackjack.lua",
    price = 5,
    description = "Beat the dealer in a race to 21.",
    category = "games",
    url = BASE_URL .. "games/blackjack.lua"
  },
  {
    id = "slots",
    name = "Slots",
    path = "games/slots.lua",
    price = 3,
    description = "Spin reels for quick wins.",
    category = "games",
    url = BASE_URL .. "games/slots.lua"
  },
  {
    id = "cantstop",
    name = "Can't Stop",
    path = "games/cantstop.lua",
    price = 4,
    description = "Push your luck dice classic.",
    category = "games",
    url = BASE_URL .. "games/cantstop.lua"
  },
  {
    id = "idlecraft",
    name = "IdleCraft",
    path = "games/idlecraft.lua",
    price = 6,
    description = "AFK-friendly cobble empire.",
    category = "games",
    url = BASE_URL .. "games/idlecraft.lua"
  },
  {
    id = "artillery",
    name = "Artillery",
    path = "games/artillery.lua",
    price = 5,
    description = "2-player tank battle.",
    category = "games",
    url = BASE_URL .. "games/artillery.lua"
  },
  {
    id = "factory_planner",
    name = "Factory Planner",
    path = "factory_planner.lua",
    price = 0,
    description = "Design factory layouts for turtles.",
    category = "actions",
    url = BASE_URL .. "factory_planner.lua"
  },
  {
    id = "inv_manager",
    name = "Inventory Manager",
    path = "inv_manager.lua",
    price = 0,
    description = "Manage inventory (Coming Soon).",
    category = "actions",
    prodReady = false,
    url = BASE_URL .. "inv_manager.lua"
  },
  {
    id = "store",
    name = "App Store",
    path = "games/store.lua",
    price = 0,
    description = "Download new games.",
    category = "system",
    url = BASE_URL .. "games/store.lua"
  },
  {
    id = "themes",
    name = "Themes",
    path = "games/themes.lua",
    price = 0,
    description = "Change system theme.",
    category = "system",
    url = BASE_URL .. "games/themes.lua"
  },
}

return programs
