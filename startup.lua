---@diagnostic disable: undefined-global, undefined-field, param-type-mismatch

-- startup.lua
-- Minimal launcher for essentials build (AE2 monitor + Factory Planner).

package.path = package.path .. ";/?.lua;/lib/?.lua"

local function runProgram(path, label)
    if fs.exists(path) then
        ---@diagnostic disable-next-line: param-type-mismatch
        shell.run(path)
    else
        print(label .. " not found at " .. path)
    end
end

if pocket then
    runProgram("/pocket_menu.lua", "Pocket Menu")
else
    runProgram("/workstation_menu.lua", "Workstation Menu")
end
