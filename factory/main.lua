--[[
Main entry point for the modular agent system.
Implements the finite state machine loop.
--]]

-- Ensure package path includes lib and arcade
if not string.find(package.path, "/lib/?.lua") then
    package.path = package.path .. ";/?.lua;/lib/?.lua;/arcade/?.lua;/factory/?.lua"
end

local logger = require("lib_logger")
local movement = require("lib_movement")
local ui = require("lib_ui")

local function interactiveSetup(ctx)
    local width = 9
    local height = 9
    local selected = 1 -- 1: Width, 2: Height, 3: FARM
    
    while true do
        ui.clear()
        ui.drawFrame(2, 2, 26, 12, "Tree Farm Setup")
        
        -- Width
        ui.label(4, 5, "Width: ")
        if selected == 1 then
            if term.isColor() then term.setTextColor(colors.yellow) end
            term.write("< " .. width .. " >")
        else
            if term.isColor() then term.setTextColor(colors.white) end
            term.write("  " .. width .. "  ")
        end
        
        -- Height
        ui.label(4, 7, "Height:")
        if selected == 2 then
            if term.isColor() then term.setTextColor(colors.yellow) end
            term.write("< " .. height .. " >")
        else
            if term.isColor() then term.setTextColor(colors.white) end
            term.write("  " .. height .. "  ")
        end
        
        -- Button
        ui.button(8, 10, "FARM", selected == 3)
        
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = selected - 1
            if selected < 1 then selected = 3 end
        elseif key == keys.down then
            selected = selected + 1
            if selected > 3 then selected = 1 end
        elseif key == keys.left then
            if selected == 1 then width = math.max(1, width - 1) end
            if selected == 2 then height = math.max(1, height - 1) end
        elseif key == keys.right then
            if selected == 1 then width = width + 1 end
            if selected == 2 then height = height + 1 end
        elseif key == keys.enter then
            if selected == 3 then
                ctx.config.mode = "treefarm"
                ctx.config.width = width
                ctx.config.height = height
                return
            end
        end
    end
end

-- Load states
local states = {
    INITIALIZE = require("state_initialize"),
    BUILD = require("state_build"),
    MINE = require("state_mine"),
    RESTOCK = require("state_restock"),
    REFUEL = require("state_refuel"),
    BLOCKED = require("state_blocked"),
    ERROR = require("state_error"),
    DONE = require("state_done"),
    CHECK_REQUIREMENTS = require("state_check_requirements"),
    TREEFARM = require("state_treefarm"),
    POTATOFARM = require("state_potatofarm")
}

local function main(args)
    -- Initialize context
    local ctx = {
        state = "INITIALIZE",
        config = {
            verbose = false,
            schemaPath = nil
        },
        origin = { x=0, y=0, z=0, facing="north" }, -- Default home
        pointer = 1, -- Current step in the build path
        schema = nil, -- Will be loaded by INITIALIZE
        strategy = nil, -- Will be computed by INITIALIZE
        inventoryState = {},
        fuelState = {},
        retries = 0
    }

    -- Parse args
    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "--verbose" then
            ctx.config.verbose = true
        elseif arg == "mine" then
            ctx.config.mode = "mine"
        elseif arg == "treefarm" then
            ctx.config.mode = "treefarm"
        elseif arg == "potatofarm" then
            ctx.config.mode = "potatofarm"
        elseif arg == "--length" then
            i = i + 1
            ctx.config.length = tonumber(args[i])
        elseif arg == "--width" then
            i = i + 1
            ctx.config.width = tonumber(args[i])
        elseif arg == "--height" then
            i = i + 1
            ctx.config.height = tonumber(args[i])
        elseif arg == "--branch-interval" then
            i = i + 1
            ctx.config.branchInterval = tonumber(args[i])
        elseif arg == "--branch-length" then
            i = i + 1
            ctx.config.branchLength = tonumber(args[i])
        elseif arg == "--torch-interval" then
            i = i + 1
            ctx.config.torchInterval = tonumber(args[i])
        elseif not arg:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
             ctx.config.schemaPath = arg
        end
        i = i + 1
    end
    
    -- If no args provided, run interactive setup
    if #args == 0 then
        interactiveSetup(ctx)
    end
    
    if not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
        ctx.config.schemaPath = "schema.json"
    end

    logger.init(ctx.config.verbose)
    logger.info("Agent starting...")

    -- State machine loop
    while ctx.state ~= "EXIT" do
        local currentStateFunc = states[ctx.state]
        if not currentStateFunc then
            logger.error("Unknown state: " .. tostring(ctx.state))
            break
        end

        logger.debug("Entering state: " .. ctx.state)
        
        local ok, nextStateOrErr = pcall(currentStateFunc, ctx)
        
        if not ok then
            logger.error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr))
            ctx.lastError = nextStateOrErr
            ctx.state = "ERROR"
        else
            ctx.state = nextStateOrErr
        end
        
        ---@diagnostic disable-next-line: undefined-global
        sleep(0) -- Yield to avoid "Too long without yielding"
    end

    logger.info("Agent finished.")
    
    if ctx.lastError then
        print("Agent finished: " .. tostring(ctx.lastError))
    else
        print("Agent finished: success!")
    end
end

local args = { ... }
main(args)
