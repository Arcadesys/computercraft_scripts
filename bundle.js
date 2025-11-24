const fs = require('fs');
const path = require('path');

// Configuration
const OUTPUT_FILENAME = 'arcadeos.lua';
// Files to exclude from the bundle to prevent recursion or clutter
const IGNORE_FILES = ['bundle.js', 'package.json', 'package-lock.json', OUTPUT_FILENAME];
const SOURCE_DIR = __dirname;

/**
 * Helper: Escapes a string for use in Lua using long brackets.
 * It dynamically adds equals signs (e.g., [=[ ... ]=]) to ensure the delimiter
 * doesn't appear inside the content itself, preventing syntax errors.
 */
function toLuaString(str) {
    let equals = '';
    // Keep adding '=' until the delimiter [=*[ is unique and doesn't exist in the string
    while (str.includes(`[${equals}[`) || str.includes(`]${equals}]`)) {
        equals += '=';
    }
    return `[${equals}[${str}]${equals}]`;
}

function createInstaller() {
    console.log('📦 Packaging ArcadeOS...');

    // 1. Find all files in the current directory
    const allFiles = fs.readdirSync(SOURCE_DIR);
    
    // 2. Filter for Lua files and exclude ignored ones
    const filesToBundle = allFiles.filter(file => {
        return file.endsWith('.lua') && !IGNORE_FILES.includes(file);
    });

    if (filesToBundle.length === 0) {
        console.log('❌ No Lua files found to bundle.');
        return;
    }

    // 3. Start building the Lua installer script
    // This string will become the content of arcadeos.lua
    let luaScript = `-- ArcadeOS Installer
-- Auto-generated installer script
-- Run this file on a ComputerCraft computer to install the OS.

print("Initializing ArcadeOS Installer...")
local files = {}

`;

    // 4. Append each file's content to the Lua table
    filesToBundle.forEach(fileName => {
        const filePath = path.join(SOURCE_DIR, fileName);
        const content = fs.readFileSync(filePath, 'utf8');
        
        console.log(`   - Adding ${fileName}`);
        
        // We use the filename as the key and the content as the value
        luaScript += `files["${fileName}"] = ${toLuaString(content)}\n`;
    });

    // 5. Add the installation logic (Lua code)
    // This Lua code iterates over the 'files' table and writes them to disk
    luaScript += `
print("Unpacking ${filesToBundle.length} files...")

for path, content in pairs(files) do
    print("  Installing: " .. path)
    local file = fs.open(path, "w")
    if file then
        file.write(content)
        file.close()
    else
        printError("  Failed to write: " .. path)
    end
end

print("Installation Complete!")
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
`;

    // 6. Write the final installer file
    fs.writeFileSync(path.join(SOURCE_DIR, OUTPUT_FILENAME), luaScript);
    console.log(`✅ Successfully created installer// filepath: c:\Users\auste\OneDrive\Documents\computercraft\bundle.js
const fs = require('fs');
const path = require('path');

// Configuration
const OUTPUT_FILENAME = 'arcadeos.lua';
// Files to exclude from the bundle to prevent recursion or clutter
const IGNORE_FILES = ['bundle.js', 'package.json', 'package-lock.json', OUTPUT_FILENAME];
const SOURCE_DIR = __dirname;

/**
 * Helper: Escapes a string for use in Lua using long brackets.
 * It dynamically adds equals signs (e.g., [=[ ... ]=]) to ensure the delimiter
 * doesn't appear inside the content itself, preventing syntax errors.
 */
function toLuaString(str) {
    let equals = '';
    // Keep adding '=' until the delimiter [=*[ is unique and doesn't exist in the string
    while (str.includes(`[${equals}[`) || str.includes(`]${equals}]`)) {
        equals += '=';
    }
    return `[${equals}[${str}]${equals}]`;
}

function createInstaller() {
    console.log('📦 Packaging ArcadeOS...');

    // 1. Find all files in the current directory
    const allFiles = fs.readdirSync(SOURCE_DIR);
    
    // 2. Filter for Lua files and exclude ignored ones
    const filesToBundle = allFiles.filter(file => {
        return file.endsWith('.lua') && !IGNORE_FILES.includes(file);
    });

    if (filesToBundle.length === 0) {
        console.log('❌ No Lua files found to bundle.');
        return;
    }

    // 3. Start building the Lua installer script
    // This string will become the content of arcadeos.lua
    let luaScript = `-- ArcadeOS Installer
-- Auto-generated installer script
-- Run this file on a ComputerCraft computer to install the OS.

print("Initializing ArcadeOS Installer...")
local files = {}

`;

    // 4. Append each file's content to the Lua table
    filesToBundle.forEach(fileName => {
        const filePath = path.join(SOURCE_DIR, fileName);
        const content = fs.readFileSync(filePath, 'utf8');
        
        console.log(`   - Adding ${fileName}`);
        
        // We use the filename as the key and the content as the value
        luaScript += `files["${fileName}"] = ${toLuaString(content)}\n`;
    });

    // 5. Add the installation logic (Lua code)
    // This Lua code iterates over the 'files' table and writes them to disk
    luaScript += `
print("Unpacking ${filesToBundle.length} files...")

for path, content in pairs(files) do
    print("  Installing: " .. path)
    local file = fs.open(path, "w")
    if file then
        file.write(content)
        file.close()
    else
        printError("  Failed to write: " .. path)
    end
end

print("Installation Complete!")
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
`;

    // 6. Write the final installer file
    fs.writeFileSync(path.join(SOURCE_DIR, OUTPUT_FILENAME), luaScript);
    console.log(`✅ Successfully created installer: ${OUTPUT_FILENAME}`);
}

// Run the builder
createInstaller();