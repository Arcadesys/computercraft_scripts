-- pocket_menu.lua
-- Slim menu for pocket computers. Focuses on terminal-friendly apps.

---@diagnostic disable: undefined-global, undefined-field

package.path = package.path .. ";/?.lua;/lib/?.lua;/arcade/?.lua;/factory/?.lua"

local menu = require("lib_menu")

local APPS = {
    { label = "Update / Install", path = "/installer.lua" },
    { label = "Factory Planner", path = "/factory_planner.lua" },
    { label = "AE2 Monitor (terminal)", path = "/ae2_me_bridge_monitor.lua" },
    { label = "Shell", action = function() shell.run("/rom/programs/shell") end },
    { label = "Reboot", action = function() os.reboot() end },
    { label = "Shutdown", action = function() os.shutdown() end },
}

local function exists(path)
    return path and fs.exists(path)
end

local function runApp(app)
    if app.action then
        app.action()
        return
    end
    if not exists(app.path) then
        print("Missing: " .. tostring(app.path))
        sleep(1.5)
        return
    end
    local ok, err = pcall(function() shell.run(app.path) end)
    if not ok and err ~= "Terminated" then
        printError("Error: " .. tostring(err))
        sleep(1.5)
    end
end

local function main()
    while true do
        local labels = {}
        for _, app in ipairs(APPS) do
            table.insert(labels, app.label)
        end
        local idx = select(1, menu.run("Pocket Menu", labels))
        if not idx then break end
        term.clear()
        term.setCursorPos(1, 1)
        runApp(APPS[idx])
    end
end

main()
