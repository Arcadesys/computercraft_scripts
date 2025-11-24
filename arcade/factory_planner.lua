---@diagnostic disable: undefined-global
-- Factory Planner
-- A tool to design factory layouts and save them to disk for turtles.
-- Features: Mouse control, Palette, Copy/Paste, Schema saving.
-- Version: 2.0 (Search & Drawer Update)

print("Loading Factory Planner v2.0...")
sleep(1)

-- Load Block Data
local blockList = {}
local ok, mod = pcall(require, "arcade.data.valhelsia_blocks")
if not ok then
    ok, mod = pcall(require, "data.valhelsia_blocks")
end
if ok then blockList = mod end

local filename = "factory_schema.lua"
local diskPath = "disk/" .. filename

-- Configuration
local gridWidth = 20
local gridHeight = 15
local menuHeight = 1

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

-- UI State
local isDrawerOpen = false
local showSearch = false
local searchQuery = ""
local searchResults = {}
local searchScroll = 1

-- Initialize Grid
for y = 1, gridHeight do
    grid[y] = {}
    for x = 1, gridWidth do
        grid[y][x] = 1 -- Air
    end
end

local function updateSearchResults()
    searchResults = {}
    if searchQuery == "" then return end
    for _, block in ipairs(blockList) do
        if string.find(string.lower(block.label), string.lower(searchQuery)) or 
           string.find(string.lower(block.id), string.lower(searchQuery)) then
            table.insert(searchResults, block)
        end
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

    -- Draw Menu Bar
    drawRect(1, 1, 51, 1, colors.gray)
    drawText(2, 1, "Save", colors.white, colors.gray)
    drawText(8, 1, "Search", colors.white, colors.gray)
    local drawerText = isDrawerOpen and "Hide >>" or "Show <<"
    drawText(40, 1, drawerText, colors.white, colors.gray)

    -- Draw Grid
    local startX = 2
    local startY = 2 + menuHeight
    
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

    -- Draw Drawer (Palette & Controls)
    if isDrawerOpen then
        local palX = startX + gridWidth + 3
        local palY = startY
        
        -- Background for drawer
        drawRect(palX - 1, 2, 20, 18, colors.black) -- Clear area

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
    end

    -- Draw Search Overlay
    if showSearch then
        local sx, sy = 5, 4
        local sw, sh = 40, 12
        drawRect(sx, sy, sw, sh, colors.blue)
        drawRect(sx + 1, sy + 1, sw - 2, sh - 2, colors.black)
        
        drawText(sx + 2, sy + 2, "Search Block: " .. searchQuery .. "_", colors.white, colors.black)
        
        for i = 1, sh - 4 do
            local idx = searchScroll + i - 1
            if idx <= #searchResults then
                local block = searchResults[idx]
                drawText(sx + 2, sy + 3 + i, block.label, colors.lightGray, colors.black)
            end
        end
        
        drawText(sx + 2, sy + sh - 1, "Enter to Add, Esc to Close", colors.gray, colors.black)
    end

    -- Draw Message
    if messageTimer > 0 then
        drawText(2, gridHeight + 4 + menuHeight, message, colors.yellow, colors.black)
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
    if showSearch then return end -- Modal blocks clicks

    -- Menu Bar Click
    if y == 1 then
        if x >= 2 and x <= 6 then -- Save
            saveSchema()
        elseif x >= 8 and x <= 14 then -- Search
            showSearch = true
            searchQuery = ""
            updateSearchResults()
        elseif x >= 40 and x <= 50 then -- Drawer
            isDrawerOpen = not isDrawerOpen
        end
        return
    end

    -- Grid Coordinates
    local startX = 2
    local startY = 2 + menuHeight
    
    local gx = x - startX + 1
    local gy = y - startY + 1

    if gx >= 1 and gx <= gridWidth and gy >= 1 and gy <= gridHeight then
        if button == 1 then -- Left Click
            grid[gy][gx] = selectedPaletteIndex
        elseif button == 2 then -- Right Click
            grid[gy][gx] = 1 -- Air
        end
    elseif isDrawerOpen then
        -- Check Palette Click
        local palX = startX + gridWidth + 3
        local palY = startY
        
        if x >= palX and x <= palX + 15 then -- Approximate width
            local py = y - palY + 1
            if py >= 1 and py <= #palette then
                selectedPaletteIndex = py
            end
        end
    end
end

local function handleKey(key, char)
    if showSearch then
        if key == keys.enter then
            if #searchResults > 0 then
                -- Add first result to palette
                local block = searchResults[1]
                table.insert(palette, {
                    id = block.id,
                    char = string.sub(block.label, 1, 1),
                    color = colors.cyan,
                    label = block.label
                })
                selectedPaletteIndex = #palette
                message = "Added " .. block.label
                messageTimer = 30
                showSearch = false
            end
        elseif key == keys.backspace then
            searchQuery = string.sub(searchQuery, 1, -2)
            updateSearchResults()
        elseif key == keys.escape then
            showSearch = false
        elseif char then
            searchQuery = searchQuery .. char
            updateSearchResults()
        end
        return
    end

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
        handleKey(p1, nil)
    elseif event == "char" then
        handleKey(nil, p1)
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
