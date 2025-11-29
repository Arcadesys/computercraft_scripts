---@diagnostic disable: undefined-global

-- video_player.lua
-- Stream and play NFP (background blit rows) video from a manifest URL.

local args = { ... }
local manifestUrl = args[1]
local monitorName = args[2]
local loopFlag = args[3] == "--loop" or args[2] == "--loop"

if not manifestUrl then
    print("Usage: video_player <manifest_url> [monitor_name] [--loop]")
    print("Example: video_player https://example.com/videos/demo/manifest.json rightMonitor --loop")
    return
end

local function jsonDecode(str)
    local ok, res = pcall(textutils.unserializeJSON, str)
    if ok then return res end
    return nil
end

local function fetch(url)
    if http and http.get then
        local h = http.get(url)
        if h then
            local body = h.readAll()
            h.close()
            return body
        end
    end
    return nil
end

local function readManifest(url)
    local body = fetch(url)
    if not body then return nil, "failed to fetch manifest" end
    local data = jsonDecode(body)
    if not data then return nil, "invalid manifest json" end
    if type(data.frames) ~= "table" then return nil, "manifest missing frames" end
    return data
end

local monitorSession = nil
local function pickTargetTerm()
    local ok, monitorUtil = pcall(require, "lib_monitor")
    if ok and monitorUtil and monitorUtil.redirectToMonitor then
        local opts = { textScale = 0.5 }
        if monitorName then opts.preferredNames = { monitorName } end
        monitorSession = monitorUtil.redirectToMonitor(opts)
        if monitorSession and monitorSession.monitor then
            return monitorSession.monitor
        end
    end

    if monitorName and peripheral and peripheral.wrap then
        local mon = peripheral.wrap(monitorName)
        if mon and mon.isColor and mon.isColor() then
            mon.setTextScale(0.5)
            return mon
        end
    end
    return term
end

local function drawFrame(t, frameRows)
    for y, row in ipairs(frameRows) do
        t.setCursorPos(1, y)
        local bg = row
        local fg = string.rep("0", #row)
        local txt = string.rep(" ", #row)
        t.blit(txt, fg, bg)
    end
end

local function readFrame(url)
    local body = fetch(url)
    if not body then return nil end
    local rows = {}
    for line in body:gmatch("[^\r\n]+") do
        table.insert(rows, line)
    end
    -- skip header "w h"
    table.remove(rows, 1)
    return rows
end

local function play(manifest, target)
    target = target or term
    local base = manifest.baseUrl or manifest.framesBasePath or ""
    local function resolve(frame)
        if frame:match("^https?://") then return frame end
        if base == "" then
            return fs.combine(fs.getDir(manifestUrl) or "", frame)
        end
        if base:match("^https?://") then
            if base:sub(-1) ~= "/" then base = base .. "/" end
            return base .. frame
        end
        return fs.combine(base, frame)
    end

    local delay = 1 / (manifest.fps or 8)

    repeat
        for i, frame in ipairs(manifest.frames) do
            local rows = readFrame(resolve(frame))
            if not rows then
                print("Failed to read frame " .. tostring(frame))
                return
            end
            drawFrame(target, rows)
            if delay > 0 then sleep(delay) end
        end
    until not loopFlag
end

local manifest, err = readManifest(manifestUrl)
if not manifest then
    print("Error: " .. (err or "unknown"))
    return
end

local function main()
    local target = pickTargetTerm()
    play(manifest, target)
end

local ok, errMain = xpcall(main, debug and debug.traceback or nil)
if monitorSession and monitorSession.restore then
    monitorSession.restore()
end
if not ok then
    error(errMain)
end
