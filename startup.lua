-- startup.lua
-- Simplified launcher for TurtleOS

package.path = package.path .. ";/?.lua;/lib/?.lua"

if fs.exists("factory/turtle_os.lua") then
    shell.run("factory/turtle_os.lua")
elseif fs.exists("/factory/turtle_os.lua") then
    shell.run("/factory/turtle_os.lua")
else
    print("Error: factory/turtle_os.lua not found.")
end
