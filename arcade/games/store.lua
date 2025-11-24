local arcade = require("arcade")
local programs = require("data.programs")

local function getStoreItems()
    local items = {}
    if type(programs) ~= "table" then return items end
    
    for _, p in ipairs(programs) do
        -- Only show items that have a price (even 0) and are not the store itself
        if p.id ~= "store" then
            table.insert(items, p)
        end
    end
    return items
end

local storeItems = getStoreItems()
local currentIndex = 1
local statusMsg = ""
local statusColor = colors.gray

local function isInstalled(item)
    -- Assume standard path structure
    local path = fs.combine("arcade", item.path)
    return fs.exists(path)
end

local function downloadItem(item)
    if not http then return false, "No HTTP" end
    if not item.url then return false, "No URL" end
    
    local response = http.get(item.url)
    if not response then return false, "Connect Fail" end
    
    local content = response.readAll()
    response.close()
    
    local path = fs.combine("arcade", item.path)
    local dir = fs.getDir(path)
    if not fs.exists(dir) then fs.makeDir(dir) end
    
    local f = fs.open(path, "w")
    if f then
        f.write(content)
        f.close()
        return true
    end
    return false, "Write Fail"
end

local game = {
    name = "App Store",
    
    init = function(a)
        a:setButtons({"Prev", "Buy/DL", "Next"})
    end,

    draw = function(a)
        a:clearPlayfield()
        a:centerPrint(2, "App Store", colors.yellow)
        
        if #storeItems == 0 then
            a:centerPrint(6, "No apps found.", colors.red)
            a:centerPrint(8, "Check data/programs.lua", colors.gray)
            return
        end

        local item = storeItems[currentIndex]
        if not item then
            currentIndex = 1
            item = storeItems[currentIndex]
        end
        
        if item then
            a:centerPrint(4, item.name, colors.white)
            a:centerPrint(6, "Price: " .. (item.price or 0) .. " Credits", colors.lightGray)
            a:centerPrint(8, item.description or "", colors.gray)
            
            if isInstalled(item) then
                a:centerPrint(10, "INSTALLED", colors.green)
            else
                a:centerPrint(10, "Available", colors.blue)
            end
        end
        
        if statusMsg ~= "" then
            a:centerPrint(12, statusMsg, statusColor)
        end
    end,

    onButton = function(a, button)
        if #storeItems == 0 then return end
        
        if button == "left" then
            currentIndex = currentIndex - 1
            if currentIndex < 1 then currentIndex = #storeItems end
            statusMsg = ""
        elseif button == "center" then
            local item = storeItems[currentIndex]
            if item and not isInstalled(item) then
                if a:getCredits() >= (item.price or 0) then
                    statusMsg = "Downloading..."
                    statusColor = colors.yellow
                    a:clearPlayfield() 
                    
                    if a:consumeCredits(item.price or 0) then
                        local ok, err = downloadItem(item)
                        if ok then
                            statusMsg = "Success!"
                            statusColor = colors.green
                        else
                            statusMsg = "Error: " .. (err or "?")
                            statusColor = colors.red
                            -- Refund?
                            a:addCredits(item.price or 0)
                        end
                    else
                         statusMsg = "Error consuming credits"
                         statusColor = colors.red
                    end
                else
                    statusMsg = "Not enough credits!"
                    statusColor = colors.red
                end
            elseif item then
                statusMsg = "Already installed"
                statusColor = colors.green
            end
        elseif button == "right" then
            currentIndex = currentIndex + 1
            if currentIndex > #storeItems then currentIndex = 1 end
            statusMsg = ""
        end
    end
}

arcade.start(game)

