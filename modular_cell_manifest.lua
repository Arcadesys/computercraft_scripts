-- modular_cell_manifest.lua  --------------------------------------------
-- Arcades Modular Factory Cell Blueprint
-- 16x16 footprint (chunk aligned), 9 blocks tall
-- Features:
--   - 14x14 interior
--   - power bus through east/west walls @ Y=5
--   - item bus ring along interior ceiling @ Y=9
--   - doorways north/south (2x3)
--   - placeholder space for future data jack

local manifest = {
  meta = {
    name = "modular_cell",
    size = {x=16, y=9, z=16},
    doors = {
      north = {x=8, z=1},  -- centered doorway
      south = {x=8, z=16},
    },
    buses = {
      energy_height = 5,
      item_height   = 9,
    },
  },

  ------------------------------------------------------------------------
  -- Layer maps
  -- Each layer is a 16-character string per row (Z direction)
  -- W = wall, F = floor, E = energy bus, P = item pipe, . = air
  ------------------------------------------------------------------------
  layers = {
    ----------------------------------------------------------------------
    -- y = 1 : floor
    ----------------------------------------------------------------------
    [1] = {
      "WWWWWWWWWWWWWWWW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WFFFFFFFFFFFFFFW",
      "WWWWWWWWWWWWWWWW",
    },

    ----------------------------------------------------------------------
    -- y = 2–4 : plain wall layers
    ----------------------------------------------------------------------
    [2] = {
      "WWWWWWWWWWWWWWWW",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "W..............W",
      "WFFFFFFFFFFFFFFW",
      "WWWWWWWWWWWWWWWW",
    },
    [3] = "SAME_AS[2]",
    [4] = "SAME_AS[2]",

    ----------------------------------------------------------------------
    -- y = 5 : energy bus through east/west walls
    ----------------------------------------------------------------------
    [5] = {
      "WWWWWWWWWWWWWWWW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WE.............EW",
      "WWWWWWWWWWWWWWWW",
    },

    ----------------------------------------------------------------------
    -- y = 6–8 : wall continuation
    ----------------------------------------------------------------------
    [6] = "SAME_AS[2]",
    [7] = "SAME_AS[2]",
    [8] = "SAME_AS[2]",

    ----------------------------------------------------------------------
    -- y = 9 : ceiling with item bus
    ----------------------------------------------------------------------
    [9] = {
      "WWWWWWWWWWWWWWWW",
      "WPEEEEEEEEEEEE PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WP.............PW",
      "WPEEEEEEEEEEEE PW",
      "WWWWWWWWWWWWWWWW",
    },
  },

  ------------------------------------------------------------------------
  -- Block mapping
  ------------------------------------------------------------------------
  legend = {
    W = "minecraft:stone_bricks",              -- structure
    F = "minecraft:polished_andesite",         -- floor
    E = "mekanism:basic_universal_cable",      -- energy bus
    P = "mekanism:basic_logistical_transporter", -- item bus
    ["."] = "minecraft:air",
  },
}

return manifest
