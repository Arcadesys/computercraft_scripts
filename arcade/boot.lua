-- Determine current program path even if the shell API is unavailable
local function detectProgramPath()
    if shell and shell.getRunningProgram then
        return shell.getRunningProgram()
    end
    if debug and debug.getinfo then
        local info = debug.getinfo(1, "S")
        if info and info.source then
            local src = info.source
            if src:sub(1, 1) == "@" then
                src = src:sub(2)
            end
            return src
        end
    end
    return nil
end

local program = detectProgramPath()
if not program then
    return -- Cannot safely configure search paths without a reference point
end

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
