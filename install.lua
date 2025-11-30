-- Simple installer that pulls the manifest.json from the main branch on GitHub
-- Usage: install <owner> <repo> [branch] [manifestPath]
-- Defaults: owner/repo from constants below, branch="main", manifestPath="manifest.json"

local DEFAULT_OWNER = "tailorswift"
local DEFAULT_REPO = "tailorswift"
local DEFAULT_BRANCH = "main"
local DEFAULT_MANIFEST_PATH = "manifest.json"

local args = {...}
local owner = args[1] or DEFAULT_OWNER
local repo = args[2] or DEFAULT_REPO
local branch = args[3] or DEFAULT_BRANCH
local manifestPath = args[4] or DEFAULT_MANIFEST_PATH

local function buildManifestUrl()
  return string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/%s",
    owner,
    repo,
    branch,
    manifestPath
  )
end

local function fetch(url)
  local response = http.get(url)
  if not response then
    error(string.format("Failed to fetch %s. Is HTTP enabled?", url))
  end
  local body = response.readAll()
  response.close()
  return body
end

local function writeFile(path, content)
  local file = fs.open(path, "w")
  if not file then
    error(string.format("Unable to open %s for writing", path))
  end
  file.write(content)
  file.close()
end

local manifestUrl = buildManifestUrl()
print("Downloading manifest from " .. manifestUrl)

local manifestBody = fetch(manifestUrl)
local manifest = textutils.unserializeJSON(manifestBody)
if not manifest then
  error("Downloaded manifest is not valid JSON")
end

writeFile(manifestPath, manifestBody)
print("Saved manifest to " .. manifestPath)

if type(manifest.files) == "table" and #manifest.files > 0 then
  print("Downloading files listed in manifest...")
  for _, fileEntry in ipairs(manifest.files) do
    local source = fileEntry.source
    local target = fileEntry.target or source
    if not source then
      print("Skipping entry with no source")
    else
      local fileUrl = string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s",
        owner,
        repo,
        branch,
        source
      )
      local ok, content = pcall(fetch, fileUrl)
      if ok then
        writeFile(target, content)
        print(string.format("Downloaded %s -> %s", source, target))
      else
        print(string.format("Failed to download %s: %s", source, content))
      end
    end
  end
else
  print("Manifest contains no files to download.")
end
