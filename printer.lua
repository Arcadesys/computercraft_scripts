--[[
    Printer Program
    Scans for JSON schemas and launches the Factory Agent.
]]

-- Ensure package path is set (in case startup didn't run or we are in a fresh shell)
if not string.find(package.path, "/lib/?.lua") then
    package.path = package.path .. ";/?.lua;/lib/?.lua;/factory/?.lua"
end

local menu = require("lib_menu")

local function getJsonFiles()
    local files = {}
    
    -- Helper to add files
    local function scan(dir, prefix)
        if not fs.exists(dir) or not fs.isDir(dir) then return end
        local list = fs.list(dir)
        for _, file in ipairs(list) do
            if file:match("%.json$") then
                table.insert(files, (prefix or "") .. file)
            end
        end
    end
    
    scan("", "")
    scan("disk", "disk/")
    
    return files
end

local function main()
    while true do
        local files = getJsonFiles()
        
        if #files == 0 then
            print("No .json schema files found.")
            print("Create one in the Designer or insert a disk.")
            print("Press any key to exit.")
            os.pullEvent("key")
            return
        end
        
        local options = {}
        for _, f in ipairs(files) do
            table.insert(options, f)
        end
        table.insert(options, "Exit")
        
        local choice = menu.run("Select Schema to Print", options)
        
        if choice == #options then
            term.clear()
            term.setCursorPos(1, 1)
            return
        end
        
        local selectedFile = files[choice]
        
        term.clear()
        term.setCursorPos(1, 1)
        print("Selected: " .. selectedFile)
        print("Launching Factory Agent...")
        sleep(1)
        
        -- Run the factory agent
        shell.run("/factory/main.lua", selectedFile)
        
        -- After run, return to menu? Or exit?
        -- Usually better to exit so user sees the output.
        print("\nPress any key to return to menu...")
        os.pullEvent("key")
    end
end

local function runWithMonitor(fn)
    local ok, monitorUtil = pcall(require, "lib_monitor")
    if ok and monitorUtil and monitorUtil.runOnMonitor then
        return monitorUtil.runOnMonitor(fn, { textScale = 0.5 })
    end
    return fn()
end

runWithMonitor(main)
