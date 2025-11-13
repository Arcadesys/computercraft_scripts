--[[
  Factory Refactor - Automated Structure Builder
  
  This script consumes manifest files that define 3D structures and builds them
  using a turtle. Manifests define layers, blocks, and metadata like doors and buses.
  
  Usage:
    factoryrefactor <manifest_path> [options]
    
  Options:
    --dry-run: Preview build without placing blocks
    --start-layer: Begin building from specific layer (default: 1)
    --end-layer: Stop building at specific layer (default: all)
    
  Manifest Structure:
    - meta: Contains size, doors, buses, and other metadata
    - layers: Table indexed by Y level, each containing rows of block codes
    - legend: Maps single-character codes to full block IDs
    
  Example:
    factoryrefactor manifest/testmanifest.lua
]]--

-- Import the turtle library
local TurtleLib = require("turtle.turtle")

-- ====================
-- CONFIGURATION
-- ====================

local Config = {
    -- Minimum fuel level before triggering refuel
    minFuelLevel = 500,
    
    -- Safety margin for fuel calculations
    fuelSafetyMargin = 100,
    
    -- Chest location for getting materials (relative to start)
    materialChestPos = {x = -1, y = 0, z = 0},
    
    -- Chest location for depositing excess items
    depositChestPos = {x = -2, y = 0, z = 0},
    
    -- How many of each material to request per trip
    materialsPerBatch = 64,
    
    -- Whether to print verbose debug output
    verboseOutput = true,
}

-- ====================
-- MANIFEST HANDLING
-- ====================

--- Load a manifest file
-- @param manifestPath Path to the manifest file
-- @return table Manifest data, or nil on error
local function loadManifest(manifestPath)
    if not fs.exists(manifestPath) then
        print("Error: Manifest file not found: " .. manifestPath)
        return nil
    end
    
    -- Load the manifest file
    -- In Lua, dofile executes a file and returns its value
    local success, manifest = pcall(dofile, manifestPath)
    
    if not success then
        print("Error loading manifest: " .. tostring(manifest))
        return nil
    end
    
    -- Validate manifest structure
    if not manifest.meta then
        print("Error: Manifest missing 'meta' section")
        return nil
    end
    
    if not manifest.layers then
        print("Error: Manifest missing 'layers' section")
        return nil
    end
    
    if not manifest.legend then
        print("Error: Manifest missing 'legend' section")
        return nil
    end
    
    return manifest
end

--- Validate manifest has required fields
-- @param manifest The manifest table
-- @return boolean True if valid
local function validateManifest(manifest)
    if not manifest.meta.size then
        print("Error: Manifest missing size definition")
        return false
    end
    
    if not manifest.meta.size.x or not manifest.meta.size.y or not manifest.meta.size.z then
        print("Error: Manifest size must have x, y, z components")
        return false
    end
    
    return true
end

--- Print manifest summary
-- @param manifest The manifest table
local function printManifestSummary(manifest)
    print("\n=== Manifest Summary ===")
    print("Name: " .. (manifest.meta.name or "Unnamed"))
    print(string.format("Size: %dx%dx%d (X x Y x Z)", 
        manifest.meta.size.x, 
        manifest.meta.size.y, 
        manifest.meta.size.z))
    
    -- Count unique block types
    local blockTypes = {}
    for code, blockId in pairs(manifest.legend) do
        if blockId ~= "minecraft:air" then
            blockTypes[blockId] = true
        end
    end
    
    local typeCount = 0
    print("\nRequired blocks:")
    for blockId, _ in pairs(blockTypes) do
        print("  - " .. blockId)
        typeCount = typeCount + 1
    end
    
    print(string.format("\nTotal block types: %d", typeCount))
    print("Total layers: " .. manifest.meta.size.y)
    print("========================\n")
end

-- ====================
-- MATERIAL MANAGEMENT
-- ====================

--- Analyze manifest to determine required materials
-- @param manifest The manifest table
-- @return table Map of block IDs to required quantities
local function calculateMaterials(manifest)
    local materials = {}
    
    -- Iterate through all layers
    for y = 1, manifest.meta.size.y do
        local layer = manifest.layers[y]
        
        if layer then
            -- Each layer is a table of strings representing rows
            for z = 1, #layer do
                local row = layer[z]
                
                -- Each character in the row represents a block
                for x = 1, #row do
                    local code = row:sub(x, x)
                    local blockId = manifest.legend[code]
                    
                    if blockId and blockId ~= "minecraft:air" then
                        materials[blockId] = (materials[blockId] or 0) + 1
                    end
                end
            end
        end
    end
    
    return materials
end

--- Print material requirements
-- @param materials Map of block IDs to quantities
local function printMaterials(materials)
    print("\n=== Material Requirements ===")
    
    local sortedMaterials = {}
    for blockId, count in pairs(materials) do
        table.insert(sortedMaterials, {id = blockId, count = count})
    end
    
    -- Sort by count (descending)
    table.sort(sortedMaterials, function(a, b) return a.count > b.count end)
    
    for _, material in ipairs(sortedMaterials) do
        print(string.format("  %3dx %s", material.count, material.id))
    end
    
    print("=============================\n")
end

--- Check if turtle has required materials in inventory
-- @param blockId The block ID to check for
-- @param quantity How many blocks needed
-- @return boolean True if turtle has enough
local function hasEnoughMaterial(blockId, quantity)
    local count = TurtleLib.countItem(blockId)
    return count >= quantity
end

--- Get materials from supply chest
-- @param blockId The block ID to retrieve
-- @param quantity How many to get
-- @return boolean Success status
local function getMaterialsFromChest(blockId, quantity)
    local currentPos = TurtleLib.getPosition()
    
    -- Navigate to material chest
    if not TurtleLib.goTo(
        Config.materialChestPos.x,
        Config.materialChestPos.y,
        Config.materialChestPos.z,
        false
    ) then
        print("Error: Could not reach material chest")
        return false
    end
    
    -- Face the chest (adjust based on your setup)
    TurtleLib.turnToFace(1)  -- Face East
    
    -- Try to get materials
    local success, amount = TurtleLib.findItemInChest(blockId, quantity, "front")
    
    if success then
        if Config.verboseOutput then
            print(string.format("Retrieved %d x %s", amount, blockId))
        end
    else
        print(string.format("Warning: Could not find %s in chest", blockId))
    end
    
    -- Return to previous position
    TurtleLib.goTo(currentPos.x, currentPos.y, currentPos.z, false)
    TurtleLib.turnToFace(currentPos.facing)
    
    return success
end

--- Ensure turtle has a specific material before placing
-- @param blockId The block ID needed
-- @param quantity How many needed (default: 1)
-- @return boolean True if material is available
local function ensureMaterial(blockId, quantity)
    quantity = quantity or 1
    
    if hasEnoughMaterial(blockId, quantity) then
        return true
    end
    
    -- Need to get materials from chest
    return getMaterialsFromChest(blockId, Config.materialsPerBatch)
end

--- Select a slot containing the specified block
-- @param blockId The block ID to select
-- @return number Slot number, or nil if not found
local function selectBlockSlot(blockId)
    local slot = TurtleLib.findItem(blockId)
    if slot then
        turtle.select(slot)
    end
    return slot
end

-- ====================
-- BUILDING LOGIC
-- ====================

--- Calculate the absolute position for a block in the structure
-- @param x X coordinate in structure (1-indexed)
-- @param y Y coordinate in structure (1-indexed)
-- @param z Z coordinate in structure (1-indexed)
-- @param startPos Starting position of build
-- @return table Position with x, y, z coordinates
local function calculateBlockPosition(x, y, z, startPos)
    -- Convert from 1-indexed structure coords to 0-indexed offsets
    -- Then add to start position
    return {
        x = startPos.x + (x - 1),
        y = startPos.y + (y - 1),
        z = startPos.z + (z - 1)
    }
end

--- Place a single block at the current position
-- @param blockId The block ID to place
-- @param direction Direction to place: "front", "up", or "down"
-- @return boolean Success status
local function placeBlock(blockId, direction)
    -- Select the correct slot
    if not selectBlockSlot(blockId) then
        print(string.format("Error: No %s in inventory", blockId))
        return false
    end
    
    -- Place based on direction
    local success, error
    
    if direction == "down" then
        success, error = TurtleLib.safePlaceDown()
    elseif direction == "up" then
        success, error = TurtleLib.safePlaceUp()
    else
        success, error = TurtleLib.safePlace()
    end
    
    if not success and Config.verboseOutput then
        print("Warning: " .. (error or "Could not place block"))
    end
    
    return success
end

--- Build a single layer of the structure
-- @param manifest The manifest table
-- @param layerNum Layer number (Y level)
-- @param startPos Starting position of build
-- @param dryRun If true, don't actually place blocks
-- @return boolean Success status
local function buildLayer(manifest, layerNum, startPos, dryRun)
    local layer = manifest.layers[layerNum]
    
    if not layer then
        print(string.format("Warning: Layer %d not defined in manifest", layerNum))
        return false
    end
    
    print(string.format("Building layer %d...", layerNum))
    
    local layerY = startPos.y + (layerNum - 1)
    local blocksPlaced = 0
    local blocksSkipped = 0
    
    -- Move to layer height
    if not TurtleLib.goTo(startPos.x, layerY, startPos.z, false) then
        print("Error: Could not reach layer height")
        return false
    end
    
    -- Iterate through each position in the layer
    -- Z represents rows (north-south), X represents columns (west-east)
    for z = 1, #layer do
        local row = layer[z]
        
        for x = 1, #row do
            local code = row:sub(x, x)
            local blockId = manifest.legend[code]
            
            -- Skip air blocks
            if blockId and blockId ~= "minecraft:air" then
                -- Calculate position for this block
                local blockPos = calculateBlockPosition(x, layerNum, z, startPos)
                
                -- Navigate to position
                if not TurtleLib.goTo(blockPos.x, blockPos.y, blockPos.z, false) then
                    print(string.format("Error: Could not reach position (%d, %d, %d)", 
                        blockPos.x, blockPos.y, blockPos.z))
                    return false
                end
                
                -- Check fuel level before continuing
                if not TurtleLib.canReturnHome(Config.fuelSafetyMargin) then
                    print("Warning: Low fuel level, returning home")
                    TurtleLib.goHome(false)
                    TurtleLib.refuelFromInventory(Config.minFuelLevel)
                    
                    -- Return to current position
                    TurtleLib.goTo(blockPos.x, blockPos.y, blockPos.z, false)
                end
                
                -- Ensure we have the material
                if not dryRun then
                    if not ensureMaterial(blockId, 1) then
                        print(string.format("Error: Cannot obtain %s", blockId))
                        return false
                    end
                    
                    -- Place the block below turtle
                    if placeBlock(blockId, "down") then
                        blocksPlaced = blocksPlaced + 1
                    else
                        blocksSkipped = blocksSkipped + 1
                    end
                else
                    -- Dry run - just count
                    blocksPlaced = blocksPlaced + 1
                end
                
                if Config.verboseOutput and blocksPlaced % 10 == 0 then
                    print(string.format("  Progress: %d blocks placed", blocksPlaced))
                end
            end
        end
    end
    
    print(string.format("Layer %d complete: %d placed, %d skipped", 
        layerNum, blocksPlaced, blocksSkipped))
    
    return true
end

--- Build the entire structure from manifest
-- @param manifest The manifest table
-- @param startPos Starting position for build
-- @param options Build options (dry_run, start_layer, end_layer)
-- @return boolean Success status
local function buildStructure(manifest, startPos, options)
    options = options or {}
    
    local startLayer = options.start_layer or 1
    local endLayer = options.end_layer or manifest.meta.size.y
    local dryRun = options.dry_run or false
    
    if dryRun then
        print("\n=== DRY RUN MODE - No blocks will be placed ===\n")
    end
    
    print(string.format("Building layers %d to %d...\n", startLayer, endLayer))
    
    -- Build each layer
    for y = startLayer, endLayer do
        if not buildLayer(manifest, y, startPos, dryRun) then
            print(string.format("Error: Failed to build layer %d", y))
            return false
        end
        
        -- Small delay between layers
        sleep(0.5)
    end
    
    print("\n=== Build Complete ===")
    
    -- Return home
    print("Returning to start position...")
    TurtleLib.goHome(false)
    
    return true
end

-- ====================
-- COMMAND LINE INTERFACE
-- ====================

--- Parse command line arguments
-- @param args Array of command line arguments
-- @return table Parsed options
local function parseArguments(args)
    local options = {
        manifest_path = nil,
        dry_run = false,
        start_layer = nil,
        end_layer = nil,
    }
    
    local i = 1
    while i <= #args do
        local arg = args[i]
        
        if arg == "--dry-run" then
            options.dry_run = true
        elseif arg == "--start-layer" then
            i = i + 1
            options.start_layer = tonumber(args[i])
        elseif arg == "--end-layer" then
            i = i + 1
            options.end_layer = tonumber(args[i])
        elseif arg == "--verbose" then
            Config.verboseOutput = true
        elseif arg == "--quiet" then
            Config.verboseOutput = false
        else
            -- Assume it's the manifest path
            options.manifest_path = arg
        end
        
        i = i + 1
    end
    
    return options
end

--- Print usage information
local function printUsage()
    print([[
Usage: factoryrefactor <manifest_path> [options]

Options:
  --dry-run          Preview build without placing blocks
  --start-layer <n>  Begin building from layer n (default: 1)
  --end-layer <n>    Stop building at layer n (default: last)
  --verbose          Print detailed progress (default)
  --quiet            Minimal output
  
Example:
  factoryrefactor manifest/testmanifest.lua
  factoryrefactor manifest/testmanifest.lua --dry-run
  factoryrefactor manifest/testmanifest.lua --start-layer 2 --end-layer 4
]])
end

-- ====================
-- MAIN PROGRAM
-- ====================

--- Main entry point
local function main(args)
    print("=== Factory Refactor - Structure Builder ===\n")
    
    -- Parse arguments
    local options = parseArguments(args)
    
    if not options.manifest_path then
        print("Error: No manifest file specified\n")
        printUsage()
        return false
    end
    
    -- Load manifest
    print("Loading manifest: " .. options.manifest_path)
    local manifest = loadManifest(options.manifest_path)
    
    if not manifest then
        return false
    end
    
    -- Validate manifest
    if not validateManifest(manifest) then
        return false
    end
    
    -- Print summary
    printManifestSummary(manifest)
    
    -- Calculate materials
    local materials = calculateMaterials(manifest)
    printMaterials(materials)
    
    -- Initialize turtle position tracking
    TurtleLib.initPosition(0, 0, 0, 0)
    
    -- Check if we should proceed
    if not options.dry_run then
        print("Ready to build. Press any key to continue, or Ctrl+T to cancel...")
        os.pullEvent("key")
    end
    
    -- Build the structure
    local startPos = {x = 0, y = 1, z = 0}  -- Start one block up
    local success = buildStructure(manifest, startPos, options)
    
    if success then
        print("\n✓ Build completed successfully!")
        return true
    else
        print("\n✗ Build failed")
        return false
    end
end

-- ====================
-- LUA TIPS FOR THIS SCRIPT
-- ====================

--[[
LUA TIPS:

1. Tables are the main data structure in Lua
   - Used as arrays, dictionaries, objects, etc.
   - Arrays are 1-indexed (first element is at [1], not [0])
   - Example: local myTable = {key = "value", 1, 2, 3}

2. String operations
   - Concatenation uses .. operator: "hello" .. "world"
   - string.sub(str, start, end) extracts substring
   - string.format() works like printf in C

3. Functions are first-class values
   - Can be stored in variables: local myFunc = function() end
   - Can be returned from functions
   - Can be passed as arguments

4. Pairs vs ipairs for iteration
   - pairs() iterates over all table entries (unordered)
   - ipairs() iterates over array portion in order (1, 2, 3...)

5. Nil is a special value
   - Missing table entries return nil
   - nil is falsy (along with false)
   - All other values are truthy (including 0 and "")

6. require() loads modules
   - Returns whatever the module file returns
   - Modules are cached (only loaded once)
   - Use relative paths: require("lib.turtle")

7. pcall() for error handling
   - pcall(func, args...) catches errors
   - Returns (true, result) or (false, error)
   - Use for risky operations like loading files

8. Variable scope
   - Always use 'local' for local variables
   - Without 'local', variables are global
   - Global variables persist between script runs in CC

9. Boolean operators
   - 'and' and 'or' are short-circuit operators
   - 'not' for negation
   - ~= means "not equal to" (not !=)

10. Comments
    - Single line: -- comment
    - Multi-line: --[[ comment ]]
]]

-- Run the main function with command line arguments
local args = {...}
main(args)
