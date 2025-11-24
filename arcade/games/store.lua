local arcade = require("arcade")

local storeItems = {
    { name = "Snake", price = 0, description = "Classic Snake game" },
    { name = "Tetris", price = 10, description = "Block stacking fun" },
    { name = "Pong", price = 5, description = "Table tennis" },
    { name = "Space Invaders", price = 15, description = "Shoot aliens" }
}

local currentIndex = 1

local game = {
    name = "App Store",
    
    init = function(a)
        a:setButtons({"Prev", "Buy", "Next"})
    end,

    draw = function(a)
        a:clearPlayfield()
        a:centerPrint(2, "App Store", colors.yellow)
        
        local item = storeItems[currentIndex]
        a:centerPrint(4, item.name, colors.white)
        a:centerPrint(6, "Price: " .. item.price .. " Credits", colors.lightGray)
        a:centerPrint(8, item.description, colors.gray)
        
        if item.installed then
            a:centerPrint(10, "INSTALLED", colors.green)
        else
            a:centerPrint(10, "Available", colors.blue)
        end
    end,

    onButton = function(a, button)
        if button == "left" then
            currentIndex = currentIndex - 1
            if currentIndex < 1 then currentIndex = #storeItems end
        elseif button == "center" then
            local item = storeItems[currentIndex]
            if not item.installed then
                if a:consumeCredits(item.price) then
                    item.installed = true
                    -- In a real app, we would download the file here.
                    -- For now, we just mark it as installed in this session.
                else
                    -- Flash error?
                end
            end
        elseif button == "right" then
            currentIndex = currentIndex + 1
            if currentIndex > #storeItems then currentIndex = 1 end
        end
    end
}

arcade.start(game)

