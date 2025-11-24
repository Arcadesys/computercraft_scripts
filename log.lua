-- log.lua
-- Tiny logger tailored for ComputerCraft turtles/computers.
-- Provides leveled logging with safe file writes so crashes are easier
-- to diagnose. Defaults to `arcade.log` in the working directory.
-- Lua Tip: Returning a constructor function lets you keep state private
-- while still exposing an easy-to-use API.

local Log = {}
Log.__index = Log

local LEVELS = {
  error = 1,
  warn = 2,
  info = 3,
  debug = 4,
}

local function now()
  if os and os.date then
    return os.date("%Y-%m-%d %H:%M:%S")
  end
  return "unknown-time"
end

---Create a new logger.
---@param options table|nil {logFile:string, level:string}
function Log.new(options)
  options = options or {}
  local self = setmetatable({}, Log)
  self.logFile = options.logFile or "arcade.log"
  self.threshold = LEVELS[string.lower(options.level or "info")] or LEVELS.info
  return self
end

local function tryWrite(path, line)
  local ok, err = pcall(function()
    local handle = fs.open(path, "a")
    if handle then
      handle.writeLine(line)
      handle.close()
    end
  end)
  if not ok then
    return false, err
  end
  return true
end

---Internal helper used by all level-specific methods.
function Log:log(level, message)
  local numeric = LEVELS[level] or LEVELS.info
  if numeric > self.threshold then return end
  local safeMessage = tostring(message)
  local line = string.format("[%s] %-5s %s", now(), level:upper(), safeMessage)
  local success, err = tryWrite(self.logFile, line)
  if not success and term then
    -- Fallback to terminal output instead of crashing the program.
    term.setTextColor(colors.red)
    print("Log write failed: " .. tostring(err))
    term.setTextColor(colors.white)
  end
end

function Log:error(message) self:log("error", message) end
function Log:warn(message) self:log("warn", message) end
function Log:info(message) self:log("info", message) end
function Log:debug(message) self:log("debug", message) end

return Log
