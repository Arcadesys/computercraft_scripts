-- builder.lua  -----------------------------------------------------------
-- Generic factory-cell builder for 16×16×9 modular design
-- Requires: modular_cell_manifest.lua in the same folder

local manifest = require("modular_cell_manifest")

-- CONFIG -----------------------------------------------------------------
local REFUEL_SLOT = 16           -- slot containing fuel
local RESTOCK_AT  = 50           -- go refuel if fuel < this
local VERBOSE     = true

-- UTILS ------------------------------------------------------------------
local function log(msg)
  if VERBOSE then print(msg) end
end

local function refuel()
  if turtle.getFuelLevel() > RESTOCK_AT then return end
  turtle.select(REFUEL_SLOT)
  turtle.refuel()
  log("Refueled: "..turtle.getFuelLevel())
end

local function placeBlock(block)
  if not block or block == "air" then return end
  for slot=1,15 do
    local detail = turtle.getItemDetail(slot)
    if detail and detail.name:find(block) then
      turtle.select(slot)
      if not turtle.placeDown() then turtle.digDown(); turtle.placeDown() end
      return
    end
  end
  log("⚠ Missing "..block)
end

-- MOVEMENT ---------------------------------------------------------------
local function forward()
  while not turtle.forward() do turtle.dig(); sleep(0.2) end
end

local function up()
  while not turtle.up() do turtle.digUp(); sleep(0.2) end
end

local function down()
  while not turtle.down() do turtle.digDown(); sleep(0.2) end
end

local function turnRight() turtle.turnRight() end
local function turnLeft()  turtle.turnLeft()  end

local function resetRow(zLen)
  turnLeft(); turnLeft()
  for i=1,zLen-1 do forward() end
  turnLeft(); forward(); turnLeft()
end

-- CORE BUILDER -----------------------------------------------------------
local function buildFromManifest()
  local size = manifest.meta.size
  local yCount, zCount, xCount = size.y, size.z or 16, size.x or 16

  for y=1,yCount do
    refuel()
    local layer = manifest.layers[y]
    if type(layer) == "string" and layer:match("SAME_AS") then
      local ref = tonumber(layer:match("%[(%d+)%]"))
      layer = manifest.layers[ref]
    end

    log("Building layer "..y)
    for z,row in ipairs(layer) do
      for x=1,#row do
        local sym = row:sub(x,x)
        local block = manifest.legend[sym]
        placeBlock(block)
        if x < #row then forward() end
      end
      if z < #layer then
        if z % 2 == 1 then turnRight(); forward(); turnRight()
        else turnLeft();  forward(); turnLeft()  end
      end
    end

    -- return to origin of layer
    if (#layer % 2 == 0) then turnRight(); for i=1,#layer-1 do forward() end; turnRight()
    else turnLeft();  for i=1,#layer-1 do forward() end; turnLeft()
    end

    up()
  end
  log("✅ Cell complete.")
end

-- MAIN -------------------------------------------------------------------
print("Starting builder for "..manifest.meta.name)
buildFromManifest()
print("Done.")
