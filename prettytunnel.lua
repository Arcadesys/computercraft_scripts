--
-- ComputerCraft Turtle: Tunnel Builder
--
-- What this does
-- - Digs a rectangular tunnel of given length, width, and height.
-- - Optional: lines the floor, walls (left/right), and ceiling with blocks you provide.
-- - Optional: places torches on the floor at a chosen interval, centered if possible.
-- - Tries to be resilient to gravel/sand/mobs and refuels automatically if it can.
--
-- Quick usage (arguments are positional and optional beyond length):
--   tunnel <length> [width=3] [height=3] [torchEvery=7] [torchOffsetFromLeft=auto]
--          [floorSlot] [wallSlot] [ceilingSlot] [torchSlot]
--
-- Examples:
--   tunnel 50                 -- 50-long, 3x3 tunnel, torches every 7 blocks on floor center
--   tunnel 100 5 3 9          -- 100-long, 5 wide x 3 tall, torches every 9 blocks
--   tunnel 30 3 3 6 1 2 3 4   -- with explicit slots: floor=1, wall=2, ceiling=3, torch=4
--
-- Interactive mode (just run without args):
--   tunnel
--   You will be asked for length, width, height, torch spacing, torch lateral offset, and slots.
--   Press Enter to accept defaults shown in [brackets]. Leave slot blank to skip that feature.
--   Torch slot may auto-detect any item containing the substring "torch" if left blank.
--
-- Inventory expectations
-- - Put the blocks you want for floor/walls/ceiling into the specified slots.
-- - If you omit slots, wall/floor/ceiling will be skipped. Torch slot can be auto-detected.
-- - Fuel can be anywhere in inventory; the turtle will try to refuel if needed.
--
-- Coordinate convention used by this script
-- - Turtle starts at the tunnel entrance, on the floor, facing forward along the tunnel axis.
-- - "Left" means turtle's left. We maintain a simple invariant: before each tunnel slice,
--   the turtle is at the leftmost floor position of that slice, facing forward.
-- - Each slice: we clear width x height at the current forward position, line surfaces,
--   place a torch if it's time, return to leftmost, then advance to the next slice.
--
-- Notes on behavior
-- - Torches are placed on the floor (reliable in CC). We center torches when width is odd.
-- - Walls are "lined": for the leftmost and rightmost columns, we dig+replace the boundary block
--   with the provided wall block at each level (0..height-1). If no wall blocks provided, we skip.
-- - Floor: we dig the block below and place your floor block so you walk on it (if provided).
-- - Ceiling: at the top level, we dig the boundary block above and replace with your ceiling block.
-- - If a material runs out, we log a warning and stop placing that material (continue tunneling).
--
-- Helpful Lua tips (TL;DR used in this file)
-- - Use `local` to avoid polluting the global scope.
-- - Return booleans and messages for helper functions to make decisions explicit.
-- - Prefer small helpers (forwardSafe, digUpSafe, etc.) to keep main logic readable.

-- ===============
-- Configuration
-- ===============
local DEFAULT_WIDTH = 3
local DEFAULT_HEIGHT = 3
local DEFAULT_TORCH_EVERY = 7

-- Capture program arguments (ComputerCraft passes them as varargs at top-level)
local PROGRAM_ARGS = { ... }

-- Advanced options (set via interactive prompt; sane defaults for CLI mode)
local advanced = {
	torchMount = "floor",   -- one of: "floor", "left", "right"
	torchHeight = 2,         -- vertical level for wall torches (1..height); 1=floor level
	returnToStart = false,   -- if true, turtle returns to entrance when done
	progressEvery = 10,      -- print progress every N blocks; 0 to disable
}

-- Stats for a friendly summary at the end
local stats = {
	distance = 0,
	torches = 0,
	floorPlaced = 0,
	wallPlaced = 0,
	ceilingPlaced = 0,
}

-- ===============
-- Utilities
-- ===============
local function println(msg)
	print(msg)
end

local function toInt(n, default)
	local v = tonumber(n)
	if v == nil then return default end
	return math.floor(v)
end

local function clamp(n, lo, hi)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- Sleep small helper (ComputerCraft provides `sleep(seconds)`)
local function pause(sec)
	if type(_G.sleep) == "function" then
		_G.sleep(sec)
	else
		-- Fallback no-op if sleep isn't available in this environment
	end
end

-- ===============
-- Inventory helpers
-- ===============
local function hasItemInSlot(slot)
	if not slot then return false end
	local d = turtle.getItemDetail(slot)
	return d ~= nil and d.count and d.count > 0
end

local function findItemSlotByName(substring)
	for s = 1, 16 do
		local d = turtle.getItemDetail(s)
		if d and d.name and string.find(d.name, substring, 1, true) then
			return s
		end
	end
	return nil
end

local function ensureSelect(slot)
	if not slot then return false end
	turtle.select(clamp(slot, 1, 16))
	return true
end

-- Returns true if refueled to at least target (or unlimited), false otherwise.
local function ensureFuel(target)
	local lvl = turtle.getFuelLevel()
	if lvl == "unlimited" then return true end
	if lvl >= target then return true end

	println("Refueling: need " .. target .. ", have " .. lvl .. " …")
	for s = 1, 16 do
		if turtle.getItemCount(s) > 0 then
			turtle.select(s)
			-- Try to eat small amounts to avoid consuming a full stack when not needed
			while turtle.getItemCount(s) > 0 and turtle.getFuelLevel() < target do
				if not turtle.refuel(1) then break end
			end
			if turtle.getFuelLevel() >= target or turtle.getFuelLevel() == "unlimited" then
				println("Refueled to " .. turtle.getFuelLevel())
				return true
			end
		end
	end
	println("Warning: insufficient fuel. Add fuel to inventory and resume.")
	return turtle.getFuelLevel() >= target
end

-- ===============
-- Movement helpers (resilient to gravel/mobs)
-- ===============
local function digSafe()
	local tries = 0
	while turtle.detect() do
		if turtle.dig() then
			pause(0.2)
		else
			turtle.attack()
			pause(0.2)
		end
		tries = tries + 1
		if tries > 50 then return false end
	end
	return true
end

local function digUpSafe()
	local tries = 0
	while turtle.detectUp() do
		if turtle.digUp() then
			pause(0.2)
		else
			turtle.attackUp()
			pause(0.2)
		end
		tries = tries + 1
		if tries > 50 then return false end
	end
	return true
end

local function digDownSafe()
	local tries = 0
	while turtle.detectDown() do
		if turtle.digDown() then
			pause(0.2)
		else
			turtle.attackDown()
			pause(0.2)
		end
		tries = tries + 1
		if tries > 50 then return false end
	end
	return true
end

local function forwardSafe()
	local tries = 0
	while not turtle.forward() do
		if turtle.detect() then
			turtle.dig()
		else
			turtle.attack()
		end
		pause(0.2)
		tries = tries + 1
		if tries > 80 then return false end
	end
	return true
end

local function upSafe()
	local tries = 0
	while not turtle.up() do
		if turtle.detectUp() then
			turtle.digUp()
		else
			turtle.attackUp()
		end
		pause(0.2)
		tries = tries + 1
		if tries > 80 then return false end
	end
	return true
end

local function downSafe()
	local tries = 0
	while not turtle.down() do
		if turtle.detectDown() then
			turtle.digDown()
		else
			turtle.attackDown()
		end
		pause(0.2)
		tries = tries + 1
		if tries > 80 then return false end
	end
	return true
end

-- Keep facing forward after a lateral move
local function strafeRightSafe()
	turtle.turnRight()
	local ok = forwardSafe()
	turtle.turnLeft()
	return ok
end

local function strafeLeftSafe()
	turtle.turnLeft()
	local ok = forwardSafe()
	turtle.turnRight()
	return ok
end

-- ===============
-- Placement helpers
-- ===============
local using = {
	floor = nil,
	wall = nil,
	ceiling = nil,
	torch = nil,
}

local warnedOut = {
	floor = false,
	wall = false,
	ceiling = false,
	torch = false,
}

local function tryPlaceDownFrom(slot)
	if not slot or not hasItemInSlot(slot) then return false end
	ensureSelect(slot)
	return turtle.placeDown()
end

local function tryPlaceUpFrom(slot)
	if not slot or not hasItemInSlot(slot) then return false end
	ensureSelect(slot)
	return turtle.placeUp()
end

local function tryPlaceFrontFrom(slot)
	if not slot or not hasItemInSlot(slot) then return false end
	ensureSelect(slot)
	return turtle.place()
end

-- Line one wall cell on the left or right at current level (don't dig unless we have the block)
local function lineWallLeft()
	if not using.wall or not hasItemInSlot(using.wall) then return end
	turtle.turnLeft()
	if turtle.detect() then turtle.dig() end
	if tryPlaceFrontFrom(using.wall) then
		stats.wallPlaced = stats.wallPlaced + 1
	end
	turtle.turnRight()
end

local function lineWallRight()
	if not using.wall or not hasItemInSlot(using.wall) then return end
	turtle.turnRight()
	if turtle.detect() then turtle.dig() end
	if tryPlaceFrontFrom(using.wall) then
		stats.wallPlaced = stats.wallPlaced + 1
	end
	turtle.turnLeft()
end

-- Place a torch according to advanced.torchMount at the given lateral offset.
-- Invariant on entry/exit: at leftmost floor position, facing forward.
local function placeTorch(width, height, offsetFromLeft)
	if not using.torch or not hasItemInSlot(using.torch) then return end

	local offset = clamp(offsetFromLeft, 1, width)
	for _ = 2, offset do strafeRightSafe() end

	local placed = false
	if advanced.torchMount == "floor" then
		placed = tryPlaceDownFrom(using.torch)
	else
		-- Wall-mounted: move up to torchHeight-1, face wall, place front
		local th = clamp(advanced.torchHeight or 2, 1, height)
		for _ = 2, th do upSafe() end

		if advanced.torchMount == "left" then
			turtle.turnLeft()
			placed = tryPlaceFrontFrom(using.torch)
			turtle.turnRight()
		else -- "right"
			turtle.turnRight()
			placed = tryPlaceFrontFrom(using.torch)
			turtle.turnLeft()
		end

		-- Return to floor
		for _ = 2, th do downSafe() end
	end

	if placed then stats.torches = stats.torches + 1 end

	-- Return to leftmost
	for _ = 2, offset do strafeLeftSafe() end
end

-- ===============
-- Slice shaping at the current forward position
-- Invariant on entry and exit: at leftmost floor position of the slice, facing forward
-- ===============
local function shapeSlice(width, height, torchPlan)
	width = math.max(1, width)
	height = math.max(1, height)

	-- For each lateral column across the tunnel width
	for x = 1, width do
		-- Floor lining at this x (dig then place your block)
		if using.floor and hasItemInSlot(using.floor) then
			digDownSafe()
			local ok = tryPlaceDownFrom(using.floor)
			if ok then stats.floorPlaced = stats.floorPlaced + 1 end
			if not ok and not warnedOut.floor then
				println("Warning: could not place floor (slot " .. tostring(using.floor) .. ") — will skip further floor placement.")
				warnedOut.floor = true
			end
		end

		-- Clear vertical and line walls; at the top, line ceiling
		for y = 1, height - 1 do
			-- Move up to next interior level, clearing if needed
			if turtle.detectUp() then digUpSafe() end
			upSafe()

			-- Line left wall at this level on leftmost column only
			if x == 1 then lineWallLeft() end

			-- Line right wall at this level on rightmost column only
			if x == width then lineWallRight() end
		end

		-- At the top level now (height-1 above floor). Line ceiling if requested.
		if height > 1 then
			if using.ceiling and hasItemInSlot(using.ceiling) then
				digUpSafe()
				local okc = tryPlaceUpFrom(using.ceiling)
				if okc then stats.ceilingPlaced = stats.ceilingPlaced + 1 end
				if not okc and not warnedOut.ceiling then
					println("Warning: could not place ceiling (slot " .. tostring(using.ceiling) .. ") — will skip further ceiling placement.")
					warnedOut.ceiling = true
				end
			end

			-- Also line walls at the top for x==1 or x==width (if not yet lined at this level)
			if x == 1 then lineWallLeft() end
			if x == width then lineWallRight() end

			-- Return down to floor level for next lateral column
			for _ = 1, height - 1 do downSafe() end
		else
			-- height == 1 case: at floor level only, still line walls at y=0 for x==edges
			if x == 1 then lineWallLeft() end
			if x == width then lineWallRight() end
		end

		-- Move right to the next lateral column (keep facing forward)
		if x < width then strafeRightSafe() end
	end

	-- Place torch (floor) if this slice wants one
	if torchPlan and torchPlan.place and using.torch and hasItemInSlot(using.torch) then
		placeTorch(width, height, torchPlan.offsetFromLeft)
	end

	-- Return to leftmost from rightmost (we're at rightmost if width>1)
	for _ = 1, width - 1 do strafeLeftSafe() end
end

-- ===============
-- Main
-- ===============
local function promptOrArgs(args)
	-- When no CLI args are supplied, interactively prompt the user for configuration.
	if #args > 0 then return args end

	println("Pretty Tunnel Interactive Setup")
	println("Leave blank to accept defaults shown in []")

	local function askNumber(label, default)
		println(label .. " [" .. default .. "]:")
		local raw = read()
		if raw == nil or raw == '' then return tostring(default) end
		return raw
	end

	local function askNumberLoop(label, default, minv, maxv)
		while true do
			local raw = askNumber(label, default)
			local val = tonumber(raw)
			if val and (not minv or val >= minv) and (not maxv or val <= maxv) then
				return tostring(math.floor(val))
			else
				println("Please enter a number" .. (minv and (" >= "..minv) or "") .. (maxv and (" and <= "..maxv) or ""))
			end
		end
	end

	local length = askNumberLoop("Tunnel length (blocks)", 50, 1, 1000000)
	local width = askNumberLoop("Tunnel width", DEFAULT_WIDTH, 1, 16)
	local height = askNumberLoop("Tunnel height", DEFAULT_HEIGHT, 1, 16)
	local torchEvery = askNumberLoop("Torch every N blocks (0=disable)", DEFAULT_TORCH_EVERY, 0, 1000000)

	-- Offer automatic center offset; if blank we'll compute later from width.
	println("Torch lateral offset from left (1..width, blank = auto center):")
	local torchOffset = read()

	-- Torches on floor or on a wall?
	println("Torch mount [floor/left/right] [floor]:")
	local torchMount = read()
	if torchMount == nil or torchMount == '' then torchMount = 'floor' end
	if torchMount ~= 'floor' and torchMount ~= 'left' and torchMount ~= 'right' then
		torchMount = 'floor'
	end
	advanced.torchMount = torchMount

	if torchMount ~= 'floor' then
		local thDefault = 2
		println("Torch height from floor (1..height) [" .. thDefault .. "]:")
		local thRaw = read()
		local th = tonumber(thRaw)
		if not th then th = thDefault end
		advanced.torchHeight = math.max(1, math.min(tonumber(height) or DEFAULT_HEIGHT, math.floor(th)))
	end

	-- Return to start toggle
	println("Return to start when done? [y/N]:")
	local ret = string.lower(read() or '')
	advanced.returnToStart = (ret == 'y' or ret == 'yes')

	-- Progress printing
	println("Show progress every N blocks (0=disable) [10]:")
	local pe = tonumber(read())
	if pe == nil then pe = 10 end
	advanced.progressEvery = math.max(0, math.floor(pe))

	local function askSlot(label)
		while true do
			println(label .. " slot (1-16, blank=skip):")
			local raw = read()
			if raw == nil or raw == '' then return '' end
			local num = tonumber(raw)
			if num and num >= 1 and num <= 16 then
				return tostring(math.floor(num))
			else
				println("Please enter a number between 1 and 16 or leave blank to skip.")
			end
		end
	end
	local floorSlot = askSlot("Floor block")
	local wallSlot = askSlot("Wall block")
	local ceilingSlot = askSlot("Ceiling block")
	local torchSlot = askSlot("Torch item")

	return {length, width, height, torchEvery, torchOffset, floorSlot, wallSlot, ceilingSlot, torchSlot}
end

local function main(args)
	args = promptOrArgs(args)
	if #args < 1 then
		println("Aborted: no configuration provided.")
		return
	end

	local length = clamp(toInt(args[1], 1), 1, 1000000)
	local width = clamp(toInt(args[2], DEFAULT_WIDTH), 1, 16)
	local height = clamp(toInt(args[3], DEFAULT_HEIGHT), 1, 16)
	local torchEvery = clamp(toInt(args[4], DEFAULT_TORCH_EVERY), 0, 1000000)

	-- Torch lateral offset from the left edge (1..width). Default to center when width is odd, left-middle when even.
	local defaultTorchOffset = math.floor((width + 1) / 2)
	local torchOffsetFromLeft = clamp(toInt(args[5], defaultTorchOffset), 1, width)

	using.floor = toInt(args[6], nil)
	using.wall = toInt(args[7], nil)
	using.ceiling = toInt(args[8], nil)
	using.torch = toInt(args[9], nil)

	-- Try to auto-find torch if not specified
	if not using.torch then
		using.torch = findItemSlotByName("torch")
	end

	println(string.format("Tunnel config => L=%d, W=%d, H=%d, torchEvery=%d, torchOffset=%d", length, width, height, torchEvery, torchOffsetFromLeft))
	println(string.format("Slots => floor=%s wall=%s ceiling=%s torch=%s", tostring(using.floor or "-"), tostring(using.wall or "-"), tostring(using.ceiling or "-"), tostring(using.torch or "-")))
	println("Starting excavation…")

	-- Rough fuel estimate per slice:
	--   forward: 1
	--   vertical moves: 2*(height-1)*width
	--   lateral strafe (right then back left): 2*(width-1)
	local perSliceMoves = 1 + 2 * (math.max(0, height - 1)) * width + 2 * (math.max(0, width - 1))
	local estimateFuel = length * perSliceMoves
	if not ensureFuel(estimateFuel) then
		println("Insufficient fuel for estimated work (" .. estimateFuel .. "). The turtle will still attempt to proceed.")
	end

	-- Main loop over tunnel length
	local distance = 0
	-- Pre-line the left wall at y=0 at the very start (the slice will handle per-position). Not required.
	for step = 1, length do
		-- Advance one block forward to the next slice position
		digSafe()
		if not forwardSafe() then
			println("Error: could not move forward at step " .. step .. ". Stopping.")
			return
		end
		distance = distance + 1
		stats.distance = distance

		-- Periodic fuel top-up attempt
		local fl = turtle.getFuelLevel()
		if fl ~= "unlimited" and type(fl) == 'number' and fl < (perSliceMoves * 2) then
			ensureFuel(fl + perSliceMoves * 5)
		end

		-- Decide torch placement for this slice
		local torchPlan = { place = false, offsetFromLeft = torchOffsetFromLeft }
		if torchEvery and torchEvery > 0 and (distance % torchEvery == 0) then
			torchPlan.place = true
		end

		-- Shape this slice
		shapeSlice(width, height, torchPlan)

		-- Progress output
		if advanced.progressEvery and advanced.progressEvery > 0 and (distance % advanced.progressEvery == 0) then
			println(string.format("Progress: %d/%d blocks; torches=%d floor=%d wall=%d ceiling=%d",
				distance, length, stats.torches, stats.floorPlaced, stats.wallPlaced, stats.ceilingPlaced))
		end
	end

	println("Tunnel complete. Final position: at tunnel end, on the left edge, facing forward.")

	-- Return to start if requested
	if advanced.returnToStart then
		turtle.turnLeft(); turtle.turnLeft()
		for _ = 1, length do
			if not forwardSafe() then
				println("Warning: could not fully return to start; path blocked.")
				break
			end
		end
		turtle.turnLeft(); turtle.turnLeft()
		println("Returned to start.")
	end

	-- Summary
	println(string.format("Summary: distance=%d, torches=%d, floor=%d, wall=%d, ceiling=%d",
		stats.distance, stats.torches, stats.floorPlaced, stats.wallPlaced, stats.ceilingPlaced))
end

-- Run
main(PROGRAM_ARGS)
