-- lib/turtle.lua -------------------------------------------------------------
-- Shared turtle controller focused on resilient movement.
--
-- This module extracts the movement safety wrappers that previously lived inside
-- turtle/factoryrefactor.lua so they can be reused by other turtle programs.
-- The controller handles:
--   * Fuel checks before every move
--   * Dig/attack retries with configurable delay
--   * Optional movement history callbacks (for custom pose tracking)
--   * Operator prompts when the turtle is blocked and auto-mode is disabled
--
-- Usage:
--   local TurtleControl = require("lib.turtle")
--   local controller = TurtleControl.new({
--     turtle = turtle,                 -- optional; defaults to global turtle
--     refuel = ensureFuel,             -- called before each move
--     maxRetries = 20,                 -- default retry budget per move
--     retryDelay = 0.2,                -- seconds between retries
--     autoWait = function() return CONFIG.autoMode end,
--     waitSeconds = 1,
--     log = log,                       -- optional logger
--     recordMove = recordHistory,      -- optional history recorder
--     applyPoseMove = updatePoseMove,  -- optional pose tracker
--     applyPoseTurn = updatePoseTurn,  -- optional pose tracker
--   })
--
--   controller:move("forward")
--   controller:turn("left")
--   controller:waitFor(function() return controller:try("forward") end, "Waiting")
-- -----------------------------------------------------------------------------

local TurtleControl = {}
TurtleControl.__index = TurtleControl

local function noop() end

local function evaluate(setting)
  if type(setting) == "function" then
    return setting()
  end
  return setting
end

--- Create a new controller instance.
-- @param options table containing dependency overrides and behaviour flags.
-- @return controller object with move/turn helpers.
function TurtleControl.new(options)
  options = options or {}
  local turtleApi = options.turtle or assert(rawget(_G, "turtle"), "turtle API unavailable")

  local self = setmetatable({}, TurtleControl)
  self.turtle = turtleApi
  self.refuelFn = options.refuel or noop
  self.maxRetries = options.maxRetries or 20
  self.retryDelay = options.retryDelay or 0.2
  self.autoWaitSetting = options.autoWait
  self.waitSecondsSetting = options.waitSeconds or 1
  self.logger = options.log or noop
  self.recordMoveFn = options.recordMove
  self.poseMoveFn = options.applyPoseMove or noop
  self.poseTurnFn = options.applyPoseTurn or noop
  self.isFuelUnlimitedFn = options.isFuelUnlimited
  self.sleepFn = options.sleep or rawget(_G, "sleep")
  self.readFn = options.read or rawget(_G, "read")
  self.printFn = options.print or print

  local attack = turtleApi.attack or noop
  local dig = turtleApi.dig or noop

  self.movement = {
    forward = { step = assert(turtleApi.forward, "turtle.forward missing"), attack = attack, dig = dig, symbol = "F" },
    back    = { step = assert(turtleApi.back, "turtle.back missing"),    attack = attack, dig = dig, symbol = "B" },
    up      = { step = assert(turtleApi.up, "turtle.up missing"),        attack = turtleApi.attackUp or noop, dig = turtleApi.digUp or noop, symbol = "U" },
    down    = { step = assert(turtleApi.down, "turtle.down missing"),    attack = turtleApi.attackDown or noop, dig = turtleApi.digDown or noop, symbol = "D" },
  }

  self.tryMovement = {
    forward = { step = turtleApi.forward, symbol = "F" },
    back    = { step = turtleApi.back,    symbol = "B" },
    up      = { step = turtleApi.up,      symbol = "U" },
    down    = { step = turtleApi.down,    symbol = "D" },
  }

  return self
end

function TurtleControl:isFuelUnlimited()
  if self.isFuelUnlimitedFn then
    return self.isFuelUnlimitedFn()
  end
  if not self.turtle.getFuelLimit then
    return false
  end
  local limit = self.turtle.getFuelLimit()
  return limit == "unlimited" or limit == math.huge
end

function TurtleControl:record(symbol, recordHistory)
  if recordHistory == false then
    return
  end
  if self.recordMoveFn then
    self.recordMoveFn(symbol)
  end
end

function TurtleControl:sleep(seconds)
  if self.sleepFn and seconds and seconds > 0 then
    self.sleepFn(seconds)
  end
end

--- Attempt a movement with dig/attack retries.
-- @return boolean success flag and optional failure reason.
function TurtleControl:move(direction, opts)
  opts = opts or {}
  local config = self.movement[direction]
  if not config then
    error("Unknown move direction: " .. tostring(direction))
  end

  local maxRetries = opts.maxRetries or self.maxRetries
  local recordHistory = opts.recordHistory
  if recordHistory == nil then
    recordHistory = true
  end

  local tries = 0
  while tries < maxRetries do
    self.refuelFn()
    if config.step() then
      self.poseMoveFn(direction)
      self:record(config.symbol, recordHistory)
      return true
    end
    config.attack()
    config.dig()
    self:sleep(self.retryDelay)
    tries = tries + 1
    if self.turtle.getFuelLevel and self.turtle.getFuelLevel() == 0 and not self:isFuelUnlimited() then
      self.logger("Move failed: out of fuel")
      return false, "out-of-fuel"
    end
  end

  self.logger(string.format("Move blocked after %d attempts", tries))
  return false, "blocked"
end

--- Execute a turn and update pose/history.
function TurtleControl:turn(direction, opts)
  opts = opts or {}
  local recordHistory = opts.recordHistory
  if recordHistory == nil then
    recordHistory = true
  end

  if direction == "right" then
    self.turtle.turnRight()
    self.poseTurnFn(direction)
    self:record("R", recordHistory)
    return true
  elseif direction == "left" then
    self.turtle.turnLeft()
    self.poseTurnFn(direction)
    self:record("L", recordHistory)
    return true
  elseif direction == "around" then
    self.turtle.turnLeft()
    self.turtle.turnLeft()
    self.poseTurnFn(direction)
    if recordHistory then
      self:record("L", true)
      self:record("L", true)
    end
    return true
  end

  error("Unknown turn direction: " .. tostring(direction))
end

--- Attempt a movement once without digging.
function TurtleControl:try(direction, opts)
  opts = opts or {}
  local entry = self.tryMovement[direction]
  if not entry then
    error("Unknown try direction: " .. tostring(direction))
  end

  local recordHistory = opts.recordHistory and true or false
  if entry.step and entry.step() then
    self.poseMoveFn(direction)
    if recordHistory then
      self:record(entry.symbol, true)
    end
    return true
  end
  return false
end

--- Wait for a movement function to succeed, prompting the operator as needed.
function TurtleControl:waitFor(stepFn, label, maxAttempts)
  label = label or "Waiting"
  local attempts = 0
  while true do
    if stepFn() then
      return true
    end
    attempts = attempts + 1
    if maxAttempts and attempts >= maxAttempts then
      return false
    end

    if evaluate(self.autoWaitSetting) ~= false then
      self.printFn(label .. " ...")
      self:sleep(evaluate(self.waitSecondsSetting) or 0)
    else
      self.printFn(label .. " (press Enter once clear)")
      if self.readFn then
        self.readFn()
      else
        self:sleep(evaluate(self.waitSecondsSetting) or 0)
      end
    end
  end
end

--- Convenience wrapper for waiting on a specific directional move.
function TurtleControl:waitForMove(direction, label, maxAttempts, opts)
  label = label or ("Moving " .. tostring(direction))
  return self:waitFor(function()
    return self:try(direction, opts)
  end, label, maxAttempts)
end

function TurtleControl:performInverse(operation, opts)
  opts = opts or {}
  local maxAttempts = opts.maxAttempts
  if operation == "F" then
    return self:waitForMove("back", "Moving back", maxAttempts)
  elseif operation == "B" then
    return self:waitForMove("forward", "Moving forward", maxAttempts)
  elseif operation == "U" then
    return self:waitForMove("down", "Moving down", maxAttempts)
  elseif operation == "D" then
    return self:waitForMove("up", "Moving up", maxAttempts)
  elseif operation == "R" then
    return self:turn("left", { recordHistory = false })
  elseif operation == "L" then
    return self:turn("right", { recordHistory = false })
  end
  return false
end

function TurtleControl:performForward(operation, opts)
  opts = opts or {}
  local maxAttempts = opts.maxAttempts
  if operation == "F" then
    return self:waitForMove("forward", "Moving forward", maxAttempts)
  elseif operation == "B" then
    return self:waitForMove("back", "Moving back", maxAttempts)
  elseif operation == "U" then
    return self:waitForMove("up", "Moving up", maxAttempts)
  elseif operation == "D" then
    return self:waitForMove("down", "Moving down", maxAttempts)
  elseif operation == "R" then
    return self:turn("right", { recordHistory = false })
  elseif operation == "L" then
    return self:turn("left", { recordHistory = false })
  end
  return false
end

return TurtleControl
