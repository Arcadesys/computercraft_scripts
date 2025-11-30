---@diagnostic disable: undefined-global

-- arcadesys_os.lua
-- Unified launcher for turtles and computers with a shared, low-dependency UX.

package.path = package.path .. ";/?.lua;/lib/?.lua;/factory/?.lua;/arcade/?.lua;/arcade/games/?.lua"

local hub = require("ui.hub")

local function detectEnv()
    local hasTerm = type(term) == "table" and type(term.clear) == "function"
    local hasShell = type(shell) == "table" and type(shell.run) == "function"
    local hasFS = type(fs) == "table" and type(fs.exists) == "function"
    local isTurtle = type(_G.turtle) == "table"
    local isPocket = type(_G.pocket) == "table"
    local headless = not hasTerm
    return {
        hasTerm = hasTerm,
        hasShell = hasShell,
        hasFS = hasFS,
        isTurtle = isTurtle,
        isPocket = isPocket,
        isComputer = not isTurtle,
        headless = headless,
    }
end

local function promptNumber(ui, label, default)
    local resp = ui:prompt(label, default)
    local num = tonumber(resp)
    if not num then return default end
    return num
end

local function ensureFactory(env, ui)
    local ok, factory = pcall(require, "factory")
    if not ok then
        ui:notify("Factory module unavailable: " .. tostring(factory))
        return nil
    end
    if not env.isTurtle then
        ui:notify("Factory actions require a turtle.")
        return nil
    end
    return factory
end

local function runFactory(factory, args, ui)
    local ok, err = pcall(function()
        factory.run(args)
    end)
    if not ok then
        ui:notify("Factory error: " .. tostring(err))
    end
end

local function actionBranchMine(ctx, ui)
    local factory = ensureFactory(ctx.env, ui)
    if not factory then return end
    local length = promptNumber(ui, "Length", 64)
    local branch = promptNumber(ui, "Branch interval", 3)
    local torch = promptNumber(ui, "Torch interval", 6)
    ui:notify("Starting branch mine...")
    runFactory(factory, { "mine", "--length", tostring(length), "--branch-interval", tostring(branch), "--torch-interval", tostring(torch) }, ui)
    ui:pause("Mining complete.")
end

local function actionTunnel(ctx, ui)
    local factory = ensureFactory(ctx.env, ui)
    if not factory then return end
    local length = promptNumber(ui, "Length", 16)
    local width = promptNumber(ui, "Width", 1)
    local height = promptNumber(ui, "Height", 2)
    local torch = promptNumber(ui, "Torch interval", 6)
    ui:notify("Starting tunnel...")
    runFactory(factory, { "tunnel", "--length", tostring(length), "--width", tostring(width), "--height", tostring(height), "--torch-interval", tostring(torch) }, ui)
    ui:pause("Tunnel complete.")
end

local function actionExcavate(ctx, ui)
    local factory = ensureFactory(ctx.env, ui)
    if not factory then return end
    local length = promptNumber(ui, "Length", 8)
    local width = promptNumber(ui, "Width", 8)
    local depth = promptNumber(ui, "Depth", 3)
    ui:notify("Starting excavation...")
    runFactory(factory, { "excavate", "--length", tostring(length), "--width", tostring(width), "--depth", tostring(depth) }, ui)
    ui:pause("Excavation complete.")
end

local function actionTreeFarm(ctx, ui)
    local factory = ensureFactory(ctx.env, ui)
    if not factory then return end
    ui:notify("Starting tree farm...")
    runFactory(factory, { "treefarm" }, ui)
    ui:pause("Tree farm done.")
end

local function actionPotatoFarm(ctx, ui)
    local factory = ensureFactory(ctx.env, ui)
    if not factory then return end
    local width = promptNumber(ui, "Width", 9)
    local length = promptNumber(ui, "Length", 9)
    ui:notify("Building potato farm...")
    runFactory(factory, { "farm", "--farm-type", "potato", "--width", tostring(width), "--length", tostring(length) }, ui)
    ui:pause("Potato farm complete.")
end

local function actionBuildSchema(ctx, ui)
    local factory = ensureFactory(ctx.env, ui)
    if not factory then return end
    local path = ui:prompt("Schema file", "schema.json")
    if not path or path == "" then
        ui:notify("No schema provided.")
        return
    end
    ui:notify("Starting build for " .. path .. "...")
    runFactory(factory, { path }, ui)
    ui:pause("Build complete.")
end

local function actionRefuel(ctx, ui)
    if not ctx.env.isTurtle then
        ui:notify("Requires turtle fuel tank.")
        return
    end
    if not _G.turtle or type(turtle.getItemDetail) ~= "function" then
        ui:notify("Turtle API unavailable.")
        return
    end
    local before = type(turtle.getFuelLevel) == "function" and turtle.getFuelLevel() or nil
    local consumed = 0
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            turtle.select(slot)
            while true do
                local ok = turtle.refuel(1)
                if not ok then break end
                consumed = consumed + 1
            end
        end
    end
    pcall(turtle.select, 1)
    if before ~= nil and type(turtle.getFuelLevel) == "function" then
        local after = turtle.getFuelLevel()
        ui:writeLine(string.format("Fuel: %s -> %s", tostring(before), tostring(after)))
    end
    ui:writeLine("Consumed items (units): " .. tostring(consumed))
    ui:pause()
end

local function runProgram(ctx, ui, path, args)
    if ctx.env.headless or not ctx.env.hasShell then
        ui:notify("Would run: " .. path)
        return
    end
    local cmd = { path }
    if args then
        for _, a in ipairs(args) do table.insert(cmd, a) end
    end
    local ok, err = pcall(function()
        shell.run(table.unpack(cmd))
    end)
    if not ok then
        ui:notify("Program error: " .. tostring(err))
    end
end

local function actionDesigner(ctx, ui)
    runProgram(ctx, ui, "factory_planner.lua")
    ui:pause()
end

local function actionVideo(ctx, ui)
    runProgram(ctx, ui, "arcade/video_player.lua")
    ui:pause()
end

local function actionGame(path)
    return function(ctx, ui)
        runProgram(ctx, ui, path)
        ui:pause()
    end
end

local function actionInstaller(ctx, ui)
    runProgram(ctx, ui, "install.lua")
    ui:pause("Update requested.")
end

local function actionReboot(ctx, ui)
    if type(os) == "table" and type(os.reboot) == "function" and not ctx.env.headless then
        os.reboot()
    else
        ui:notify("Reboot not available in this environment.")
    end
end

local function fileExists(path, env)
    if not env.hasFS then return true end
    return fs.exists(path)
end

local function buildSections(env)
    local sections = {}

    if env.isTurtle then
        table.insert(sections, {
            label = "Factory",
            items = {
                { label = "Branch Mine", hint = "Length/branch/torch prompts", action = actionBranchMine },
                { label = "Tunnel", hint = "Length/width/height", action = actionTunnel },
                { label = "Excavate", hint = "Box dig", action = actionExcavate },
                { label = "Tree Farm", action = actionTreeFarm },
                { label = "Potato Farm", action = actionPotatoFarm },
                { label = "Build Schema", action = actionBuildSchema },
                { label = "Refuel", action = actionRefuel },
            }
        })
    else
        table.insert(sections, {
            label = "Factory",
            items = {
                { label = "Factory Planner", hint = "Design builds", action = actionDesigner },
            }
        })
    end

    table.insert(sections, {
        label = "Arcade",
        items = {
            { label = "Slots", action = actionGame("arcade/games/slots.lua") },
            { label = "Blackjack", action = actionGame("arcade/games/blackjack.lua") },
            { label = "Video Player", action = fileExists("arcade/video_player.lua", env) and actionVideo or function(_, ui) ui:notify("Video player missing.") end },
        }
    })

    table.insert(sections, {
        label = "Tools",
        items = {
            { label = "Factory Planner", action = actionDesigner },
            { label = "Update from GitHub", action = actionInstaller },
        }
    })

    table.insert(sections, {
        label = "System",
        items = {
            { label = "Reboot/Exit", action = actionReboot },
        }
    })

    return sections
end

local function main()
    local env = detectEnv()
    local subtitle = env.isTurtle and "Turtle mode" or "Computer mode"
    if env.headless then subtitle = subtitle .. " (headless UI)" end

    hub.run({
        title = "Arcadesys",
        subtitle = subtitle,
        sections = buildSections(env),
        ctx = { env = env },
    })
end

main()
