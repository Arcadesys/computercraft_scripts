-- Headless tests for potato farming state.
package.path = package.path .. ";./?.lua;./?/init.lua"

local debug = debug

-- Stub dependencies that aren't under test.
package.loaded["lib_logger"] = { log = function() end }
package.loaded["lib_movement"] = {
    goTo = function() return true end,
    up = function() return true end,
}
package.loaded["lib_fuel"] = {}
package.loaded["lib_wizard"] = {}
package.loaded["lib_startup"] = { runFuelCheck = function() return true end }
package.loaded["lib_farming"] = { deposit = function() return true end }

_G.sleep = function() end

local inventory = require("lib_inventory")

local function mockTurtle(inventorySlots, initialBlock)
    local selected = 1
    local slots = inventorySlots or {}
    local block = initialBlock or { name = "minecraft:air" }

    local turtleMock = {
        select = function(slot)
            selected = slot
            return true
        end,
        getItemCount = function(slot)
            return slots[slot] and slots[slot].count or 0
        end,
        getItemDetail = function(slot)
            local item = slots[slot]
            if not item then return nil end
            return { name = item.name, count = item.count }
        end,
        inspectDown = function()
            return true, block
        end,
        placeDown = function()
            local item = slots[selected]
            if not item or item.count == 0 then return false end
            if item.name:find("hoe") then
                block = { name = "minecraft:farmland" }
                return true
            elseif item.name == "minecraft:potato" then
                block = { name = "minecraft:potatoes", state = { age = 0 } }
                item.count = item.count - 1
                return true
            end
            return false
        end,
        suckDown = function()
            return false
        end,
        digDown = function()
            block = { name = "minecraft:air" }
            return true
        end,
    }

    return turtleMock, function()
        return block
    end
end

local function getEnsureFarmland()
    local potatofarm = require("factory.state_potatofarm")
    for i = 1, 10 do
        local name, value = debug.getupvalue(potatofarm, i)
        if name == "ensureFarmland" then
            return value
        end
    end
    error("ensureFarmland upvalue not found")
end

local function testTillsDirtWithHoe()
    local turtleMock, getBlock = mockTurtle({
        [1] = { name = "minecraft:wooden_hoe", count = 1 }
    }, { name = "minecraft:dirt" })
    _G.turtle = turtleMock

    local ensureFarmland = getEnsureFarmland()
    local ctx = { inventoryState = {} }

    local ok = ensureFarmland(ctx, { name = "minecraft:dirt" })
    assert(ok, "expected ensureFarmland to succeed")
    assert(getBlock().name == "minecraft:farmland", "block should be tilled into farmland")
end

local function testPlantsFromUpdatedInventory()
    local turtleMock, getBlock = mockTurtle({
        [1] = { name = "minecraft:wooden_hoe", count = 1 },
        [2] = { name = "minecraft:potato", count = 3 }
    }, { name = "minecraft:farmland" })
    _G.turtle = turtleMock

    local potatofarm = require("factory.state_potatofarm")

    local ctx = {
        potatofarm = {
            state = "SCAN",
            width = 3,
            height = 3,
            nextX = 0,
            nextZ = 0,
            chests = {},
        },
        inventoryState = {
            dirty = false,
            slots = {},
            materialSlots = {},
            materialTotals = {},
            emptySlots = {},
            totalItems = 0,
        },
    }

    local state = potatofarm(ctx)
    assert(state == "POTATOFARM", "state machine should continue running")
    assert(getBlock().name == "minecraft:potatoes", "should plant potatoes on farmland")
    assert(ctx.inventoryState.dirty == true, "inventory should be marked dirty after planting")
end

local function main()
    testTillsDirtWithHoe()
    testPlantsFromUpdatedInventory()
    print("potatofarm_spec.lua ok")
end

main()
