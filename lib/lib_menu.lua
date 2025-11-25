--[[
    lib_menu.lua
    Simple monochrome, mouse-less navigation system.
    Usage:
        local menu = require("lib_menu")
        local choice = menu.run("Main Menu", {"Option 1", "Option 2", "Exit"})
]]
---@diagnostic disable: undefined-global, undefined-field

local menu = {}

-- Helper to center text
local function centerText(y, text)
    local w, h = term.getSize()
    local x = math.floor((w - #text) / 2) + 1
    term.setCursorPos(x, y)
    term.write(text)
end

function menu.draw(title, options, selectedIndex, scrollOffset)
    local w, h = term.getSize()
    if term.isColor() then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end
    term.clear()
    
    -- Draw Title
    if term.isColor() then
        term.setTextColor(colors.yellow)
    end
    centerText(1, title)
    
    if term.isColor() then
        term.setTextColor(colors.white)
    end
    term.setCursorPos(1, 2)
    term.write(string.rep("-", w))
    
    -- Calculate visible area
    local listStart = 3
    local listHeight = h - 4 -- Reserve space for title (2) and footer (1)
    
    -- Draw Options
    for i = 1, listHeight do
        local optionIndex = i + scrollOffset
        if optionIndex <= #options then
            local option = options[optionIndex]
            local text = type(option) == "table" and option.text or tostring(option)
            
            -- Truncate if too long
            if #text > w - 4 then
                text = string.sub(text, 1, w - 7) .. "..."
            end

            term.setCursorPos(2, listStart + i - 1)
            
            if optionIndex == selectedIndex then
                -- Selected Item
                if term.isColor() then
                    term.setTextColor(colors.lime)
                end
                term.write("> " .. text .. " <")
            else
                -- Normal Item
                if term.isColor() then
                    term.setTextColor(colors.white)
                end
                term.write("  " .. text)
            end
        end
    end
    
    -- Draw Footer
    term.setCursorPos(1, h)
    if term.isColor() then term.setTextColor(colors.gray) end
    local footer = "Up/Down: Move | Enter: Select"
    centerText(h, footer)
    
    -- Reset colors
    if term.isColor() then term.setTextColor(colors.white) end
end

function menu.run(title, options)
    local selectedIndex = 1
    local scrollOffset = 0
    local w, h = term.getSize()
    local listHeight = h - 4
    
    while true do
        -- Adjust scroll to keep selected item in view
        if selectedIndex <= scrollOffset then
            scrollOffset = selectedIndex - 1
        elseif selectedIndex > scrollOffset + listHeight then
            scrollOffset = selectedIndex - listHeight
        end
        
        menu.draw(title, options, selectedIndex, scrollOffset)
        
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            selectedIndex = selectedIndex - 1
            if selectedIndex < 1 then selectedIndex = #options end
        elseif key == keys.down then
            selectedIndex = selectedIndex + 1
            if selectedIndex > #options then selectedIndex = 1 end
        elseif key == keys.enter then
            term.clear()
            term.setCursorPos(1,1)
            return selectedIndex, options[selectedIndex]
        end
    end
end

return menu
