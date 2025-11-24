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

## Usage

* **Computers**: Launches ArcadeOS automatically.
* **Turtles**: Launches the Factory Agent automatically.

## Building the Installer

1. Ensure Node.js is installed.
2. From the repo root, run:

```bash
node build/bundle.js
```

3. This generates `arcadesys_installer.lua` (~724 KB), a self-contained bundle containing all Lua files.
4. Copy `arcadesys_installer.lua` onto a ComputerCraft computer or turtle.
5. Run it:

```lua
shell.run("arcadesys_installer.lua")
```

6. It will unpack all files, recreate the folder structure, and report completion.
7. Reboot or run `startup` to launch the appropriate system.
