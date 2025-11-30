-- ComputerCraft installer for Arcadesys/computercraft_scripts
-- Usage: install [owner] [repo] [branch] [subdirectory]
-- Defaults install directly from the Arcadesys/computercraft_scripts main branch.

local DEFAULT_OWNER = "Arcadesys"
local DEFAULT_REPO = "computercraft_scripts"
local DEFAULT_BRANCH = "main"
local DEFAULT_SUBDIR = ""
local MANIFEST_PATH = "manifest.json"

local args = {...}
local owner = args[1] or DEFAULT_OWNER
local repo = args[2] or DEFAULT_REPO
local branch = args[3] or DEFAULT_BRANCH
local subdir = args[4] or DEFAULT_SUBDIR

local USER_AGENT = { ["User-Agent"] = "computercraft-installer" }

local function buildRawUrl(path)
  return string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/%s",
    owner,
    repo,
    branch,
    path
  )
end

local function buildContentsUrl(path)
  local base = string.format("https://api.github.com/repos/%s/%s/contents", owner, repo)
  if path and path ~= "" then
    base = base .. "/" .. path
  end
  return base .. "?ref=" .. branch
end

local function fetch(url)
  local response = http.get(url, USER_AGENT)
  if not response then
    error(string.format("Failed to fetch %s. Is HTTP enabled?", url))
  end
  local body = response.readAll()
  response.close()
  return body
end

local function fetchJson(url)
  local raw = fetch(url)
  local ok, data = pcall(textutils.unserializeJSON, raw)
  if not ok then
    error(string.format("Response from %s was not valid JSON", url))
  end
  return data
end

local function writeFile(path, content)
  local dir = fs.getDir(path)
  if dir and dir ~= "" then
    fs.makeDir(dir)
  end
  local file = fs.open(path, "w")
  if not file then
    error(string.format("Unable to open %s for writing", path))
  end
  file.write(content)
  file.close()
end

local function installFile(path)
  local url = buildRawUrl(path)
  local ok, content = pcall(fetch, url)
  if not ok then
    print(string.format("Failed to download %s: %s", path, content))
    return
  end
  writeFile(path, content)
  print(string.format("Installed %s", path))
end

local function installFromManifest(manifest)
  print("Installing files from manifest.json...")
  for _, entry in ipairs(manifest.files or {}) do
    local source = entry.source or entry.path
    local target = entry.target or source
    if source and target then
      local url = buildRawUrl(source)
      local ok, content = pcall(fetch, url)
      if ok then
        writeFile(target, content)
        print(string.format("Downloaded %s -> %s", source, target))
      else
        print(string.format("Failed to download %s: %s", source, content))
      end
    else
      print("Skipping manifest entry without source/target")
    end
  end
end

local function shouldSkip(name)
  return name == ".git" or name == "tests" or name == "docs" or name == "node_modules"
end

local function installTree(path)
  local contentsUrl = buildContentsUrl(path)
  local data = fetchJson(contentsUrl)

  if data.type == "file" then
    installFile(data.path)
    return
  end

  if type(data) ~= "table" or #data == 0 then
    error(string.format("No contents found at %s", contentsUrl))
  end

  for _, entry in ipairs(data) do
    if not shouldSkip(entry.name) then
      if entry.type == "file" then
        installFile(entry.path)
      elseif entry.type == "dir" then
        installTree(entry.path)
      end
    end
  end
end

local function tryInstallManifest()
  local ok, manifestBody = pcall(fetch, buildRawUrl(MANIFEST_PATH))
  if not ok or not manifestBody then
    return false
  end
  local okParse, manifest = pcall(textutils.unserializeJSON, manifestBody)
  if not okParse or type(manifest) ~= "table" then
    return false
  end
  if type(manifest.files) == "table" and #manifest.files > 0 then
    writeFile(MANIFEST_PATH, manifestBody)
    installFromManifest(manifest)
    return true
  end
  return false
end

print(string.format("Installing from https://github.com/%s/%s (branch %s)%s", owner, repo, branch, subdir ~= "" and (" path " .. subdir) or ""))

local manifestInstalled = tryInstallManifest()
if manifestInstalled then
  print("Finished manifest install.")
else
  if subdir ~= "" then
    installTree(subdir)
  else
    installTree("")
  end
end

print("Installation complete.")
