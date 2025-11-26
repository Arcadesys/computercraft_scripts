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
Usage: factory_planner.lua [--load <schema-file>] [--help]

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

local function parseArgs()
    local config = {}
    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "--load" or arg == "-l" then
            i = i + 1
            local path = args[i]
            if not path then
                print("Missing value for " .. arg)
                return nil, true
            end
            config.loadPath = path
        elseif arg == "--help" or arg == "-h" then
            printUsage()
            return nil, true
        else
            print("Unknown argument: " .. tostring(arg))
            printUsage()
            return nil, true
        end
        i = i + 1
    end
    return config
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

    local ok, err = pcall(designer.run, runOpts)
    if not ok then
        print("Designer crashed: " .. tostring(err))
    end
end

main()
