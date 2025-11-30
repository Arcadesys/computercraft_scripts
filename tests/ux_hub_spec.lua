-- Simple headless test for ui.hub using plain Lua.
package.path = package.path .. ";./?.lua;./?/init.lua"

local hub = require("ui.hub")

local calls = 0
local output = {}

hub.run({
    title = "Hub Test",
    sections = {
        {
            label = "Demo",
            items = {
                {
                    label = "Call",
                    action = function()
                        calls = calls + 1
                    end
                }
            }
        }
    },
    platform = hub.Platform.new({
        inputs = { "1", "q" },
        outputs = output,
        headless = true,
    })
})

if calls ~= 1 then
    error("Expected action to be called once, got " .. tostring(calls))
end

print("ux_hub_spec.lua ok")
