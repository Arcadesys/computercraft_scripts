---@diagnostic disable: undefined-global, undefined-field, param-type-mismatch

-- startup.lua
-- Unified Arcadesys launcher for turtles and computers.

package.path = package.path .. ";/?.lua;/lib/?.lua"

local function findLauncher()
    local here = fs.getDir(shell and shell.getRunningProgram and shell.getRunningProgram() or "") or ""
    local candidates = {
        fs.combine(here, "arcadesys_os.lua"),
        "/arcadesys_os.lua",
    }
    for _, path in ipairs(candidates) do
        if fs.exists(path) then
            return path
        end
    end
    return nil
end

local launcher = findLauncher()
if launcher then
    shell.run(launcher)
else
    print("arcadesys_os.lua missing; please run install.lua")
end
