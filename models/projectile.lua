local function newPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
  return {
    x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3,
    c = c,
  }
end

local proj = {}
local color = colors.red

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

addBox(proj, 0, 0, 0, 0.2, 0.2, 0.2, color)

return proj