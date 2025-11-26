
-- Test script for arcadesys_installer.lua
-- Run with standard Lua (lua5.1+)

local mock_fs = {}
local written_files = {}

-- Mock fs API
fs = {
    combine = function(base, part)
        return base .. "/" .. part
    end,
    getDir = function(path)
        return path:match("(.*)/.*") or ""
    end,
    exists = function(path)
        return mock_fs[path] ~= nil
    end,
    makeDir = function(path)
        mock_fs[path] = "directory"
    end,
    delete = function(path)
        mock_fs[path] = nil
        -- Also delete children in mock (simple prefix match)
        for k, v in pairs(mock_fs) do
            if k:sub(1, #path + 1) == path .. "/" then
                mock_fs[k] = nil
            end
        end
    end,
    open = function(path, mode)
        if mode == "w" then
            return {
                write = function(content)
                    written_files[path] = (written_files[path] or "") .. content
                    mock_fs[path] = "file"
                end,
                close = function() end
            }
        end
        return nil
    end
}

-- Mock shell API (used in some bundled scripts, but maybe not at top level of installer?)
-- The installer calls shell.run at the end of one of the bundled files, but that's inside the string content.
-- However, the installer itself might use shell?
-- Looking at the code: `local BASE_DIR = fs.getDir(shell and shell.getRunningProgram and ...)`
-- So we should mock shell.
shell = {
    getRunningProgram = function() return "installer.lua" end,
    run = function() end
}

-- Mock print and printError
function print(...) end
function printError(...) end

-- Load and run the installer
local installer_path = "arcadesys_installer.lua"
local chunk, err = loadfile(installer_path)

if not chunk then
    io.stderr:write("Failed to load installer: " .. err .. "\n")
    os.exit(1)
end

-- Run the installer
local status, err = pcall(chunk)
if not status then
    io.stderr:write("Installer crashed: " .. err .. "\n")
    os.exit(1)
end

-- Assertions
local function assert_file_exists(path)
    if not written_files[path] then
        io.stderr:write("FAIL: File not found in installer: " .. path .. "\n")
        os.exit(1)
    end
end

local function assert_file_contains(path, search_string)
    assert_file_exists(path)
    if not written_files[path]:find(search_string, 1, true) then
        io.stderr:write("FAIL: File " .. path .. " does not contain expected string.\n")
        io.stderr:write("Expected: " .. search_string:sub(1, 50) .. "...\n")
        os.exit(1)
    end
end

print("Verifying build artifacts...")

-- Check for critical files
assert_file_exists("factory/state_treefarm.lua")
assert_file_exists("startup.lua")
assert_file_exists("lib/lib_fuel.lua")

-- Check for the specific fix in state_treefarm.lua
-- The fix was: if type(needed) ~= "number" then needed = 1000 end
local fix_string = 'if type(needed) ~= "number" then needed = 1000 end'
assert_file_contains("factory/state_treefarm.lua", fix_string)

print("SUCCESS: Build verification passed.")
print(" - Installer runs successfully")
print(" - Files are unpacked correctly")
print(" - Critical fixes are present")
