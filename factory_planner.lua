---@diagnostic disable: undefined-global, undefined-field

-- Factory Designer Launcher
-- Thin wrapper around lib_designer so players always get the full feature set.

local function ensurePackagePath()
    if not package or type(package.path) ~= "string" then
        package = package or {}
        package.path = package.path or ""
    end

    if not string.find(package.path, "/lib/?.lua", 1, true) then
        package.path = package.path .. ";/?.lua;/lib/?.lua;/factory/?.lua;/arcade/?.lua"
    end
end

ensurePackagePath()

local designer = require("lib_designer")
local parser = require("lib_parser")

local args = { ... }

local function printUsage()
    print([[Factory Designer
Usage: factory_planner.lua [--load <schema-file>] [--farm <tree|potato>] [--help]

Controls are available inside the designer (press M for menu).]])
end

local function resolveSchemaPath(rawPath)
    if fs.exists(rawPath) then
        return rawPath
    end
    if fs.exists(rawPath .. ".json") then
        return rawPath .. ".json"
    end
    if fs.exists(rawPath .. ".txt") then
        return rawPath .. ".txt"
    end
    return rawPath
end

local function loadInitialSchema(path)
    local resolved = resolveSchemaPath(path)
    if not fs.exists(resolved) then
        print("Warning: schema file not found: " .. resolved)
        return nil
    end

    local ok, schema, metadata = parser.parseFile(nil, resolved)
    if not ok then
        print("Failed to load schema: " .. tostring(schema))
        return nil
    end

    print("Loaded schema: " .. resolved)
    return {
        schema = schema,
        metadata = metadata,
    }
end

local function main()
    local config, handled = parseArgs()
    if handled then return end

    local runOpts = {}
    if config and config.loadPath then
        local initial = loadInitialSchema(config.loadPath)
        if initial then
            runOpts.schema = initial.schema
            runOpts.metadata = initial.metadata
        end
    end

    if config and config.farmType then
        if config.farmType == "tree" then
            runOpts.meta = { mode = "treefarm" }
            runOpts.palette = {
                { id = "minecraft:stone_bricks", color = colors.gray, sym = "#" },
                { id = "minecraft:dirt", color = colors.brown, sym = "D" },
                { id = "minecraft:oak_sapling", color = colors.green, sym = "S" },
                { id = "minecraft:torch", color = colors.yellow, sym = "i" },
                { id = "minecraft:chest", color = colors.orange, sym = "C" },
            }
        elseif config.farmType == "potato" then
            runOpts.meta = { mode = "potatofarm" }
            runOpts.palette = {
                { id = "minecraft:stone_bricks", color = colors.gray, sym = "#" },
                { id = "minecraft:dirt", color = colors.brown, sym = "D" },
                { id = "minecraft:water_bucket", color = colors.blue, sym = "W" },
                { id = "minecraft:potato", color = colors.yellow, sym = "P" },
                { id = "minecraft:chest", color = colors.orange, sym = "C" },
            }
        else
            print("Unknown farm type: " .. config.farmType)
            return
        end
    end

    local ok, err = pcall(designer.run, runOpts)
    if not ok then
        print("Designer crashed: " .. tostring(err))
    end
end

main()
