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
- **MIDI Player** (`midi_player.lua`): Standalone program that parses standard `.mid` files.
  - Place MIDI files under `/midi` (folders are created automatically on first run).
  - Choose a file interactively or pass the path/filename as the first argument.
  - Pick the ComputerCraft instrument for every detected MIDI channel before playback.
  - Supports looping playback via `--loop` or a prompt.

## Installation

1. Copy the `startup.lua` file to the root of your ComputerCraft computer.
2. (Optional) Copy `midi_player.lua` alongside `startup.lua` to enable MIDI playback.
3. Reboot the computer.

## Usage

- **Mouse**: Use the mouse to interact with windows and menus.
- **Shutdown**: Open the Start menu and click "Shutdown" (or the area where it would be).
- **MIDI Player**: Run `midi_player` from the shell. Follow the prompts to select a `.mid` file, map instruments, and choose whether to loop.

## Development

The main logic is in `startup.lua`.

- `windows` table: Defines the initial windows.
- `draw()`: Handles rendering.
- `handleClick()`: Handles mouse interaction.

`midi_player.lua` is a separate script with its own entry point. It includes a lightweight SMF (Standard MIDI File) parser and playback loop for speaker peripherals.
