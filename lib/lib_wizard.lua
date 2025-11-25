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
        
        local missing = {}
        
        for dir, req in pairs(requirements) do
            -- Face direction
            if not movement.faceDirection(ctx, dir) then
                table.insert(missing, "Could not face " .. dir)
            else
                -- Inspect
                local hasBlock, data = turtle.inspect()
                if not hasBlock then
                    table.insert(missing, "Missing " .. req.name .. " at " .. dir)
                elseif req.type == "chest" and not data.name:find("chest") and not data.name:find("barrel") then
                    table.insert(missing, "Incorrect block at " .. dir .. " (Found " .. data.name .. ")")
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
            print("\nPress [Enter] to try again.")
            read()
        end
    end
end

return wizard
