---@diagnostic disable: undefined-global, undefined-field
-- Clear potentially failed loads
package.loaded["arcade"] = nil
package.loaded["log"] = nil

local function setupPaths()
    local program = shell.getRunningProgram()
    -- themes is in arcade/games/themes.lua
    -- dir is arcade/games
    -- root is arcade
    -- parent of root is installation root
    local gamesDir = fs.getDir(program)
    local arcadeDir = fs.getDir(gamesDir)
    local root = fs.getDir(arcadeDir)
    
    local function add(path)
        local part = fs.combine(root, path)
        -- fs.combine strips leading slashes, so we force absolute path
        local pattern = "/" .. fs.combine(part, "?.lua")
        
        if not string.find(package.path, pattern, 1, true) then
            package.path = package.path .. ";" .. pattern
        end
    end
    
    add("lib")
    add("arcade")

    -- Ensure root is in path so require("arcade.ui.renderer") works
    if not string.find(package.path, ";/?.lua", 1, true) then
        package.path = package.path .. ";/?.lua"
    end
end

setupPaths()

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
local SKIN_FILE = "arcade_skin.settings"

local function saveSkin(skin)
    local f = fs.open(SKIN_FILE, "w")
    if f then
        f.write(textutils.serialize(skin))
        f.close()
    end
end

local function loadSkin()
    if fs.exists(SKIN_FILE) then
        local f = fs.open(SKIN_FILE, "r")
        if f then
            local content = f.readAll()
            f.close()
            return textutils.unserialize(content)
        end
    end
    return nil
end

-- UI
local w, h = term.getSize()
local currentSkin = loadSkin()

local function draw()
    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" Theme Switcher")
    
    -- Footer
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" Enter: Apply  Q: Quit")
    
    -- List
    for i, theme in ipairs(themes) do
        local y = i + 2
        term.setCursorPos(1, y)
        term.clearLine()
        
        if i == currentIndex then
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
        else
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
        end
        
        term.write(" " .. theme.name)
        
        -- Indicate active
        if currentSkin and currentSkin.background == theme.skin.background and currentSkin.titleColor == theme.skin.titleColor then
            term.setCursorPos(w - 8, y)
            term.setTextColor(colors.green)
            term.write("(Active)")
        end
    end
end

while true do
    draw()
    local ev, p1 = os.pullEvent()
    if ev == "key" then
        if p1 == keys.up then
            currentIndex = currentIndex - 1
            if currentIndex < 1 then currentIndex = #themes end
        elseif p1 == keys.down then
            currentIndex = currentIndex + 1
            if currentIndex > #themes then currentIndex = 1 end
        elseif p1 == keys.enter then
            local theme = themes[currentIndex]
            saveSkin(theme.skin)
            currentSkin = theme.skin
            
            term.setCursorPos(1, h-1)
            term.setBackgroundColor(colors.green)
            term.setTextColor(colors.white)
            term.clearLine()
            term.write(" Theme Applied! ")
            os.sleep(1)
        elseif p1 == keys.q then
            break
        end
    end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)

