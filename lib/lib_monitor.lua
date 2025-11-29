--[[
Utility helpers for directing terminal output to an attached monitor.
Exposes two helpers:
  - redirectToMonitor(opts): attempts to redirect term output, returning a
    session table { monitor, native, restore } or nil on failure.
  - runOnMonitor(fn, opts): runs fn inside a protected call while redirecting
    to a monitor if one is available; always restores the native terminal.

Options table (all optional):
  preferredNames = { "right", "top" } -- list of peripheral names/sides to try first
  textScale = 0.5                     -- scale to apply to the monitor
  clear = true                        -- clear and reset cursor after redirect
  requireColor = false                -- set true to only use advanced monitors
  skipOnTurtle = false                -- skip redirect when running on turtles if true
]]

local monitor = {}

local function safeInvoke(obj, method, ...)
    if not obj then return nil end
    local fn = obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, obj, ...)
    if ok then return res end
    return nil
end

local function pickMonitor(opts)
    if not peripheral or type(peripheral.find) ~= "function" then
        return nil
    end

    opts = opts or {}
    local preferred = {}
    if type(opts.preferredName) == "string" then
        preferred[#preferred + 1] = opts.preferredName
    end
    if type(opts.preferredNames) == "table" then
        for _, name in ipairs(opts.preferredNames) do
            if type(name) == "string" then
                preferred[#preferred + 1] = name
            end
        end
    end

    if #preferred > 0 and peripheral.wrap then
        for _, name in ipairs(preferred) do
            local ok, wrapped = pcall(peripheral.wrap, name)
            if ok and wrapped then
                return wrapped
            end
        end
    end

    local requireColor = opts.requireColor == true
    local userFilter = type(opts.filter) == "function" and opts.filter or nil
    local filter = nil
    if requireColor or userFilter then
        filter = function(name, wrapped)
            if userFilter then
                local ok, res = pcall(userFilter, name, wrapped)
                if not ok then return false end
                if res == false then return false end
            end
            if requireColor then
                local isColor = safeInvoke(wrapped, "isColor")
                if isColor == false then return false end
            end
            return true
        end
    end

    local ok, wrapped = pcall(peripheral.find, "monitor", filter)
    if ok then
        return wrapped
    end
    return nil
end

---Redirect the current terminal to an attached monitor if found.
---@param opts table|nil
---@return table|nil session table {monitor, native, restore} or nil if no monitor/redirect failed
---@return any err optional error when redirect fails
function monitor.redirectToMonitor(opts)
    opts = opts or {}
    if opts.skipOnTurtle and turtle then
        return nil
    end
    if not term or type(term.redirect) ~= "function" or type(term.current) ~= "function" then
        return nil
    end

    local target = pickMonitor(opts)
    if not target then
        return nil
    end

    if opts.textScale then
        safeInvoke(target, "setTextScale", opts.textScale)
    end
    if opts.clear ~= false then
        safeInvoke(target, "setBackgroundColor", colors.black)
        safeInvoke(target, "setTextColor", colors.white)
        safeInvoke(target, "clear")
        safeInvoke(target, "setCursorPos", 1, 1)
    end

    local native = term.current()
    if native == target then
        return { monitor = target, native = native, restore = function() end }
    end

    local ok, err = pcall(term.redirect, target)
    if not ok then
        return nil, err
    end

    local restored = false
    local function restore()
        if restored then return end
        restored = true
        if native then
            pcall(term.redirect, native)
        end
    end

    return {
        monitor = target,
        native = native,
        restore = restore,
    }
end

---Run a function while redirecting output to a monitor when available.
---@param fn function
---@param opts table|nil options forwarded to redirectToMonitor
function monitor.runOnMonitor(fn, opts)
    if type(fn) ~= "function" then
        return nil, "fn_missing"
    end
    local session = monitor.redirectToMonitor(opts)
    local handler = (debug and debug.traceback) or function(err) return err end
    local ok, res = xpcall(fn, handler)
    if session and session.restore then
        session.restore()
    end
    if not ok then
        error(res)
    end
    return res
end

return monitor
