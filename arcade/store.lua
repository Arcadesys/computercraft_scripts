-- store.lua
-- App Store for Arcade

-- Clear potentially failed loads
package.loaded["arcade"] = nil
package.loaded["log"] = nil

local function setupPaths()
    local program = shell.getRunningProgram()
    local dir = fs.getDir(program)
    local root = fs.getDir(dir)
    
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
end

setupPaths()

local programs = require("data.programs")
local LicenseStore = require("license_store")

-- Configuration
local CREDITS_FILE = "credits.txt"
local LICENSE_DIR = "licenses"

-- Helpers
local function getDiskPath()
    local drive = peripheral.find("drive")
    if drive and drive.getMountPath then
        return drive.getMountPath()
    end
    return nil
end

local function getCreditsPath()
    local disk = getDiskPath()
    if disk then return fs.combine(disk, CREDITS_FILE) end
    return CREDITS_FILE
end

local function loadCredits()
    local path = getCreditsPath()
    if fs.exists(path) then
        local f = fs.open(path, "r")
        if f then
            local n = tonumber(f.readAll())
            f.close()
            return n or 0
        end
    end
    return 0
end

local function saveCredits(amount)
    local path = getCreditsPath()
    local f = fs.open(path, "w")
    if f then
        f.write(tostring(amount))
        f.close()
    end
end

local function getLicenseStore()
    local disk = getDiskPath()
    local root = disk or ""
    local path = fs.combine(root, LICENSE_DIR)
    return LicenseStore.new(path)
end

local function isInstalled(item)
    local path = fs.combine("arcade", item.path)
    return fs.exists(path)
end

local function downloadItem(item)
    if not http then return false, "HTTP API disabled" end
    if not item.url then return false, "No URL" end
    
    local response = http.get(item.url)
    if not response then return false, "Connection failed" end
    
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
    return false, "Write failed"
end

-- UI
local w, h = term.getSize()
local selectedIndex = 1
local scrollOffset = 0
local credits = loadCredits()
local licenseStore = getLicenseStore()

local function drawHeader()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" App Store")
    
    local cStr = "Credits: " .. credits
    term.setCursorPos(w - #cStr, 1)
    term.write(cStr)
end

local function drawList(items)
    local listH = h - 2 -- Header and footer
    
    for i = 1, listH do
        local idx = i + scrollOffset
        local item = items[idx]
        local y = i + 1
        
        term.setCursorPos(1, y)
        term.setBackgroundColor(colors.black)
        term.clearLine()
        
        if item then
            if idx == selectedIndex then
                term.setBackgroundColor(colors.lightGray)
                term.setTextColor(colors.black)
            else
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.white)
            end
            
            local status = ""
            if isInstalled(item) then
                status = "Installed"
            elseif licenseStore:has(item.id) then
                status = "Owned"
            else
                status = item.price .. " C"
            end
            
            local label = " " .. item.name
            term.write(label)
            
            term.setCursorPos(w - #status - 1, y)
            term.write(status)
        end
    end
end

local function drawFooter()
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" Enter: Details/Buy  Q: Quit")
end

local function showDetails(item)
    term.setBackgroundColor(colors.blue)
    term.clear()
    
    local function center(y, text, bg, fg)
        term.setCursorPos(math.floor((w - #text) / 2) + 1, y)
        if bg then term.setBackgroundColor(bg) end
        if fg then term.setTextColor(fg) end
        term.write(text)
    end
    
    -- Box
    local bw, bh = 26, 12
    local bx = math.floor((w - bw) / 2) + 1
    local by = math.floor((h - bh) / 2) + 1
    
    paintutils.drawFilledBox(bx, by, bx + bw - 1, by + bh - 1, colors.lightGray)
    paintutils.drawFilledBox(bx, by, bx + bw - 1, by, colors.cyan)
    
    term.setCursorPos(bx + 1, by)
    term.setTextColor(colors.black)
    term.setBackgroundColor(colors.cyan)
    term.write(item.name)
    
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    
    -- Description (simple wrap)
    local desc = item.description or "No description."
    local lines = {}
    local line = ""
    for word in desc:gmatch("%S+") do
        if #line + #word + 1 > bw - 2 then
            table.insert(lines, line)
            line = word
        else
            if #line > 0 then line = line .. " " .. word else line = word end
        end
    end
    table.insert(lines, line)
    
    for i, l in ipairs(lines) do
        if i > 5 then break end
        term.setCursorPos(bx + 1, by + 1 + i)
        term.write(l)
    end
    
    local owned = licenseStore:has(item.id)
    local installed = isInstalled(item)
    local price = item.price or 0
    
    local action = ""
    if installed then
        action = "Re-download"
    elseif owned then
        action = "Download"
    else
        action = "Buy (" .. price .. ")"
    end
    
    term.setCursorPos(bx + 1, by + bh - 3)
    term.write("Status: " .. (installed and "Installed" or (owned and "Owned" or "Available")))
    
    -- Button
    term.setCursorPos(bx + 2, by + bh - 2)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.white)
    term.write(" " .. action .. " ")
    
    term.setBackgroundColor(colors.blue)
    
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "key" then
            if p1 == keys.enter or p1 == keys.space then
                -- Action
                if not owned and not installed then
                    if credits >= price then
                        credits = credits - price
                        saveCredits(credits)
                        licenseStore:save(item.id, price, "store purchase")
                        owned = true
                    else
                        term.setCursorPos(bx + 2, by + bh - 1)
                        term.setBackgroundColor(colors.red)
                        term.write(" Not enough credits! ")
                        os.sleep(1)
                        return
                    end
                end
                
                -- Download
                term.setCursorPos(bx + 2, by + bh - 1)
                term.setBackgroundColor(colors.yellow)
                term.setTextColor(colors.black)
                term.write(" Downloading... ")
                
                local ok, err = downloadItem(item)
                if ok then
                    term.setCursorPos(bx + 2, by + bh - 1)
                    term.setBackgroundColor(colors.green)
                    term.write(" Success! ")
                else
                    term.setCursorPos(bx + 2, by + bh - 1)
                    term.setBackgroundColor(colors.red)
                    term.write(" Error: " .. (err or "?") .. " ")
                end
                os.sleep(1)
                return
            elseif p1 == keys.q or p1 == keys.backspace then
                return
            end
        end
    end
end

local function main()
    local items = {}
    for _, p in ipairs(programs) do
        if p.id ~= "store" then
            table.insert(items, p)
        end
    end
    
    while true do
        drawHeader()
        drawList(items)
        drawFooter()
        
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "key" then
            if p1 == keys.up then
                selectedIndex = selectedIndex - 1
                if selectedIndex < 1 then selectedIndex = 1 end
                if selectedIndex <= scrollOffset then scrollOffset = selectedIndex - 1 end
            elseif p1 == keys.down then
                selectedIndex = selectedIndex + 1
                if selectedIndex > #items then selectedIndex = #items end
                if selectedIndex > scrollOffset + (h - 2) then scrollOffset = selectedIndex - (h - 2) end
            elseif p1 == keys.enter then
                showDetails(items[selectedIndex])
                -- Refresh credits/state
                credits = loadCredits()
                licenseStore = getLicenseStore()
                term.setBackgroundColor(colors.black)
                term.clear()
            elseif p1 == keys.q then
                break
            end
        elseif ev == "mouse_scroll" then
            if p1 > 0 then
                selectedIndex = selectedIndex + 1
                if selectedIndex > #items then selectedIndex = #items end
                if selectedIndex > scrollOffset + (h - 2) then scrollOffset = selectedIndex - (h - 2) end
            elseif p1 < 0 then
                selectedIndex = selectedIndex - 1
                if selectedIndex < 1 then selectedIndex = 1 end
                if selectedIndex <= scrollOffset then scrollOffset = selectedIndex - 1 end
            end
        end
    end
    
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

main()

