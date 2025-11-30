---@diagnostic disable: undefined-global, undefined-field, param-type-mismatch

-- startup.lua
-- Unified Arcadesys launcher for turtles and computers.

package.path = package.path .. ";/?.lua;/lib/?.lua"

if fs.exists("/arcadesys_os.lua") then
    shell.run("/arcadesys_os.lua")
else
    print("arcadesys_os.lua missing; please run install.lua")
end
