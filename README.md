# ComputerCraft Personal OS

This is a simple GUI-based operating system for ComputerCraft, styled after early Windows systems (Windows 95/98).

## Features

- **Desktop Environment**: Classic cyan background.
- **Taskbar**: Located at the bottom with a Start button.
- **Window Management**:
  - Drag windows by the title bar.
  - Close windows with the 'X' button.
  - Click a window to bring it to the front.
- **Start Menu**: Click "Start" to open. Includes a "Shutdown" option.
- **Sequencer**: A built-in 4-track, 16-step sequencer.
  - Each track can target any vanilla note block instrument.
  - Select steps to adjust pitch (0-24) and note length (1-8 steps).
  - Click steps to toggle them on/off; right-click to select without toggling.
  - Plays through an attached speaker peripheral with per-step indicators.

## Installation

1. Copy the `startup.lua` file to the root of your ComputerCraft computer.
2. Reboot the computer.

## Usage

- **Mouse**: Use the mouse to interact with windows and menus.
- **Shutdown**: Open the Start menu and click "Shutdown" (or the area where it would be).

## Development

The main logic is in `startup.lua`.

- `windows` table: Defines the initial windows.
- `draw()`: Handles rendering.
- `handleClick()`: Handles mouse interaction.
