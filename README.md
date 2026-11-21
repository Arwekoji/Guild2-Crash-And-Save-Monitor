# The Guild 2: Renaissance — Crash, Sync & Save Monitor

A lightweight, single-file PowerShell/Batch utility designed to protect your progress in **The Guild 2: Renaissance** (including **Reforged** and other mods) against 32-bit 4 GB memory crashes, corrupted saves, and multiplayer desyncs.

*Author: AI*

## Key Features
- **32-Bit Memory Leak Tracker:** Monitors Private Memory usage against the 4096 MB engine limit and calculates a live sliding-window estimate (`~Xh Ym to 3000 MB`) before an out-of-memory crash occurs.
- **Multiplayer Sync Monitor:** Parses `logfile.log` in real time to detect tick desyncs (`|Received - Own|`) before a session freeze.
- **Save Protection & Auto-Backup:** Plays an audio cue on valid saves, skips corrupted/0 KB crash-saves (`< 0.5 MB`), and keeps a rotating history of the last 10 valid saves in `_MonitorBackup`.
- **Universal Cascade Launcher:** Works out-of-the-box with **Steam**, **GOG**, and **Standalone/DRM-free** builds—just double-click `Guild2_Monitor.cmd` instead of your game shortcut.


## Requirements
- **OS:** Windows 10 / Windows 11 (Windows 7 SP1 / 8.1 supported)
- **Dependencies:** None (uses built-in Windows PowerShell 5.1 & .NET Framework)


## Quick Start
1. Download `Guild2_Monitor.cmd` from this repository.
2. Place it anywhere (or inside your game folder) and run it to launch the game and start monitoring automatically.
3. *(Optional)* Open `Guild2_Monitor.cmd` in any text editor to customize thresholds, sound cues, or custom launcher paths in `Section 0`.


## Feedback & Bug Reports
This utility was created with the help of AI and thoroughly tested in long late-game multiplayer sessions (*Reforged*). 

If you run into a bug, layout glitch, or compatibility issue on your setup, feel free to open an **Issue** on GitHub (or leave a comment on Steam). Please include:
- Your game edition / mod (e.g., Steam, GOG, Reforged version)
- A screenshot of the console window or the exact error message

Fixes and updates are maintained on a best-effort basis whenever time permits—and since this is Public Domain (`The Unlicense`), anyone is also welcome to fork or tweak it freely!


## Download (1-Click)
👉 **[Click here to download the latest version of Guild2_Monitor](https://github.com/Arwekoji/Guild2-Crash-And-Save-Monitor/releases/tag/guild-2)**

1. Open the link above and click **`Guild2_Monitor.cmd`** (or the `.zip` archive) under **Assets** at the bottom of the page.
2. Place the file anywhere on your PC (e.g., on your Desktop or inside the game folder).
3. Double-click **`Guild2_Monitor.cmd`** to launch the game and start monitoring!
