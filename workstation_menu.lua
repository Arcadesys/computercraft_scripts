-- Workstation launcher
-- Simple DOS-style menu to start apps. Passive apps prefer an attached monitor;
-- active apps stay in the terminal window.

---@diagnostic disable: undefined-global, undefined-field

package.path = package.path .. ";/?.lua;/lib/?.lua;/arcade/?.lua;/factory/?.lua"

local menu = require("lib_menu")
local monUtil = require("lib_monitor")

local APPS = {
    {
        id = "update",
        label = "Update / Install",
        path = "/installer.lua",
        mode = "active",
        desc = "Pull latest Arcadesys build from GitHub",
    },
    {
        id = "ae2_monitor",
        label = "AE2 Storage Monitor",
        path = "/ae2_me_bridge_monitor.lua",
        mode = "passive",
        monitor = { textScale = 0.5 },
        desc = "Passive monitor for ME storage via meBridge",
    },
    {
        id = "factory_planner",
        label = "Factory Planner",
        path = "/factory_planner.lua",
        mode = "active",
        desc = "Interactive planning tool",
    },
}

local function appExists(app)
    return app.path and fs.exists(app.path)
end

local function buildOptions()
    local opts = {}
    for _, app in ipairs(APPS) do
        if appExists(app) then
            table.insert(opts, app)
        end
    end
    table.insert(opts, { id = "shell", label = "Shell", mode = "active", action = function() shell.run("/rom/programs/shell") end })
    table.insert(opts, { id = "reboot", label = "Reboot", mode = "active", action = function() os.reboot() end })
    table.insert(opts, { id = "shutdown", label = "Shutdown", mode = "active", action = function() os.shutdown() end })
    return opts
end

local function runWithMonitor(app)
    local runner = function()
        shell.run(app.path)
    end
    local session, err = monUtil.redirectToMonitor(app.monitor or { textScale = 0.5 })
    if not session then
        print("No monitor found (" .. tostring(err or "nil") .. "). Running in terminal.")
        return pcall(runner)
    end
    local ok, res = pcall(runner)
    if session.restore then
        session.restore()
    end
    return ok, res
end

local function runApp(app)
    if app.action then
        app.action()
        return
    end

    if app.mode == "passive" then
        local ok, err = runWithMonitor(app)
        if not ok and err ~= "Terminated" then
            printError("App error: " .. tostring(err))
            sleep(2)
        end
    else
        local ok, err = pcall(function()
            shell.run(app.path)
        end)
        if not ok and err ~= "Terminated" then
            printError("App error: " .. tostring(err))
            sleep(2)
        end
    end
end

local function formatOptionText(app)
    local suffix = app.mode == "passive" and "[monitor]" or ""
    return app.label .. (suffix ~= "" and (" " .. suffix) or "")
end

local function main()
    while true do
        local options = buildOptions()
        local textOptions = {}
        for _, app in ipairs(options) do
            table.insert(textOptions, formatOptionText(app))
        end
        local idx = select(1, menu.run("Workstation", textOptions))
        if not idx then
            term.clear()
            term.setCursorPos(1, 1)
            break
        end
        local choice = options[idx]
        if choice then
            term.clear()
            term.setCursorPos(1, 1)
            runApp(choice)
        end
    end
end

main()
