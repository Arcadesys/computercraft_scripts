# Arcade wrapper (lib/arcade.lua)

A tiny helper module to standardize three-button arcade machines on CC:Tweaked monitors.

What it gives you:

- Monitor setup and layout for a persistent bottom bar with three buttons (Left, Center, Right)
- Simple drawing helpers for a playfield area (above the buttons)
- Debounced input from monitor_touch/mouse_click/keys, with a small tick loop for animations
- Credit persistence to a disk drive if present (falls back to a local file)

Quick start:

```lua
local arcade = require("lib.arcade")

local game = {
  name = "Demo",
  init = function(a)
    a:setButtons({"Act","+1","Quit"})
  end,
  draw = function(a)
    a:clearPlayfield()
    a:centerPrint(1, "Demo: " .. a:getCredits() .. " credits")
  end,
  onButton = function(a, which)
    if which == "left" then a:consumeCredits(1) end
    if which == "center" then a:addCredits(1) end
    if which == "right" then a:requestQuit() end
  end,
}

arcade.start(game)
```

API cheatsheet:

- a:setButtons({left, center, right}, [enabledTable]) → set button labels and optionally enable/disable (true/false) per slot
- a:enableButton(index, bool) → toggle one button
- a:clearPlayfield([bg], [fg]) → clear the content area
- a:centerPrint(relY, text, [fg], [bg]) → centered line in playfield (relY starts at 1)
- a:getCredits() → integer
- a:addCredits(delta) → add/remove credits; persists automatically
- a:consumeCredits(amount) → boolean success
- a:requestQuit() → exits the arcade loop cleanly

Lua tips:

- Prefer local variables where possible to avoid polluting globals.
- Use tables to pass around a small set of related functions (like the `a` adapter here).
- Guard side-effectful calls (like `require`) with `pcall` when optional.

Notes:

- The module will look for a `drive` peripheral. If a disk is inserted, credits are stored on that disk under `credits.txt` by default. Otherwise, it will use a local file in the game’s working directory.
- Text scale defaults to 0.5 for monitors; override by passing a second table to `arcade.start(game, { textScale = 1.0 })`.
