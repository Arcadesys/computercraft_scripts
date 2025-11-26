---@diagnostic disable: undefined-global
--[[
Wizard library for interactive setup.
--]]

local ui = require("lib_ui")
local movement = require("lib_movement")
local logger = require("lib_logger")

local wizard = {}

function wizard.runChestSetup(ctx, requirements)
    -- requirements: { [direction] = { type="chest", name="Output" }, ... }
    -- direction: "north", "south", "east", "west"
    
    while true do
        ui.clear()
        print("Setup Wizard")
        print("============")
        print("Please place the following chests:")
        
        -- Draw diagram
        -- Assuming North is Forward
        --      N
        --   W  T  E
        --      S
        
        local w = requirements.west and "C" or " "
        local e = requirements.east and "C" or " "
        local n = requirements.north and "C" or " "
        local s = requirements.south and "C" or " "
        
        print(string.format("      %s", n))
        print(string.format("   %s  T  %s", w, e))
        print(string.format("      %s", s))
        print("")
        
        for dir, req in pairs(requirements) do
            local label = dir:upper()
            if dir == "north" then label = "FRONT (North)"
            elseif dir == "south" then label = "BACK (South)"
            elseif dir == "east" then label = "RIGHT (East)"
            elseif dir == "west" then label = "LEFT (West)"
            end
            print(string.format("- %s: %s", label, req.name))
        end
        
        print("\nPress [Enter] to verify setup.")
        read()
        
        -- Reset to North so user can verify start orientation
        print("Aligning to NORTH (Front)...")
        movement.faceDirection(ctx, "north")
        
        local missing = {}
        
        for dir, req in pairs(requirements) do
            -- Face direction
            if not movement.faceDirection(ctx, dir) then
                table.insert(missing, "Could not face " .. dir)
            else
                sleep(0.25)
                -- Inspect
                local hasBlock, data = turtle.inspect()
                if not hasBlock then
                    table.insert(missing, "Missing " .. req.name .. " at " .. dir .. " (Is turtle facing correctly?)")
                elseif req.type == "chest" and not data.name:find("chest") and not data.name:find("barrel") then
                    table.insert(missing, "Incorrect block at " .. dir .. " (Found " .. data.name .. ") [Facing: " .. movement.getFacing(ctx) .. "]")
                end
            end
        end
        
        if #missing == 0 then
            print("Setup verified!")
            sleep(1)
            return true
        else
            print("\nIssues found:")
            for _, m in ipairs(missing) do
                print("- " .. m)
            end
            print("\nOptions:")
            print("  [Enter] Auto-align orientation (Recommended)")
            print("  'r'     Retry manually")
            print("  'skip'  Ignore errors")
            
            local input = read()
            if input == "skip" then return true end
            if input ~= "r" then
                print("Scanning surroundings to auto-align...")
                -- 1. Scan surroundings (0=Front, 1=Right, 2=Back, 3=Left)
                local surroundings = {}
                for i = 0, 3 do
                    local hasBlock, data = turtle.inspect()
                    if hasBlock and (data.name:find("chest") or data.name:find("barrel")) then
                        surroundings[i] = true
                    else
                        surroundings[i] = false
                    end
                    turtle.turnRight()
                end
                -- Turtle is now back to original physical facing
                
                -- 2. Score candidates
                local CARDINALS = {"north", "east", "south", "west"}
                local bestScore = -1
                local bestFacing = nil
                
                for i, candidate in ipairs(CARDINALS) do
                    -- candidate is what we assume "Front" (0) is.
                    local score = 0
                    for dir, req in pairs(requirements) do
                        if req.type == "chest" then
                            -- Find index of 'dir' in CARDINALS
                            local dirIdx = -1
                            for k, v in ipairs(CARDINALS) do if v == dir then dirIdx = k break end end
                            
                            -- Find index of 'candidate' in CARDINALS
                            local candIdx = i
                            
                            if dirIdx ~= -1 then
                                local offset = (dirIdx - candIdx) % 4
                                if surroundings[offset] then
                                    score = score + 1
                                end
                            end
                        end
                    end
                    
                    if score > bestScore then
                        bestScore = score
                        bestFacing = candidate
                    end
                end
                
                if bestFacing and bestScore > 0 then
                    print("Auto-aligned to " .. bestFacing .. " (Score: " .. bestScore .. ")")
                    ctx.movement = ctx.movement or {}
                    ctx.movement.facing = bestFacing
                    ctx.origin = ctx.origin or {}
                    ctx.origin.facing = bestFacing
                    sleep(1)
                else
                    print("Could not determine orientation.")
                    sleep(1)
                end
            end
        end
    end
end

return wizard
