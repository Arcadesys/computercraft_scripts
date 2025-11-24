-- Farm Manager
-- A tool to generate and manage farm layouts.
-- Reuses concepts from Factory Planner.

local strategyFarm = require("lib.lib_strategy_farm")
local completion = require("cc.completion")

-- Configuration
local filename = "farm_schema.lua"
local diskPath = "disk/" .. filename

-- State
local farmTypes = { "tree", "wheat", "potato", "carrot", "beetroot", "nether_wart" }
local selectedTypeIndex = 1
local width = 9
local length = 9
local generatedSchema = nil
local message = ""
local messageTimer = 0

-- UI Colors
local colors = {
    bg = term.isColor() and colors.black or colors.black,
    text = term.isColor() and colors.white or colors.white,
    header = term.isColor() and colors.blue or colors.white,
    headerText = term.isColor() and colors.white or colors.black,
    button = term.isColor() and colors.gray or colors.white,
    buttonText = term.isColor() and colors.white or colors.black,
    field = term.isColor() and colors.lightGray or colors.white,
    fieldText = term.isColor() and colors.black or colors.black,
    highlight = term.isColor() and colors.cyan or colors.white,
}

local function drawText(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
    term.write(text)
end

local function drawRect(x, y, w, h, color)
    term.setBackgroundColor(color)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end
end

local function centerText(y, text, fg, bg)
    local w, h = term.getSize()
    local x = math.floor((w - string.len(text)) / 2) + 1
    drawText(x, y, text, fg, bg)
end

local function drawUI()
    local w, h = term.getSize()
    
    -- Background
    drawRect(1, 1, w, h, colors.bg)
    
    -- Header
    drawRect(1, 1, w, 1, colors.header)
    centerText(1, "Farm Manager", colors.headerText, colors.header)
    
    -- Form
    local startY = 3
    drawText(2, startY, "Farm Type: ", colors.text, colors.bg)
    drawText(14, startY, "< " .. farmTypes[selectedTypeIndex] .. " >", colors.highlight, colors.bg)
    
    drawText(2, startY + 2, "Width: ", colors.text, colors.bg)
    drawText(14, startY + 2, "- " .. tostring(width) .. " +", colors.highlight, colors.bg)
    
    drawText(2, startY + 3, "Length: ", colors.text, colors.bg)
    drawText(14, startY + 3, "- " .. tostring(length) .. " +", colors.highlight, colors.bg)
    
    -- Buttons
    drawText(2, startY + 5, "[ Generate ]", colors.buttonText, colors.button)
    drawText(16, startY + 5, "[ Save to Disk ]", colors.buttonText, colors.button)
    drawText(34, startY + 5, "[ Exit ]", colors.buttonText, colors.button)
    
    -- Preview Area
    drawText(2, startY + 7, "Preview (Layer 1):", colors.text, colors.bg)
    
    if generatedSchema then
        local px, py = 2, startY + 9
        -- Draw a mini map of the farm
        -- We only have limited space, so we might need to scroll or scale?
        -- For now, just draw characters.
        
        for z = 0, length - 1 do
            if py + z < h - 1 then
                term.setCursorPos(px, py + z)
                for x = 0, width - 1 do
                    if px + x < w then
                        local block = nil
                        if generatedSchema[x] and generatedSchema[x][1] and generatedSchema[x][1][z] then
                            block = generatedSchema[x][1][z] -- Layer 1 (Crops/Saplings)
                        elseif generatedSchema[x] and generatedSchema[x][0] and generatedSchema[x][0][z] then
                            block = generatedSchema[x][0][z] -- Layer 0 (Soil) if Layer 1 is empty
                        end
                        
                        local char = "."
                        local color = colors.text
                        
                        if block then
                            if string.find(block.material, "log") then char = "L"; color = colors.brown
                            elseif string.find(block.material, "sapling") then char = "S"; color = colors.green
                            elseif string.find(block.material, "leaves") then char = "#"; color = colors.green
                            elseif string.find(block.material, "water") then char = "~"; color = colors.blue
                            elseif string.find(block.material, "farmland") then char = "_"; color = colors.brown
                            elseif string.find(block.material, "dirt") then char = "."; color = colors.brown
                            elseif string.find(block.material, "stone") then char = "#"; color = colors.gray
                            elseif string.find(block.material, "planks") then char = "="; color = colors.brown
                            elseif string.find(block.material, "torch") then char = "i"; color = colors.yellow
                            elseif string.find(block.material, "wheat") then char = "W"; color = colors.yellow
                            elseif string.find(block.material, "potato") then char = "P"; color = colors.yellow
                            elseif string.find(block.material, "carrot") then char = "C"; color = colors.orange
                            elseif string.find(block.material, "beetroot") then char = "B"; color = colors.red
                            elseif string.find(block.material, "nether_wart") then char = "N"; color = colors.red
                            end
                        end
                        
                        if term.isColor() and color == colors.brown then color = colors.orange end -- Brown not always available
                        
                        term.setTextColor(color)
                        term.write(char)
                    end
                end
            end
        end
    else
        drawText(2, startY + 9, "No preview generated.", colors.gray, colors.bg)
    end
    
    -- Message
    if messageTimer > 0 then
        centerText(h, message, colors.white, colors.red)
        messageTimer = messageTimer - 1
    end
end

local function saveSchema()
    if not generatedSchema then
        message = "Generate a schema first!"
        messageTimer = 30
        return
    end
    
    -- Convert schema to format expected by factory (if different)
    -- lib_strategy_farm returns schema[x][y][z] = { material = ... }
    -- Factory expects... let's check factory.lua or lib_schema.lua
    -- But for now, let's just save what we have.
    
    -- Actually, factory_planner saves a grid of indices into a palette.
    -- But strategies generate actual block names.
    -- We should probably save it as a "blueprint" or "schema" that the factory can read.
    -- The factory likely uses `lib_schema` to parse.
    
    -- Let's save it as a Lua table.
    local file = fs.open(diskPath, "w")
    if not file then
        -- Try local file if disk not found
        file = fs.open(filename, "w")
        if not file then
            message = "Could not open file for writing"
            messageTimer = 30
            return
        end
        message = "Saved to " .. filename
    else
        message = "Saved to " .. diskPath
    end
    
    file.write("return " .. textutils.serialize(generatedSchema))
    file.close()
    messageTimer = 30
end

local function handleEvents()
    local event, p1, p2, p3 = os.pullEvent()
    
    if event == "mouse_click" then
        local button, x, y = p1, p2, p3
        local startY = 3
        
        -- Farm Type
        if y == startY and x >= 14 and x <= 30 then
            selectedTypeIndex = (selectedTypeIndex % #farmTypes) + 1
        end
        
        -- Width
        if y == startY + 2 then
            if x == 14 then width = math.max(1, width - 1)
            elseif x >= 16 and x <= 18 then width = width + 1 -- Rough hit area
            end
        end
        
        -- Length
        if y == startY + 3 then
            if x == 14 then length = math.max(1, length - 1)
            elseif x >= 16 and x <= 18 then length = length + 1
            end
        end
        
        -- Buttons
        if y == startY + 5 then
            if x >= 2 and x <= 12 then -- Generate
                generatedSchema = strategyFarm.generate(farmTypes[selectedTypeIndex], width, length)
                message = "Generated!"
                messageTimer = 20
            elseif x >= 16 and x <= 30 then -- Save
                saveSchema()
            elseif x >= 34 and x <= 40 then -- Exit
                return false
            end
        end
    elseif event == "key" then
        local key = p1
        if key == keys.q or key == keys.x then
            return false
        end
    end
    
    return true
end

-- Main Loop
while true do
    drawUI()
    if not handleEvents() then break end
end

term.clear()
term.setCursorPos(1, 1)
