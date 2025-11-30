# ComputerCraft installer

This folder contains `@install.lua`, a ComputerCraft-friendly installer that pulls programs directly from [`Arcadesys/computercraft_scripts`](https://github.com/Arcadesys/computercraft_scripts).

## Usage

Download `@install.lua` to your ComputerCraft computer (for example via the raw GitHub URL for this file) and run it:

```
wget https://raw.githubusercontent.com/<owner>/<repo>/main/tools/computercraft/%40install.lua @install.lua
@install.lua
```

Arguments can override the defaults if you want to point at a different fork or branch:

```
@install.lua <owner> <repo> [branch] [subdirectory]
```

- **owner**: GitHub owner (default `Arcadesys`)
- **repo**: Repository name (default `computercraft_scripts`)
- **branch**: Branch to install from (default `main`)
- **subdirectory**: Optional subdirectory inside the repo to restrict installations
