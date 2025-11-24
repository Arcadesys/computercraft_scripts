-- Compatibility shim so legacy code can require("games.arcade")
-- regardless of where the real arcade library lives.
local ok, mod = pcall(require, "arcade")
if ok and mod then
    return mod
end
error("Unable to load arcade library via either 'games.arcade' shim or 'arcade'")
