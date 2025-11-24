local arcade = require("arcade")

local themes = {
    {
        name = "Default",
        skin = {
            background = colors.black,
            playfield = colors.black,
            buttonBar = { background = colors.black },
            titleColor = colors.orange,
            buttons = {
                enabled = { labelColor = colors.orange, shadowColor = colors.gray },
                disabled = { labelColor = colors.lightGray, shadowColor = colors.black }
            }
        }
    },
    {
        name = "Ocean",
        skin = {
            background = colors.blue,
            playfield = colors.lightBlue,
            buttonBar = { background = colors.blue },
            titleColor = colors.cyan,
            buttons = {
                enabled = { labelColor = colors.white, shadowColor = colors.blue },
                disabled = { labelColor = colors.gray, shadowColor = colors.blue }
            }
        }
    },
    {
        name = "Forest",
        skin = {
            background = colors.green,
            playfield = colors.lime,
            buttonBar = { background = colors.green },
            titleColor = colors.yellow,
            buttons = {
                enabled = { labelColor = colors.white, shadowColor = colors.green },
                disabled = { labelColor = colors.gray, shadowColor = colors.green }
            }
        }
    },
    {
        name = "Retro",
        skin = {
            background = colors.gray,
            playfield = colors.lightGray,
            buttonBar = { background = colors.gray },
            titleColor = colors.black,
            buttons = {
                enabled = { labelColor = colors.black, shadowColor = colors.white },
                disabled = { labelColor = colors.gray, shadowColor = colors.white }
            }
        }
    }
}

local currentIndex = 1

local game = {
    name = "Theme Switcher",
    
    init = function(a)
        a:setButtons({"Prev", "Apply", "Next"})
    end,

    draw = function(a)
        a:clearPlayfield()
        a:centerPrint(2, "Select Theme", colors.white)
        
        local theme = themes[currentIndex]
        a:centerPrint(5, theme.name, theme.skin.titleColor)
        
        a:centerPrint(8, "Press Apply to set", colors.lightGray)
        a:centerPrint(10, "Right click to Quit", colors.gray)
    end,

    onButton = function(a, button)
        if button == "left" then
            currentIndex = currentIndex - 1
            if currentIndex < 1 then currentIndex = #themes end
        elseif button == "center" then
            local theme = themes[currentIndex]
            a:setSkin(theme.skin)
        elseif button == "right" then
            currentIndex = currentIndex + 1
            if currentIndex > #themes then currentIndex = 1 end
        end
    end
}

arcade.start(game)

