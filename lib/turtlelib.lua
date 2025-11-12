-- lib/turtlelib.lua
-- Reusable turtle helpers for movement, fuel, inventory, and placement.
--
-- Why this exists
-- - Consolidates the common patterns from tools/branchminer.lua and factory/factorybuilder.lua
-- - Safe movement with dig/attack retries and fuel checks
-- - Simple, composable inventory and placement utilities
-- - Optional fuel restock from adjacent storage
--
-- How to use
--   local tlib = require("lib.turtlelib")
--   tlib.setConfig({ fuelThreshold = 80 })
--   tlib.forward()           -- moves forward with safety (dig/attack)
--   tlib.placeDown("minecraft:cobblestone")
--
-- Lua tips (brief)
-- - Use `local` to avoid polluting globals; return a table of functions at the end.
-- - Tables are used as objects; prefer small, focused helpers.
-- - When in doubt, nil-check optional values before indexing.

local M = {}

-- Configuration with sensible defaults; override via setConfig().
local CONFIG = {
  verbose = false,            -- extra logs
  moveMaxRetries = 20,        -- attempts for movement before giving up
  retryDelay = 0.2,           -- seconds between dig/attack retries
  fuelThreshold = 100,        -- minimum fuel to try to maintain
  preferFuelSlot = 16,        -- slot typically used for fuel
  restockMaxPulls = 12,       -- max suck attempts per container side when restocking fuel/items
}

-- Internal logging helpers --------------------------------------------------
local function vprint(msg, ...)
  if not CONFIG.verbose then return end
  if select('#', ...) > 0 then
    print("[turtlelib] " .. string.format(msg, ...))
  else
    print("[turtlelib] " .. tostring(msg))
  end
end

function M.setConfig(user)
  user = user or {}
  for k, v in pairs(user) do CONFIG[k] = v end
  return CONFIG
end

function M.getConfig()
  return CONFIG
end

-- Fuel helpers --------------------------------------------------------------
local function isFuelUnlimited()
  if not turtle.getFuelLimit then return false end
  local lim = turtle.getFuelLimit()
  return lim == "unlimited" or lim == math.huge
end
M.isFuelUnlimited = isFuelUnlimited

local function ensureFuel(minLevel)
  if isFuelUnlimited() then return true end
  local target = math.max(minLevel or 1, CONFIG.fuelThreshold or 0)
  if (turtle.getFuelLevel() or 0) >= target then return true end

  -- Try preferred slot then scan all
  local selected = turtle.getSelectedSlot()
  local function trySlot(slot)
    if slot and slot >= 1 and slot <= 16 and turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      local consumed = false
      while turtle.refuel(1) do
        consumed = true
        if turtle.getFuelLevel() >= target then break end
      end
      return consumed
    end
    return false
  end

  if trySlot(CONFIG.preferFuelSlot) then
    turtle.select(selected)
    return true
  end
  for i = 1, 16 do
    if i ~= CONFIG.preferFuelSlot and trySlot(i) then
      turtle.select(selected)
      return true
    end
  end
  turtle.select(selected)
  return (turtle.getFuelLevel() or 0) >= (minLevel or 1)
end
M.ensureFuel = ensureFuel

-- Item/Inventory helpers ----------------------------------------------------
function M.tallyInventory()
  local totals = {}
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.name then totals[d.name] = (totals[d.name] or 0) + (d.count or 0) end
  end
  return totals
end

function M.countEmptySlots()
  local empty = 0
  for i = 1, 16 do if turtle.getItemCount(i) == 0 then empty = empty + 1 end end
  return empty
end

function M.isInventoryFull()
  return M.countEmptySlots() == 0
end

function M.selectSlot(predicate)
  predicate = predicate or function(_) return true end
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and predicate(d) then turtle.select(i); return i, d end
  end
  return nil
end

-- Treat Mekanism tiered items as a family (basic/advanced/elite/ultimate)
local function splitModAndId(name)
  if not name then return nil, nil end
  local mod, id = name:match("([^:]+):(.+)")
  return mod, id
end

local function stripTierPrefix(id)
  if not id then return nil end
  return (id
    :gsub("^basic_", "")
    :gsub("^advanced_", "")
    :gsub("^elite_", "")
    :gsub("^ultimate_", ""))
end

function M.isSameFamily(expected, actual)
  if expected == actual then return true end
  local em, ei = splitModAndId(expected)
  local am, ai = splitModAndId(actual)
  if not (em and ei and am and ai) then return false end
  if em ~= am then return false end
  return stripTierPrefix(ei) == stripTierPrefix(ai)
end

function M.findSlotByNameOrFamily(name)
  -- Returns slot and detail for exact or family match; prefers exact.
  if not name then return nil end
  -- exact
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.name == name and d.count > 0 then return i, d end
  end
  -- family
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.count > 0 and M.isSameFamily(name, d.name) then return i, d end
  end
  return nil
end

-- Placement helpers ---------------------------------------------------------
local function blockMatchesFamily(inspectFn, targetName)
  if not targetName then return true end
  local ok, data = inspectFn()
  if ok and data and (data.name == targetName or M.isSameFamily(targetName, data.name)) then
    return true
  end
  return false
end

function M.placeDown(name)
  if not name then return true end
  -- Skip if already correct
  if blockMatchesFamily(turtle.inspectDown, name) then return true end
  local slot = M.findSlotByNameOrFamily(name)
  if not slot then return false end
  local prev = turtle.getSelectedSlot()
  turtle.select(slot)
  local ok = turtle.placeDown()
  turtle.select(prev)
  return ok
end

function M.placeForward(name)
  if not name then return true end
  if blockMatchesFamily(turtle.inspect, name) then return true end
  local slot = M.findSlotByNameOrFamily(name)
  if not slot then return false end
  local prev = turtle.getSelectedSlot()
  turtle.select(slot)
  local ok = turtle.place()
  turtle.select(prev)
  return ok
end

function M.placeUp(name)
  if not name then return true end
  if blockMatchesFamily(turtle.inspectUp, name) then return true end
  local slot = M.findSlotByNameOrFamily(name)
  if not slot then return false end
  local prev = turtle.getSelectedSlot()
  turtle.select(slot)
  local ok = turtle.placeUp()
  turtle.select(prev)
  return ok
end

-- Movement (with retries, dig/attack, and fuel) ----------------------------
local function retryMove(stepFn, attackFn, digFn)
  local tries = 0
  local maxT = CONFIG.moveMaxRetries or 20
  while tries < maxT do
    ensureFuel(1)
    if stepFn() then return true end
    if attackFn then attackFn() end
    if digFn then digFn() end
    if _G.sleep then sleep(CONFIG.retryDelay or 0.2) end
    tries = tries + 1
    if not isFuelUnlimited() and (turtle.getFuelLevel() or 0) <= 0 then
      return false, "out-of-fuel"
    end
  end
  return false, "blocked"
end

function M.forward()
  return retryMove(turtle.forward, turtle.attack, turtle.dig)
end

function M.back()
  -- Use native back; if blocked, turn around and use forward logic once.
  ensureFuel(1)
  if turtle.back() then return true end
  turtle.turnLeft(); turtle.turnLeft()
  local ok, reason = retryMove(turtle.forward, turtle.attack, turtle.dig)
  turtle.turnLeft(); turtle.turnLeft()
  return ok, reason
end

function M.up()
  return retryMove(turtle.up, turtle.attackUp, turtle.digUp)
end

function M.down()
  return retryMove(turtle.down, turtle.attackDown, turtle.digDown)
end

-- Non-destructive moves (do not dig); useful near torches or placed floors ---
function M.forwardNoDig()
  ensureFuel(1)
  if turtle.detect and turtle.detect() then return false, "blocked" end
  if turtle.forward() then return true end
  return false, "entity-blocked"
end

function M.backNoDig()
  ensureFuel(1)
  if turtle.back() then return true end
  turtle.turnLeft(); turtle.turnLeft()
  local ok = (not (turtle.detect and turtle.detect())) and turtle.forward()
  turtle.turnLeft(); turtle.turnLeft()
  if ok then return true end
  return false, "blocked"
end

-- Fuel restock from adjacent storage ---------------------------------------
local function isInventoryBlockName(name)
  if not name then return false end
  name = name:lower()
  return name:find("chest", 1, true) or name:find("barrel", 1, true) or name:find("drawer", 1, true) or name:find("shulker_box", 1, true)
end

-- Attempt to suck items from adjacent inventories and consume as fuel until we
-- cross targetLevel. Returns two booleans: (pulledFuel, foundAnyContainer).
function M.attemptFuelRestock(targetLevel)
  if isFuelUnlimited() then return true, false end
  targetLevel = targetLevel or CONFIG.fuelThreshold or 0

  local pulledFuel, foundContainer = false, false

  local function tryConsumeToTarget()
    local started = turtle.getFuelLevel() or 0
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot)
      if d then
        local prev = turtle.getSelectedSlot()
        turtle.select(slot)
        while turtle.refuel(1) do
          pulledFuel = true
          if (turtle.getFuelLevel() or 0) > targetLevel then break end
        end
        turtle.select(prev)
        if (turtle.getFuelLevel() or 0) > targetLevel then break end
      end
    end
    return (turtle.getFuelLevel() or 0) > started
  end

  local function noop() end
  local function turnAround() turtle.turnRight(); turtle.turnRight() end

  local dirs = {
    {prep=noop,        clean=noop,        inspect=turtle.inspect,     suck=turtle.suck,     drop=turtle.drop},
    {prep=turtle.turnRight, clean=turtle.turnLeft, inspect=turtle.inspect,     suck=turtle.suck,     drop=turtle.drop},
    {prep=turnAround,  clean=turnAround,  inspect=turtle.inspect,     suck=turtle.suck,     drop=turtle.drop},
    {prep=turtle.turnLeft,  clean=turtle.turnRight, inspect=turtle.inspect,     suck=turtle.suck,     drop=turtle.drop},
    {prep=noop,        clean=noop,        inspect=turtle.inspectUp,   suck=turtle.suckUp,   drop=turtle.dropUp},
    {prep=noop,        clean=noop,        inspect=turtle.inspectDown, suck=turtle.suckDown, drop=turtle.dropDown},
  }

  for _, d in ipairs(dirs) do
    if (turtle.getFuelLevel() or 0) > targetLevel then break end
    d.prep()
    local ok, data = d.inspect()
    if ok and data and isInventoryBlockName(data.name) then
      foundContainer = true
      -- try a few pulls and then consume
      for _ = 1, (CONFIG.restockMaxPulls or 8) do
        if (turtle.getFuelLevel() or 0) > targetLevel then break end
        d.suck(1)
        if tryConsumeToTarget() and (turtle.getFuelLevel() or 0) > targetLevel then break end
      end
      -- Drop back anything not fuel (best-effort)
      for slot = 1, 16 do
        local det = turtle.getItemDetail(slot)
        if det then
          local prev = turtle.getSelectedSlot()
          turtle.select(slot)
          if not turtle.refuel(0) then
            d.drop()
          end
          turtle.select(prev)
        end
      end
    end
    d.clean()
  end

  return pulledFuel or ((turtle.getFuelLevel() or 0) > targetLevel), foundContainer
end

-- High-level refuel that uses inventory first, then adjacent storage.
function M.refuel(target)
  if isFuelUnlimited() then return true end
  target = target or CONFIG.fuelThreshold or 0
  if ensureFuel(target) then return true end
  local pulled = M.attemptFuelRestock(target)
  return pulled and (turtle.getFuelLevel() or 0) >= target
end

-- Chest helpers (minimal) ---------------------------------------------------
function M.placeChestBehind(opts)
  opts = opts or {}
  local chestSlot = opts.chestSlot
  if not chestSlot or turtle.getItemCount(chestSlot) == 0 then
    for i = 1, 16 do
      local d = turtle.getItemDetail(i)
      local n = d and d.name and d.name:lower() or ""
      if n:find("chest",1,true) or n:find("barrel",1,true) then chestSlot = i; break end
    end
  end
  if not chestSlot or turtle.getItemCount(chestSlot) == 0 then return false, "no-chest" end
  local prev = turtle.getSelectedSlot()
  turtle.select(chestSlot)
  turtle.turnRight(); turtle.turnRight()
  local placed = false
  if not turtle.detect() then
    placed = turtle.place()
  end
  turtle.turnRight(); turtle.turnRight()
  turtle.select(prev)
  return placed
end

function M.depositToChest(opts)
  -- Place chest behind (if possible) and drop all but selected, chest, and one trash stack.
  local ok = M.placeChestBehind({ chestSlot = opts and opts.chestSlot })
  if not ok then return false, "place-chest-failed" end

  turtle.turnRight(); turtle.turnRight()
  local selected = turtle.getSelectedSlot()

  -- keep one trash stack if any (prefer current replace slot if specified)
  local keepSlot = opts and opts.keepTrashSlot
  if not keepSlot then
    for i = 1, 16 do
      local d = turtle.getItemDetail(i)
      if d then
        local nm = (d.name or ""):lower()
        if nm:find("cobble",1,true) or nm:find("deepslate",1,true) or nm:find("stone",1,true) or nm:find("basalt",1,true) then
          keepSlot = i; break
        end
      end
    end
  end

  local chestSlot = opts and opts.chestSlot
  for i = 1, 16 do
    if i ~= selected and i ~= keepSlot and i ~= chestSlot then
      local d = turtle.getItemDetail(i)
      if d then turtle.select(i); turtle.drop() end
    end
  end
  turtle.select(selected)
  turtle.turnRight(); turtle.turnRight()
  return true
end

return M
