--[[
 Workstation installer for ComputerCraft / CC:Tweaked
 -----------------------------------------------------
 This script wipes the computer (except the ROM) and then installs the
 Workstation OS from a manifest, similar to applying an image. It works on
 both computers and turtles.

 Usage examples:
   install                 -- use the default manifest URL
   install <manifest_url>  -- override the manifest location

 The manifest is expected to look like:
 {
   "name": "Workstation",
   "version": "1.0.0",
   "files": [
     { "path": "startup.lua", "url": "https://.../startup.lua" },
     { "path": "apps/home.lua", "url": "https://.../home.lua" }
   ]
 }

 If HTTP is disabled or the manifest download fails, the installer falls
 back to a tiny embedded Workstation image so that the machine remains
 bootable.
]]

local tArgs = { ... }

-- Change this to point at your canonical Workstation manifest.
local DEFAULT_MANIFEST_URL =
  "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/manifest.json"

-- Minimal offline image that keeps the computer usable even if remote
-- downloads fail.
local EMBEDDED_IMAGE = {
  name = "Workstation",
  version = "embedded",
  files = {}
}

local function addEmbeddedFile(path, content)
  table.insert(EMBEDDED_IMAGE.files, { path = path, content = content })
end

-- START_EMBEDDED_FILES
addEmbeddedFile("startup.lua", [[
local version = "Workstation (embedded)"
term.clear()
term.setCursorPos(1, 1)
print(version)
print("Booting...")
local home = "home.lua"
if fs.exists(home) then
  shell.run(home)
else
  print("Home program missing.")
end
]])

addEmbeddedFile("home.lua", [[
local version = "Workstation (embedded)"
term.clear()
term.setCursorPos(1, 1)
print(version)
print(string.rep("-", string.len(version)))
print("This is the built-in rescue image installed by install.lua.")
print("Replace it by running the installer with a proper manifest URL.")
print()
print("Suggestions:")
print(" - Verify HTTP is enabled in your ComputerCraft/CC:Tweaked config.")
print(" - Run: install <https://your.domain/manifest.json>")
print()
print("Shell available below. Type 'reboot' when finished.")
print()
shell.run("shell")
]])

addEmbeddedFile("factory/schema_farm_tree.txt", [[legend:
. = minecraft:air
D = minecraft:dirt
S = minecraft:oak_sapling
# = minecraft:stone_bricks

meta:
mode = treefarm

layer:0
#####
#DDD#
#DDD#
#DDD#
#####

layer:1
.....
.S.S.
.....
.S.S.
.....
]])

addEmbeddedFile("factory/schema_farm_potato.txt", [[legend:
. = minecraft:air
D = minecraft:dirt
W = minecraft:water_bucket
P = minecraft:potatoes
# = minecraft:stone_bricks

meta:
mode = potatofarm

layer:0
#####
#DDD#
#DWD#
#DDD#
#####

layer:1
.....
.PPP.
.P.P.
.PPP.
.....
]])

addEmbeddedFile("factory_planner.lua", [=[---@diagnostic disable: undefined-global, undefined-field

-- Factory Designer Launcher
-- Thin wrapper around lib_designer so players always get the full feature set.

local function ensurePackagePath()
    if not package or type(package.path) ~= "string" then
        package = package or {}
        package.path = package.path or ""
    end

    if not string.find(package.path, "/lib/?.lua", 1, true) then
        package.path = package.path .. ";/?.lua;/lib/?.lua;/factory/?.lua;/arcade/?.lua"
    end
end

ensurePackagePath()

local designer = require("lib_designer")
local parser = require("lib_parser")

local args = { ... }

local function printUsage()
    print([[Factory Designer
Usage: factory_planner.lua [--load <schema-file>] [--farm <tree|potato>] [--help]

Controls are available inside the designer (press M for menu).]])
end

local function resolveSchemaPath(rawPath)
    if fs.exists(rawPath) then
        return rawPath
    end
    if fs.exists(rawPath .. ".json") then
        return rawPath .. ".json"
    end
    if fs.exists(rawPath .. ".txt") then
        return rawPath .. ".txt"
    end
    return rawPath
end

local function loadInitialSchema(path)
    local resolved = resolveSchemaPath(path)
    if not fs.exists(resolved) then
        print("Warning: schema file not found: " .. resolved)
        return nil
    end

    local ok, schema, metadata = parser.parseFile(nil, resolved)
    if not ok then
        print("Failed to load schema: " .. tostring(schema))
        return nil
    end

    print("Loaded schema: " .. resolved)
    return {
        schema = schema,
        metadata = metadata,
    }
end

local function main()
    local config, handled = parseArgs()
    if handled then return end

    local runOpts = {}
    if config and config.loadPath then
        local initial = loadInitialSchema(config.loadPath)
        if initial then
            runOpts.schema = initial.schema
            runOpts.metadata = initial.metadata
        end
    end

    if config and config.farmType then
        if config.farmType == "tree" then
            runOpts.meta = { mode = "treefarm" }
            runOpts.palette = {
                { id = "minecraft:stone_bricks", color = colors.gray, sym = "#" },
                { id = "minecraft:dirt", color = colors.brown, sym = "D" },
                { id = "minecraft:oak_sapling", color = colors.green, sym = "S" },
                { id = "minecraft:torch", color = colors.yellow, sym = "i" },
                { id = "minecraft:chest", color = colors.orange, sym = "C" },
            }
        elseif config.farmType == "potato" then
            runOpts.meta = { mode = "potatofarm" }
            runOpts.palette = {
                { id = "minecraft:stone_bricks", color = colors.gray, sym = "#" },
                { id = "minecraft:dirt", color = colors.brown, sym = "D" },
                { id = "minecraft:water_bucket", color = colors.blue, sym = "W" },
                { id = "minecraft:potato", color = colors.yellow, sym = "P" },
                { id = "minecraft:chest", color = colors.orange, sym = "C" },
            }
        else
            print("Unknown farm type: " .. config.farmType)
            return
        end
    end

    local ok, err = pcall(designer.run, runOpts)
    if not ok then
        print("Designer crashed: " .. tostring(err))
    end
end

main()
]=])

addEmbeddedFile("lib/version.lua", [=[--[[
Version and build counter for Arcadesys TurtleOS.
Build counter increments on each bundle/rebuild.
]]

local version = {}

version.MAJOR = 2
version.MINOR = 1
version.PATCH = 1
version.BUILD = 47

--- Format version string (e.g., "v2.1.1 (build 42)")
function version.toString()
    return string.format("v%d.%d.%d (build %d)", 
        version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end

--- Format short display (e.g., "TurtleOS v2.1.1 #42")
function version.display()
    return string.format("TurtleOS v%d.%d.%d #%d", 
        version.MAJOR, version.MINOR, version.PATCH, version.BUILD)
end

return version
]=])

addEmbeddedFile("lib/lib_json.lua", [=[--[[
JSON library for CC:Tweaked turtles.
Provides helpers for encoding and decoding JSON.
--]]

---@diagnostic disable: undefined-global

local json_utils = {}

function json_utils.encode(data)
    if textutils and textutils.serializeJSON then
        return textutils.serializeJSON(data)
    end
    return nil, "json_encoder_unavailable"
end

function json_utils.decodeJson(text)
    if type(text) ~= "string" then
        return nil, "invalid_json"
    end
    if textutils and textutils.unserializeJSON then
        local ok, result = pcall(textutils.unserializeJSON, text)
        if ok and result ~= nil then
            return result
        end
        return nil, "json_parse_failed"
    end
    local ok, json = pcall(require, "json")
    if ok and type(json) == "table" and type(json.decode) == "function" then
        local okDecode, result = pcall(json.decode, text)
        if okDecode then
            return result
        end
        return nil, "json_parse_failed"
    end
    return nil, "json_decoder_unavailable"
end

return json_utils
]=])

addEmbeddedFile("lib/lib_ui.lua", [=[--[[
UI Library for TurtleOS (Mouse/GUI Edition)
Provides DOS-style windowing and widgets.
--]]

local ui = {}

local colors_bg = colors.blue
local colors_fg = colors.white
local colors_btn = colors.lightGray
local colors_btn_text = colors.black
local colors_input = colors.black
local colors_input_text = colors.white

function ui.clear()
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.clear()
end

function ui.drawBox(x, y, w, h, bg, fg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end
end

function ui.drawFrame(x, y, w, h, title)
    ui.drawBox(x, y, w, h, colors.gray, colors.white)
    ui.drawBox(x + 1, y + 1, w - 2, h - 2, colors_bg, colors_fg)
    
    -- Shadow
    term.setBackgroundColor(colors.black)
    for i = 1, h do
        term.setCursorPos(x + w, y + i)
        term.write(" ")
    end
    for i = 1, w do
        term.setCursorPos(x + i, y + h)
        term.write(" ")
    end

    if title then
        term.setCursorPos(x + 2, y + 1)
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        term.write(" " .. title .. " ")
    end
end

function ui.button(x, y, text, active)
    term.setCursorPos(x, y)
    if active then
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
    else
        term.setBackgroundColor(colors_btn)
        term.setTextColor(colors_btn_text)
    end
    term.write(" " .. text .. " ")
end

function ui.label(x, y, text)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.write(text)
end

function ui.inputText(x, y, width, value, active)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_input)
    term.setTextColor(colors_input_text)
    local display = value or ""
    if #display > width then
        display = display:sub(-width)
    end
    term.write(display .. string.rep(" ", width - #display))
    if active then
        term.setCursorPos(x + #display, y)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
end

function ui.drawPreview(schema, x, y, w, h)
    -- Find bounds
    local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            if nx < minX then minX = nx end
            if nx > maxX then maxX = nx end
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        if nz < minZ then minZ = nz end
                        if nz > maxZ then maxZ = nz end
                    end
                end
            end
        end
    end

    if minX > maxX then return end -- Empty schema

    local scaleX = w / (maxX - minX + 1)
    local scaleZ = h / (maxZ - minZ + 1)
    local scale = math.min(scaleX, scaleZ, 1) -- Keep aspect ratio, max 1:1

    -- Draw background
    term.setBackgroundColor(colors.black)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end

    -- Draw blocks
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        -- Map to screen
                        local scrX = math.floor((nx - minX) * scale) + x
                        local scrY = math.floor((nz - minZ) * scale) + y
                        
                        if scrX >= x and scrX < x + w and scrY >= y and scrY < y + h then
                            term.setCursorPos(scrX, scrY)
                            
                            -- Color mapping
                            local mat = block.material
                            local color = colors.gray
                            local char = " "
                            
                            if mat:find("water") then color = colors.blue
                            elseif mat:find("log") then color = colors.brown
                            elseif mat:find("leaves") then color = colors.green
                            elseif mat:find("sapling") then color = colors.green; char = "T"
                            elseif mat:find("sand") then color = colors.yellow
                            elseif mat:find("dirt") then color = colors.brown
                            elseif mat:find("grass") then color = colors.green
                            elseif mat:find("stone") then color = colors.lightGray
                            elseif mat:find("cane") then color = colors.lime; char = "!"
                            elseif mat:find("potato") then color = colors.orange; char = "."
                            elseif mat:find("torch") then color = colors.orange; char = "i"
                            end
                            
                            term.setBackgroundColor(color)
                            if color == colors.black then term.setTextColor(colors.white) else term.setTextColor(colors.black) end
                            term.write(char)
                        end
                    end
                end
            end
        end
    end
end

-- Simple Event Loop for a Form
-- form = { title = "", elements = { {type="button", x=, y=, text=, id=}, ... } }
function ui.runForm(form)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local running = true
    local result = nil
    local activeInput = nil

    -- Identify focusable elements
    local focusableIndices = {}
    for i, el in ipairs(form.elements) do
        if el.type == "input" or el.type == "button" then
            table.insert(focusableIndices, i)
        end
    end
    local currentFocusIndex = 1
    if #focusableIndices > 0 then
        local el = form.elements[focusableIndices[currentFocusIndex]]
        if el.type == "input" then activeInput = el end
    end

    while running do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, form.title)
        
        -- Custom Draw
        if form.onDraw then
            form.onDraw(fx, fy, fw, fh)
        end

        -- Draw elements
        for i, el in ipairs(form.elements) do
            local ex, ey = fx + el.x, fy + el.y
            local isFocused = false
            if #focusableIndices > 0 and focusableIndices[currentFocusIndex] == i then
                isFocused = true
            end

            if el.type == "button" then
                ui.button(ex, ey, el.text, isFocused)
            elseif el.type == "label" then
                ui.label(ex, ey, el.text)
            elseif el.type == "input" then
                ui.inputText(ex, ey, el.width, el.value, activeInput == el or isFocused)
            end
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            local clickedSomething = false
            
            for i, el in ipairs(form.elements) do
                local ex, ey = fx + el.x, fy + el.y
                if el.type == "button" then
                    if my == ey and mx >= ex and mx < ex + #el.text + 2 then
                        ui.button(ex, ey, el.text, true) -- Flash
                        sleep(0.1)
                        if el.callback then
                            local res = el.callback(form)
                            if res then return res end
                        end
                        clickedSomething = true
                        -- Update focus
                        for fi, idx in ipairs(focusableIndices) do
                            if idx == i then currentFocusIndex = fi; break end
                        end
                        activeInput = nil
                    end
                elseif el.type == "input" then
                    if my == ey and mx >= ex and mx < ex + el.width then
                        activeInput = el
                        clickedSomething = true
                        -- Update focus
                        for fi, idx in ipairs(focusableIndices) do
                            if idx == i then currentFocusIndex = fi; break end
                        end
                    end
                end
            end
            
            if not clickedSomething then
                activeInput = nil
            end
            
        elseif event == "char" and activeInput then
            if not activeInput.stepper then
                activeInput.value = (activeInput.value or "") .. p1
            end
        elseif event == "key" then
            local key = p1
            local focusedEl = (#focusableIndices > 0) and form.elements[focusableIndices[currentFocusIndex]] or nil
            local function adjustStepper(el, delta)
                if not el or not el.stepper then return end
                local step = el.step or 1
                local current = tonumber(el.value) or 0
                local nextVal = current + (delta * step)
                if el.min then nextVal = math.max(el.min, nextVal) end
                if el.max then nextVal = math.min(el.max, nextVal) end
                el.value = tostring(nextVal)
            end

            if key == keys.backspace and activeInput then
                local val = activeInput.value or ""
                if #val > 0 then
                    activeInput.value = val:sub(1, -2)
                end
            elseif (key == keys.left or key == keys.right) and focusedEl and focusedEl.stepper then
                local delta = key == keys.left and -1 or 1
                adjustStepper(focusedEl, delta)
                activeInput = nil
            elseif key == keys.tab or key == keys.down then
                if #focusableIndices > 0 then
                    currentFocusIndex = currentFocusIndex + 1
                    if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
                    local el = form.elements[focusableIndices[currentFocusIndex]]
                    activeInput = (el.type == "input") and el or nil
                end
            elseif key == keys.up then
                if #focusableIndices > 0 then
                    currentFocusIndex = currentFocusIndex - 1
                    if currentFocusIndex < 1 then currentFocusIndex = #focusableIndices end
                    local el = form.elements[focusableIndices[currentFocusIndex]]
                    activeInput = (el.type == "input") and el or nil
                end
            elseif key == keys.enter then
                if activeInput then
                    activeInput = nil
                    -- Move to next
                    if #focusableIndices > 0 then
                        currentFocusIndex = currentFocusIndex + 1
                        if currentFocusIndex > #focusableIndices then currentFocusIndex = 1 end
                        local el = form.elements[focusableIndices[currentFocusIndex]]
                        activeInput = (el.type == "input") and el or nil
                    end
                else
                    -- Activate button
                    if #focusableIndices > 0 then
                        local el = form.elements[focusableIndices[currentFocusIndex]]
                        if el.type == "button" then
                            ui.button(fx + el.x, fy + el.y, el.text, true) -- Flash
                            sleep(0.1)
                            if el.callback then
                                local res = el.callback(form)
                                if res then return res end
                            end
                        elseif el.type == "input" then
                            activeInput = el
                        end
                    end
                end
            end
        end
    end
end

-- Simple Scrollable Menu
-- items = { { text="Label", callback=function() end }, ... }
function ui.runMenu(title, items)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local scroll = 0
    local maxVisible = fh - 4 -- Title + padding (top/bottom)
    local selectedIndex = 1

    while true do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, title)
        
        -- Draw items
        for i = 1, maxVisible do
            local idx = i + scroll
            if idx <= #items then
                local item = items[idx]
                local isSelected = (idx == selectedIndex)
                ui.button(fx + 2, fy + 1 + i, item.text, isSelected)
            end
        end
        
        -- Scroll indicators
        if scroll > 0 then
            ui.label(fx + fw - 2, fy + 2, "^")
        end
        if scroll + maxVisible < #items then
            ui.label(fx + fw - 2, fy + fh - 2, "v")
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            
            -- Check items
            for i = 1, maxVisible do
                local idx = i + scroll
                if idx <= #items then
                    local item = items[idx]
                    local bx, by = fx + 2, fy + 1 + i
                    -- Button width is text length + 2 spaces
                    if my == by and mx >= bx and mx < bx + #item.text + 2 then
                        ui.button(bx, by, item.text, true) -- Flash
                        sleep(0.1)
                        if item.callback then
                            local res = item.callback()
                            if res then return res end
                        end
                        selectedIndex = idx
                    end
                end
            end
            
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir > 0 then
                if scroll + maxVisible < #items then scroll = scroll + 1 end
            else
                if scroll > 0 then scroll = scroll - 1 end
            end
        elseif event == "key" then
            local key = p1
            if key == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                    if selectedIndex <= scroll then
                        scroll = selectedIndex - 1
                    end
                end
            elseif key == keys.down then
                if selectedIndex < #items then
                    selectedIndex = selectedIndex + 1
                    if selectedIndex > scroll + maxVisible then
                        scroll = selectedIndex - maxVisible
                    end
                end
            elseif key == keys.enter then
                local item = items[selectedIndex]
                if item and item.callback then
                    ui.button(fx + 2, fy + 1 + (selectedIndex - scroll), item.text, true) -- Flash
                    sleep(0.1)
                    local res = item.callback()
                    if res then return res end
                end
            end
        end
    end
end

-- Form Class
function ui.Form(title)
    local self = {
        title = title,
        elements = {},
        _row = 0,
    }
    
    function self:addInput(id, label, value)
        local y = 2 + self._row
        table.insert(self.elements, { type = "label", x = 2, y = y, text = label })
        table.insert(self.elements, { type = "input", x = 15, y = y, width = 20, value = value, id = id })
        self._row = self._row + 1
    end

    function self:addStepper(id, label, value, opts)
        opts = opts or {}
        local y = 2 + self._row
        table.insert(self.elements, { type = "label", x = 2, y = y, text = label })
        table.insert(self.elements, {
            type = "input",
            x = 15,
            y = y,
            width = 12,
            value = tostring(value or 0),
            id = id,
            stepper = true,
            step = opts.step or 1,
            min = opts.min,
            max = opts.max,
        })
        self._row = self._row + 1
    end
    
    function self:addButton(id, label, callback)
         local y = 2 + self._row
         table.insert(self.elements, { type = "button", x = 2, y = y, text = label, id = id, callback = callback })
         self._row = self._row + 1
    end

    function self:run()
        -- Add OK/Cancel buttons
        local y = 2 + self._row + 2
        table.insert(self.elements, { 
            type = "button", x = 2, y = y, text = "OK", 
            callback = function(form) return "ok" end 
        })
        table.insert(self.elements, { 
            type = "button", x = 10, y = y, text = "Cancel", 
            callback = function(form) return "cancel" end 
        })
        
        return ui.runForm(self)
    end
    
    return self
end

function ui.toBlit(color)
    if colors.toBlit then return colors.toBlit(color) end
    local exponent = math.log(color) / math.log(2)
    return string.sub("0123456789abcdef", exponent + 1, exponent + 1)
end

return ui
]=])

addEmbeddedFile("lib/lib_parser.lua", [=[--[[
Parser library for CC:Tweaked turtles.
Normalises schema sources (JSON, text grids, voxel tables) into the canonical
schema[x][y][z] format used by the build states. All public entry points
return success booleans with optional error messages and metadata tables.
--]]

---@diagnostic disable: undefined-global

local parser = {}
local logger = require("lib_logger")
local table_utils = require("lib_table")
local fs_utils = require("lib_fs")
local json_utils = require("lib_json")
local schema_utils = require("lib_schema")

local function parseLayerRows(schema, bounds, counts, layerDef, legend, opts)
    local rows = layerDef.rows
    if type(rows) ~= "table" then
        return false, "invalid_layer"
    end
    local height = #rows
    if height == 0 then
        return true
    end
    local width = nil
    for rowIndex, row in ipairs(rows) do
        if type(row) ~= "string" then
            return false, "invalid_row"
        end
        if width == nil then
            width = #row
            if width == 0 then
                return false, "empty_row"
            end
        elseif width ~= #row then
            return false, "ragged_row"
        end
        for col = 1, #row do
            local symbol = row:sub(col, col)
            local entry, err = schema_utils.resolveSymbol(symbol, legend, opts)
            if err then
                return false, string.format("legend_error:%s", symbol)
            end
            if entry then
                local x = (layerDef.x or 0) + (col - 1)
                local y = layerDef.y or 0
                local z = (layerDef.z or 0) + (rowIndex - 1)
                local ok, addErr = schema_utils.addBlock(schema, bounds, counts, x, y, z, entry.material, entry.meta)
                if not ok then
                    return false, addErr
                end
            end
        end
    end
    return true
end

local function toLayerRows(layer)
    if type(layer) == "string" then
        local rows = {}
        for line in layer:gmatch("([^\r\n]+)") do
            rows[#rows + 1] = line
        end
        return { rows = rows }
    end
    if type(layer) == "table" then
        if layer.rows then
            local rows = {}
            for i = 1, #layer.rows do
                rows[i] = tostring(layer.rows[i])
            end
            return {
                rows = rows,
                y = layer.y or layer.height or layer.level or 0,
                x = layer.x or layer.offsetX or 0,
                z = layer.z or layer.offsetZ or 0,
            }
        end
        local rows = {}
        local count = 0
        for _, value in ipairs(layer) do
            rows[#rows + 1] = tostring(value)
            count = count + 1
        end
        if count > 0 then
            return { rows = rows, y = layer.y or 0, x = layer.x or 0, z = layer.z or 0 }
        end
    end
    return nil
end

local function parseLayers(schema, bounds, counts, def, legend, opts)
    local layers = def.layers
    if type(layers) ~= "table" then
        return false, "invalid_layers"
    end
    local used = 0
    for index, layer in ipairs(layers) do
        local layerRows = toLayerRows(layer)
        if not layerRows then
            return false, "invalid_layer"
        end
        if not layerRows.y then
            layerRows.y = (def.baseY or 0) + (index - 1)
        else
            layerRows.y = layerRows.y + (def.baseY or 0)
        end
        if def.baseX then
            layerRows.x = (layerRows.x or 0) + def.baseX
        end
        if def.baseZ then
            layerRows.z = (layerRows.z or 0) + def.baseZ
        end
        local ok, err = parseLayerRows(schema, bounds, counts, layerRows, legend, opts)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_layers"
    end
    return true
end

local function parseBlockList(schema, bounds, counts, blocks)
    local used = 0
    for _, block in ipairs(blocks) do
        if type(block) ~= "table" then
            return false, "invalid_block"
        end
        local x = block.x or block[1]
        local y = block.y or block[2]
        local z = block.z or block[3]
        local material = block.material or block.name or block.block
        local meta = block.meta or block.data
        if type(meta) ~= "table" then
            meta = {}
        end
        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_blocks"
    end
    return true
end

local function parseVoxelGrid(schema, bounds, counts, grid)
    if type(grid) ~= "table" then
        return false, "invalid_grid"
    end
    local used = 0
    for xKey, xColumn in pairs(grid) do
        local x = tonumber(xKey) or xKey
        if type(x) ~= "number" then
            return false, "invalid_coordinate"
        end
        if type(xColumn) ~= "table" then
            return false, "invalid_grid"
        end
        for yKey, yColumn in pairs(xColumn) do
            local y = tonumber(yKey) or yKey
            if type(y) ~= "number" then
                return false, "invalid_coordinate"
            end
            if type(yColumn) ~= "table" then
                return false, "invalid_grid"
            end
            for zKey, entry in pairs(yColumn) do
                local z = tonumber(zKey) or zKey
                if type(z) ~= "number" then
                    return false, "invalid_coordinate"
                end
                if entry ~= nil then
                    local material
                    local meta = {}
                    if type(entry) == "string" then
                        material = entry
                    elseif type(entry) == "table" then
                        material = entry.material or entry.name or entry.block
                        meta = type(entry.meta) == "table" and entry.meta or {}
                    else
                        return false, "invalid_block"
                    end
                    if material and material ~= "" then
                        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
                        if not ok then
                            return false, err
                        end
                        used = used + 1
                    end
                end
            end
        end
    end
    if used == 0 then
        return false, "empty_grid"
    end
    return true
end

local function summarise(bounds, counts, meta)
    local materials = {}
    for material, count in pairs(counts) do
        materials[#materials + 1] = { material = material, count = count }
    end
    table.sort(materials, function(a, b)
        if a.count == b.count then
            return a.material < b.material
        end
        return a.count > b.count
    end)
    local total = 0
    for _, entry in ipairs(materials) do
        total = total + entry.count
    end
    return {
        bounds = {
            min = table_utils.shallowCopy(bounds.min),
            max = table_utils.shallowCopy(bounds.max),
        },
        materials = materials,
        totalBlocks = total,
        meta = meta
    }
end

local function buildCanonical(def, opts)
    local schema = {}
    local bounds = schema_utils.newBounds()
    local counts = {}
    local ok, err
    if def.blocks then
        ok, err = parseBlockList(schema, bounds, counts, def.blocks)
    elseif def.layers then
        ok, err = parseLayers(schema, bounds, counts, def, def.legend, opts)
    elseif def.grid then
        ok, err = parseVoxelGrid(schema, bounds, counts, def.grid)
    else
        return nil, "unknown_definition"
    end
    if not ok then
        return nil, err
    end
    if bounds.min.x == math.huge then
        return nil, "empty_schema"
    end
    return schema, summarise(bounds, counts, def.meta)
end

local function detectFormatFromExtension(path)
    if type(path) ~= "string" then
        return nil
    end
    local ext = path:match("%.([%w_%-]+)$")
    if not ext then
        return nil
    end
    ext = ext:lower()
    if ext == "json" or ext == "schem" then
        return "json"
    end
    if ext == "txt" or ext == "grid" then
        return "grid"
    end
    if ext == "vox" or ext == "voxel" then
        return "voxel"
    end
    return nil
end

local function detectFormatFromText(text)
    if type(text) ~= "string" then
        return nil
    end
    local trimmed = text:match("^%s*(.-)%s*$") or text
    local firstChar = trimmed:sub(1, 1)
    if firstChar == "{" or firstChar == "[" then
        return "json"
    end
    return "grid"
end

local function parseLegendBlock(lines, index)
    local legend = {}
    local pos = index
    while pos <= #lines do
        local line = lines[pos]
        if line == "" then
            break
        end
        if line:match("^layer") then
            break
        end
        local symbol, rest = line:match("^(%S+)%s*[:=]%s*(.+)$")
        if not symbol then
            symbol, rest = line:match("^(%S+)%s+(.+)$")
        end
        if symbol and rest then
            rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
            local value
            if rest:sub(1, 1) == "{" then
                local parsed = json_utils.decodeJson(rest)
                if parsed then
                    value = parsed
                else
                    value = rest
                end
            else
                value = rest
            end
            legend[symbol] = value
        end
        pos = pos + 1
    end
    return legend, pos
end

local function parseTextGridContent(text, opts)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        lines[#lines + 1] = line
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, nil)
    local layers = {}
    local current = {}
    local currentY = nil
    local lineIndex = 1
    while lineIndex <= #lines do
        local line = lines[lineIndex]
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == "" then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
                currentY = nil
            end
            lineIndex = lineIndex + 1
        elseif trimmed:lower() == "legend:" then
            local legendBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1)
            legend = schema_utils.mergeLegend(legend, legendBlock)
            lineIndex = nextIndex
        elseif trimmed:lower() == "meta:" then
            local metaBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1) -- Reuse parseLegendBlock as format is identical
            if not opts then opts = {} end
            opts.meta = schema_utils.mergeLegend(opts.meta, metaBlock)
            lineIndex = nextIndex
        elseif trimmed:match("^layer") then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
            end
            local yValue = trimmed:match("layer%s*[:=]%s*(-?%d+)")
            currentY = yValue and tonumber(yValue) or (#layers)
            lineIndex = lineIndex + 1
        else
            current[#current + 1] = line
            lineIndex = lineIndex + 1
        end
    end
    if #current > 0 then
        layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
    end
    if not legend or next(legend) == nil then
        return nil, "missing_legend"
    end
    if #layers == 0 then
        return nil, "empty_layers"
    end
    return {
        layers = layers,
        legend = legend,
    }
end

local function parseJsonContent(obj, opts)
    if type(obj) ~= "table" then
        return nil, "invalid_json_root"
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, obj.legend or nil)
    if obj.blocks then
        return {
            blocks = obj.blocks,
            legend = legend,
        }
    end
    if obj.layers then
        return {
            layers = obj.layers,
            legend = legend,
            baseX = obj.baseX,
            baseY = obj.baseY,
            baseZ = obj.baseZ,
        }
    end
    if obj.grid or obj.voxels then
        return {
            grid = obj.grid or obj.voxels,
            legend = legend,
        }
    end
    if #obj > 0 then
        return {
            blocks = obj,
            legend = legend,
        }
    end
    return nil, "unrecognised_json"
end

local function assignToContext(ctx, schema, info)
    if type(ctx) ~= "table" then
        return
    end
    ctx.schema = schema
    ctx.schemaInfo = info
end

local function ensureSpecTable(spec)
    if type(spec) == "table" then
        return table_utils.shallowCopy(spec)
    end
    if type(spec) == "string" then
        return { source = spec }
    end
    return {}
end

function parser.parse(ctx, spec)
    spec = ensureSpecTable(spec)
    local format = spec.format
    local text = spec.text
    local data = spec.data
    local path = spec.path or spec.sourcePath
    local source = spec.source
    if not format and spec.path then
        format = detectFormatFromExtension(spec.path)
    end
    if not format and spec.formatHint then
        format = spec.formatHint
    end
    if not text and not data then
        if spec.textContent then
            text = spec.textContent
        elseif spec.raw then
            text = spec.raw
        elseif spec.sourceText then
            text = spec.sourceText
        end
    end
    if not path and type(source) == "string" and text == nil and data == nil then
        local maybeFormat = detectFormatFromExtension(source)
        if maybeFormat then
            path = source
            format = format or maybeFormat
        else
            text = source
        end
    end
    if text == nil and path then
        local contents, err = fs_utils.readFile(path)
        if not contents then
            return false, err or "read_failed"
        end
        text = contents
        if not format then
            format = detectFormatFromExtension(path) or detectFormatFromText(text)
        end
    end
    if not format then
        if data then
            if data.layers then
                format = "grid"
            elseif data.blocks then
                format = "json"
            elseif data.grid or data.voxels then
                format = "voxel"
            end
        elseif text then
            format = detectFormatFromText(text)
        end
    end
    if not format then
        return false, "unknown_format"
    end
    local definition, err
    if format == "json" then
        if data then
            definition, err = parseJsonContent(data, spec)
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            definition, err = parseJsonContent(obj, spec)
        end
    elseif format == "grid" then
        if data and (data.layers or data.rows) then
            definition = {
                layers = data.layers or { data.rows },
                legend = schema_utils.mergeLegend(spec.legend or nil, data.legend or nil),
                meta = spec.meta or data.meta
            }
        else
            definition, err = parseTextGridContent(text, spec)
            if definition and spec.meta then
                 definition.meta = schema_utils.mergeLegend(definition.meta, spec.meta)
            end
        end
    elseif format == "voxel" then
        if data then
            definition = {
                grid = data.grid or data.voxels or data,
            }
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            if obj.grid or obj.voxels then
                definition = {
                    grid = obj.grid or obj.voxels,
                }
            else
                definition, err = parseJsonContent(obj, spec)
            end
        end
    else
        return false, "unsupported_format"
    end
    if not definition then
        return false, err or "invalid_definition"
    end
    if spec.legend then
        definition.legend = schema_utils.mergeLegend(definition.legend, spec.legend)
    end
    local schema, metadata = buildCanonical(definition, spec)
    if not schema then
        return false, metadata or "parse_failed"
    end
    if type(metadata) ~= "table" then
        metadata = { note = metadata }
    end
    metadata = metadata or {}
    metadata.format = format
    metadata.path = path
    assignToContext(ctx, schema, metadata)
    logger.log(ctx, "debug", string.format("Parsed schema with %d blocks", metadata.totalBlocks or 0))
    return true, schema, metadata
end

function parser.parseFile(ctx, path, opts)
    opts = opts or {}
    opts.path = path
    return parser.parse(ctx, opts)
end

function parser.parseText(ctx, text, opts)
    opts = opts or {}
    opts.text = text
    opts.format = opts.format or "grid"
    return parser.parse(ctx, opts)
end

function parser.parseJson(ctx, data, opts)
    opts = opts or {}
    opts.data = data
    opts.format = "json"
    return parser.parse(ctx, opts)
end

return parser
]=])

addEmbeddedFile("lib/lib_items.lua", [=[--[[
Item definitions and properties.
Maps Minecraft item IDs to symbols, colors, and other metadata.
--]]

local items = {
    { id = "minecraft:stone", sym = "#", color = colors.lightGray },
    { id = "minecraft:cobblestone", sym = "c", color = colors.gray },
    { id = "minecraft:dirt", sym = "d", color = colors.brown },
    { id = "minecraft:grass_block", sym = "g", color = colors.green },
    { id = "minecraft:planks", sym = "p", color = colors.orange },
    { id = "minecraft:log", sym = "L", color = colors.brown },
    { id = "minecraft:leaves", sym = "l", color = colors.green },
    { id = "minecraft:glass", sym = "G", color = colors.lightBlue },
    { id = "minecraft:sand", sym = "s", color = colors.yellow },
    { id = "minecraft:gravel", sym = "v", color = colors.gray },
    { id = "minecraft:coal_ore", sym = "C", color = colors.black },
    { id = "minecraft:iron_ore", sym = "I", color = colors.white },
    { id = "minecraft:gold_ore", sym = "O", color = colors.yellow },
    { id = "minecraft:diamond_ore", sym = "D", color = colors.cyan },
    { id = "minecraft:redstone_ore", sym = "R", color = colors.red },
    { id = "minecraft:lapis_ore", sym = "B", color = colors.blue },
    { id = "minecraft:chest", sym = "H", color = colors.orange },
    { id = "minecraft:furnace", sym = "F", color = colors.gray },
    { id = "minecraft:crafting_table", sym = "T", color = colors.brown },
    { id = "minecraft:torch", sym = "i", color = colors.yellow },
    { id = "minecraft:water_bucket", sym = "W", color = colors.blue },
    { id = "minecraft:lava_bucket", sym = "A", color = colors.orange },
    { id = "minecraft:bucket", sym = "u", color = colors.lightGray },
    { id = "minecraft:wheat_seeds", sym = ".", color = colors.green },
    { id = "minecraft:wheat", sym = "w", color = colors.yellow },
    { id = "minecraft:carrot", sym = "r", color = colors.orange },
    { id = "minecraft:potato", sym = "o", color = colors.yellow },
    { id = "minecraft:sugar_cane", sym = "|", color = colors.lime },
    { id = "minecraft:oak_sapling", sym = "S", color = colors.green },
    { id = "minecraft:spruce_sapling", sym = "S", color = colors.green },
    { id = "minecraft:birch_sapling", sym = "S", color = colors.green },
    { id = "minecraft:jungle_sapling", sym = "S", color = colors.green },
    { id = "minecraft:acacia_sapling", sym = "S", color = colors.green },
    { id = "minecraft:dark_oak_sapling", sym = "S", color = colors.green },
    { id = "minecraft:stone_bricks", sym = "#", color = colors.gray },
}

return items
]=])

addEmbeddedFile("lib/lib_schema.lua", [=[--[[
Schema utilities.
Helpers for resolving symbols, managing bounds, and manipulating schema data.
--]]

local schema_utils = {}
local items = require("lib_items")
local table_utils = require("lib_table")

function schema_utils.newBounds()
    return {
        min = { x = math.huge, y = math.huge, z = math.huge },
        max = { x = -math.huge, y = -math.huge, z = -math.huge },
    }
end

function schema_utils.updateBounds(bounds, x, y, z)
    if x < bounds.min.x then bounds.min.x = x end
    if y < bounds.min.y then bounds.min.y = y end
    if z < bounds.min.z then bounds.min.z = z end
    if x > bounds.max.x then bounds.max.x = x end
    if y > bounds.max.y then bounds.max.y = y end
    if z > bounds.max.z then bounds.max.z = z end
end

function schema_utils.resolveSymbol(symbol, legend, opts)
    local entry = legend and legend[symbol]
    if not entry then
        -- Default fallbacks
        if symbol == "." then return nil end -- Air
        return nil, "unknown_symbol"
    end

    local material, meta
    if type(entry) == "table" then
        material = entry.material or entry.block or entry.name
        meta = entry.meta or entry.data or {}
    else
        material = entry
        meta = {}
    end

    if material == "minecraft:air" or material == "air" then
        return nil
    end

    -- Apply global meta overrides if present
    if opts and opts.meta then
        meta = table_utils.merge(meta, opts.meta)
    end

    return { material = material, meta = meta }
end

function schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
    if not material then return true end -- Skip air/nil

    if not schema[x] then schema[x] = {} end
    if not schema[x][y] then schema[x][y] = {} end
    
    -- Check for conflict? For now, overwrite.
    schema[x][y][z] = {
        material = material,
        meta = meta
    }

    schema_utils.updateBounds(bounds, x, y, z)
    counts[material] = (counts[material] or 0) + 1
    return true
end

function schema_utils.mergeLegend(base, override)
    if not base and not override then return {} end
    if not base then return override end
    if not override then return base end
    
    local merged = table_utils.shallowCopy(base)
    for k, v in pairs(override) do
        merged[k] = v
    end
    return merged
end

function schema_utils.cloneMeta(meta)
    if not meta then return {} end
    return table_utils.deepCopy(meta)
end

function schema_utils.canonicalToVoxelDefinition(schema)
    -- Convert canonical [x][y][z] format back to a voxel grid format suitable for JSON export
    -- This is essentially just the schema table itself, but we might want to ensure keys are strings for JSON
    -- However, CC's textutils.serializeJSON handles number keys as array indices if contiguous, or object keys if strings.
    -- To be safe and consistent with "grid" format, we can keep it as is, or convert to a list of blocks.
    -- Let's stick to the grid format as it's more compact for dense structures.
    
    -- Actually, to ensure JSON compatibility (string keys for sparse arrays), we might need to be careful.
    -- But for now, let's just return the schema structure.
    return { grid = schema }
end

return schema_utils
]=])

local lib_designer_part1 = [=[--[[
Graphical Schema Designer (Paint-style)
]]

local ui = require("lib_ui")
local json = require("lib_json")
local items = require("lib_items")
local schema_utils = require("lib_schema")
local parser = require("lib_parser")
local version = require("version")

local designer = {}

-- --- Constants & Config ---

local COLORS = {
    bg = colors.gray,
    canvas_bg = colors.black,
    grid = colors.lightGray,
    text = colors.white,
    btn_active = colors.blue,
    btn_inactive = colors.lightGray,
    btn_text = colors.black,
}

local DEFAULT_MATERIALS = {
    { id = "minecraft:stone", color = colors.lightGray, sym = "#" },
    { id = "minecraft:dirt", color = colors.brown, sym = "d" },
    { id = "minecraft:cobblestone", color = colors.gray, sym = "c" },
    { id = "minecraft:planks", color = colors.orange, sym = "p" },
    { id = "minecraft:glass", color = colors.lightBlue, sym = "g" },
    { id = "minecraft:log", color = colors.brown, sym = "L" },
    { id = "minecraft:torch", color = colors.yellow, sym = "i" },
    { id = "minecraft:iron_block", color = colors.white, sym = "I" },
    { id = "minecraft:gold_block", color = colors.yellow, sym = "G" },
    { id = "minecraft:diamond_block", color = colors.cyan, sym = "D" },
}

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

-- --- State ---

local state = {}

local function resetState()
    state.running = true
    state.w = 14
    state.h = 14
    state.d = 5
    state.data = {} -- [x][y][z] = material_index (0 or nil for air)
    state.meta = {} -- [x][y][z] = meta table
    state.fileMeta = nil -- Global file metadata
    state.palette = {}
    state.paletteEditMode = false
    state.offset = { x = 0, y = 0, z = 0 }

    state.view = {
        layer = 0, -- Current Y level
        offsetX = 4, -- Screen X offset of canvas
        offsetY = 3, -- Screen Y offset of canvas
        scrollX = 0,
        scrollY = 0,
        cursorX = 0,
        cursorY = 0,
    }

    state.menuOpen = false
    state.inventoryOpen = false
    state.searchOpen = false
    state.searchQuery = ""
    state.searchResults = {}
    state.searchScroll = 0
    state.dragItem = nil -- { id, sym, color }

    state.tool = TOOLS.PENCIL
    state.primaryColor = 1 -- Index in palette
    state.secondaryColor = 0 -- 0 = Air/Eraser

    state.mouse = {
        down = false,
        drag = false,
        startX = 0, startY = 0, -- Canvas coords
        currX = 0, currY = 0,   -- Canvas coords
        btn = 1
    }

    state.status = "Ready"

    for i, m in ipairs(DEFAULT_MATERIALS) do
        state.palette[i] = { id = m.id, color = m.color, sym = m.sym }
    end
end

resetState()

-- --- Helpers ---

local function getMaterial(idx)
    if idx == 0 or not idx then return nil end
    return state.palette[idx]
end

local function getBlock(x, y, z)
    if not state.data[x] then return 0 end
    if not state.data[x][y] then return 0 end
    return state.data[x][y][z] or 0
end

local function setBlock(x, y, z, matIdx, meta)
    if x < 0 or x >= state.w or z < 0 or z >= state.h or y < 0 or y >= state.d then return end

    if not state.data[x] then state.data[x] = {} end
    if not state.data[x][y] then state.data[x][y] = {} end
    if not state.meta[x] then state.meta[x] = {} end
    if not state.meta[x][y] then state.meta[x][y] = {} end

    if matIdx == 0 then
        state.data[x][y][z] = nil
        if state.meta[x] and state.meta[x][y] then
            state.meta[x][y][z] = nil
        end
    else
        state.data[x][y][z] = matIdx
        state.meta[x][y][z] = meta or {}
    end
end

local function getBlockMeta(x, y, z)
    if not state.meta[x] or not state.meta[x][y] then return {} end
    return schema_utils.cloneMeta(state.meta[x][y][z])
end

local function findItemDef(id)
    for _, item in ipairs(items) do
        if item.id == id then
            return item
        end
    end
    return nil
end

local function ensurePaletteMaterial(material)
    for idx, mat in ipairs(state.palette) do
        if mat.id == material then
            return idx
        end
    end

    local fallback = findItemDef(material)
    local entry = {
        id = material,
        color = fallback and fallback.color or colors.white,
        sym = fallback and fallback.sym or "?",
    }

    table.insert(state.palette, entry)
    return #state.palette
end

local function clearCanvas()
    state.data = {}
    state.meta = {}
end

local function loadCanonical(schema, metadata)
    if type(schema) ~= "table" then
        return false, "invalid_schema"
    end

    clearCanvas()

    local bounds = schema_utils.newBounds()
    local blockCount = 0

    for xKey, xColumn in pairs(schema) do
        if type(xColumn) == "table" then
            local x = tonumber(xKey) or xKey
            if type(x) ~= "number" then return false, "invalid_coordinate" end
            for yKey, yColumn in pairs(xColumn) do
                if type(yColumn) == "table" then
                    local y = tonumber(yKey) or yKey
                    if type(y) ~= "number" then return false, "invalid_coordinate" end
                    for zKey, block in pairs(yColumn) do
                        if type(block) == "table" and block.material then
                            local z = tonumber(zKey) or zKey
                            if type(z) ~= "number" then return false, "invalid_coordinate" end
                            schema_utils.updateBounds(bounds, x, y, z)
                            blockCount = blockCount + 1
                        end
                    end
                end
            end
        end
    end

    if blockCount == 0 then
        state.status = "Loaded empty schema"
        return true
    end

    state.offset = {
        x = bounds.min.x,
        y = bounds.min.y,
        z = bounds.min.z,
    }

    state.w = math.max(1, (bounds.max.x - bounds.min.x) + 1)
    state.d = math.max(1, (bounds.max.y - bounds.min.y) + 1)
    state.h = math.max(1, (bounds.max.z - bounds.min.z) + 1)

    for xKey, xColumn in pairs(schema) do
        if type(xColumn) == "table" then
            local x = tonumber(xKey) or xKey
            if type(x) ~= "number" then return false, "invalid_coordinate" end
            for yKey, yColumn in pairs(xColumn) do
                if type(yColumn) == "table" then
                    local y = tonumber(yKey) or yKey
                    if type(y) ~= "number" then return false, "invalid_coordinate" end
                    for zKey, block in pairs(yColumn) do
                        if type(block) == "table" and block.material then
                            local z = tonumber(zKey) or zKey
                            if type(z) ~= "number" then return false, "invalid_coordinate" end
                            local matIdx = ensurePaletteMaterial(block.material)
                            local localX = x - state.offset.x
                            local localY = y - state.offset.y
                            local localZ = z - state.offset.z
                            setBlock(localX, localY, localZ, matIdx, schema_utils.cloneMeta(block.meta))
                        end
                    end
                end
            end
        end
    end

    state.status = string.format("Loaded %d blocks", blockCount)
    if metadata and metadata.path then
        state.status = state.status .. " from " .. metadata.path
    end

    if metadata and metadata.meta then
        state.fileMeta = metadata.meta
    end

    return true
end

local function exportCanonical()
    local schema = {}
    local bounds = schema_utils.newBounds()
    local total = 0

    for x, xColumn in pairs(state.data) do
        for y, yColumn in pairs(xColumn) do
            for z, matIdx in pairs(yColumn) do
                local mat = getMaterial(matIdx)
                if mat then
                    local worldX = x + state.offset.x
                    local worldY = y + state.offset.y
                    local worldZ = z + state.offset.z
                    schema[worldX] = schema[worldX] or {}
                    schema[worldX][worldY] = schema[worldX][worldY] or {}
                    schema[worldX][worldY][worldZ] = {
                        material = mat.id,
                        meta = getBlockMeta(x, y, z),
                    }
                    schema_utils.updateBounds(bounds, worldX, worldY, worldZ)
                    total = total + 1
                end
            end
        end
    end

    local info = { totalBlocks = total }
    if total > 0 then
        info.bounds = bounds
    end

    return schema, info
end

local function exportVoxelDefinition()
    local canonical, info = exportCanonical()
    return schema_utils.canonicalToVoxelDefinition(canonical), info
end

-- --- Algorithms ---

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

local function drawRect(x0, y0, x1, y1, filled, callback)
    local minX, maxX = math.min(x0, x1), math.max(x0, x1)
    local minY, maxY = math.min(y0, y1), math.max(y0, y1)
    
    for x = minX, maxX do
        for y = minY, maxY do
            if filled or (x == minX or x == maxX or y == minY or y == maxY) then
                callback(x, y)
            end
        end
    end
end

local function drawCircle(x0, y0, x1, y1, filled, callback)
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

local function floodFill(startX, startY, targetColor, replaceColor)
    if targetColor == replaceColor then return end
    
    local queue = { {x = startX, y = startY} }
    local visited = {}
    
    local function key(x, y) return x .. "," .. y end
    
    while #queue > 0 do
        local p = table.remove(queue, 1)
        local k = key(p.x, p.y)
        
        if not visited[k] then
            visited[k] = true
            local curr = getBlock(p.x, state.view.layer, p.y)
            
            if curr == targetColor then
                setBlock(p.x, state.view.layer, p.y, replaceColor)
                
                local neighbors = {
                    {x = p.x + 1, y = p.y},
                    {x = p.x - 1, y = p.y},
                    {x = p.x, y = p.y + 1},
                    {x = p.x, y = p.y - 1}
                }
                
                for _, n in ipairs(neighbors) do
                    if n.x >= 0 and n.x < state.w and n.y >= 0 and n.y < state.h then
                        table.insert(queue, n)
                    end
                end
            end
        end
    end
end

-- --- Rendering ---

local drawSearch

local function drawMenu()
    if not state.menuOpen then return end
    
    local w, h = term.getSize()
    local mx, my = w - 12, 2
    local mw, mh = 12, 8
    
    ui.drawFrame(mx, my, mw, mh, "Menu")
    
    local options = { "Resize", "Save", "Load", "Clear", "Inventory", "Quit" }
    for i, opt in ipairs(options) do
        term.setCursorPos(mx + 1, my + i)
        term.setBackgroundColor(COLORS.bg)
        term.setTextColor(COLORS.text)
        if opt == "Inventory" and state.inventoryOpen then
            term.setTextColor(colors.yellow)
        end
        term.write(opt)
    end
end

local function drawInventory()
    if not state.inventoryOpen then return end
    
    local w, h = term.getSize()
    local iw, ih = 18, 6 -- 4x4 grid + border
    local ix, iy = math.floor((w - iw)/2), math.floor((h - ih)/2)
    
    ui.drawFrame(ix, iy, iw, ih, "Inventory")
    
    -- Draw 4x4 grid
    for row = 0, 3 do
        for col = 0, 3 do
            local slot = row * 4 + col + 1
            local item = turtle.getItemDetail(slot)
            
            term.setCursorPos(ix + 1 + (col * 4), iy + 1 + row)
            
            local sym = "."
            local color = colors.gray
            
            if item then
                sym = item.name:sub(11, 11):upper() -- First char of name after minecraft:
                color = colors.white
            end
            
            term.setBackgroundColor(colors.black)
            term.setTextColor(color)
            term.write(" " .. sym .. " ")
        end
    end
    
    term.setCursorPos(ix + 1, iy + ih)
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.text)
    term.write("Drag to Palette")
end

local function drawDragItem()
    if state.dragItem and state.mouse.screenX then
        term.setCursorPos(state.mouse.screenX, state.mouse.screenY)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.write(state.dragItem.sym)
    end
end

local function drawUI()
    ui.clear()
    
    -- Toolbar (Top)
    term.setBackgroundColor(COLORS.bg)
    term.setCursorPos(1, 1)
    term.clearLine()
    
    -- [M] Button
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.write(" M ")
    
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.text)
    term.write(string.format(" Designer [%d,%d,%d] Layer: %d/%d", state.w, state.h, state.d, state.view.layer, state.d - 1))
    
    -- Tools (Left Side)
    local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
    for i, t in ipairs(toolsList) do
        term.setCursorPos(1, 2 + i)
        if state.tool == t then
            term.setBackgroundColor(COLORS.btn_active)
            term.setTextColor(colors.white)
            term.write(" " .. t:sub(1,1) .. " ")
        else
            term.setBackgroundColor(COLORS.btn_inactive)
            term.setTextColor(COLORS.btn_text)
            term.write(" " .. t:sub(1,1) .. " ")
        end
    end
    
    -- Palette (Right Side)
    local palX = 2 + state.w + 2
    term.setCursorPos(palX, 2)
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.text)
    
    local editLabel = state.paletteEditMode and "[EDITING]" or "[Edit]"
    if state.paletteEditMode then term.setTextColor(colors.red) end
    term.write("Pal " .. editLabel)
    
    -- Search Button
    term.setCursorPos(palX + 14, 2)
    term.setBackgroundColor(COLORS.btn_inactive)
    term.setTextColor(COLORS.btn_text)
    term.write("Find")
    
    for i, mat in ipairs(state.palette) do
        term.setCursorPos(palX, 3 + i)
        
        -- Indicator for selection
        local indicator = " "
        if state.primaryColor == i then indicator = "L" end
        if state.secondaryColor == i then indicator = "R" end
        if state.primaryColor == i and state.secondaryColor == i then indicator = "B" end
        
        term.setBackgroundColor(COLORS.bg)
        term.setTextColor(COLORS.text)
        term.write(indicator)
        
        term.setBackgroundColor(mat.color)
        term.setTextColor(colors.black)
        term.write(" " .. mat.sym .. " ")
        
        term.setBackgroundColor(COLORS.bg)
        term.setTextColor(COLORS.text)
        local name = mat.id:match(":(.+)") or mat.id
        term.write(" " .. name)
    end
    
    -- Status Bar (Bottom)
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(COLORS.bg)
    term.clearLine()
    term.write(state.status)
    
    -- Display version in bottom right corner
    local versionText = version.display()
    term.setCursorPos(w - #versionText + 1, h)
    term.setTextColor(colors.lightGray)
    term.write(versionText)
    term.setTextColor(COLORS.text)
    
    -- Instructions
    term.setCursorPos(1, h-1)
    term.write("S:Save L:Load F:Find R:Resize C:Clear Q:Quit PgUp/Dn:Layer")
    
    drawMenu()
    drawInventory()
    drawSearch()
    drawDragItem()
end

local function drawCanvas()
    local ox, oy = state.view.offsetX, state.view.offsetY
    local sx, sy = state.view.scrollX, state.view.scrollY
    
    -- Draw Border
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(colors.white)
    ui.drawBox(ox - 1, oy - 1, state.w + 2, state.h + 2, COLORS.bg, colors.white)
    
    -- Draw Pixels
    for x = 0, state.w - 1 do
        for z = 0, state.h - 1 do
            -- Apply scroll
            local screenX = ox + x - sx
            local screenY = oy + z - sy
            
            -- Only draw if within canvas view area (roughly)
            -- Actually, we should clip to the border box
            -- For simplicity, let's just draw if it fits on screen
            local w, h = term.getSize()
            if screenX >= ox and screenX < w and screenY >= oy and screenY < h - 2 then
                local matIdx = getBlock(x, state.view.layer, z)
                local mat = getMaterial(matIdx)
                
                local bg = COLORS.canvas_bg
                local char = "."
                local fg = COLORS.grid
                
                if mat then
]=]

local lib_designer_part2 = [=[                    bg = mat.color
                    char = mat.sym
                    fg = colors.black
                    if bg == colors.black then fg = colors.white end
                end
                
                -- Ghost drawing
                if state.mouse.down and state.mouse.drag then
                    local isGhost = false
                    local ghostColor = (state.mouse.btn == 1) and state.primaryColor or state.secondaryColor
                    
                    local function checkGhost(gx, gy)
                        if gx == x and gy == z then isGhost = true end
                    end
                    
                    if state.tool == TOOLS.PENCIL then
                        checkGhost(state.mouse.currX, state.mouse.currY)
                    elseif state.tool == TOOLS.LINE then
                        drawLine(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, checkGhost)
                    elseif state.tool == TOOLS.RECT then
                        drawRect(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, false, checkGhost)
                    elseif state.tool == TOOLS.RECT_FILL then
                        drawRect(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, true, checkGhost)
                    elseif state.tool == TOOLS.CIRCLE then
                        drawCircle(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, false, checkGhost)
                    elseif state.tool == TOOLS.CIRCLE_FILL then
                        drawCircle(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, true, checkGhost)
                    end
                    
                    if isGhost then
                        local gMat = getMaterial(ghostColor)
                        if gMat then
                            bg = gMat.color
                            char = gMat.sym
                            fg = colors.black
                        else
                            bg = COLORS.canvas_bg
                            char = "x"
                            fg = colors.red
                        end
                    end
                end
                
                term.setCursorPos(screenX, screenY)
                term.setBackgroundColor(bg)
                term.setTextColor(fg)
                term.write(char)
            end
        end
    end

    -- Draw Cursor
    local cx, cy = state.view.cursorX, state.view.cursorY
    local screenX = ox + cx - sx
    local screenY = oy + cy - sy
    local w, h = term.getSize()
    
    if screenX >= ox and screenX < w and screenY >= oy and screenY < h - 2 then
        term.setCursorPos(screenX, screenY)
        if os.clock() % 0.8 < 0.4 then
            term.setBackgroundColor(colors.white)
            term.setTextColor(colors.black)
        else
            local matIdx = getBlock(cx, state.view.layer, cy)
            local mat = getMaterial(matIdx)
            if mat then
                term.setBackgroundColor(mat.color == colors.white and colors.black or colors.white)
                term.setTextColor(mat.color)
            else
                term.setBackgroundColor(colors.white)
                term.setTextColor(colors.black)
            end
        end
        local matIdx = getBlock(cx, state.view.layer, cy)
        local mat = getMaterial(matIdx)
        term.write(mat and mat.sym or "+")
    end
end



-- --- Logic ---

local function applyTool(x, y, btn)
    local color = (btn == 1) and state.primaryColor or state.secondaryColor
    
    if state.tool == TOOLS.PENCIL then
        setBlock(x, state.view.layer, y, color)
    elseif state.tool == TOOLS.BUCKET then
        local target = getBlock(x, state.view.layer, y)
        floodFill(x, y, target, color)
    elseif state.tool == TOOLS.PICKER then
        local picked = getBlock(x, state.view.layer, y)
        if btn == 1 then state.primaryColor = picked else state.secondaryColor = picked end
        state.tool = TOOLS.PENCIL -- Auto switch back
    end
end

local function applyShape(x0, y0, x1, y1, btn)
    local color = (btn == 1) and state.primaryColor or state.secondaryColor
    
    local function plot(x, y)
        setBlock(x, state.view.layer, y, color)
    end
    
    if state.tool == TOOLS.LINE then
        drawLine(x0, y0, x1, y1, plot)
    elseif state.tool == TOOLS.RECT then
        drawRect(x0, y0, x1, y1, false, plot)
    elseif state.tool == TOOLS.RECT_FILL then
        drawRect(x0, y0, x1, y1, true, plot)
    elseif state.tool == TOOLS.CIRCLE then
        drawCircle(x0, y0, x1, y1, false, plot)
    elseif state.tool == TOOLS.CIRCLE_FILL then
        drawCircle(x0, y0, x1, y1, true, plot)
    end
end

local function loadSchema()
    ui.clear()
    term.setCursorPos(1, 1)
    print("Load Schema")
    term.write("Filename: ")
    local name = read()
    if name == "" then return end
    
    -- Try to load file
    if not fs.exists(name) then
        if fs.exists(name .. ".json") then name = name .. ".json"
        elseif fs.exists(name .. ".txt") then name = name .. ".txt"
        else
            state.status = "File not found"
            return
        end
    end
    
    local ok, schema, meta = parser.parseFile(nil, name)
    
    if ok then
        local ok2, err = loadCanonical(schema, meta)
        if ok2 then
            state.status = "Loaded " .. name
        else
            state.status = "Error loading: " .. err
        end
    else
        state.status = "Parse error: " .. schema
    end
end

local function saveSchema()
    ui.clear()
    term.setCursorPos(1, 1)
    print("Save Schema")
    term.write("Filename: ")
    local name = read()
    if name == "" then return end
    if not name:find("%.json$") then name = name .. ".json" end
    
    local exportDef, info = exportVoxelDefinition()
    
    -- Inject file metadata if present
    if state.fileMeta then
        exportDef.meta = state.fileMeta
    end

    local f = fs.open(name, "w")
    f.write(json.encode(exportDef))
    f.close()
    state.status = "Saved to " .. name
end

local function resizeCanvas()
    ui.clear()
    print("Resize Canvas")
    term.write("Width (" .. state.w .. "): ")
    local w = tonumber(read()) or state.w
    term.write("Height/Depth (" .. state.h .. "): ")
    local h = tonumber(read()) or state.h
    term.write("Layers (" .. state.d .. "): ")
    local d = tonumber(read()) or state.d
    
    state.w = w
    state.h = h
    state.d = d
end

local function editPaletteItem(idx)
    ui.clear()
    term.setCursorPos(1, 1)
    print("Edit Palette Item #" .. idx)
    
    local current = state.palette[idx]
    
    term.write("ID (" .. current.id .. "): ")
    local newId = read()
    if newId == "" then newId = current.id end
    
    term.write("Symbol (" .. current.sym .. "): ")
    local newSym = read()
    if newSym == "" then newSym = current.sym end
    newSym = newSym:sub(1, 1)
    
    -- Color selection is tricky in text mode, let's skip for now or cycle
    -- For now, keep color
    
    state.palette[idx].id = newId
    state.palette[idx].sym = newSym
    state.status = "Updated Item #" .. idx
end

local function updateSearchResults()
    state.searchResults = {}
    local query = state.searchQuery:lower()
    for _, item in ipairs(items) do
        if item.name:lower():find(query, 1, true) or item.id:lower():find(query, 1, true) then
            table.insert(state.searchResults, item)
        end
    end
    state.searchScroll = 0
end

drawSearch = function()
    if not state.searchOpen then return end
    
    local w, h = term.getSize()
    local sw, sh = 24, 14
    local sx, sy = math.floor((w - sw)/2), math.floor((h - sh)/2)
    
    ui.drawFrame(sx, sy, sw, sh, "Item Search")
    
    -- Search Box
    term.setCursorPos(sx + 1, sy + 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(state.searchQuery .. "_")
    local padding = sw - 2 - #state.searchQuery - 1
    if padding > 0 then term.write(string.rep(" ", padding)) end
    
    -- Results List
    local maxLines = sh - 3
    for i = 1, maxLines do
        local idx = state.searchScroll + i
        local item = state.searchResults[idx]
        
        term.setCursorPos(sx + 1, sy + 2 + i)
        if item then
            term.setBackgroundColor(colors.black)
            term.setTextColor(item.color or colors.white)
            local label = item.name or item.id
            if #label > sw - 4 then label = label:sub(1, sw - 4) end
            term.write(" " .. item.sym .. " " .. label)
            local pad = sw - 2 - 3 - #label
            if pad > 0 then term.write(string.rep(" ", pad)) end
        else
            term.setBackgroundColor(COLORS.bg)
            term.write(string.rep(" ", sw - 2))
        end
    end
end

-- --- Main ---

function designer.run(opts)
    opts = opts or {}
    resetState()

    if opts.palette then
        state.palette = {}
        for i, item in ipairs(opts.palette) do
            table.insert(state.palette, {
                id = item.id,
                color = item.color,
                sym = item.sym
            })
        end
    end

    if opts.meta then
        state.fileMeta = opts.meta
    end

    if opts.schema then
        local ok, err = loadCanonical(opts.schema, opts.metadata)
        if not ok then
            return false, err
        end
    end

    state.running = true

    while state.running do
        drawUI()
        drawCanvas()
        drawMenu()
        drawInventory()
        drawSearch()
        drawDragItem()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "char" and state.searchOpen then
            state.searchQuery = state.searchQuery .. p1
            updateSearchResults()

        elseif event == "mouse_scroll" and state.searchOpen then
            local dir = p1
            state.searchScroll = math.max(0, state.searchScroll + dir)

        elseif event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            state.mouse.screenX = mx
            state.mouse.screenY = my
            local handled = false

            -- 0. Check Search (Topmost)
            if state.searchOpen then
                local w, h = term.getSize()
                local sw, sh = 24, 14
                local sx, sy = math.floor((w - sw)/2), math.floor((h - sh)/2)

                if mx >= sx and mx < sx + sw and my >= sy and my < sy + sh then
                    -- Inside Search Window
                    if my >= sy + 3 then
                        local idx = state.searchScroll + (my - (sy + 2))
                        local item = state.searchResults[idx]
                        if item then
                            state.dragItem = { id = item.id, sym = item.sym, color = item.color }
                            state.searchOpen = false
                        end
                    end
                    handled = true
                else
                    state.searchOpen = false
                    handled = true
                end
            end

            -- 1. Check Menu (Topmost)
            if not handled and state.menuOpen then
                local w, h = term.getSize()
                local menuX, menuY = w - 12, 2
                if mx >= menuX and mx < menuX + 12 and my >= menuY and my < menuY + 8 then
                    local idx = my - menuY
                    local options = { "Resize", "Save", "Load", "Clear", "Inventory", "Quit" }
                    if options[idx] then
                        if options[idx] == "Quit" then state.running = false
                        elseif options[idx] == "Inventory" then state.inventoryOpen = not state.inventoryOpen
                        elseif options[idx] == "Resize" then resizeCanvas()
                        elseif options[idx] == "Save" then saveSchema()
                        elseif options[idx] == "Clear" then clearCanvas()
                        elseif options[idx] == "Load" then loadSchema()
                        end
                        if options[idx] ~= "Inventory" then state.menuOpen = false end
                    end
                    handled = true
                else
                    -- Click outside menu closes it
                    state.menuOpen = false
                    handled = true -- Consume click
                end
            end

            -- 2. Check Inventory (Topmost)
            if not handled and state.inventoryOpen then
                local w, h = term.getSize()
                local iw, ih = 18, 6
                local ix, iy = math.floor((w - iw)/2), math.floor((h - ih)/2)

                if mx >= ix and mx < ix + iw and my >= iy and my < iy + ih then
                    -- Check slot click
                    local relX, relY = mx - ix - 1, my - iy - 1
                    if relX >= 0 and relY >= 0 then
                        local col = math.floor(relX / 4)
                        local row = relY
                        if col >= 0 and col <= 3 and row >= 0 and row <= 3 then
                            local slot = row * 4 + col + 1
                            local item = turtle.getItemDetail(slot)
                            if item then
                                state.dragItem = {
                                    id = item.name,
                                    sym = item.name:sub(11, 11):upper(),
                                    color = colors.white
                                }
                            end
                        end
                    end
                    handled = true
                end
            end

            -- 3. Check [M] Button
            if not handled and mx >= 1 and mx <= 3 and my == 1 then
                state.menuOpen = not state.menuOpen
                handled = true
            end

            -- 4. Check Palette (Drop Target & Selection)
            local palX = 2 + state.w + 2
            if not handled and mx >= palX and mx <= palX + 18 then -- Expanded for Search button
                if my == 2 then
                    -- Check Edit vs Search
                    if mx >= palX + 14 and mx <= palX + 17 then
                        state.searchOpen = not state.searchOpen
                        if state.searchOpen then
                            state.searchQuery = ""
                            updateSearchResults()
                        end
                    elseif mx <= palX + 13 then
                        state.paletteEditMode = not state.paletteEditMode
                    end
                    handled = true
                elseif my >= 4 and my < 4 + #state.palette then
                    local idx = my - 3
                    if state.paletteEditMode then
                        editPaletteItem(idx)
                    else
                        if btn == 1 then state.primaryColor = idx
                        elseif btn == 2 then state.secondaryColor = idx end
                    end
                    handled = true
                end
            end

            -- 5. Check Tools
            if not handled and mx >= 1 and mx <= 3 and my >= 3 and my < 3 + 8 then
                local idx = my - 2
                local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
                if toolsList[idx] then state.tool = toolsList[idx] end
                handled = true
            end

            -- 6. Check Canvas
            if not handled then
                local cx = mx - state.view.offsetX
                local cy = my - state.view.offsetY

                if cx >= 0 and cx < state.w and cy >= 0 and cy < state.h then
                    state.mouse.down = true
                    state.mouse.btn = btn
                    state.mouse.startX = cx
                    state.mouse.startY = cy
                    state.mouse.currX = cx
                    state.mouse.currY = cy

                    if state.tool == TOOLS.PENCIL or state.tool == TOOLS.BUCKET or state.tool == TOOLS.PICKER then
                        applyTool(cx, cy, btn)
                    end
                end
            end

        elseif event == "mouse_drag" then
            local btn, mx, my = p1, p2, p3
            state.mouse.screenX = mx
            state.mouse.screenY = my
            local cx = mx - state.view.offsetX
            local cy = my - state.view.offsetY

            if state.mouse.down then
                -- Clamp to canvas
                cx = math.max(0, math.min(state.w - 1, cx))
                cy = math.max(0, math.min(state.h - 1, cy))

                state.mouse.currX = cx
                state.mouse.currY = cy
                state.mouse.drag = true

                if state.tool == TOOLS.PENCIL then
                    applyTool(cx, cy, state.mouse.btn)
                end
            end

        elseif event == "mouse_up" then
            local btn, mx, my = p1, p2, p3

            -- Handle Drag Drop to Palette
            if state.dragItem then
                local palX = 2 + state.w + 2
                if mx >= palX and mx <= palX + 15 and my >= 4 and my < 4 + #state.palette then
                    local idx = my - 3
                    state.palette[idx].id = state.dragItem.id
                    state.palette[idx].sym = state.dragItem.sym
                    state.status = "Assigned " .. state.dragItem.id .. " to slot " .. idx
                end
                state.dragItem = nil
            end

            if state.mouse.down and state.mouse.drag then
                -- Commit shape
                if state.tool == TOOLS.LINE or state.tool == TOOLS.RECT or state.tool == TOOLS.RECT_FILL or state.tool == TOOLS.CIRCLE then
                    applyShape(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, state.mouse.btn)
                end
            end
            state.mouse.down = false
            state.mouse.drag = false

        elseif event == "key" then
            local key = p1

            if state.searchOpen then
                if key == keys.backspace then
                    state.searchQuery = state.searchQuery:sub(1, -2)
                    updateSearchResults()
                elseif key == keys.enter then
                    if #state.searchResults > 0 then
                        local item = state.searchResults[1]
                        state.dragItem = { id = item.id, sym = item.sym, color = item.color }
                        state.searchOpen = false
                    end
                elseif key == keys.up then
                    state.searchScroll = math.max(0, state.searchScroll - 1)
                elseif key == keys.down then
                    state.searchScroll = state.searchScroll + 1
                end
            else
                -- Cursor Movement
                if key == keys.up then
                    state.view.cursorY = math.max(0, state.view.cursorY - 1)
                    if state.view.cursorY < state.view.scrollY then state.view.scrollY = state.view.cursorY end
                    if state.mouse.drag then state.mouse.currY = state.view.cursorY end
                elseif key == keys.down then
                    state.view.cursorY = math.min(state.h - 1, state.view.cursorY + 1)
                    local h = term.getSize()
                    local viewH = h - 2 - state.view.offsetY
                    if state.view.cursorY >= state.view.scrollY + viewH then state.view.scrollY = state.view.cursorY - viewH + 1 end
                    if state.mouse.drag then state.mouse.currY = state.view.cursorY end
                elseif key == keys.left then
                    state.view.cursorX = math.max(0, state.view.cursorX - 1)
                    if state.view.cursorX < state.view.scrollX then state.view.scrollX = state.view.cursorX end
                    if state.mouse.drag then state.mouse.currX = state.view.cursorX end
                elseif key == keys.right then
                    state.view.cursorX = math.min(state.w - 1, state.view.cursorX + 1)
                    local w = term.getSize()
                    local viewW = w - state.view.offsetX
                    if state.view.cursorX >= state.view.scrollX + viewW then state.view.scrollX = state.view.cursorX - viewW + 1 end
                    if state.mouse.drag then state.mouse.currX = state.view.cursorX end
                
                -- Actions
                elseif key == keys.space or key == keys.enter then
                    if state.tool == TOOLS.PENCIL or state.tool == TOOLS.BUCKET or state.tool == TOOLS.PICKER then
                        applyTool(state.view.cursorX, state.view.cursorY, 1)
                    else
                        -- Shape tools: Toggle drag
                        if not state.mouse.drag then
                            state.mouse.startX = state.view.cursorX
                            state.mouse.startY = state.view.cursorY
                            state.mouse.currX = state.view.cursorX
                            state.mouse.currY = state.view.cursorY
                            state.mouse.drag = true
                            state.mouse.down = true
                            state.mouse.btn = 1
                        else
                            state.mouse.currX = state.view.cursorX
                            state.mouse.currY = state.view.cursorY
                            applyShape(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, 1)
                            state.mouse.drag = false
                            state.mouse.down = false
                        end
                    end
                
                -- Palette
                elseif key == keys.leftBracket then
                    state.primaryColor = math.max(1, state.primaryColor - 1)
                elseif key == keys.rightBracket then
                    state.primaryColor = math.min(#state.palette, state.primaryColor + 1)
                
                -- Tools (Number keys 1-8)
                elseif key >= keys.one and key <= keys.eight then
                    local idx = key - keys.one + 1
                    local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
                    if toolsList[idx] then state.tool = toolsList[idx] end
                end

                if key == keys.q then state.running = false end
                if key == keys.f then 
                    state.searchOpen = not state.searchOpen 
                    if state.searchOpen then 
                        state.searchQuery = "" 
                        updateSearchResults()
                    end
                end
                if key == keys.s then saveSchema() end
                if key == keys.r then resizeCanvas() end
                if key == keys.c then clearCanvas() end -- Clear all
                if key == keys.pageUp then state.view.layer = math.min(state.d - 1, state.view.layer + 1) end
                if key == keys.pageDown then state.view.layer = math.max(0, state.view.layer - 1) end
            end
        end
    end

    if opts.returnSchema then
        return exportCanonical()
    end
end

designer.loadCanonical = loadCanonical
designer.exportCanonical = exportCanonical
designer.exportVoxelDefinition = exportVoxelDefinition

return designer
]=]

addEmbeddedFile("lib/lib_designer.lua", lib_designer_part1 .. lib_designer_part2)

addEmbeddedFile("factory/turtle_os.lua", [=[--[[
TurtleOS v2.0
Graphical launcher for the factory agent.
--]]

---@diagnostic disable: undefined-global

-- Minimal require compat so this file can run even when Arcadesys didn't
-- install a global require (eg. when invoked directly on CraftOS turtles).
if type(package) ~= "table" then package = { path = "" } end
if type(package.path) ~= "string" then package.path = package.path or "" end
package.loaded = package.loaded or {}

local function requireCompat(name)
    if package.loaded[name] ~= nil then return package.loaded[name] end

    local lastErr
    for pattern in string.gmatch(package.path or "", "([^;]+)") do
        local candidate = pattern:gsub("%?", name)
        if fs.exists(candidate) and not fs.isDir(candidate) then
            local fn, err = loadfile(candidate)
            if not fn then
                lastErr = err
            else
                local ok, res = pcall(fn)
                if not ok then
                    lastErr = res
                else
                    package.loaded[name] = res
                    return res
                end
            end
        end
    end

    error(string.format("module '%s' not found%s", name, lastErr and (": " .. tostring(lastErr)) or ""))
end

local function ensurePackagePaths(baseDir)
    local root = baseDir == "" and "/" or baseDir
    local paths = {
        "/?.lua",
        "/lib/?.lua",
        fs.combine(root, "?.lua"),
        fs.combine(root, "lib/?.lua"),
        fs.combine(root, "factory/?.lua"),
        fs.combine(root, "ui/?.lua"),
        fs.combine(root, "tools/?.lua"),
    }

    local current = package.path or ""
    if current ~= "" then table.insert(paths, current) end

    local seen, final = {}, {}
    for _, p in ipairs(paths) do
        if p and p ~= "" and not seen[p] then
            seen[p] = true
            table.insert(final, p)
        end
    end
    package.path = table.concat(final, ";")
end

local function detectBaseDir()
    if shell and shell.getRunningProgram then
        return fs.getDir(shell.getRunningProgram())
    end
    if debug and debug.getinfo then
        local info = debug.getinfo(1, "S")
        if info and info.source then
            local src = info.source
            if src:sub(1, 1) == "@" then src = src:sub(2) end
            return fs.getDir(src)
        end
    end
    return ""
end

ensurePackagePaths(detectBaseDir())
local require = _G.require or requireCompat
_G.require = require

local ui = require("lib_ui")
local parser = require("lib_parser")
local json = require("lib_json")
local schema_utils = require("lib_schema")

-- Hack to load factory without running it immediately
_G.__FACTORY_EMBED__ = true
local factory = require("factory")
_G.__FACTORY_EMBED__ = nil

-- Helper to pause before returning
local function pauseAndReturn(retVal)
    print("\nOperation finished.")
    print("Press Enter to continue...")
    read()
    return retVal
end

-- --- ACTIONS ---

local function runMining(form)
    local length = 64
    local interval = 3
    local torch = 6
    
    for _, el in ipairs(form.elements) do
        if el.id == "length" then length = tonumber(el.value) or 64 end
        if el.id == "interval" then interval = tonumber(el.value) or 3 end
        if el.id == "torch" then torch = tonumber(el.value) or 6 end
    end
    
    ui.clear()
    print("Starting Mining Operation...")
    print(string.format("Length: %d, Interval: %d", length, interval))
    sleep(1)
    
    factory.run({ "mine", "--length", tostring(length), "--branch-interval", tostring(interval), "--torch-interval", tostring(torch) })
    
    return pauseAndReturn("stay")
end

local function runTunnel()
    local length = 16
    local width = 1
    local height = 2
    local torch = 6
    
    local form = ui.Form("Tunnel Configuration")
    form:addInput("length", "Length", tostring(length))
    form:addInput("width", "Width", tostring(width))
    form:addInput("height", "Height", tostring(height))
    form:addInput("torch", "Torch Interval", tostring(torch))
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "length" then length = tonumber(el.value) or 16 end
        if el.id == "width" then width = tonumber(el.value) or 1 end
        if el.id == "height" then height = tonumber(el.value) or 2 end
        if el.id == "torch" then torch = tonumber(el.value) or 6 end
    end
    
    ui.clear()
    print("Starting Tunnel Operation...")
    print(string.format("L: %d, W: %d, H: %d", length, width, height))
    sleep(1)
    
    factory.run({ "tunnel", "--length", tostring(length), "--width", tostring(width), "--height", tostring(height), "--torch-interval", tostring(torch) })
    
    return pauseAndReturn("stay")
end

local function runExcavate()
    local length = 8
    local width = 8
    local depth = 3
    
    local form = ui.Form("Excavation Configuration")
    form:addInput("length", "Length", tostring(length))
    form:addInput("width", "Width", tostring(width))
    form:addInput("depth", "Depth", tostring(depth))
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "length" then length = tonumber(el.value) or 8 end
        if el.id == "width" then width = tonumber(el.value) or 8 end
        if el.id == "depth" then depth = tonumber(el.value) or 3 end
    end
    
    ui.clear()
    print("Starting Excavation Operation...")
    print(string.format("L: %d, W: %d, D: %d", length, width, depth))
    sleep(1)
    
    factory.run({ "excavate", "--length", tostring(length), "--width", tostring(width), "--depth", tostring(depth) })
    
    return pauseAndReturn("stay")
end

local function runTreeFarm()
    ui.clear()
    print("Starting Tree Farm...")
    sleep(1)
    factory.run({ "treefarm" })
    return pauseAndReturn("stay")
end

local function runPotatoFarm()
    local width = 9
    local length = 9
    
    local form = ui.Form("Potato Farm Configuration")
    form:addStepper("width", "Width", width, { min = 3, max = 25 })
    form:addStepper("length", "Length", length, { min = 3, max = 25 })
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "width" then width = tonumber(el.value) or 9 end
        if el.id == "length" then length = tonumber(el.value) or 9 end
    end
    
    ui.clear()
    print("Starting Potato Farm Build...")
    print(string.format("W: %d, L: %d", width, length))
    sleep(1)
    
    factory.run({ "farm", "--farm-type", "potato", "--width", tostring(width), "--length", tostring(length) })
    
    return pauseAndReturn("stay")
end

local function runBuild(schemaFile)
    ui.clear()
    print("Starting Build Operation...")
    print("Schema: " .. schemaFile)
end

local function main()
    while true do
        ui.clear()
        print("TurtleOS v2.0")
        print("-------------")
        
        local options = {
            { text = "Tree Farm", action = runTreeFarm },
            { text = "Potato Farm", action = runPotatoFarm },
            { text = "Excavate", action = runExcavate },
            { text = "Tunnel", action = runTunnel },
            { text = "Mine", action = runMining },
            { text = "Farm Designer", action = function()
                local sub = ui.Menu("Farm Designer")
                sub:addOption("Tree Farm Design", function()
                    ui.clear()
                    shell.run("factory_planner.lua", "--farm", "tree")
                end)
                sub:addOption("Potato Farm Design", function()
                    ui.clear()
                    shell.run("factory_planner.lua", "--farm", "potato")
                end)
                sub:addOption("Back", function() return "back" end)
                sub:run()
            end },
            { text = "Exit", action = function() return "exit" end }
        }
        
        local menu = ui.Menu("Main Menu")
        for _, opt in ipairs(options) do
            menu:addOption(opt.text, opt.action)
        end
        
        local result = menu:run()
        if result == "exit" then break end
    end
end

main()
]=])

addEmbeddedFile("factory/factory.lua", [=[--[[
Factory entry point for the modular agent system.
Exposes a `run(args)` helper so it can be required/bundled while remaining
runnable as a stand-alone turtle program.
]]

local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")
local debug = debug

-- Force reload of state modules to ensure updates are applied
local function requireForce(name)
    package.loaded[name] = nil
    return require(name)
end

local states = {
    INITIALIZE = requireForce("state_initialize"),
    CHECK_REQUIREMENTS = requireForce("state_check_requirements"),
    BUILD = requireForce("state_build"),
    MINE = requireForce("state_mine"),
    TREEFARM = requireForce("state_treefarm"),
    POTATOFARM = requireForce("state_potatofarm"),
    RESTOCK = requireForce("state_restock"),
    REFUEL = requireForce("state_refuel"),
    BLOCKED = requireForce("state_blocked"),
    ERROR = requireForce("state_error"),
    DONE = requireForce("state_done"),
}

local function mergeTables(base, extra)
    if type(base) ~= "table" then
        base = {}
    end
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            base[key] = value
        end
    end
    return base
end

local function buildPayload(ctx, extra)
    local payload = { context = diagnostics.snapshot(ctx) }
    if extra then
        mergeTables(payload, extra)
    end
    return payload
end

local function run(args)
    local ctx = {
        state = "INITIALIZE",
        config = {
            verbose = false,
            schemaPath = nil,
        },
        origin = { x = 0, y = 0, z = 0, facing = "north" },
        pointer = 1,
        schema = nil,
        strategy = nil,
        inventoryState = {},
        fuelState = {},
        retries = 0,
    }

    local index = 1
    while index <= #args do
        local value = args[index]
        if value == "--verbose" then
            ctx.config.verbose = true
        elseif value == "mine" then
            ctx.config.mode = "mine"
        elseif value == "tunnel" then
            ctx.config.mode = "tunnel"
        elseif value == "excavate" then
            ctx.config.mode = "excavate"
        elseif value == "treefarm" then
            ctx.config.mode = "treefarm"
            -- ctx.state = "TREEFARM" -- Let INITIALIZE handle setup
        elseif value == "potatofarm" then
            ctx.config.mode = "potatofarm"
        elseif value == "farm" then
            ctx.config.mode = "farm"
        elseif value == "--farm-type" then
            index = index + 1
            ctx.config.farmType = args[index]
        elseif value == "--width" then
            index = index + 1
            ctx.config.width = tonumber(args[index])
        elseif value == "--height" then
            index = index + 1
            ctx.config.height = tonumber(args[index])
        elseif value == "--depth" then
            index = index + 1
            ctx.config.depth = tonumber(args[index])
        elseif value == "--length" then
            index = index + 1
            ctx.config.length = tonumber(args[index])
        elseif value == "--branch-interval" then
            index = index + 1
            ctx.config.branchInterval = tonumber(args[index])
        elseif value == "--branch-length" then
            index = index + 1
            ctx.config.branchLength = tonumber(args[index])
        elseif value == "--torch-interval" then
            index = index + 1
            ctx.config.torchInterval = tonumber(args[index])
        elseif not value:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
            ctx.config.schemaPath = value
        end
        index = index + 1
    end

    if not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
        ctx.config.schemaPath = "schema.json"
    end

    -- Initialize logger
    local logOpts = {
        level = ctx.config.verbose and "debug" or "info",
        timestamps = true
    }
    logger.attach(ctx, logOpts)
    
    ctx.logger:info("Agent starting...")

    -- Load previous state if available
    local persistence = require("lib_persistence")
    local savedState = persistence.load(ctx)
    if savedState then
        ctx.logger:info("Resuming from saved state...")
        -- Merge saved state into context
        mergeTables(ctx, savedState)
        
        -- Restore movement state explicitly if needed
        if ctx.movement then
            local movement = require("lib_movement")
            movement.ensureState(ctx)
            -- Force the library to recognize the loaded position/facing
            -- (ensureState does this by checking ctx.movement, which we just loaded)
        end
    end

    -- Initial fuel check
    if turtle and turtle.getFuelLevel then
        local level = turtle.getFuelLevel()
        local limit = turtle.getFuelLimit()
        ctx.logger:info(string.format("Fuel: %s / %s", tostring(level), tostring(limit)))
        if level ~= "unlimited" and type(level) == "number" and level < 100 then
             ctx.logger:warn("Fuel is very low on startup!")
             -- Attempt emergency refuel
             local fuelLib = require("lib_fuel")
             fuelLib.refuel(ctx, { target = 2000 })
        end
    end

    -- Helper to save state
    ctx.save = function()
        persistence.save(ctx)
    end

    while ctx.state ~= "EXIT" do
        -- Save state before executing the next step
        ctx.save()

        local stateHandler = states[ctx.state]
        if not stateHandler then
            ctx.logger:error("Unknown state: " .. tostring(ctx.state), buildPayload(ctx))
            break
        end

        ctx.logger:debug("Entering state: " .. ctx.state)
        local ok, nextStateOrErr = pcall(stateHandler, ctx)
        if not ok then
            local trace = debug and debug.traceback and debug.traceback() or nil
            ctx.logger:error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr),
                buildPayload(ctx, { error = tostring(nextStateOrErr), traceback = trace }))
            ctx.lastError = nextStateOrErr
            ctx.state = "ERROR"
        else
            if type(nextStateOrErr) ~= "string" or nextStateOrErr == "" then
                ctx.logger:error("State returned invalid transition", buildPayload(ctx, { result = tostring(nextStateOrErr) }))
                ctx.lastError = nextStateOrErr
                ctx.state = "ERROR"
            elseif not states[nextStateOrErr] and nextStateOrErr ~= "EXIT" then
                ctx.logger:error("Transitioned to unknown state: " .. tostring(nextStateOrErr), buildPayload(ctx))
                ctx.state = "ERROR"
            else
                ctx.state = nextStateOrErr
            end
        end

        ---@diagnostic disable-next-line: undefined-global
        sleep(0)
    end
    
    -- Clear state on clean exit
    persistence.clear(ctx)

    ctx.logger:info("Agent finished.")
end

local module = { run = run }

---@diagnostic disable-next-line: undefined-field
if not _G.__FACTORY_EMBED__ then
    local argv = { ... }
    run(argv)
end

return module
]=])

addEmbeddedFile("factory/state_initialize.lua", [=[---@diagnostic disable: undefined-global
--[[
State: INITIALIZE
Loads schema, parses it, and computes the build strategy.
--]]

local parser = require("lib_parser")
local orientation = require("lib_orientation")
local logger = require("lib_logger")
local strategyTunnel = require("lib_strategy_tunnel")
local strategyExcavate = require("lib_strategy_excavate")
local strategyFarm = require("lib_strategy_farm")
local ui = require("lib_ui")
local startup = require("lib_startup")
local inventory = require("lib_inventory")

local function validateSchema(schema)
    if type(schema) ~= "table" then return false, "Schema is not a table" end
    local count = 0
    for _ in pairs(schema) do count = count + 1 end
    if count == 0 then return false, "Schema is empty" end
    return true
end

local function getBlock(schema, x, y, z)
    local xLayer = schema[x] or schema[tostring(x)]
    if not xLayer then return nil end
    local yLayer = xLayer[y] or xLayer[tostring(y)]
    if not yLayer then return nil end
    return yLayer[z] or yLayer[tostring(z)]
end

local function isPlaceable(block)
    if not block then return false end
    local name = block.material
    if not name or name == "" then return false end
    if name == "minecraft:air" or name == "air" then return false end
    return true
end

local function computeApproachLocal(localPos, side)
    side = side or "down"
    if side == "up" then
        return { x = localPos.x, y = localPos.y - 1, z = localPos.z }, side
    elseif side == "down" then
        return { x = localPos.x, y = localPos.y + 1, z = localPos.z }, side
    else
        return { x = localPos.x, y = localPos.y, z = localPos.z }, side
    end
end

local function computeLocalXZ(bounds, x, z, orientationKey)
    local orient = orientation.resolveOrientationKey(orientationKey)
    local relativeX = x - bounds.minX
    local relativeZ = z - bounds.minZ
    local localZ = - (relativeZ + 1)
    local localX
    if orient == "forward_right" then
        localX = relativeX + 1
    else
        localX = - (relativeX + 1)
    end
    return localX, localZ
end

local function normaliseBounds(info)
    if not info or not info.bounds then return nil, "missing_bounds" end
    local minB = info.bounds.min
    local maxB = info.bounds.max
    if not (minB and maxB) then return nil, "missing_bounds" end
    
    local function norm(t, k) return tonumber(t[k]) end
    
    return {
        minX = norm(minB, "x") or 0,
        minY = norm(minB, "y") or 0,
        minZ = norm(minB, "z") or 0,
        maxX = norm(maxB, "x") or 0,
        maxY = norm(maxB, "y") or 0,
        maxZ = norm(maxB, "z") or 0,
    }
end

local function buildOrder(schema, info, opts)
    local bounds, err = normaliseBounds(info)
    if not bounds then return nil, err or "missing_bounds" end
    
    opts = opts or {}
    local offsetLocal = opts.offsetLocal or { x = 0, y = 0, z = 0 }
    local offsetXLocal = offsetLocal.x or 0
    local offsetYLocal = offsetLocal.y or 0
    local offsetZLocal = offsetLocal.z or 0
    
    -- Default to forward_left if not specified
    local orientKey = opts.orientation or "forward_left"

    local order = {}
    for y = bounds.minY, bounds.maxY do
        for row = 0, bounds.maxZ - bounds.minZ do
            local z = bounds.minZ + row
            local forward = (row % 2) == 0
            local xStart = forward and bounds.minX or bounds.maxX
            local xEnd = forward and bounds.maxX or bounds.minX
            local step = forward and 1 or -1
            local x = xStart
            while true do
                local block = getBlock(schema, x, y, z)
                if isPlaceable(block) then
                    local baseX, baseZ = computeLocalXZ(bounds, x, z, orientKey)
                    local localPos = {
                        x = baseX + offsetXLocal,
                        y = y + offsetYLocal,
                        z = baseZ + offsetZLocal,
                    }
                    local meta = (block and type(block.meta) == "table") and block.meta or nil
                    local side = (meta and meta.side) or "down"
                    local approach, resolvedSide = computeApproachLocal(localPos, side)
                    order[#order + 1] = {
                        schemaPos = { x = x, y = y, z = z },
                        localPos = localPos,
                        approachLocal = approach,
                        block = block,
                        side = resolvedSide,
                    }
                end
                if x == xEnd then break end
                x = x + step
            end
        end
    end
    return order, bounds
end

local function INITIALIZE(ctx)
    logger.log(ctx, "info", "Initializing...")
    
    -- Startup Logic (Fuel & Chests)
    if not ctx.chests then
        ctx.chests = startup.runChestSetup(ctx)
    end
    
    if not startup.runFuelCheck(ctx, ctx.chests) then
        return "INITIALIZE"
    end
    
    if ctx.config.mode == "mine" then
        logger.log(ctx, "info", "Starting Branch Mine mode...")
        ctx.branchmine = {
            length = tonumber(ctx.config.length) or 60,
            branchInterval = tonumber(ctx.config.branchInterval) or 3,
            branchLength = tonumber(ctx.config.branchLength) or 16,
            torchInterval = tonumber(ctx.config.torchInterval) or 6,
            currentDist = 0,
            state = "SPINE",
            spineY = 0, -- Assuming we start at 0 relative to start
            chests = ctx.chests
        }
        ctx.nextState = "BRANCHMINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "tunnel" then
        logger.log(ctx, "info", "Generating tunnel strategy...")
        local length = tonumber(ctx.config.length) or 16
        local width = tonumber(ctx.config.width) or 1
        local height = tonumber(ctx.config.height) or 2
        local torchInterval = tonumber(ctx.config.torchInterval) or 6
        
        ctx.strategy = strategyTunnel.generate(length, width, height, torchInterval)
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Tunnel Plan: %d steps.", #ctx.strategy))
        ctx.nextState = "MINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "excavate" then
        logger.log(ctx, "info", "Generating excavation strategy...")
        local length = tonumber(ctx.config.length) or 8
        local width = tonumber(ctx.config.width) or 8
        local depth = tonumber(ctx.config.depth) or 3
        
        ctx.strategy = strategyExcavate.generate(length, width, depth)
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Excavation Plan: %d steps.", #ctx.strategy))
        ctx.nextState = "MINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "treefarm" then
        logger.log(ctx, "info", "Starting Tree Farm mode...")
        ctx.treefarm = {
            width = tonumber(ctx.config.width) or 9,
            height = tonumber(ctx.config.height) or 9,
            currentX = 0,
            currentZ = 0, -- Using Z for the second dimension to match Minecraft coordinates usually
            state = "SCAN",
            chests = ctx.chests
        }
        return "TREEFARM"
    end

    if ctx.config.mode == "potatofarm" then
        logger.log(ctx, "info", "Starting Potato Farm mode...")
        ctx.potatofarm = {
            width = tonumber(ctx.config.width) or 9,
            height = tonumber(ctx.config.height) or 9,
            currentX = 0,
            currentZ = 0,
            nextX = 0,
            nextZ = 0,
            state = "SCAN",
            chests = ctx.chests
        }
        return "POTATOFARM"
    end

    if ctx.config.mode == "farm" then
        logger.log(ctx, "info", "Generating farm strategy...")
        local farmType = ctx.config.farmType or "tree"
        local width = tonumber(ctx.config.width) or 9
        local length = tonumber(ctx.config.length) or 9
        
        local schema = strategyFarm.generate(farmType, width, length)
        
        local valid, err = validateSchema(schema)
        if not valid then
            ctx.lastError = "Generated schema invalid: " .. tostring(err)
            return "ERROR"
        end

        -- Preview
        ui.clear()
        ui.drawPreview(schema, 2, 2, 30, 15)
        term.setCursorPos(1, 18)
        print("Previewing " .. farmType .. " farm.")
        print("Press Enter to confirm, 'q' to quit.")
        local input = read()
        if input == "q" or input == "Q" then
            return "DONE"
        end
        
        -- Normalize schema for buildOrder
        -- We need to calculate bounds manually since we don't have parser info
        local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
        local minY, maxY = 0, 1 -- Assuming 2 layers for now
        
        for sx, row in pairs(schema) do
            local nx = tonumber(sx)
            if nx then
                if nx < minX then minX = nx end
                if nx > maxX then maxX = nx end
                for sy, col in pairs(row) do
                    for sz, block in pairs(col) do
                        local nz = tonumber(sz)
                        if nz then
                            if nz < minZ then minZ = nz end
                            if nz > maxZ then maxZ = nz end
                        end
                    end
                end
            end
        end
        
        ctx.schema = schema
        ctx.schemaInfo = {
            bounds = {
                min = { x = minX, y = minY, z = minZ },
                max = { x = maxX, y = maxY, z = maxZ }
            }
        }
        
        logger.log(ctx, "info", "Computing build strategy...")
        local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
        if not order then
            ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
            return "ERROR"
        end

        ctx.strategy = order
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Plan: %d steps.", #order))
        ctx.nextState = "BUILD"
        return "CHECK_REQUIREMENTS"
    end
    
    if not ctx.config.schemaPath then
        ctx.lastError = "No schema path provided"
        return "ERROR"
    end

    logger.log(ctx, "info", "Loading schema: " .. ctx.config.schemaPath)
    local ok, schemaOrErr, info = parser.parseFile(ctx, ctx.config.schemaPath, { formatHint = nil })
    if not ok then
        ctx.lastError = "Failed to parse schema: " .. tostring(schemaOrErr)
        return "ERROR"
    end

    ctx.schema = schemaOrErr
    ctx.schemaInfo = info

    local valid, err = validateSchema(ctx.schema)
    if not valid then
        ctx.lastError = "Loaded schema invalid: " .. tostring(err)
        return "ERROR"
    end

    logger.log(ctx, "info", "Computing build strategy...")
    local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
    if not order then
        ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
        return "ERROR"
    end

    ctx.strategy = order
    ctx.pointer = 1
    
    logger.log(ctx, "info", string.format("Plan: %d steps.", #order))

    -- Check for schema metadata to trigger next state
    if ctx.schemaInfo and ctx.schemaInfo.meta then
        local meta = ctx.schemaInfo.meta
        if meta.mode == "treefarm" then
            logger.log(ctx, "info", "Schema defines a Tree Farm. Will transition to TREEFARM after build.")
            ctx.onBuildComplete = "TREEFARM"
            
            -- Calculate dimensions from bounds
            local bounds = ctx.schemaInfo.bounds
            local width = (bounds.max.x - bounds.min.x) + 1
            local height = (bounds.max.z - bounds.min.z) + 1
            
            ctx.treefarm = {
                width = width,
                height = height,
                currentX = 0,
                currentZ = 0,
                state = "SCAN",
                chests = ctx.chests,
                useSchema = true -- Flag to tell TREEFARM to use schema locations
            }
        elseif meta.mode == "potatofarm" then
            logger.log(ctx, "info", "Schema defines a Potato Farm. Will transition to POTATOFARM after build.")
            ctx.onBuildComplete = "POTATOFARM"
            
            local bounds = ctx.schemaInfo.bounds
            local width = (bounds.max.x - bounds.min.x) + 1
            local height = (bounds.max.z - bounds.min.z) + 1
            
            ctx.potatofarm = {
                width = width,
                height = height,
                currentX = 0,
                currentZ = 0,
                nextX = 0,
                nextZ = 0,
                state = "SCAN",
                chests = ctx.chests,
                useSchema = true
            }
        end
    end

    ctx.nextState = "BUILD"
    return "CHECK_REQUIREMENTS"
end

return INITIALIZE
]=])

addEmbeddedFile("factory/state_check_requirements.lua", [=[---@diagnostic disable: undefined-global
--[[
State: CHECK_REQUIREMENTS
Verifies that the turtle has enough fuel and materials to complete the task.
Prompts the user if items are missing.
--]]

local inventory = require("lib_inventory")
local logger = require("lib_logger")
local fuel = require("lib_fuel")
local diagnostics = require("lib_diagnostics")
local movement = require("lib_movement")

local MATERIAL_ALIASES = {
    ["minecraft:potatoes"] = { "minecraft:potato" }, -- Blocks vs. item name
    ["minecraft:water_bucket"] = { "minecraft:water_bucket_bucket" }, -- Allow buckets to satisfy water needs
}

local function countWithAliases(invCounts, material)
    local total = invCounts[material] or 0
    local aliases = MATERIAL_ALIASES[material]
    if aliases then
        for _, alias in ipairs(aliases) do
            total = total + (invCounts[alias] or 0)
        end
    end
    return total
end

local function buildPullList(missing)
    local pull = {}
    for mat, count in pairs(missing) do
        local aliases = MATERIAL_ALIASES[mat]
        if aliases then
            for _, alias in ipairs(aliases) do
                pull[alias] = math.max(pull[alias] or 0, count)
            end
        else
            pull[mat] = count
        end
    end
    return pull
end

local function calculateRequirements(ctx, strategy)
    -- Potatofarm: assume soil is prepped at y=0; only require fuel and potatoes for replanting.
    if ctx.potatofarm then
        local width = tonumber(ctx.potatofarm.width) or tonumber(ctx.config.width) or 9
        local height = tonumber(ctx.potatofarm.height) or tonumber(ctx.config.height) or 9
        -- Rough fuel budget: sweep the inner grid twice plus margin.
        local inner = math.max(1, (width - 2)) * math.max(1, (height - 2))
        local fuelNeeded = math.ceil(inner * 2.0) + 100
        local potatoesNeeded = inner -- enough to replant every spot once
        return {
            fuel = fuelNeeded,
            materials = { ["minecraft:potato"] = potatoesNeeded }
        }
    end

    local reqs = {
        fuel = 0,
        materials = {}
    }

    -- Estimate fuel
    -- A simple heuristic: 1 fuel per step.
    if strategy then
        reqs.fuel = #strategy
    end
    
    -- Add a safety margin for fuel (e.g. 10% + 100)
    reqs.fuel = math.ceil(reqs.fuel * 1.1) + 100

    -- Calculate materials
    if ctx.config.mode == "mine" then
        -- Mining mode
        -- Check for torches if strategy has place_torch
        for _, step in ipairs(strategy) do
            if step.type == "place_torch" then
                reqs.materials["minecraft:torch"] = (reqs.materials["minecraft:torch"] or 0) + 1
            elseif step.type == "place_chest" then
                reqs.materials["minecraft:chest"] = (reqs.materials["minecraft:chest"] or 0) + 1
            end
        end
    else
        -- Build mode
        for _, step in ipairs(strategy) do
            if step.block and step.block.material then
                local mat = step.block.material
                reqs.materials[mat] = (reqs.materials[mat] or 0) + 1
            end
        end
    end

    return reqs
end

local function calculateBranchmineRequirements(ctx)
    local bm = ctx.branchmine or {}
    local length = tonumber(bm.length or ctx.config.length) or 60
    local branchInterval = tonumber(bm.branchInterval or ctx.config.branchInterval) or 3
    local branchLength = tonumber(bm.branchLength or ctx.config.branchLength) or 16
    local torchInterval = tonumber(bm.torchInterval or ctx.config.torchInterval) or 6

    branchInterval = math.max(branchInterval, 1)
    torchInterval = math.max(torchInterval, 1)
    branchLength = math.max(branchLength, 1)

    local branchPairs = math.floor(length / branchInterval)
    local branchTravel = branchPairs * (4 * branchLength + 4)
    local totalTravel = length + branchTravel

    local reqs = {
        fuel = math.ceil(totalTravel * 1.1) + 100,
        materials = {}
    }

    local torchItem = ctx.config.torchItem or "minecraft:torch"
    local torchCount = math.max(1, math.floor(length / torchInterval))
    reqs.materials[torchItem] = torchCount

    return reqs
end

local function CHECK_REQUIREMENTS(ctx)
    logger.log(ctx, "info", "Checking requirements...")

    local reqs
    if ctx.branchmine then
        reqs = calculateBranchmineRequirements(ctx)
    else
        if ctx.config.mode == "mine" then
            logger.log(ctx, "warn", "Branchmine context missing, re-initializing...")
            ctx.branchmine = {
                length = tonumber(ctx.config.length) or 60,
                branchInterval = tonumber(ctx.config.branchInterval) or 3,
                branchLength = tonumber(ctx.config.branchLength) or 16,
                torchInterval = tonumber(ctx.config.torchInterval) or 6,
                currentDist = 0,
                state = "SPINE",
                spineY = 0,
                chests = ctx.chests
            }
            ctx.nextState = "BRANCHMINE"
            reqs = calculateBranchmineRequirements(ctx)
        else
            local strategy, errMsg = diagnostics.requireStrategy(ctx)
            if not strategy then
                ctx.lastError = errMsg or "Strategy missing"
                return "ERROR"
            end
            reqs = calculateRequirements(ctx, strategy)
        end
    end
    -- Assume dirt is already placed in the world; do not require the turtle to carry dirt.
    if reqs and reqs.materials then
        reqs.materials["minecraft:dirt"] = nil
        -- Do not require water buckets for farm strategies; assume water is pre-placed in the world.
        reqs.materials["minecraft:water_bucket"] = nil
    end

    local invCounts = inventory.getCounts(ctx)
    local currentFuel = turtle.getFuelLevel()
    if currentFuel == "unlimited" then currentFuel = 999999 end
    if type(currentFuel) ~= "number" then currentFuel = 0 end

    local missing = {
        fuel = 0,
        materials = {}
    }
    local hasMissing = false

    -- Check fuel
    if currentFuel < reqs.fuel then
        -- Attempt to refuel from inventory or nearby sources
        print("Attempting to refuel to meet requirements...")
        logger.log(ctx, "info", "Attempting to refuel to meet requirements...")
        fuel.refuel(ctx, { target = reqs.fuel, excludeItems = { "minecraft:torch" } })
        
        currentFuel = turtle.getFuelLevel()
        if currentFuel == "unlimited" then currentFuel = 999999 end
        if type(currentFuel) ~= "number" then currentFuel = 0 end
    end

    if currentFuel < reqs.fuel then
        missing.fuel = reqs.fuel - currentFuel
        hasMissing = true
    end

    -- Check materials
    for mat, count in pairs(reqs.materials) do
        -- Assume water is pre-placed; treat requirement as satisfied.
        if mat == "minecraft:water_bucket" then
            invCounts[mat] = count
        end
        -- Assume dirt is already available in the world (don't require the turtle to carry it).
        if mat == "minecraft:dirt" then
            invCounts[mat] = count
        end

        local have = countWithAliases(invCounts, mat)
        
        -- Special handling for chests: allow any chest/barrel if "minecraft:chest" is requested
        if mat == "minecraft:chest" and have < count then
            local totalChests = 0
            for invMat, invCount in pairs(invCounts) do
                if invMat:find("chest") or invMat:find("barrel") or invMat:find("shulker") then
                    totalChests = totalChests + invCount
                end
            end
            if totalChests >= count then
                have = count -- Satisfied
            end
        end

        if have < count then
            missing.materials[mat] = count - have
            hasMissing = true
        end
    end

    if hasMissing then
        print("Checking nearby chests for missing items...")
        local pullList = buildPullList(missing.materials)
        if inventory.retrieveFromNearby(ctx, pullList) then
             -- Re-check inventory
             invCounts = inventory.getCounts(ctx)
             -- Re-apply assumptions (water/dirt) after re-check
             for mat, count in pairs(reqs.materials) do
                if mat == "minecraft:water_bucket" or mat == "minecraft:dirt" then
                    invCounts[mat] = count
                end
             end
             hasMissing = false
             missing.materials = {}
             for mat, count in pairs(reqs.materials) do
                local have = countWithAliases(invCounts, mat)
                if have < count then
                    missing.materials[mat] = count - have
                    hasMissing = true
                end
             end
        end
    end

    -- If we're still missing items, check whether nearby chests have enough
    -- even if we can't hold them all at once (e.g., lots of water buckets).
    local nearby = nil
    if hasMissing then
        nearby = inventory.checkNearby(ctx, buildPullList(missing.materials))
        for mat, deficit in pairs(missing.materials) do
            local total = countWithAliases(invCounts, mat)
            total = total + (nearby[mat] or 0)
            local aliases = MATERIAL_ALIASES[mat]
            if aliases then
                for _, alias in ipairs(aliases) do
                    total = total + (nearby[alias] or 0)
                end
            end

            -- If the material is dirt, assume it's available in-world and treat as satisfied.
            if mat == "minecraft:dirt" then
                total = reqs.materials[mat] or total
            end

            if total >= (reqs.materials[mat] or 0) then
                missing.materials[mat] = nil
            end
        end

        -- Recompute hasMissing after relaxing for nearby stock
        hasMissing = missing.fuel > 0
        for _ in pairs(missing.materials) do
            hasMissing = true
            break
        end
    end

    if not hasMissing then
        logger.log(ctx, "info", "All requirements met.")
        return ctx.nextState or "DONE"
    end

    -- Report missing
    print("\n=== MISSING REQUIREMENTS ===")
    if missing.fuel > 0 then
        print(string.format("- Fuel: %d (Have %d, Need %d)", missing.fuel, currentFuel, reqs.fuel))
    end
    for mat, count in pairs(missing.materials) do
        print(string.format("- %s: %d", mat, count))
    end

    -- Check nearby
    nearby = nearby or inventory.checkNearby(ctx, missing.materials)
    local foundNearby = false
    for mat, count in pairs(nearby) do
        if not foundNearby then
            print("\n=== FOUND IN NEARBY CHESTS ===")
            foundNearby = true
        end
        print(string.format("- %s: %d", mat, count))
    end

    print("\nPress Enter to re-check, or type 'q' then Enter to quit.")
    local input = read()
    if input == "q" or input == "Q" then
        return "DONE"
    end
    
    return "CHECK_REQUIREMENTS"
end

return CHECK_REQUIREMENTS
]=])

addEmbeddedFile("lib/lib_world.lua", [=[local world = {}

function world.getInspect(side)
    if side == "forward" then
        return turtle.inspect
    elseif side == "up" then
        return turtle.inspectUp
    elseif side == "down" then
        return turtle.inspectDown
    end
    return nil
end

local SIDE_ALIASES = {
    forward = "forward",
    front = "forward",
    down = "down",
    bottom = "down",
    up = "up",
    top = "up",
    left = "left",
    right = "right",
    back = "back",
    behind = "back",
}

function world.normaliseSide(side)
    if type(side) ~= "string" then
        return nil
    end
    return SIDE_ALIASES[string.lower(side)]
end

function world.toPeripheralSide(side)
    local normalised = world.normaliseSide(side) or side
    if normalised == "forward" then
        return "front"
    elseif normalised == "up" then
        return "top"
    elseif normalised == "down" then
        return "bottom"
    elseif normalised == "back" then
        return "back"
    elseif normalised == "left" then
        return "left"
    elseif normalised == "right" then
        return "right"
    end
    return normalised
end

function world.inspectSide(side)
    local normalised = world.normaliseSide(side)
    if normalised == "forward" then
        return turtle and turtle.inspect and turtle.inspect()
    elseif normalised == "up" then
        return turtle and turtle.inspectUp and turtle.inspectUp()
    elseif normalised == "down" then
        return turtle and turtle.inspectDown and turtle.inspectDown()
    end
    return false
end

function world.isContainer(detail)
    if type(detail) ~= "table" then
        return false
    end
    local name = string.lower(detail.name or "")
    if name:find("chest", 1, true) or name:find("barrel", 1, true) or name:find("drawer", 1, true) then
        return true
    end
    if type(detail.tags) == "table" then
        for tag in pairs(detail.tags) do
            local lowered = string.lower(tag)
            if lowered:find("inventory", 1, true) or lowered:find("chest", 1, true) or lowered:find("barrel", 1, true) then
                return true
            end
        end
    end
    return false
end

function world.normalizeSide(value)
    if type(value) ~= "string" then
        return nil
    end
    local lower = value:lower()
    if lower == "forward" or lower == "front" or lower == "fwd" then
        return "forward"
    end
    if lower == "up" or lower == "top" or lower == "above" then
        return "up"
    end
    if lower == "down" or lower == "bottom" or lower == "below" then
        return "down"
    end
    return nil
end

function world.resolveSide(ctx, opts)
    if type(opts) == "string" then
        local direct = world.normalizeSide(opts)
        return direct or "forward"
    end

    local candidate
    if type(opts) == "table" then
        candidate = opts.side or opts.direction or opts.facing or opts.containerSide or opts.defaultSide
        if not candidate and type(opts.location) == "string" then
            candidate = opts.location
        end
    end

    if not candidate and type(ctx) == "table" then
        local cfg = ctx.config
        if type(cfg) == "table" then
            candidate = cfg.inventorySide or cfg.materialSide or cfg.supplySide or cfg.defaultInventorySide
        end
        if not candidate and type(ctx.inventoryState) == "table" then
            candidate = ctx.inventoryState.defaultSide
        end
    end

    local normalised = world.normalizeSide(candidate)
    if normalised then
        return normalised
    end

    return "forward"
end

function world.isContainerBlock(name, tags)
    if type(name) ~= "string" then
        return false
    end
    local lower = name:lower()
    for _, keyword in ipairs(CONTAINER_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true
        end
    end
    return world.hasContainerTag(tags)
end

function world.inspectForwardForContainer()
    if not turtle or type(turtle.inspect) ~= "function" then
        return false
    end
    local ok, data = turtle.inspect()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectUpForContainer()
    if not turtle or type(turtle.inspectUp) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectUp()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectDownForContainer()
    if not turtle or type(turtle.inspectDown) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectDown()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.peripheralSideForDirection(side)
    if side == "forward" or side == "front" then
        return "front"
    end
    if side == "up" or side == "top" then
        return "top"
    end
    if side == "down" or side == "bottom" then
        return "bottom"
    end
    return side
end

function world.computePrimaryPushDirection(ctx, periphSide)
    if periphSide == "front" then
        local facing = movement.getFacing(ctx)
        if facing then
            return OPPOSITE_FACING[facing]
        end
    elseif periphSide == "top" then
        return "down"
    elseif periphSide == "bottom" then
        return "up"
    end
    return nil
end

function world.normaliseCoordinate(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    if number >= 0 then
        return math.floor(number + 0.5)
    end
    return math.ceil(number - 0.5)
end

function world.normalisePosition(pos)
    if type(pos) ~= "table" then
        return nil, "invalid_position"
    end
    local xRaw = pos.x
    if xRaw == nil then
        xRaw = pos[1]
    end
    local yRaw = pos.y
    if yRaw == nil then
        yRaw = pos[2]
    end
    local zRaw = pos.z
    if zRaw == nil then
        zRaw = pos[3]
    end
    local x = world.normaliseCoordinate(xRaw)
    local y = world.normaliseCoordinate(yRaw)
    local z = world.normaliseCoordinate(zRaw)
    if not x or not y or not z then
        return nil, "invalid_position"
    end
    return { x = x, y = y, z = z }
end

function world.normaliseFacing(facing)
    facing = type(facing) == "string" and facing:lower() or "north"
    if facing ~= "north" and facing ~= "east" and facing ~= "south" and facing ~= "west" then
        return "north"
    end
    return facing
end

function world.facingVectors(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return { forward = { x = 0, z = -1 }, right = { x = 1, z = 0 } }
    elseif facing == "east" then
        return { forward = { x = 1, z = 0 }, right = { x = 0, z = 1 } }
    elseif facing == "south" then
        return { forward = { x = 0, z = 1 }, right = { x = -1, z = 0 } }
    else -- west
        return { forward = { x = -1, z = 0 }, right = { x = 0, z = -1 } }
    end
end

function world.rotateLocalOffset(localOffset, facing)
    local vectors = world.facingVectors(facing)
    local dx = localOffset.x or 0
    local dz = localOffset.z or 0
    local right = vectors.right
    local forward = vectors.forward
    return {
        x = (right.x * dx) + (forward.x * dz),
        z = (right.z * dx) + (forward.z * dz),
    }
end

function world.localToWorld(localOffset, facing)
    facing = world.normaliseFacing(facing)
    local dx = localOffset and localOffset.x or 0
    local dz = localOffset and localOffset.z or 0
    local rotated = world.rotateLocalOffset({ x = dx, z = dz }, facing)
    return {
        x = rotated.x,
        y = localOffset and localOffset.y or 0,
        z = rotated.z,
    }
end

function world.localToWorldRelative(origin, localPos)
    local rotated = world.localToWorld(localPos, origin.facing)
    return {
        x = origin.x + rotated.x,
        y = origin.y + rotated.y,
        z = origin.z + rotated.z
    }
end

function world.copyPosition(pos)
    if type(pos) ~= "table" then
        return nil
    end
    return {
        x = pos.x or 0,
        y = pos.y or 0,
        z = pos.z or 0,
    }
end

function world.detectContainers(io)
    local found = {}
    local sides = { "forward", "down", "up" }
    local labels = {
        forward = "front",
        down = "below",
        up = "above",
    }
    for _, side in ipairs(sides) do
        local inspect
        if side == "forward" then
            inspect = turtle.inspect
        elseif side == "up" then
            inspect = turtle.inspectUp
        else
            inspect = turtle.inspectDown
        end
        if type(inspect) == "function" then
            local ok, detail = inspect()
            if ok then
                local name = type(detail.name) == "string" and detail.name or "unknown"
                found[#found + 1] = string.format(" %s: %s", labels[side] or side, name)
            end
        end
    end
    if io.print then
        if #found == 0 then
            io.print("Detected containers: <none>")
        else
            io.print("Detected containers:")
            for _, line in ipairs(found) do
                io.print(" -" .. line)
            end
        end
    end
end

return world
]=])

addEmbeddedFile("lib/lib_gps.lua", [=[--[[
GPS library for CC:Tweaked turtles.
Provides helpers for using the GPS API.
--]]

---@diagnostic disable: undefined-global

local gps_utils = {}

function gps_utils.detectFacingWithGps(logger)
    if not gps or type(gps.locate) ~= "function" then
        return nil, "gps_unavailable"
    end
    if not turtle or type(turtle.forward) ~= "function" or type(turtle.back) ~= "function" then
        return nil, "turtle_api_unavailable"
    end

    local function locate(timeout)
        local ok, x, y, z = pcall(gps.locate, timeout)
        if ok and x then
            return x, y, z
        end
        return nil, nil, nil
    end

    local x1, _, z1 = locate(0.5)
    if not x1 then
        x1, _, z1 = locate(1)
        if not x1 then
            return nil, "gps_initial_failed"
        end
    end

    if not turtle.forward() then
        return nil, "forward_blocked"
    end

    local x2, _, z2 = locate(0.5)
    if not x2 then
        x2, _, z2 = locate(1)
    end

    local returned = turtle.back()
    if not returned then
        local attempts = 0
        while attempts < 5 and not returned do
            returned = turtle.back()
            attempts = attempts + 1
            if not returned and sleep then
                sleep(0)
            end
        end
        if not returned then
            if logger then
                logger:warn("Facing detection failed to restore the turtle's start position; adjust the turtle manually and rerun.")
            end
            return nil, "return_failed"
        end
    end

    if not x2 then
        return nil, "gps_second_failed"
    end

    local dx = x2 - x1
    local dz = z2 - z1
    local threshold = 0.2

    if math.abs(dx) < threshold and math.abs(dz) < threshold then
        return nil, "gps_delta_small"
    end

    if math.abs(dx) >= math.abs(dz) then
        if dx > threshold then
            return "east"
        elseif dx < -threshold then
            return "west"
        end
    else
        if dz > threshold then
            return "south"
        elseif dz < -threshold then
            return "north"
        end
    end

    return nil, "gps_delta_small"
end

return gps_utils
]=])

addEmbeddedFile("lib/lib_orientation.lua", [=[--[[
Orientation library for CC:Tweaked turtles.
Provides helpers for facing, orientation, and coordinate transformations.
--]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local world = require("lib_world")
local gps_utils = require("lib_gps")

local orientation = {}

local START_ORIENTATIONS = {
    [1] = { label = "Forward + Left", key = "forward_left" },
    [2] = { label = "Forward + Right", key = "forward_right" },
}
local DEFAULT_ORIENTATION = 1

function orientation.resolveOrientationKey(raw)
    if type(raw) == "string" then
        local key = raw:lower()
        if key == "forward_left" or key == "forward-left" or key == "left" or key == "l" then
            return "forward_left"
        elseif key == "forward_right" or key == "forward-right" or key == "right" or key == "r" then
            return "forward_right"
        end
    elseif type(raw) == "number" and START_ORIENTATIONS[raw] then
        return START_ORIENTATIONS[raw].key
    end
    return START_ORIENTATIONS[DEFAULT_ORIENTATION].key
end

function orientation.orientationLabel(key)
    local resolved = orientation.resolveOrientationKey(key)
    for _, entry in pairs(START_ORIENTATIONS) do
        if entry.key == resolved then
            return entry.label
        end
    end
    return START_ORIENTATIONS[DEFAULT_ORIENTATION].label
end

function orientation.normaliseFacing(facing)
    return world.normaliseFacing(facing)
end

function orientation.facingVectors(facing)
    return world.facingVectors(facing)
end

function orientation.rotateLocalOffset(localOffset, facing)
    return world.rotateLocalOffset(localOffset, facing)
end

function orientation.localToWorld(localOffset, facing)
    return world.localToWorld(localOffset, facing)
end

function orientation.detectFacingWithGps(logger)
    return gps_utils.detectFacingWithGps(logger)
end

function orientation.turnLeftOf(facing)
    return movement.turnLeftOf(facing)
end

function orientation.turnRightOf(facing)
    return movement.turnRightOf(facing)
end

function orientation.turnBackOf(facing)
    return movement.turnBackOf(facing)
end

return orientation
]=])

-- END_EMBEDDED_FILES

local function log(msg)
  print("[install] " .. msg)
end

local function readAll(handle)
  local content = handle.readAll()
  handle.close()
  return content
end

local function fetch(url)
  if not http then
    return nil, "HTTP API is disabled"
  end

  local response, err = http.get(url)
  if not response then
    return nil, err or "unknown HTTP error"
  end

  return readAll(response)
end

local function decodeJson(payload)
  local ok, result = pcall(textutils.unserializeJSON, payload)
  if not ok then
    return nil, "Invalid JSON: " .. tostring(result)
  end
  return result
end

local function promptConfirm()
  term.write("This will ERASE everything except the ROM. Continue? (y/N) ")
  local reply = string.lower(read() or "")
  return reply == "y" or reply == "yes"
end

local function sanitizeManifest(manifest)
  if type(manifest) ~= "table" then
    return nil, "Manifest is not a table"
  end
  if type(manifest.files) ~= "table" or #manifest.files == 0 then
    return nil, "Manifest contains no files"
  end
  return manifest
end

local function loadManifest(url)
  if not url then
    return nil, "No manifest URL provided"
  end

  log("Fetching manifest from " .. url)
  local body, err = fetch(url)
  if not body then
    return nil, err
  end

  local manifest, decodeErr = decodeJson(body)
  if not manifest then
    return nil, decodeErr
  end

  local valid, reason = sanitizeManifest(manifest)
  if not valid then
    return nil, reason
  end

  return manifest
end

local function downloadFiles(manifest)
  local bundle = {
    name = manifest.name or "Workstation",
    version = manifest.version or "unknown",
    files = {},
  }

  for _, file in ipairs(manifest.files) do
    if not file.path then
      return nil, "File entry missing 'path'"
    end

    if file.content then
      table.insert(bundle.files, { path = file.path, content = file.content })
    elseif file.url then
      log("Downloading " .. file.path)
      local data, err = fetch(file.url)
      if not data then
        return nil, err or ("Failed to download " .. file.url)
      end
      table.insert(bundle.files, { path = file.path, content = data })
    else
      return nil, "File entry for " .. file.path .. " needs 'url' or 'content'"
    end
  end

  return bundle
end

local function formatDisk()
  log("Formatting computer...")
  for _, entry in ipairs(fs.list("/")) do
    if entry ~= "rom" then
      fs.delete(entry)
    end
  end
end

local function writeFile(path, content)
  local dir = fs.getDir(path)
  if dir ~= "" then
    fs.makeDir(dir)
  end

  local handle = fs.open(path, "wb") or fs.open(path, "w")
  if not handle then
    error("Unable to write to " .. path)
  end

  handle.write(content)
  handle.close()
end

local function installImage(image)
  log("Installing " .. (image.name or "Workstation") .. " (" .. (image.version or "unknown") .. ")")
  for _, file in ipairs(image.files) do
    writeFile(file.path, file.content or "")
  end
end

local function summarizeInstall(image)
  local files = image.files or {}
  print("")
  print("Install summary:")
  print(string.format(" - Name: %s", image.name or "Workstation"))
  print(string.format(" - Version: %s", image.version or "unknown"))
  print(string.format(" - Files installed: %d", #files))
  for _, file in ipairs(files) do
    if file.path then
      print("   * " .. file.path)
    end
  end
end

local function main()
  local manifestUrl = tArgs[1] or DEFAULT_MANIFEST_URL

  if manifestUrl == "embedded" then
    log("Using embedded Workstation image only.")
  elseif not http then
    log("HTTP is disabled; falling back to embedded image.")
    manifestUrl = "embedded"
  end

  local image
  if manifestUrl ~= "embedded" then
    local manifest, err = loadManifest(manifestUrl)
    if not manifest then
      log("Manifest error: " .. err)
      log("Falling back to embedded image.")
    else
      local bundle, downloadErr = downloadFiles(manifest)
      if not bundle then
        log("Download error: " .. downloadErr)
        log("Falling back to embedded image.")
      else
        image = bundle
      end
    end
  end

  if not image then
    image = EMBEDDED_IMAGE
  end

  if not promptConfirm() then
    log("Installation cancelled.")
    return
  end

  -- Ensure we have data before wiping the disk.
  formatDisk()
  installImage(image)
  -- Persist the installed manifest/image so users can verify what was applied.
  pcall(function()
    if type(textutils) == "table" and textutils.serializeJSON then
      writeFile("/arcadesys_installed_manifest.json", textutils.serializeJSON(image))
    else
      writeFile("/arcadesys_installed_manifest.json", "{ \"name\": \"" .. tostring(image.name) .. "\", \"version\": \"" .. tostring(image.version) .. "\" }")
    end
  end)
  log("Installation complete.")
  summarizeInstall(image)
  print("")
  term.write("Press Enter to reboot (or type 'cancel' to stay): ")
  local resp = string.lower(read() or "")
  if resp == "cancel" or resp == "c" or resp == "no" then
    log("Reboot skipped by user.")
    return
  end
  log("Rebooting...")
  sleep(1)
  os.reboot()
end

main()
