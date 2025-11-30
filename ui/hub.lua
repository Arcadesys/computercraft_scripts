--[[
Arcadesys Hub
Lightweight, dependency-light menu runner so we can exercise the UX
both inside ComputerCraft and in plain Lua (for fast iteration/tests).

Usage:
  local hub = require("ui.hub")
  hub.run({
    title = "Arcadesys",
    sections = {
      { label = "Demo", items = { { label = "Say hi", action = function(ctx, ui) ui:notify("hi") end } } }
    }
  })
]]

local Hub = {}

-- Small sleep shim that works in plain Lua.
local function pauseBrief()
    if type(_G.sleep) == "function" then
        pcall(_G.sleep, 0.05)
    end
end

-- Platform adapter so rendering/input can be swapped for tests.
local Platform = {}
Platform.__index = Platform

local function readLineCompat()
    if type(_G.read) == "function" then
        return _G.read()
    elseif io and io.read then
        return io.read("*l")
    end
    return nil
end

function Platform.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Platform)
    self.inputs = opts.inputs or nil
    self.outputs = opts.outputs or nil
    self.echoInputs = opts.echoInputs or false
    self.inputIdx = 1
    self.headless = opts.headless or false
    self.hasTerm = type(term) == "table" and type(term.clear) == "function" and not self.headless
    self.readLine = opts.readLine or readLineCompat
    self.lineWriter = opts.writeLine or function(text)
        if io and io.write then
            io.write((text or "") .. "\n")
        end
    end
    return self
end

function Platform:nextInput()
    if self.inputs and self.inputIdx <= #self.inputs then
        local v = self.inputs[self.inputIdx]
        self.inputIdx = self.inputIdx + 1
        if self.outputs and self.echoInputs then
            table.insert(self.outputs, "> " .. tostring(v))
        end
        return v
    end
    if self.readLine then
        return self.readLine()
    end
    return nil
end

function Platform:clear()
    if self.hasTerm then
        if _G.colors then
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
        end
        term.clear()
        term.setCursorPos(1, 1)
    else
        self:writeLine(string.rep("-", 40))
    end
end

function Platform:write(text)
    if self.outputs then table.insert(self.outputs, tostring(text or "")) end
    if self.hasTerm then
        io.write(text or "")
    elseif io and io.write then
        io.write(text or "")
    end
end

function Platform:writeLine(text)
    if self.outputs then table.insert(self.outputs, tostring(text or "")) end
    if self.hasTerm then
        print(text)
    else
        self.lineWriter(text or "")
    end
end

function Platform:prompt(label, default)
    local suffix = default and (" [" .. tostring(default) .. "]") or ""
    self:write(label .. suffix .. ": ")
    local resp = self:nextInput()
    if resp == nil then return default end
    resp = tostring(resp)
    if resp == "" and default ~= nil then
        return default
    end
    return resp
end

function Platform:notify(msg)
    self:writeLine(msg)
    pauseBrief()
end

function Platform:pause(msg)
    if msg then self:writeLine(msg) end
    self:writeLine("(Press Enter to continue)")
    self:nextInput()
end

Hub.Platform = Platform

local function flattenSections(sections)
    local flat = {}
    for _, section in ipairs(sections or {}) do
        if not section.hidden then
            for _, item in ipairs(section.items or {}) do
                if not item.hidden then
                    table.insert(flat, {
                        section = section,
                        item = item,
                    })
                end
            end
        end
    end
    return flat
end

local function renderScreen(ui, cfg, flat)
    ui:clear()
    ui:writeLine(cfg.title or "Arcadesys")
    if cfg.subtitle then
        ui:writeLine(cfg.subtitle)
    end
    ui:writeLine("")
    for idx, entry in ipairs(flat) do
        local label = entry.item.label or ("Item " .. idx)
        local hint = entry.item.hint and (" - " .. entry.item.hint) or ""
        ui:writeLine(string.format("%2d) [%s] %s%s", idx, entry.section.label or "Section", label, hint))
    end
    ui:writeLine(" q) Quit")
end

local function safeCall(action, ctx, ui)
    local ok, err = pcall(action, ctx, ui)
    if not ok then
        ui:notify("Action failed: " .. tostring(err))
    end
end

-- Run the interactive hub.
-- cfg = { title, subtitle, sections = { { label, items = { { label, hint, action=function(ctx,ui) end } } } }, platform }
function Hub.run(cfg)
    cfg = cfg or {}
    local ui = cfg.platform or Platform.new()
    local ctx = cfg.ctx or {}
    local running = true

    while running do
        local flat = flattenSections(cfg.sections)
        renderScreen(ui, cfg, flat)

        local choice = ui:prompt("Select option", nil)
        if not choice then return end
        local lowered = tostring(choice):lower()
        if lowered == "q" or lowered == "quit" or lowered == "exit" then
            return
        end
        local idx = tonumber(choice)
        local entry = idx and flat[idx] or nil
        if entry and type(entry.item.action) == "function" then
            safeCall(entry.item.action, ctx, ui)
        else
            ui:notify("Invalid choice")
        end
    end
end

return Hub
