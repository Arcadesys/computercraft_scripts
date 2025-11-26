local ui = require("lib_ui")
local mining = require("lib_mining")
local valhelsia_blocks = require("arcade.data.valhelsia_blocks")

local trash_config = {}

function trash_config.run()
    local searchTerm = ""
    local scroll = 0
    local selectedIndex = 1
    local filteredBlocks = {}
    
    -- Helper to update filtered list
    local function updateFilter()
        filteredBlocks = {}
        for _, block in ipairs(valhelsia_blocks) do
            if searchTerm == "" or 
               block.label:lower():find(searchTerm:lower()) or 
               block.id:lower():find(searchTerm:lower()) then
                table.insert(filteredBlocks, block)
            end
        end
    end
    
    updateFilter()
    
    while true do
        ui.clear()
        ui.drawFrame(2, 2, 48, 16, "Trash Configuration")
        
        -- Search Bar
        ui.label(4, 4, "Search: ")
        ui.inputText(12, 4, 30, searchTerm, true)
        
        -- List Header
        ui.label(4, 6, "Name")
        ui.label(35, 6, "Trash?")
        ui.drawBox(4, 7, 44, 1, colors.gray, colors.white)
        
        -- List Items
        local listHeight = 8
        local maxScroll = math.max(0, #filteredBlocks - listHeight)
        if scroll > maxScroll then scroll = maxScroll end
        
        for i = 1, listHeight do
            local idx = i + scroll
            if idx <= #filteredBlocks then
                local block = filteredBlocks[idx]
                local y = 7 + i
                
                local isTrash = mining.TRASH_BLOCKS[block.id]
                local trashLabel = isTrash and "[YES]" or "[NO ]"
                local trashColor = isTrash and colors.red or colors.green
                
                if i == selectedIndex then
                    term.setBackgroundColor(colors.white)
                    term.setTextColor(colors.black)
                else
                    term.setBackgroundColor(colors.blue)
                    term.setTextColor(colors.white)
                end
                
                term.setCursorPos(4, y)
                local label = block.label
                if #label > 30 then label = label:sub(1, 27) .. "..." end
                term.write(label .. string.rep(" ", 31 - #label))
                
                term.setCursorPos(35, y)
                if i == selectedIndex then
                    term.setTextColor(colors.black)
                else
                    term.setTextColor(trashColor)
                end
                term.write(trashLabel)
            end
        end
        
        -- Instructions
        ui.label(4, 17, "Arrows: Move/Scroll  Enter: Toggle  Esc: Save")
        
        local event, p1 = os.pullEvent()
        
        if event == "char" then
            searchTerm = searchTerm .. p1
            updateFilter()
            selectedIndex = 1
            scroll = 0
        elseif event == "key" then
            if p1 == keys.backspace then
                searchTerm = searchTerm:sub(1, -2)
                updateFilter()
                selectedIndex = 1
                scroll = 0
            elseif p1 == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                elseif scroll > 0 then
                    scroll = scroll - 1
                end
            elseif p1 == keys.down then
                if selectedIndex < math.min(listHeight, #filteredBlocks) then
                    selectedIndex = selectedIndex + 1
                elseif scroll < maxScroll then
                    scroll = scroll + 1
                end
            elseif p1 == keys.enter then
                local idx = selectedIndex + scroll
                if filteredBlocks[idx] then
                    local block = filteredBlocks[idx]
                    if mining.TRASH_BLOCKS[block.id] then
                        mining.TRASH_BLOCKS[block.id] = nil -- Remove from trash
                    else
                        mining.TRASH_BLOCKS[block.id] = true -- Add to trash
                    end
                end
            elseif p1 == keys.enter or p1 == keys.escape then
                mining.saveConfig()
                return
            end
        end
    end
end

return trash_config
