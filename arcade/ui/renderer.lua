-- ui/renderer.lua
-- Lightweight textured renderer for ComputerCraft monitors/terminals.
-- Provides sprite-style drawing helpers, hit-testing, and a pluggable skin
-- system so games can share visual assets while keeping logic minimal.
-- Lua Tip: Tables can act like objects when we set a metatable with __index.

---@diagnostic disable: undefined-global

local Renderer = {}
Renderer.__index = Renderer

-- Convert a colors.<name> entry into a blit hex digit.
local function toBlit(color)
    if colors.toBlit then return colors.toBlit(color) end
    -- Fallback: derive from bit position (useful when running outside CC tooling)
    local idx = math.floor(math.log(color, 2))
    return ("0123456789abcdef"):sub(idx + 1, idx + 1)
end

-- Repeat a pattern string to at least width characters, trimming if necessary.
local function repeatToWidth(pattern, desiredWidth)
    local out = ""
    while #out < desiredWidth do
        out = out .. pattern
    end
    if #out > desiredWidth then
        out = out:sub(1, desiredWidth)
    end
    return out
end

local function copyTable(tbl)
    local out = {}
    for k, v in pairs(tbl or {}) do
        if type(v) == "table" then
            out[k] = copyTable(v)
        else
            out[k] = v
        end
    end
    return out
end

local function deepMerge(base, override)
    local out = copyTable(base)
    for k, v in pairs(override or {}) do
        if type(v) == "table" and type(out[k]) == "table" then
            out[k] = deepMerge(out[k], v)
        else
            out[k] = v
        end
    end
    return out
end

local function normalizeTexture(texture)
    if not texture then return nil end
    if not texture.rows or #texture.rows == 0 then return nil end
    texture.width = texture.width or #texture.rows[1].text
    texture.height = texture.height or #texture.rows
    return texture
end

local function tryBuildPineTexture(width, height, baseColor, accentColor)
    -- We intentionally use pcall to avoid crashing when pine3d isn't present.
    local ok, pine3d = pcall(require, "pine3d")
    if not ok or type(pine3d) ~= "table" then return nil end

    local okTexture, texture = pcall(function()
        -- Lua Tip: feature detection keeps optional dependencies from breaking core logic.
        local canvasBuilder = pine3d.newCanvas or pine3d.canvas or pine3d.newRenderer
        if not canvasBuilder then return nil end
        local canvas = canvasBuilder(width, height)
        if canvas.clear then canvas:clear(baseColor) end
        -- Draw a pair of angular polygons for a "90s" tech-panel vibe.
        if canvas.polygon then
            canvas:polygon({0, 0}, {width - 1, 1}, {width - 2, height - 1}, {0, height - 2}, accentColor)
            canvas:polygon({2, 0}, {width - 1, 0}, {width - 1, height - 1}, {3, height - 2}, colors.black)
        end
        -- Exporters vary by pine3d version; try the common ones.
        if canvas.exportTexture then return normalizeTexture(canvas:exportTexture()) end
        if canvas.toTexture then return normalizeTexture(canvas:toTexture()) end
        if canvas.export then return normalizeTexture(canvas:export()) end
        return nil
    end)

    if okTexture then return texture end
    return nil
end

local function defaultButtonTexture(light, mid, dark)
    local pineTexture = tryBuildPineTexture(6, 3, dark, light)
    if pineTexture then return pineTexture end
    -- Two-tone diagonal stripes to give a bit of depth when pine3d is unavailable.
    local fgLight, fgDark = toBlit(colors.white), toBlit(colors.lightGray)
    return normalizeTexture({
        rows = {
            { text = "\\\\\\\\", fg = repeatToWidth(fgDark, 4), bg = repeatToWidth(toBlit(light), 4) },
            { text = "////", fg = repeatToWidth(fgLight, 4), bg = repeatToWidth(toBlit(mid), 4) },
            { text = "    ", fg = repeatToWidth(fgDark, 4), bg = repeatToWidth(toBlit(dark), 4) },
        }
    })
end

local function buildDefaultSkin()
    local base = colors.black
    local accent = colors.orange
    local accentDark = colors.brown
    return {
        background = base,
        playfield = base,
        buttonBar = { background = base },
        buttons = {
            enabled = {
                texture = defaultButtonTexture(accent, accentDark, base),
                labelColor = colors.orange,
                shadowColor = colors.gray,
            },
            disabled = {
                texture = defaultButtonTexture(colors.gray, colors.black, colors.black),
                labelColor = colors.lightGray,
                shadowColor = colors.black,
            }
        },
        titleColor = colors.orange,
    }
end

---Create a renderer instance.
---@param opts table|nil {skin=table, monitor=peripheral, textScale=number}
function Renderer.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Renderer)
    self.skin = deepMerge(buildDefaultSkin(), opts.skin or {})
    self.monitor = nil
    self.nativeTerm = term.current()
    self.w, self.h = term.getSize()
    self.hotspots = {}
    if opts.monitor then
        self:attachToMonitor(opts.monitor, opts.textScale)
    end
    return self
end

function Renderer:getSize()
    self.w, self.h = term.getSize()
    return self.w, self.h
end

function Renderer:attachToMonitor(monitor, textScale)
    self.monitor = monitor
    if not monitor then
        if self.nativeTerm then term.redirect(self.nativeTerm) end
        self.w, self.h = term.getSize()
        return
    end
    if textScale then monitor.setTextScale(textScale) end
    term.redirect(monitor)
    self.w, self.h = term.getSize()
end

function Renderer:restore()
    if self.nativeTerm then
        term.redirect(self.nativeTerm)
        self.monitor = nil
    end
end

function Renderer:setSkin(skin)
    self.skin = deepMerge(buildDefaultSkin(), skin or {})
end

function Renderer:registerHotspot(name, rect)
    self.hotspots[name] = copyTable(rect)
end

function Renderer:hitTest(name, x, y)
    local r = self.hotspots[name]
    if not r then return false end
    return x >= r.x and x <= r.x + r.w - 1 and y >= r.y and y <= r.y + r.h - 1
end

function Renderer:fillRect(x, y, w, h, bg, fg, ch)
    local bgBlit = repeatToWidth(toBlit(bg or colors.black), w)
    local fgBlit = repeatToWidth(toBlit(fg or bg or colors.black), w)
    local text = repeatToWidth(ch or " ", w)
    for yy = y, y + h - 1 do
        term.setCursorPos(x, yy)
        term.blit(text, fgBlit, bgBlit)
    end
end

function Renderer:drawTextureRect(texture, x, y, w, h)
    local tex = normalizeTexture(texture)
    if not tex then
        self:fillRect(x, y, w, h, colors.black, colors.black, " ")
        return
    end
    for row = 0, h - 1 do
        local src = tex.rows[(row % tex.height) + 1]
        local text = repeatToWidth(src.text, w)
        local fg = repeatToWidth(src.fg, w)
        local bg = repeatToWidth(src.bg, w)
        term.setCursorPos(x, y + row)
        term.blit(text, fg, bg)
    end
end

function Renderer:drawLabelCentered(x, y, w, text, color, shadowColor)
    if not text or text == "" then return end
    local tx = x + math.floor((w - #text) / 2)
    if shadowColor then
        term.setTextColor(shadowColor)
        term.setCursorPos(tx + 1, y + 1)
        term.write(text)
    end
    term.setTextColor(color or colors.white)
    term.setCursorPos(tx, y)
    term.write(text)
end

function Renderer:drawButton(rect, label, enabled)
    local skin = enabled and self.skin.buttons.enabled or self.skin.buttons.disabled
    self:drawTextureRect(skin.texture, rect.x, rect.y, rect.w, rect.h)
    self:drawLabelCentered(rect.x, rect.y + math.floor(rect.h / 2), rect.w, label, skin.labelColor, skin.shadowColor)
end

function Renderer:paintSurface(rect, surface)
    if type(surface) == "table" then
        self:drawTextureRect(surface, rect.x, rect.y, rect.w, rect.h)
    else
        self:fillRect(rect.x, rect.y, rect.w, rect.h, surface or colors.black)
    end
end

function Renderer.defaultSkin()
    return buildDefaultSkin()
end

function Renderer.mergeSkin(base, override)
    return deepMerge(base, override)
end

return Renderer
