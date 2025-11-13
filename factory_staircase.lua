-- staircase.lua
-- Usage: staircase.lua <width> <length>
--
-- Builds an ascending OR descending staircase in front of the turtle. The turtle should
-- start at the bottom-left corner of the desired staircase, facing the
-- forward direction of the staircase (the direction you want the stairs to go).
--
-- Arguments (if no args, prompt user):
--   width  - number of blocks across for each step (columns)
--   length - number of steps (height)
--   distance - how long to build the staircase (steps)
--
-- Behavior summary:
--   For each step from 1..length:
--     - Place 'width' blocks along the forward direction (building the step surface)
--     - Move back to the left side, move forward one block (to shift), and move up one
--   This creates a staircase where each higher step is shifted forward by 1.
--   - The turtle must have enough fuel for movement (or be in creative / have no fuel limits).
--   - The turtle will attempt to dig obstructing blocks in the way while moving.
--
-- IMPLEMENTATION NOTES
-- - We interpret "width" as the number of blocks across each tread (perpendicular to the
--   forward direction), and "steps" as how many treads to build.
-- - The turtle must start at the bottom-left corner of the staircase, facing forward.
-- - Direction can be "up" (default) or "down". For "down", the turtle moves forward and down
--   each step while placing treads at the lower levels.
-- - The script is interactive if arguments are omitted and will attempt to refuel and prompt
--   for more blocks as needed.

-- Tip: Lua basics used here
-- - Tables are 1-indexed. We loop from 1..n.
-- - Local variables are preferred (use 'local') to avoid polluting the global environment.
-- - Functions are first-class; we define helpers for movement, placement, and refueling.

-- ============================================================
-- Argument parsing and user prompts
-- ============================================================

local args = { ... }

-- Compatibility shim: When linting outside of ComputerCraft, the global 'turtle',
-- 'sleep', and 'read' may not exist. We provide harmless fallbacks so static
-- analysis doesn't fail. Inside ComputerCraft these are supplied by the runtime.
if not turtle then
	turtle = {
		forward = function() return true end,
		inspect = function() return false, {} end,
		dig = function() end,
		attack = function() end,
		up = function() return true end,
		inspectUp = function() return false, {} end,
		digUp = function() end,
		attackUp = function() end,
		down = function() return true end,
		inspectDown = function() return false, {} end,
		digDown = function() end,
		attackDown = function() end,
		getFuelLevel = function() return 100000 end,
		select = function(_) end,
		refuel = function(_) return false end,
		getItemCount = function(_) return 0 end,
		placeDown = function() return true end,
		detectDown = function() return true end,
		turnRight = function() end,
	}
end
if not sleep then sleep = function(_) end end
if not read then read = function() return io.read() end end

local function to_number_or_nil(s)
	local n = tonumber(s)
	if n == nil then return nil end
	if n < 1 then return nil end
	return math.floor(n)
end

local function parse_direction(token)
	if token == nil then return "up" end
	token = string.lower(tostring(token))
	if token == "up" or token == "u" or token == "ascend" or token == "a" then return "up" end
	if token == "down" or token == "d" or token == "descend" then return "down" end
	print("Unrecognized direction '" .. token .. "', defaulting to 'up'.")
	return "up"
end

local function prompt_number(prompt)
	while true do
		io.write(prompt)
		local s = read()
		local n = tonumber(s)
		if n and n >= 1 then return math.floor(n) end
		print("Please enter a positive integer.")
	end
end

local function prompt_direction()
	while true do
		io.write("Direction [up/down] (default up): ")
		local s = read()
		if s == nil or s == "" then return "up" end
		local d = parse_direction(s)
		if d == "up" or d == "down" then return d end
	end
end

local function usage()
	print("Usage: staircase <width> <steps> [up|down]")
	print("- width: number of blocks across each tread (columns)")
	print("- steps: number of treads to build (height)")
	print("- direction: 'up' to ascend (default) or 'down' to descend")
end

local width
local steps
local direction

if #args >= 2 then
	width = to_number_or_nil(args[1])
	steps = to_number_or_nil(args[2])
	if not width or not steps then
		usage()
		error("Invalid numeric arguments.")
	end
	direction = parse_direction(args[3])
else
	usage()
	width = prompt_number("Width (columns across each step): ")
	steps = prompt_number("Steps (number of treads): ")
	direction = prompt_direction()
end

-- ============================================================
-- Safety checks
-- ============================================================

if not turtle then
	error("This program must run on a Turtle (turtle API not found).")
end

-- ============================================================
-- Fuel management
-- ============================================================

local function ensure_fuel(target)
	-- Returns true if current fuel is unlimited or >= target
	local level = turtle.getFuelLevel()
	if level == "unlimited" then return true end
	if level >= target then return true end

	-- Try to refuel from inventory
	for slot = 1, 16 do
		if turtle.getItemCount(slot) > 0 then
			turtle.select(slot)
			if turtle.refuel(0) then
				while turtle.getFuelLevel() < target and turtle.getItemCount(slot) > 0 do
					turtle.refuel(1)
				end
				if turtle.getFuelLevel() >= target then return true end
			end
		end
	end
	return turtle.getFuelLevel() >= target
end

local function ensure_fuel_interactive(target)
	while true do
		if ensure_fuel(target) then return true end
		print("Not enough fuel. Add fuel items to inventory and press Enter to retry...")
		read()
	end
end

local function estimate_required_fuel(w, s)
	-- Heuristic: per step, we traverse across (w-1), back (w-1), then forward (1) and up/down (1)
	-- Turns are free. Add a small buffer per step.
	local per_step_moves = 2 * (math.max(0, w - 1)) + 2
	return s * per_step_moves + 4
end

-- ============================================================
-- Movement/placement helpers (robust digging/attacking)
-- ============================================================

local function try_forward()
	local attempts = 0
	while true do
		if turtle.forward() then return true end
		local ok, data = turtle.inspect()
		if ok then
			turtle.dig()
		else
			turtle.attack()
		end
		attempts = attempts + 1
		if attempts > 100 then return false end
		sleep(0.2)
	end
end

local function try_up()
	local attempts = 0
	while true do
		if turtle.up() then return true end
		local ok, data = turtle.inspectUp()
		if ok then
			turtle.digUp()
		else
			turtle.attackUp()
		end
		attempts = attempts + 1
		if attempts > 100 then return false end
		sleep(0.2)
	end
end

local function try_down()
	local attempts = 0
	while true do
		if turtle.down() then return true end
		local ok, data = turtle.inspectDown()
		if ok then
			turtle.digDown()
		else
			turtle.attackDown()
		end
		attempts = attempts + 1
		if attempts > 100 then return false end
		sleep(0.2)
	end
end

local function ensure_block_below()
	-- Place a block below the turtle if missing. Returns true when a block is present (placed or already existed).
	if turtle.detectDown() then return true end
	for slot = 1, 16 do
		if turtle.getItemCount(slot) > 0 then
			turtle.select(slot)
			if turtle.placeDown() then return true end
			-- If cannot place due to entity/gravity, try to clear and retry
			if not turtle.detectDown() then
				turtle.digDown()
				if turtle.placeDown() then return true end
			end
		end
	end
	return turtle.detectDown()
end

local function ensure_block_below_interactive()
	while true do
		if ensure_block_below() then return true end
		print("Out of placeable blocks. Add blocks to inventory and press Enter to continue...")
		read()
	end
end

-- ============================================================
-- Core building logic
-- ============================================================

local function build_row_across_width(w)
	-- At call: facing FORWARD. We'll turn right to traverse across the width.
	turtle.turnRight()

	for col = 1, w do
		ensure_block_below_interactive()
		if col < w then
			if not try_forward() then error("Failed to move across the row.") end
		end
	end

	-- We're at the far right, facing across the width. Return to the left side.
	turtle.turnRight()   -- turn around
	turtle.turnRight()
	for _ = 1, math.max(0, w - 1) do
		if not try_forward() then error("Failed to return to left side.") end
	end
	turtle.turnRight()   -- face forward again
end

local function shift_and_rise(dir)
	-- Move forward one, then up or down one based on dir
	if not try_forward() then error("Failed to move forward to next step.") end
	if dir == "up" then
		if not try_up() then error("Failed to move up for next step.") end
	else
		if not try_down() then error("Failed to move down for next step.") end
	end
end

-- ============================================================
-- Run
-- ============================================================

local required_fuel = estimate_required_fuel(width, steps)
ensure_fuel_interactive(required_fuel)

print(("Building staircase: width=%d, steps=%d, direction=%s"):format(width, steps, direction))
sleep(0.2)

for step_index = 1, steps do
	print(("Step %d/%d: laying tread"):format(step_index, steps))
	build_row_across_width(width)
	if step_index < steps then
		shift_and_rise(direction)
	end
end

print("Staircase complete.")

-- ============================================================
-- Extra tips for Lua and turtles (quick reference)
-- ============================================================
-- - Turning doesn't consume fuel; moving does. Keep some buffer fuel.
-- - turtle.inspect() returns (success, data). Use detect()/inspect() to check blocks.
-- - Prefer small helper functions and local variables; it makes code easier to read.
-- - When in doubt, add prints to trace progress. You can remove them when you're confident.
-- - This script prompts if it runs out of fuel or building blocks so you can top up and continue.
