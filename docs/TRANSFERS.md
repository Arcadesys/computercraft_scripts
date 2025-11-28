Transfer options for schemas (PC ↔ Turtle)

Goal: get saved JSON schema files from your PC environment into a ComputerCraft turtle/computer in-game.

1) Floppy / Disk Drive (sneakernet)
- How it works: The designer saves to `disk/` when a disk is present in the ComputerCraft computer running the designer.
- Workflow:
  - Insert a floppy disk in a disk drive attached to the computer running the designer (the computer that shows the designer UI).
  - The designer will detect `disk/` and save files into that directory. Files will be written to the floppy's filesystem.
  - Remove the floppy and give it to the turtle (place in inventory).
  - On the turtle or another computer with a disk drive, insert the floppy into a disk drive and access the files under `disk/`.
- Notes:
  - Turtles cannot hold a disk drive block themselves, but they can carry floppies in their inventory and interact with a placed disk drive block (e.g., by placing the drive or using peripheral calls after the disk is inserted in the world).

2) Wireless Network (recommended for convenience)
- How it works: The designer can `NetSave` (network send) or we can send files using `network.sendSchema`. A receiver script listens via `rednet` and writes incoming files.
- What I added: `tools/receive_schema.lua` — run this on the turtle or a computer in-game. It opens the wireless modem and listens for incoming schema sends. When it receives a file it saves it to `disk/` (if a floppy is present) or to the local filesystem.
- Usage:
  - Make sure both the sending computer and the receiving turtle/computer have wireless modems.
  - On the turtle/computer that will receive files, copy `tools/receive_schema.lua` into the world and run it: `receive_schema.lua`.
  - In the designer, open the menu and choose `NetSave` (or use the network send path). Select a target device when prompted.
  - The receiver will print a message and save the file.

  Send multiple files (installer payload)
  - You can push a set of files to many devices at once by creating a directory named `install_payload/` next to your project files and placing the files (and subdirectories) you want installed there.
  - Use the sender script `tools/install_sender.lua` on the machine running the designer to scan `install_payload/`, discover devices, and send each file using the existing schema-send message format.
  - On target devices run `tools/receive_schema.lua` (or keep `receive_schema.lua` running). The receiver will save each incoming file with the original relative path.

  *** Usage Example ***
  1. Prepare `install_payload/` with the files to install (paths preserved).
  2. Start the receiver on each turtle/computer you want to install to:

  ```lua
  receive_schema.lua
  ```

  3. On the sender machine (designer/computer), run:

  ```lua
  install_sender.lua
  ```

  The sender will discover devices and send files to each one. The receivers will save files to `disk/` if a floppy is present or to the local filesystem otherwise.

3) HTTP / Pastebin (fallback)
- If you have HTTP enabled in-game, you can host schema files externally and use `shell.run("pastebin get <id> filename")` or `http.get`+`fs.open` to download.
- This needs server hosting and game HTTP access enabled.

Notes and troubleshooting
- If `disk/` is not detected, ensure a floppy is inserted into a disk drive attached to the computer running the designer. Check `fs.list("disk")` at the Lua prompt.
- For wireless, ensure rednet is open: `rednet.open(peripheral.getName(modem))` and modems are wireless (some modems are wired).
- If NetSave doesn't show receivers, run `receive_schema.lua` and keep it running (it broadcasts presence when started). If firewall/tick issues happen, try increasing timeouts in the device discovery.

If you want, I can:
- Add a simple sender CLI (that calls `network.sendSchema`) to make sending files from shells easier.
- Add a turtle-side helper that, when it receives a floppy in its inventory, automatically places it into a nearby disk drive and copies files.
