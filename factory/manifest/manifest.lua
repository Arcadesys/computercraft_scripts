--[[
  Manifest Helper
  Resolves and loads build manifests for the factory refactor workflow.

  Features:
  - Resolve manifest names to actual file paths with sane defaults
  - Load manifests via dofile with basic error reporting
  - Enumerate candidate manifests inside the /manifest directory
  - Self-test to demonstrate resolution logic
]]

local Manifest = {}

local function getEnvField(name)
    local env = _ENV or _G
    if type(env) ~= "table" then return nil end
    return rawget(env, name)
end

local fs = getEnvField("fs")

--- Resolve a manifest name to a filesystem path.
-- Accepts bare names like "testmanifest" or full paths.
function Manifest.resolve(name)
    if not name or name == "" then
        return nil, "Manifest name is required"
    end

    local candidate = name
    if not fs or not fs.exists then
        return candidate, nil
    end

    if fs.exists(candidate) and not fs.isDir(candidate) then
        return candidate, nil
    end

    if not candidate:match("%.lua$") then
        candidate = candidate .. ".lua"
    end

    if fs.exists(candidate) and not fs.isDir(candidate) then
        return candidate, nil
    end

    local inManifestDir = fs.combine("manifest", candidate)
    if fs.exists(inManifestDir) and not fs.isDir(inManifestDir) then
        return inManifestDir, nil
    end

    return nil, "Manifest not found: " .. name
end

--- Load and execute a manifest file, returning its table.
function Manifest.load(name)
    local path, err = Manifest.resolve(name)
    if not path then
        return nil, err
    end

    local ok, result = pcall(dofile, path)
    if not ok then
        return nil, result
    end

    return result, path
end

--- Enumerate files inside the /manifest directory.
function Manifest.list()
    if not fs or not fs.exists or not fs.list then
        return {}
    end

    local items = {}
    if fs.exists("manifest") and fs.isDir("manifest") then
        for _, entry in ipairs(fs.list("manifest")) do
            if entry:match("%.lua$") then
                table.insert(items, entry)
            end
        end
    end
    table.sort(items)
    return items
end

--- Self-test routine that reports available manifests and attempts to load one.
function Manifest.runSelfTest()
    print("[manifest] Starting self-test")
    local entries = Manifest.list()
    if #entries == 0 then
        print("[manifest] No manifests found in /manifest")
    else
        print("[manifest] Available manifests:")
        for _, entry in ipairs(entries) do
            print("  - " .. entry)
        end
    end

    local target = entries[1] or "manifest/testmanifest.lua"
    local manifest, err = Manifest.load(target)
    if manifest then
        local name = manifest.meta and manifest.meta.name or "(unnamed)"
        print(string.format("[manifest] Loaded '%s' from %s", name, target))
    else
        print(string.format("[manifest] Failed to load %s -> %s", target, tostring(err)))
    end

    print("[manifest] Self-test complete")
end

local moduleName = ...
if moduleName == nil then
    Manifest.runSelfTest()
end

return Manifest
