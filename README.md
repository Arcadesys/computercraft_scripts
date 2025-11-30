# Arcadesys

A unified ComputerCraft repository containing both the ArcadeOS system and the Factory Agent.

## Structure

* **`/arcade`**: ArcadeOS UI, games, and tools.
* **`/factory`**: Autonomous Turtle Agent for building and mining.
* **`/lib`**: Shared libraries used by both systems.
* **`/docs`**: Documentation.

## Installation

Use the single installer entrypoint: `install.lua`.
It pulls the latest Arcadesys installer from GitHub and runs it.
The installer autodetects whether it is running on a turtle or a computer.

## Usage

* **Shared UI**: Both turtles and computers launch `arcadesys_os.lua`, a unified menu that links factory jobs, games, and tools.
* **Factory Designer**: Run `factory_planner.lua` (optionally `--load path/to/schema.json`) for the graphical designer powered by `lib_designer`.

## Building Installers

Legacy per-experience installers can still be produced with the Node scripts below (optional):

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
