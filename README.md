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
