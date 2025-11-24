---@diagnostic disable: undefined-global
-- Factory Planner
-- A tool to design factory layouts and save them to disk for turtles.
-- Features: Mouse control, Palette, Copy/Paste, Schema saving.

local filename = "factory_schema.lua"
local diskPath = "disk/" .. filename

-- Configuration
local gridWidth = 20
local gridHeight = 15
local cellSize = 1 -- 1x1 char per cell? Or maybe 2x1 for square-ish look?
-- Terminals are usually 51x19. 20x15 fits easily.

local palette = {
    { id = "minecraft:air", char = " ", color = colors.black, label = "Air" },
    { id = "minecraft:stone", char = "#", color = colors.gray, label = "Stone" },
    { id = "minecraft:dirt", char = "#", color = colors.brown, label = "Dirt" },
    { id = "minecraft:planks", char = "=", color = colors.orange, label = "Planks" },
    { id = "minecraft:cobblestone", char = "%", color = colors.lightGray, label = "Cobble" },
    { id = "computercraft:turtle_advanced", char = "T", color = colors.yellow, label = "Turtle" },
    { id = "minecraft:chest", char = "C", color = colors.orange, label = "Chest" },
    { id = "minecraft:furnace", char = "F", color = colors.gray, label = "Furnace" },
}

-- State
local grid = {} -- 2D array [y][x] = paletteIndex
local selectedPaletteIndex = 2 -- Default to Stone
local clipboard = nil
local isRunning = true
local message = "Welcome to Factory Planner"
local messageTimer = 0

-- Initialize Grid
for y = 1, gridHeight do
    grid[y] = {}
    for x = 1, gridWidth do
        grid[y][x] = 1 -- Air
    end
end

-- Helper Functions
local function clear()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawRect(x, y, w, h, color)
    term.setBackgroundColor(color)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end
end

local function drawText(x, y, text, fg, bg)
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
    term.setCursorPos(x, y)
    term.write(text)
end

-- Drawing
local function draw()
    clear()

    -- Draw Grid
    local startX = 2
    local startY = 2
    
    -- Draw Border
    drawRect(startX - 1, startY - 1, gridWidth + 2, gridHeight + 2, colors.white)
    drawRect(startX, startY, gridWidth, gridHeight, colors.black)

    for y = 1, gridHeight do
        for x = 1, gridWidth do
            local itemIndex = grid[y][x]
            local item = palette[itemIndex]
            drawText(startX + x - 1, startY + y - 1, item.char, item.color, colors.black)
        end
    end

    -- Draw Palette
    local palX = startX + gridWidth + 3
    local palY = 2
    drawText(palX, palY - 1, "Palette:", colors.white, colors.black)
    
    for i, item in ipairs(palette) do
        local prefix = (i == selectedPaletteIndex) and "> " or "  "
        drawText(palX, palY + i - 1, prefix .. item.char .. " " .. item.label, item.color, colors.black)
    end

    -- Draw Controls / Help
    local helpX = palX
    local helpY = palY + #palette + 2
    drawText(helpX, helpY, "Controls:", colors.white, colors.black)
    drawText(helpX, helpY + 1, "L-Click: Paint", colors.lightGray, colors.black)
    drawText(helpX, helpY + 2, "R-Click: Erase", colors.lightGray, colors.black)
    drawText(helpX, helpY + 3, "C: Copy Grid", colors.lightGray, colors.black)
    drawText(helpX, helpY + 4, "V: Paste Grid", colors.lightGray, colors.black)
    drawText(helpX, helpY + 5, "S: Save to Disk", colors.lightGray, colors.black)
    drawText(helpX, helpY + 6, "Q: Quit", colors.lightGray, colors.black)

    -- Draw Message
    if messageTimer > 0 then
        drawText(2, gridHeight + 4, message, colors.yellow, colors.black)
    end
end

-- Logic
local function saveSchema()
    local data = {
        width = gridWidth,
        height = gridHeight,
        palette = palette,
        grid = grid
    }
    
    -- Try to save to disk first
    local path = filename
    if fs.exists("disk") then
        path = diskPath
    end

    local file = fs.open(path, "w")
    if file then
        file.write(textutils.serialize(data))
        file.close()
        message = "Saved to " .. path
    else
        message = "Error saving to " .. path
    end
    messageTimer = 50
end

local function copyGrid()
    clipboard = textutils.unserialize(textutils.serialize(grid)) -- Deep copy
    message = "Grid copied to clipboard"
    messageTimer = 30
end

local function pasteGrid()
    if clipboard then
        grid = textutils.unserialize(textutils.serialize(clipboard))
        message = "Grid pasted from clipboard"
    else
        message = "Clipboard empty"
    end
    messageTimer = 30
end

local function handleMouse(button, x, y)
    -- Grid Coordinates
    local startX = 2
    local startY = 2
    
    local gx = x - startX + 1
    local gy = y - startY + 1

    if gx >= 1 and gx <= gridWidth and gy >= 1 and gy <= gridHeight then
        if button == 1 then -- Left Click
            grid[gy][gx] = selectedPaletteIndex
        elseif button == 2 then -- Right Click
            grid[gy][gx] = 1 -- Air
        end
    else
        -- Check Palette Click
        local palX = startX + gridWidth + 3
        local palY = 2
        
        if x >= palX and x <= palX + 15 then -- Approximate width
            local py = y - palY + 1
            if py >= 1 and py <= #palette then
                selectedPaletteIndex = py
            end
        end
    end
end

local function handleKey(key)
    if key == keys.q then
        isRunning = false
    elseif key == keys.s then
        saveSchema()
    elseif key == keys.c then
        copyGrid()
    elseif key == keys.v then
        pasteGrid()
    end
end

-- Main Loop
while isRunning do
    draw()
    
    local event, p1, p2, p3 = os.pullEvent()
    
    if event == "mouse_click" or event == "mouse_drag" then
        handleMouse(p1, p2, p3)
    elseif event == "key" then
        handleKey(p1)
    elseif event == "timer" then
        if p1 == messageTimerId then
            -- Timer handled
        end
    end

    if messageTimer > 0 then
        messageTimer = messageTimer - 1
    end
end

clear()
print("Exited Factory Planner")
