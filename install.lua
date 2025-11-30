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
  "https://raw.githubusercontent.com/example/workstation/main/manifest.json"

-- Minimal offline image that keeps the computer usable even if remote
-- downloads fail.
local EMBEDDED_IMAGE = {
  name = "Workstation",
  version = "embedded",
  files = {
    {
      path = "startup.lua",
      content = [[
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
]],
    },
    {
      path = "home.lua",
      content = [[
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
]],
    },
  },
}

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
  log("Installation complete. Rebooting...")
  sleep(1)
  os.reboot()
end

main()
