-- arcade/boot.lua
-- Sets up package.path for arcade games

local program = shell.getRunningProgram()
local dir = fs.getDir(program)

local function findRoot(startDir)
    local current = startDir
    while true do
        if fs.exists(fs.combine(current, "lib")) then
            return current
        end
        if current == "" or current == ".." then break end
        current = fs.getDir(current)
    end
    return nil
end

local root = findRoot(dir)

if root then
    local function add(path)
        local part = fs.combine(root, path)
        local pattern = "/" .. fs.combine(part, "?.lua")
        if not string.find(package.path, pattern, 1, true) then
            package.path = package.path .. ";" .. pattern
        end
    end
    
    add("lib")
    add("arcade")
    add("arcade/ui")
    
    if not string.find(package.path, ";/?.lua", 1, true) then
        package.path = package.path .. ";/?.lua"
    end
end
