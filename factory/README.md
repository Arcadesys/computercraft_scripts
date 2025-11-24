# Factory Planner

A graphical tool for designing factory layouts on Advanced Computers.

## Features

- **Mouse Control**: Click to paint, right-click to erase.
- **Palette**: Select from a list of predefined items (Stone, Dirt, Turtle, etc.).
- **Copy/Paste**: Copy the entire grid to an internal clipboard and paste it back.
- **Save Schema**: Saves the design to a file (`factory_schema.lua`), automatically targeting a connected Disk Drive if available (`disk/factory_schema.lua`).

## Controls

- **Left Click**: Place selected item.
- **Right Click**: Erase item (set to Air).
- **Click Palette**: Select item to paint.
- **C**: Copy Grid to Clipboard.
- **V**: Paste Grid from Clipboard.
- **S**: Save Schema to Disk.
- **Q**: Quit.

## Schema Format

The saved file is a Lua table with the following structure:

```lua
{
  width = 20,
  height = 15,
  palette = {
    { id = "minecraft:stone", char = "#", color = 128, label = "Stone" },
    -- ...
  },
  grid = {
    [1] = { 1, 1, 2, ... }, -- Row 1 (indices into palette)
    [2] = { ... },
    -- ...
  }
}
```

## Usage

1. Run `factory_planner` on an Advanced Computer.
2. Draw your layout.
3. Insert a Disk into a Disk Drive.
4. Press `S` to save the layout to the disk.
5. Take the disk to a Turtle to execute the layout (requires a separate turtle script).
