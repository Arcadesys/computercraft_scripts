# Arcadesys

A unified ComputerCraft repository containing both the ArcadeOS system and the Factory Agent.

## Structure

* **`/arcade`**: ArcadeOS UI, games, and tools.
* **`/factory`**: Autonomous Turtle Agent for building and mining.
* **`/lib`**: Shared libraries used by both systems.
* **`/docs`**: Documentation.

## Installation

Run `installer.lua` to set up the environment.
The system automatically detects if it is running on a Turtle or a Computer.

For network installs (recommended), use the targeted installers:
- `turtle_os_install.lua` – refreshes/installs the turtle experience
- `arcade_os_install.lua` – refreshes/installs ArcadeOS (button-driven)
- `workstation_install.lua` – refreshes/installs the workstation experience on a computer

## Usage

* **Computers**: Launches ArcadeOS automatically.
* **Turtles**: Launches the Factory Agent automatically.
* **Factory Designer**: Run `factory_planner.lua` (optionally `--load path/to/schema.json`) to open the full graphical designer powered by `lib_designer`.

## Building Installers

1. Ensure Node.js is installed.
2. From the repo root, run:

   ```bash
   node build/turtle_os_install.js
   node build/arcade_os_install.js
   node build/workstation_install.js
   ```

3. Copy the desired installer onto a ComputerCraft computer or turtle (e.g., via `pastebin run` or `wget`).
4. Run it:

   ```lua
   shell.run("<installer>.lua")
   ```

5. It will download the needed Lua files from GitHub for that experience, recreate the folder structure, and report completion.
6. Reboot or run `startup` to launch the appropriate system.
