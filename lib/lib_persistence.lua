--[[
Persistence library for TurtleOS.
Handles saving and loading the agent's state to a JSON file.
]]

local json = require("lib_json")
local logger = require("lib_logger")

local persistence = {}
local STATE_FILE = "state.json"

---@class PersistenceConfig
---@field path string|nil Path to the state file (default: "state.json")

---Load state from disk.
---@param ctx table Context table for logging
---@param config PersistenceConfig|nil Configuration options
---@return table|nil state The loaded state table, or nil if not found/error
function persistence.load(ctx, config)
    local path = (config and config.path) or STATE_FILE
    
    if not fs.exists(path) then
        logger.log(ctx, "info", "No previous state found at " .. path)
        return nil
    end

    local f = fs.open(path, "r")
    if not f then
        logger.log(ctx, "error", "Failed to open state file for reading: " .. path)
        return nil
    end

    local content = f.readAll()
    f.close()

    if not content or content == "" then
        logger.log(ctx, "warn", "State file was empty")
        return nil
    end

    local state = json.decode(content)
    if not state then
        logger.log(ctx, "error", "Failed to decode state JSON")
        return nil
    end

    logger.log(ctx, "info", "State loaded from " .. path)
    return state
end

---Save state to disk.
---@param ctx table Context table containing the state to save
---@param config PersistenceConfig|nil Configuration options
---@return boolean success
function persistence.save(ctx, config)
    local path = (config and config.path) or STATE_FILE
    
    -- Construct a serializable snapshot of the context
    -- We don't want to save everything (like functions or the logger itself)
    local snapshot = {
        state = ctx.state,
        config = ctx.config,
        origin = ctx.origin,
        movement = ctx.movement, -- Contains position and facing
        chests = ctx.chests,     -- Save chest locations
        -- Save specific state data if it exists
        potatofarm = ctx.potatofarm,
        treefarm = ctx.treefarm,
        mine = ctx.mine,
        -- Add other state-specific tables here as needed
    }

    local content = json.encode(snapshot)
    if not content then
        logger.log(ctx, "error", "Failed to encode state to JSON")
        return false
    end

    local f = fs.open(path, "w")
    if not f then
        logger.log(ctx, "error", "Failed to open state file for writing: " .. path)
        return false
    end

    f.write(content)
    f.close()

    return true
end

---Clear the saved state file.
---@param ctx table Context table
---@param config PersistenceConfig|nil
function persistence.clear(ctx, config)
    local path = (config and config.path) or STATE_FILE
    if fs.exists(path) then
        fs.delete(path)
        logger.log(ctx, "info", "Cleared state file: " .. path)
    end
end

return persistence
