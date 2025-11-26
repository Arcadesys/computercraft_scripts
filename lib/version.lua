--[[
Version and build counter for Arcadesys TurtleOS.
Build counter increments on each bundle/rebuild.
]]

local version = {}

version.MAJOR = 2
version.MINOR = 1
version.PATCH = 1
version.BUILD = 13

--- Format version string (e.g., "v2.1.1 (build 42)")
function version.toString()
    return string.format("v%d.%d.%d (build %d)", 
        version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end

--- Format short display (e.g., "TurtleOS v2.1.1 #42")
function version.display()
    return string.format("TurtleOS v%d.%d.%d #%d", 
        version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end

return version
