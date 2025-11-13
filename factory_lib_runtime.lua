--[[
    Factory Runtime Bootstrap
    Extends package search paths so underscore-style module names like
    "factory_lib_service" work without manual setup.

    Usage:
        dofile("/factory_lib_runtime.lua") -- once per shell/program
        local Service = require("factory_lib_service")
]]

local Runtime = {}

local function ensurePackagePath(pattern)
    if type(package) ~= "table" then
        return
    end
    if type(package.path) ~= "string" then
        package.path = pattern
        return
    end
    if not package.path:find(pattern, 1, true) then
        package.path = package.path .. ";" .. pattern
    end
end

ensurePackagePath("/?.lua")
ensurePackagePath("/?/init.lua")

local function loadModuleFrom(rootedPath, moduleName)
    local path = rootedPath
    if not path:match("^/") then
        path = "/" .. path
    end

    local chunk, err = loadfile(path)
    if not chunk then
        error(string.format("Unable to load %s from %s: %s", moduleName, path, tostring(err)))
    end

    local result = chunk(moduleName)

    if type(package) == "table" and type(package.loaded) == "table" then
        package.loaded[moduleName] = result
    end

    return result
end

local function registerPreload(alias, moduleName, rootedPath)
    if type(package) ~= "table" or type(package.preload) ~= "table" then
        return
    end
    if package.preload[alias] then
        return
    end
    package.preload[alias] = function()
        return loadModuleFrom(rootedPath, moduleName or alias)
    end
end

registerPreload("factory_lib_movement", "factory_lib_movement", "factory_lib_movement.lua")
registerPreload("factory_lib_inventory", "factory_lib_inventory", "factory_lib_inventory.lua")
registerPreload("factory_lib_service", "factory_lib_service", "factory_lib_service.lua")
-- Compatibility aliases for older dotted namespaces.
registerPreload("factory.lib.movement", "factory_lib_movement", "factory_lib_movement.lua")
registerPreload("factory.lib.inventory", "factory_lib_inventory", "factory_lib_inventory.lua")
registerPreload("factory.lib.service", "factory_lib_service", "factory_lib_service.lua")

function Runtime.require(moduleName)
    return require(moduleName)
end

function Runtime.load(moduleName, rootedPath)
    return loadModuleFrom(rootedPath or moduleName .. ".lua", moduleName)
end

return Runtime
