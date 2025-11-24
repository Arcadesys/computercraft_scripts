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

## Bundler

Run `node build/bundle.js` from the repo root to generate `arcadesys_installer.lua`. Copy that single Lua file onto a ComputerCraft computer or turtle and run it to unpack the entire suite.
