---@diagnostic disable: undefined-global
local function newPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
  return {
    x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3,
    c = c,
  }
end

local tank = {}
local bodyColor = colors.green
local turretColor = colors.lime

-- Helper to add a box
local function addBox(list, x, y, z, w, h, d, color)
    local x1, y1, z1 = x - w/2, y - h/2, z - d/2
    local x2, y2, z2 = x + w/2, y + h/2, z + d/2
    
    -- Front
    table.insert(list, newPoly(x1, y1, z1, x2, y1, z1, x2, y2, z1, color))
    table.insert(list, newPoly(x1, y1, z1, x2, y2, z1, x1, y2, z1, color))
    -- Back
    table.insert(list, newPoly(x1, y1, z2, x2, y2, z2, x2, y1, z2, color))
    table.insert(list, newPoly(x1, y1, z2, x2, y1, z2, x1, y2, z2, color))
    -- Top
    table.insert(list, newPoly(x1, y2, z1, x2, y2, z1, x2, y2, z2, color))
    table.insert(list, newPoly(x1, y2, z1, x2, y2, z2, x1, y2, z2, color))
    -- Bottom
    table.insert(list, newPoly(x1, y1, z1, x2, y1, z2, x2, y1, z1, color))
    table.insert(list, newPoly(x1, y1, z1, x1, y1, z2, x2, y1, z2, color))
    -- Left
    table.insert(list, newPoly(x1, y1, z1, x1, y2, z1, x1, y2, z2, color))
    table.insert(list, newPoly(x1, y1, z1, x1, y2, z2, x1, y1, z2, color))
    -- Right
    table.insert(list, newPoly(x2, y1, z1, x2, y2, z2, x2, y2, z1, color))
    table.insert(list, newPoly(x2, y1, z1, x2, y1, z2, x2, y2, z2, color))
end

addBox(tank, 0, 0, 0, 1, 0.5, 1.5, bodyColor) -- Body
addBox(tank, 0, 0.5, 0, 0.6, 0.4, 0.8, turretColor) -- Turret

return tank