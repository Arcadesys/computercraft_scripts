---@diagnostic disable: undefined-global
-- license_store.lua
-- Simple disk-backed license manager for arcade programs.
-- Uses lightweight signatures to discourage casual tampering of license files.

local LicenseStore = {}
LicenseStore.__index = LicenseStore

-- Lua tip: small helper functions keep the public API easy to read.
local function ensureDirectory(path)
  if not fs.exists(path) then
    fs.makeDir(path)
  end
end

local function computeHash(input)
  if textutils.sha256 then
    return textutils.sha256(input)
  end
  -- Fallback checksum if sha256 is unavailable; keeps deterministic signature.
  local sum = 0
  for i = 1, #input do
    sum = (sum + string.byte(input, i)) % 0xFFFFFFFF
  end
  return string.format("%08x", sum)
end

local function signaturePayload(license)
  return table.concat({
    license.programId or "",
    tostring(license.purchasedAt or ""),
    tostring(license.pricePaid or ""),
    tostring(license.note or ""),
  }, "|")
end

local function signatureFor(license, secret)
  return computeHash(signaturePayload(license) .. "|" .. secret)
end

function LicenseStore.new(rootPath, secret)
  local store = setmetatable({}, LicenseStore)
  store.rootPath = rootPath or "licenses"
  store.secret = secret or "arcade-license-v1"
  ensureDirectory(store.rootPath)
  return store
end

function LicenseStore:licensePath(programId)
  return fs.combine(self.rootPath, programId .. ".lic")
end

function LicenseStore:load(programId)
  local path = self:licensePath(programId)
  if not fs.exists(path) then
    return nil, "missing"
  end

  local handle = fs.open(path, "r")
  local content = handle.readAll()
  handle.close()

  local data = textutils.unserialize(content)
  if type(data) ~= "table" then
    return nil, "corrupt"
  end

  local expected = signatureFor(data, self.secret)
  if data.signature ~= expected then
    return nil, "invalid_signature"
  end

  return data
end

function LicenseStore:has(programId)
  local license = self:load(programId)
  if license then
    return true, license
  end
  return false
end

function LicenseStore:save(programId, pricePaid, note)
  local license = {
    programId = programId,
    purchasedAt = os.epoch("utc"),
    pricePaid = pricePaid or 0,
    note = note,
  }
  license.signature = signatureFor(license, self.secret)

  local handle = fs.open(self:licensePath(programId), "w")
  handle.write(textutils.serialize(license))
  handle.close()

  return license
end

return LicenseStore
