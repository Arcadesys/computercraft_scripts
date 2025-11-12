-- Flat require: run this script from the same directory as the manifest
local manifest = require("modularfactorymanifest")

local CELL_SIZE = 16
local ENERGY_Y  = manifest.meta.buses.energy_height
local ITEM_Y    = manifest.meta.buses.item_height

-- Cell registry
cells = {
  {x=0, z=0},
  {x=16, z=0},
  {x=0, z=16},
  {x=16, z=16},
}

----------------------------------------------------------
-- 1. Spawn or call builder turtles to construct cells
----------------------------------------------------------
function buildAllCells()
  for _, cell in ipairs(cells) do
    moveTo(cell.x, cell.z)
    deployBuilder(cell)
  end
end

function deployBuilder(cell)
  -- Optional: drop a turtle with manifest + materials
  broadcast("BUILD", cell)
end

----------------------------------------------------------
-- 2. Bridge function for energy bus between neighbors
----------------------------------------------------------
function bridgeEnergy(cellA, cellB, direction)
  -- Assume cells share a wall and are aligned.
  local offsetX, offsetZ = 0, 0
  if direction == "east"  then offsetX = CELL_SIZE
  elseif direction == "west" then offsetX = -CELL_SIZE
  elseif direction == "south" then offsetZ = CELL_SIZE
  elseif direction == "north" then offsetZ = -CELL_SIZE
  end

  local x = cellA.x + (direction == "east" and CELL_SIZE or 1)
  local zStart = cellA.z + 1
  local zEnd   = cellA.z + CELL_SIZE - 2

  moveTo(x, ENERGY_Y, zStart)
  for z = zStart, zEnd do
    digForward()              -- open the wall gap
    place("mekanism_cable_basic")  -- lay energy cable
    forward()
  end
end

----------------------------------------------------------
-- 3. Auto-detect adjacent cells and bridge them
----------------------------------------------------------
function bridgeAll()
  for _, cellA in ipairs(cells) do
    for _, cellB in ipairs(cells) do
      if cellB ~= cellA then
        -- east-west neighbors
        if cellB.x == cellA.x + CELL_SIZE and cellB.z == cellA.z then
          bridgeEnergy(cellA, cellB, "east")
        end
        -- north-south neighbors
        if cellB.z == cellA.z + CELL_SIZE and cellB.x == cellA.x then
          bridgeEnergy(cellA, cellB, "south")
        end
      end
    end
  end
end

----------------------------------------------------------
-- 4. Main workflow
----------------------------------------------------------
buildAllCells()
bridgeAll()
announce("Factory grid complete!")
