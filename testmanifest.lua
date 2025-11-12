-- Mini Cell Manifest (4x4x4)
-- For testing build-manifest, SAME_AS expansion, legend, and layer parsing.

local manifest = {
  meta = {
    name = "mini_test_cell",
    size = {x=4, y=4, z=4},
    doors = {
      north = {x=2, z=1},
      south = {x=2, z=4},
    },
    buses = {
      energy_height = 3,
      item_height   = 4,
    },
  },

  layers = {
    ----------------------------------------------------------------------
    -- y = 1 : floor (4x4)
    ----------------------------------------------------------------------
    [1] = {
      "WWWW",
      "WFFW",
      "WFFW",
      "WWWW",
    },

    ----------------------------------------------------------------------
    -- y = 2 : plain walls
    ----------------------------------------------------------------------
    [2] = {
      "WWWW",
      "W..W",
      "W..W",
      "WWWW",
    },

    ----------------------------------------------------------------------
    -- y = 3 : energy bus through east/west walls
    ----------------------------------------------------------------------
    [3] = {
      "WWWW",
      "WE.E",
      "WE.E",
      "WWWW",
    },

    ----------------------------------------------------------------------
    -- y = 4 : ceiling w/ item bus ring
    ----------------------------------------------------------------------
    [4] = {
      "WWWW",
      "WP.P",
      "WP.P",
      "WWWW",
    },
  },

  legend = {
    W = "minecraft:stone_bricks",
    F = "minecraft:polished_andesite",
    E = "mekanism:basic_universal_cable",
    P = "mekanism:basic_logistical_transporter",
    ["."] = "minecraft:air",
  },
}

return manifest
