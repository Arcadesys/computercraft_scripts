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
local gridDepth = 5 -- Number of layers
local menuHeight = 1

local TOOLS = {
    PENCIL = "Pencil",
    LINE = "Line",
    RECT = "Rect",
    RECT_FILL = "FillRect",
    CIRCLE = "Circle",
    CIRCLE_FILL = "FillCircle",
    BUCKET = "Bucket",
    PICKER = "Picker"
}

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
local layers = {} -- 3D array [z][y][x] = paletteIndex
local currentLayer = 1
local grid = {} -- Reference to current layer [y][x]
local selectedPaletteIndex = 2 -- Default to Stone
local currentTool = TOOLS.PENCIL
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

-- Mouse State for Tools
local mouseState = {
    isDown = false,
    startX = 0,
    startY = 0,
    currX = 0,
    currY = 0,
    button = 1
}

-- Edit Menu State
local isEditMenuOpen = false
local showResize = false
local resizeWidthInput = ""
local resizeHeightInput = ""
local activeResizeInput = 1

-- Initialize Layers
for z = 1, gridDepth do
    layers[z] = {}
    for y = 1, gridHeight do
        layers[z][y] = {}
        for x = 1, gridWidth do
            layers[z][y][x] = 1 -- Air
        end
    end
end
grid = layers[currentLayer]

local function updateSearchResults()
    searchResults = {}
    if searchQuery == "" then return end
    for _, block in ipairs(blockList) do
        -- Use plain search (4th arg = true) to avoid pattern matching errors with special chars
        local labelMatch = block.label and string.find(string.lower(block.label), string.lower(searchQuery), 1, true)
        local idMatch = block.id and string.find(string.lower(block.id), string.lower(searchQuery), 1, true)
        
        if labelMatch or idMatch then
            table.insert(searchResults, block)
        end
    end
end

-- Tool Algorithms
local function drawLine(x0, y0, x1, y1, callback)
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy

    while true do
        callback(x0, y0)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x0 = x0 + sx
        end
        if e2 < dx then
            err = err + dx
            y0 = y0 + sy
        end
    end
end

local function drawRectShape(x0, y0, x1, y1, filled, callback)
    local minX, maxX = math.min(x0, x1), math.max(x0, x1)
    local minY, maxY = math.min(y0, y1), math.max(y0, y1)
    
    for y = minY, maxY do
        for x = minX, maxX do
            if filled or (x == minX or x == maxX or y == minY or y == maxY) then
                callback(x, y)
            end
        end
    end
end

local function drawCircleShape(x0, y0, x1, y1, filled, callback)
    -- Midpoint circle algorithm adapted for ellipse/bounds
    local r = math.floor(math.min(math.abs(x1 - x0), math.abs(y1 - y0)) / 2)
    local cx = math.floor((x0 + x1) / 2)
    local cy = math.floor((y0 + y1) / 2)
    
    local x = r
    local y = 0
    local err = 0

    while x >= y do
        if filled then
            for i = cx - x, cx + x do callback(i, cy + y); callback(i, cy - y) end
            for i = cx - y, cx + y do callback(i, cy + x); callback(i, cy - x) end
        else
            callback(cx + x, cy + y)
            callback(cx + y, cy + x)
            callback(cx - y, cy + x)
            callback(cx - x, cy + y)
            callback(cx - x, cy - y)
            callback(cx - y, cy - x)
            callback(cx + y, cy - x)
            callback(cx + x, cy - y)
        end

        if err <= 0 then
            y = y + 1
            err = err + 2 * y + 1
        end
        if err > 0 then
            x = x - 1
            err = err - 2 * x + 1
        end
    end
end

local function floodFill(startX, startY, targetIndex, replaceIndex)
    if targetIndex == replaceIndex then return end
    if grid[startY][startX] ~= targetIndex then return end
    
    local queue = { {x = startX, y = startY} }
    local visited = {}
    
    local function key(x, y) return x .. "," .. y end
    
    while #queue > 0 do
        local p = table.remove(queue, 1)
        local k = key(p.x, p.y)
        
        if not visited[k] then
            visited[k] = true
            
            if grid[p.y] and grid[p.y][p.x] == targetIndex then
                grid[p.y][p.x] = replaceIndex
                
                local neighbors = {
                    {x = p.x + 1, y = p.y},
                    {x = p.x - 1, y = p.y},
                    {x = p.x, y = p.y + 1},
                    {x = p.x, y = p.y - 1}
                }
                
                for _, n in ipairs(neighbors) do
                    if n.x >= 1 and n.x <= gridWidth and n.y >= 1 and n.y <= gridHeight then
                        table.insert(queue, n)
                    end
                end
            end
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
    drawText(8, 1, "Edit", colors.white, colors.gray)
    local drawerText = isDrawerOpen and "Hide >>" or "Show <<"
    drawText(40, 1, drawerText, colors.white, colors.gray)
    
    -- Draw Layer Info
    drawText(20, 1, "Layer: " .. currentLayer .. "/" .. gridDepth, colors.yellow, colors.gray)

    -- Draw Grid
    local startX = 2
    local startY = 2 + menuHeight
    
    -- Draw Border
    drawRect(startX - 1, startY - 1, gridWidth + 2, gridHeight + 2, colors.white)
    drawRect(startX, startY, gridWidth, gridHeight, colors.black)

    -- Draw Base Grid
    for y = 1, gridHeight do
        for x = 1, gridWidth do
            local itemIndex = grid[y][x]
            local item = palette[itemIndex]
            drawText(startX + x - 1, startY + y - 1, item.char, item.color, colors.black)
        end
    end
    
    -- Draw Ghost of Lower Layer (if current layer is air)
    if currentLayer > 1 then
        for y = 1, gridHeight do
            for x = 1, gridWidth do
                if grid[y][x] == 1 then -- If current is air
                    local lowerIndex = layers[currentLayer - 1][y][x]
                    if lowerIndex ~= 1 then
                        local item = palette[lowerIndex]
                        drawText(startX + x - 1, startY + y - 1, ".", item.color, colors.black)
                    end
                end
            end
        end
    end

    -- Draw Tool Preview
    if mouseState.isDown and mouseState.currX > 0 then
        local function previewCallback(x, y)
            if x >= 1 and x <= gridWidth and y >= 1 and y <= gridHeight then
                local item = palette[selectedPaletteIndex]
                if mouseState.button == 2 then item = palette[1] end -- Eraser
                drawText(startX + x - 1, startY + y - 1, item.char, item.color, colors.black)
            end
        end

        if currentTool == TOOLS.LINE then
            drawLine(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, previewCallback)
        elseif currentTool == TOOLS.RECT then
            drawRectShape(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, false, previewCallback)
        elseif currentTool == TOOLS.RECT_FILL then
            drawRectShape(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, true, previewCallback)
        elseif currentTool == TOOLS.CIRCLE then
            drawCircleShape(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, false, previewCallback)
        elseif currentTool == TOOLS.CIRCLE_FILL then
            drawCircleShape(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, true, previewCallback)
        end
    end

    -- Draw Drawer (Palette & Controls)
    if isDrawerOpen then
        local palX = startX + gridWidth + 3
        local palY = startY
        
        -- Background for drawer
        drawRect(palX - 1, 2, 20, 18, colors.black) -- Clear area

        -- Tools Section
        drawText(palX, palY - 1, "Tools:", colors.white, colors.black)
        local toolList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
        for i, tool in ipairs(toolList) do
            local prefix = (tool == currentTool) and "> " or "  "
            drawText(palX, palY + i - 1, prefix .. tool, colors.lightGray, colors.black)
        end

        local palOffsetY = #toolList + 2
        drawText(palX, palY + palOffsetY - 1, "Palette:", colors.white, colors.black)
        
        for i, item in ipairs(palette) do
            local prefix = (i == selectedPaletteIndex) and "> " or "  "
            drawText(palX, palY + palOffsetY + i - 1, prefix .. item.char .. " " .. item.label, item.color, colors.black)
        end

        -- Draw Controls / Help
        local helpX = palX
        local helpY = palY + palOffsetY + #palette + 2
        drawText(helpX, helpY, "Controls:", colors.white, colors.black)
        drawText(helpX, helpY + 1, "L-Click: Paint", colors.lightGray, colors.black)
        drawText(helpX, helpY + 2, "R-Click: Erase", colors.lightGray, colors.black)
        drawText(helpX, helpY + 3, "C: Copy Layer", colors.lightGray, colors.black)
        drawText(helpX, helpY + 4, "V: Paste Layer", colors.lightGray, colors.black)
        drawText(helpX, helpY + 5, "PgUp/Dn: Layer", colors.lightGray, colors.black)
    end

    -- Draw Edit Menu
    if isEditMenuOpen then
        drawRect(8, 2, 10, 2, colors.lightGray)
        drawText(9, 2, "Palette", colors.black, colors.lightGray)
        drawText(9, 3, "Size", colors.black, colors.lightGray)
    end

    -- Draw Resize Dialog
    if showResize then
        local rx, ry, rw, rh = 10, 5, 30, 8
        drawRect(rx, ry, rw, rh, colors.blue)
        drawRect(rx + 1, ry + 1, rw - 2, rh - 2, colors.black)
        
        drawText(rx + 2, ry + 2, "Resize Grid", colors.white, colors.black)
        
        drawText(rx + 2, ry + 4, "Width:  " .. resizeWidthInput .. (activeResizeInput == 1 and "_" or ""), colors.white, colors.black)
        drawText(rx + 2, ry + 5, "Height: " .. resizeHeightInput .. (activeResizeInput == 2 and "_" or ""), colors.white, colors.black)
        
        drawText(rx + 2, ry + 7, "Enter to Apply", colors.gray, colors.black)
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
        depth = gridDepth,
        palette = palette,
        layers = layers
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
    message = "Layer copied to clipboard"
    messageTimer = 30
end

local function pasteGrid()
    if clipboard then
        local newGrid = textutils.unserialize(textutils.serialize(clipboard))
        layers[currentLayer] = newGrid
        grid = newGrid
        message = "Layer pasted from clipboard"
    else
        message = "Clipboard empty"
    end
    messageTimer = 30
end

local function handleMouse(event, button, x, y)
    if showSearch then return end -- Modal blocks clicks
    if showResize then return end -- Modal blocks clicks

    -- Menu Bar Click
    if y == 1 and event == "mouse_click" then
        if x >= 2 and x <= 6 then -- Save
            saveSchema()
            isEditMenuOpen = false
        elseif x >= 8 and x <= 12 then -- Edit
            isEditMenuOpen = not isEditMenuOpen
        elseif x >= 40 and x <= 50 then -- Drawer
            isDrawerOpen = not isDrawerOpen
            isEditMenuOpen = false
        else
            isEditMenuOpen = false
        end
        return
    end

    -- Edit Menu Click
    if isEditMenuOpen and event == "mouse_click" then
        if x >= 8 and x <= 17 then
            if y == 2 then -- Palette
                showSearch = true
                searchQuery = ""
                updateSearchResults()
                isEditMenuOpen = false
                return
            elseif y == 3 then -- Size
                showResize = true
                resizeWidthInput = tostring(gridWidth)
                resizeHeightInput = tostring(gridHeight)
                activeResizeInput = 1
                isEditMenuOpen = false
                return
            end
        end
        isEditMenuOpen = false -- Clicked outside menu
        return 
    end

    -- Grid Coordinates
    local startX = 2
    local startY = 2 + menuHeight
    
    local gx = x - startX + 1
    local gy = y - startY + 1

    if gx >= 1 and gx <= gridWidth and gy >= 1 and gy <= gridHeight then
        if event == "mouse_click" then
            mouseState.isDown = true
            mouseState.startX = gx
            mouseState.startY = gy
            mouseState.currX = gx
            mouseState.currY = gy
            mouseState.button = button

            if currentTool == TOOLS.PENCIL then
                if button == 1 then grid[gy][gx] = selectedPaletteIndex
                elseif button == 2 then grid[gy][gx] = 1 end
            elseif currentTool == TOOLS.BUCKET then
                local targetIdx = grid[gy][gx]
                local replaceIdx = (button == 1) and selectedPaletteIndex or 1
                floodFill(gx, gy, targetIdx, replaceIdx)
            elseif currentTool == TOOLS.PICKER then
                if button == 1 then
                    selectedPaletteIndex = grid[gy][gx]
                    currentTool = TOOLS.PENCIL -- Switch back to pencil after picking
                    message = "Picked " .. palette[selectedPaletteIndex].label
                    messageTimer = 30
                end
            end
        elseif event == "mouse_drag" and mouseState.isDown then
            mouseState.currX = gx
            mouseState.currY = gy
            
            if currentTool == TOOLS.PENCIL then
                if mouseState.button == 1 then grid[gy][gx] = selectedPaletteIndex
                elseif mouseState.button == 2 then grid[gy][gx] = 1 end
            end
        elseif event == "mouse_up" and mouseState.isDown then
            mouseState.isDown = false
            mouseState.currX = gx
            mouseState.currY = gy
            
            local function commitCallback(cx, cy)
                if cx >= 1 and cx <= gridWidth and cy >= 1 and cy <= gridHeight then
                    if mouseState.button == 1 then grid[cy][cx] = selectedPaletteIndex
                    elseif mouseState.button == 2 then grid[cy][cx] = 1 end
                end
            end

            if currentTool == TOOLS.LINE then
                drawLine(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, commitCallback)
            elseif currentTool == TOOLS.RECT then
                drawRectShape(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, false, commitCallback)
            elseif currentTool == TOOLS.RECT_FILL then
                drawRectShape(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, true, commitCallback)
            elseif currentTool == TOOLS.CIRCLE then
                drawCircleShape(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, false, commitCallback)
            elseif currentTool == TOOLS.CIRCLE_FILL then
                drawCircleShape(mouseState.startX, mouseState.startY, mouseState.currX, mouseState.currY, true, commitCallback)
            end
        end
    elseif isDrawerOpen and event == "mouse_click" then
        -- Check Palette & Tools Click
        local palX = startX + gridWidth + 3
        local palY = startY
        
        if x >= palX and x <= palX + 15 then -- Approximate width
            local py = y - palY + 1
            local toolList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
            
            if py >= 1 and py <= #toolList then
                currentTool = toolList[py]
            else
                local palOffsetY = #toolList + 2
                local palIndex = py - palOffsetY
                if palIndex >= 1 and palIndex <= #palette then
                    selectedPaletteIndex = palIndex
                end
            end
        end
    elseif event == "mouse_up" then
        mouseState.isDown = false
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

    if showResize then
        if key == keys.enter then
            local w = tonumber(resizeWidthInput)
            local h = tonumber(resizeHeightInput)
            if w and h and w > 0 and h > 0 then
                -- Resize grid
                local newLayers = {}
                for z = 1, gridDepth do
                    newLayers[z] = {}
                    for y = 1, h do
                        newLayers[z][y] = {}
                        for x = 1, w do
                            if y <= gridHeight and x <= gridWidth then
                                newLayers[z][y][x] = layers[z][y][x]
                            else
                                newLayers[z][y][x] = 1 -- Air
                            end
                        end
                    end
                end
                layers = newLayers
                grid = layers[currentLayer]
                gridWidth = w
                gridHeight = h
                message = "Resized to " .. w .. "x" .. h
                messageTimer = 30
            end
            showResize = false
        elseif key == keys.tab then
            activeResizeInput = (activeResizeInput % 2) + 1
        elseif key == keys.backspace then
            if activeResizeInput == 1 then
                resizeWidthInput = string.sub(resizeWidthInput, 1, -2)
            else
                resizeHeightInput = string.sub(resizeHeightInput, 1, -2)
            end
        elseif key == keys.escape then
            showResize = false
        elseif char and tonumber(char) then
            if activeResizeInput == 1 then
                resizeWidthInput = resizeWidthInput .. char
            else
                resizeHeightInput = resizeHeightInput .. char
            end
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
    elseif key == keys.pageUp then
        if currentLayer < gridDepth then
            currentLayer = currentLayer + 1
            grid = layers[currentLayer]
            message = "Layer " .. currentLayer
            messageTimer = 20
        end
    elseif key == keys.pageDown then
        if currentLayer > 1 then
            currentLayer = currentLayer - 1
            grid = layers[currentLayer]
            message = "Layer " .. currentLayer
            messageTimer = 20
        end
    end
end

-- Main Loop
while isRunning do
    draw()
    
    local event, p1, p2, p3 = os.pullEvent()
    
    if event == "mouse_click" or event == "mouse_drag" or event == "mouse_up" then
        handleMouse(event, p1, p2, p3)
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
