---@diagnostic disable: undefined-global
-- Shim so games written for `games/arcade.lua` can require the shared adapter
-- even when the files are placed at the repository root.
return require("arcade")
