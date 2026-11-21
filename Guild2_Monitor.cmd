<# :
@echo off
title The Guild 2 Monitor
set "SCRIPT_PATH=%~f0"
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:SCRIPT_PATH, [System.Text.Encoding]::UTF8))"
pause
exit /b
#>

# ==============================================================================
# THE GUILD 2: RENAISSANCE - REAL-TIME SESSION & SAVE MONITOR
# Author: Made by AI
# ==============================================================================
# DESCRIPTION:
# A lightweight, zero-dependency external monitoring utility for The Guild 2:
# Renaissance (supports Steam, GOG, standalone builds, and mods like Reforged).
# Designed to protect long singleplayer and multiplayer sessions from 32-bit
# memory limit crashes (4 GB cap), network desyncs, and corrupted save files.
#
# HOW TO USE:
# 1. Place this .cmd file anywhere (e.g., on your Desktop or inside the game
#    folder) and double-click it to launch.
# 2. The script automatically detects and launches your game (via running
#    process, custom shortcut, local folder, Steam library, or fallback path).
# 3. After 1 minute, the monitor window briefly pops up over the game to
#    confirm tracking, then stays silently in the background.
# 4. Audio cues let you play on a single monitor without alt-tabbing:
#    - Rising double-beep (1000 -> 1200 Hz): Save succeeded & backed up.
#    - Falling double-beep (1000 -> 400 Hz): Corrupted/0 KB save detected!
#    - High beep (800 Hz): Critical memory warning (save & restart soon).
#    - Mid beep (600 Hz): Multiplayer network sync load warning.
#    - Long low beep (350 Hz): Game crashed unexpectedly.
# 5. All thresholds, paths, and backup limits can be customized in Section 0.
# ==============================================================================

# ==============================================================================
# SYSTEM REQUIREMENTS & COMPATIBILITY
# ==============================================================================
# - OS:           Windows 10 / Windows 11 (also works on Windows 7 SP1 / 8.1)
# - Runtime:      Built-in Windows PowerShell 5.1 & .NET Framework 4.5+
#                 (pre-installed in Windows 10/11, no external software needed)
# - Console:      Classic Windows Console (conhost.exe) & Windows Terminal
# - Permissions:  Standard user rights (Run as Administrator only if the game
#                 is installed inside protected 'C:\Program Files (x86)\')
# - Game Builds:  Compatible with all editions & mods (Steam, GOG, Retail,
#                 Standalone/DRM-free, Reforged, Fajeth's MegaMod, etc.)
# ==============================================================================

#region 0. CONFIGURATION (USER SETTINGS)
# ==============================================================================
$ProcessName          = "GuildII"
$SteamAppId           = "39680"
$SteamAppUri          = "steam://rungameid/$SteamAppId"

# Custom launch & paths (leave "" to use automatic cascade detection)
$LauncherShortcutPath = ""        # Path to your custom shortcut (.lnk / .url), launcher (.exe), or .bat file
$LaunchCommandArgs    = ""        # Extra command-line arguments (e.g., "-windowed")
$CustomSavesFolder    = ""        # Manual path to your savegames folder (highest priority)
$CustomGameDir        = "D:\Steam\steamapps\common\The Guild 2 Renaissance" # Fallback game directory

# Alert & warning thresholds
$WarningMB            = 3000      # Private Memory threshold (in MB) for critical alert (32-bit 4 GB cap protection)
$SessionWarnMin       = 120       # Session duration threshold in minutes (2 hours = 120 min)
$BaselineMinutes      = 1         # Delay in minutes before starting leak tracking and bringing window to front
$LeakWindowMinutes    = 10        # Sliding window (in minutes) used to calculate current memory leak rate
$SaveGreenSec         = 60        # Duration in seconds a save is highlighted as fresh (green)
$SaveYellowMin        = 15        # Minutes without a save (within current session) before yellow warning triggers
$SaveCorruptGrace     = 10        # Grace period in seconds to wait for save write completion before flagging as broken
$SyncWarnDelta        = 5000      # Tick delta threshold (Received - Own) for multiplayer sync alert

# Audio notification settings
$SaveBeepGapMs        = 120       # Pause in milliseconds between the two save confirmation beeps
$AlertCooldownSec     = 3         # Minimum cooldown (in seconds) between repeating critical alert beeps

# Auto-backup settings
$EnableBackup         = $true     # Enable ($true) or disable ($false) automatic savegame backups
$MinValidSaveMB       = 0.5       # Minimum valid save file size in MB (protects backups from 0 KB crash saves)
$MaxBackups           = 10        # Maximum number of recent backup copies to keep

# Technical loop & console window parameters
$RefreshSec           = 1         # Screen refresh interval in seconds
$MinProcessMB         = 150MB     # Minimum working set size to ignore Steam launcher stub processes
$WinWidth             = 86        # Console window width (in characters)
$WinHeight            = 19        # Console window height (in lines)
$BoxInnerWidth        = 80        # Inner text width inside UI boxes
#endregion

#region 1. CONSOLE & VIRTUAL FRAME ENGINE (UI & WinAPI)
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($WinWidth, $WinHeight)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size($WinWidth, $WinHeight)
} catch {}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinFocus {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@ -ErrorAction SilentlyContinue

function Disable-ConsoleQuickEdit {
    try {
        $STD_INPUT_HANDLE       = -10
        $ENABLE_QUICK_EDIT_MODE = 0x0040
        $ENABLE_EXTENDED_FLAGS  = 0x0080
        $handle = [WinFocus]::GetStdHandle($STD_INPUT_HANDLE)
        $mode   = [uint32]0
        if ([WinFocus]::GetConsoleMode($handle, [ref]$mode)) {
            $mode = ($mode -band (-bnot $ENABLE_QUICK_EDIT_MODE)) -bor $ENABLE_EXTENDED_FLAGS
            [WinFocus]::SetConsoleMode($handle, $mode) | Out-Null
        }
    } catch {}
}

function Bring-ConsoleToFront {
    try {
        $hwnd = [WinFocus]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            [WinFocus]::ShowWindow($hwnd, 9) | Out-Null
            [WinFocus]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x0003) | Out-Null
            [WinFocus]::SetWindowPos($hwnd, [IntPtr](-2), 0, 0, 0, 0, 0x0003) | Out-Null
            [WinFocus]::SetForegroundWindow($hwnd) | Out-Null
        }
    } catch {}
}

function Sanitize-Text {
    param([string]$InputText)
    if ($null -eq $InputText) { return "" }
    return ($InputText -replace '[\x00-\x1F\x7F\uFFFD]', ' ')
}

function Format-CompactPath {
    param([string]$FullPath, [int]$MaxLen)
    $clean = Sanitize-Text $FullPath
    if ($clean.Length -le $MaxLen) { return $clean }
    if ($MaxLen -lt 10) { return $clean.Substring(0, $MaxLen) }
    $prefix  = if ($clean.Length -ge 3 -and $clean[1] -eq ':') { $clean.Substring(0, 3) } else { "" }
    $tailLen = $MaxLen - $prefix.Length - 3
    if ($tailLen -le 0) { return $clean.Substring(0, $MaxLen) }
    return ($prefix + "..." + $clean.Substring($clean.Length - $tailLen))
}

function New-FrameRow {
    param([array]$Segments, [int]$TotalWidth = 84)
    $cleanSegs = @()
    $used = 0
    foreach ($seg in $Segments) {
        $txt = Sanitize-Text ([string]$seg.Text)
        $col = if ($seg.Color) { $seg.Color } else { "Gray" }
        $rem = $TotalWidth - $used
        if ($rem -le 0) { break }
        if ($txt.Length -gt $rem) { $txt = $txt.Substring(0, $rem) }
        if ($txt.Length -gt 0) {
            $cleanSegs += @{ Text = $txt; Color = $col }
            $used += $txt.Length
        }
    }
    $pad = [math]::Max(0, $TotalWidth - $used)
    if ($pad -gt 0) {
        $cleanSegs += @{ Text = (" " * $pad); Color = "Gray" }
    }
    return ,$cleanSegs
}

function New-BoxTopRow {
    param([string]$Title, [int]$InnerWidth)
    $cleanTitle = Sanitize-Text $Title
    $prefix     = "┌─ "
    $suffix     = " "
    $dashCount  = [math]::Max(1, $InnerWidth + 3 - $prefix.Length - $cleanTitle.Length - $suffix.Length)
    return @(
        @{ Text = $prefix; Color = "DarkGray" },
        @{ Text = $cleanTitle; Color = "White" },
        @{ Text = ($suffix + ("─" * $dashCount) + "┐"); Color = "DarkGray" }
    )
}

function New-BoxLineRow {
    param([array]$Segments, [int]$InnerWidth)
    $rowSegs = @(@{ Text = "│ "; Color = "DarkGray" })
    $used = 0
    foreach ($seg in $Segments) {
        $txt = Sanitize-Text ([string]$seg.Text)
        $col = if ($seg.Color) { $seg.Color } else { "Gray" }
        $rem = $InnerWidth - $used
        if ($rem -le 0) { break }
        if ($txt.Length -gt $rem) { $txt = $txt.Substring(0, $rem) }
        if ($txt.Length -gt 0) {
            $rowSegs += @{ Text = $txt; Color = $col }
            $used += $txt.Length
        }
    }
    $pad = [math]::Max(0, $InnerWidth - $used)
    $rowSegs += @{ Text = ((" " * $pad) + " │"); Color = "DarkGray" }
    return ,$rowSegs
}

function New-BoxBottomRow {
    param([int]$InnerWidth)
    return @(@{ Text = ("└" + ("─" * ($InnerWidth + 2)) + "┘"); Color = "DarkGray" })
}

function Render-VirtualFrame {
    param([array]$Rows)
    [Console]::SetCursorPosition(0, 0)
    foreach ($row in $Rows) {
        foreach ($seg in $row) {
            Write-Host $seg.Text -ForegroundColor $seg.Color -NoNewline
        }
        Write-Host ""
    }
}
#endregion

#region 2. CASCADE LAUNCHER & PATH RESOLVER
# ==============================================================================
function Find-SteamLibraryFolder {
    param([string]$ExeName)
    try {
        $steamReg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($steamReg -and $steamReg.SteamPath) {
            $steamRoot = $steamReg.SteamPath -replace '/', '\'
            $libs = @($steamRoot)
            $vdfPath = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
            if (Test-Path $vdfPath) {
                $vdfContent = Get-Content -Path $vdfPath -Raw -ErrorAction SilentlyContinue
                $matches = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
                foreach ($m in $matches) {
                    $libPath = $m.Groups[1].Value -replace '\\', '\'
                    if ($libPath -and ($libs -notcontains $libPath)) {
                        $libs += $libPath
                    }
                }
            }
            foreach ($lib in $libs) {
                $candidate = Join-Path $lib "steamapps\common\The Guild 2 Renaissance"
                if (Test-Path (Join-Path $candidate "$ExeName.exe")) {
                    return $candidate
                }
            }
        }
    } catch {}
    return $null
}

function Find-Guild2Directory {
    param([string]$FallbackDir, [string]$ExeName, [string]$ShortcutPath)

    $running = Get-Process -Name $ExeName -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
    if ($running -and $running.Path) {
        return @{ Dir = (Split-Path -Parent $running.Path); Mode = "Running" }
    }

    if ($ShortcutPath -and (Test-Path $ShortcutPath)) {
        if ($ShortcutPath -like "*.url") {
            $steamDir = Find-SteamLibraryFolder -ExeName $ExeName
            if ($steamDir) {
                return @{ Dir = $steamDir; Mode = "Shortcut" }
            }
        } else {
            $resolvedTarget = $ShortcutPath
            if ($ShortcutPath -like "*.lnk") {
                try {
                    $wsh = New-Object -ComObject WScript.Shell
                    $lnk = $wsh.CreateShortcut($ShortcutPath)
                    if ($lnk.TargetPath -and (Test-Path $lnk.TargetPath)) {
                        $resolvedTarget = $lnk.TargetPath
                    }
                } catch {}
            }
            $targetDir = Split-Path -Parent $resolvedTarget
            if ($targetDir -and (Test-Path (Join-Path $targetDir "$ExeName.exe"))) {
                return @{ Dir = $targetDir; Mode = "Shortcut" }
            }
        }
    }

    $scriptDir = if ($env:SCRIPT_DIR) { $env:SCRIPT_DIR.TrimEnd('\') } else { "" }
    if ($scriptDir -and (Test-Path (Join-Path $scriptDir "$ExeName.exe"))) {
        return @{ Dir = $scriptDir; Mode = "Folder" }
    }

    $steamDetected = Find-SteamLibraryFolder -ExeName $ExeName
    if ($steamDetected) {
        return @{ Dir = $steamDetected; Mode = "Steam" }
    }

    if ($FallbackDir -and (Test-Path (Join-Path $FallbackDir "$ExeName.exe"))) {
        return @{ Dir = $FallbackDir; Mode = "Custom" }
    }

    return @{ Dir = $null; Mode = "Manual" }
}

function Resolve-SaveDirectory {
    param([string]$RootGameDir, [string]$ManualSaveDir)
    if ($ManualSaveDir -and $ManualSaveDir.Trim() -ne "") {
        return $ManualSaveDir.Trim()
    }
    if ($RootGameDir) {
        $moddedPath = Join-Path $RootGameDir "savegames\modded\Reforged"
        if (Test-Path $moddedPath) { return $moddedPath }

        $rootSavePath = Join-Path $RootGameDir "savegames"
        if (Test-Path $rootSavePath) { return $rootSavePath }
    }
    $docSavePath = Join-Path $env:USERPROFILE "Documents\The Guild 2 Renaissance\SaveGames"
    if (Test-Path $docSavePath) { return $docSavePath }

    if ($RootGameDir) { return (Join-Path $RootGameDir "savegames\modded\Reforged") }
    return $docSavePath
}

Disable-ConsoleQuickEdit
[Console]::CursorVisible = $false
Clear-Host

$foundInfo      = Find-Guild2Directory -FallbackDir $CustomGameDir -ExeName $ProcessName -ShortcutPath $LauncherShortcutPath
$GameDir        = $foundInfo.Dir
$LaunchVersion  = $foundInfo.Mode
$alreadyRunning = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.WorkingSet64 -gt $MinProcessMB }

if (-not $alreadyRunning) {
    if ($LauncherShortcutPath -and (Test-Path $LauncherShortcutPath)) {
        $LaunchVersion = "Shortcut"
        Write-Host "Launching custom shortcut/launcher: $LauncherShortcutPath" -ForegroundColor Cyan
        if ($LaunchCommandArgs -and $LaunchCommandArgs.Trim() -ne "" -and ($LauncherShortcutPath -notlike "*.url")) {
            Start-Process -FilePath $LauncherShortcutPath -ArgumentList $LaunchCommandArgs
        } else {
            Start-Process -FilePath $LauncherShortcutPath
        }
    } elseif ($GameDir) {
        $exePath  = Join-Path $GameDir "$ProcessName.exe"
        $steamApi = Join-Path $GameDir "steam_api.dll"
        $steamOn  = Get-Process -Name "steam" -ErrorAction SilentlyContinue

        if ((Test-Path $steamApi) -and $steamOn -and (-not $LaunchCommandArgs)) {
            Write-Host "Found Steam build ($LaunchVersion) at: $GameDir" -ForegroundColor DarkGray
            Write-Host "Starting The Guild 2 via Steam..." -ForegroundColor Cyan
            Start-Process $SteamAppUri
        } else {
            if ($LaunchVersion -eq "Steam") { $LaunchVersion = "Standalone" }
            Write-Host "Found standalone build ($LaunchVersion) at: $GameDir" -ForegroundColor DarkGray
            Write-Host "Launching $ProcessName.exe directly..." -ForegroundColor Cyan
            if ($LaunchCommandArgs -and $LaunchCommandArgs.Trim() -ne "") {
                Start-Process -FilePath $exePath -WorkingDirectory $GameDir -ArgumentList $LaunchCommandArgs
            } else {
                Start-Process -FilePath $exePath -WorkingDirectory $GameDir
            }
        }
    } else {
        $LaunchVersion = "Manual"
        Write-Host "Game folder not auto-detected. Please launch $ProcessName.exe manually..." -ForegroundColor Yellow
    }
} else {
    $LaunchVersion = "Running"
    Write-Host "Attaching to already running $ProcessName.exe..." -ForegroundColor Cyan
}

Write-Host "Waiting for main $ProcessName.exe process..." -ForegroundColor Yellow

while ($true) {
    $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.WorkingSet64 -gt $MinProcessMB }
    if ($p) {
        if (-not $GameDir -and $p.Path) {
            $GameDir = Split-Path -Parent $p.Path
        }
        break
    }
    Start-Sleep -Seconds 1
}

$SaveDir   = Resolve-SaveDirectory -RootGameDir $GameDir -ManualSaveDir $CustomSavesFolder
$BackupDir = Join-Path $SaveDir "_MonitorBackup"
$LogFile   = if ($GameDir) { Join-Path $GameDir "logfile.log" } else { "" }

Clear-Host
#endregion

#region 3. SESSION STATE INITIALIZATION
# ==============================================================================
$TrackedProc      = $null
$SessionStartTime = Get-Date
$LastGameRound    = "None"
$MemHistory       = New-Object System.Collections.Generic.List[PSObject]
$PopupShown       = $false
$LastAlertBeep    = (Get-Date).AddMinutes(-10)
$SeenSaveKeys     = New-Object System.Collections.Generic.HashSet[string]
$BackupStatusText = "Backup: Ready"
$BackupStatusCol  = "DarkGray"
$LastFrameRows    = 15

if (Test-Path $SaveDir) {
    $existingSaves = Get-ChildItem -Path $SaveDir -Filter "*.wld" -File -ErrorAction SilentlyContinue
    foreach ($s in $existingSaves) {
        [void]$SeenSaveKeys.Add("$($s.Name)_$($s.LastWriteTime.Ticks)")
    }
}
#endregion

#region 4. MAIN MONITORING LOOP
# ==============================================================================
while ($true) {
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
            Sort-Object PrivateMemorySize64 -Descending |
            Select-Object -First 1
    
    if ($proc -and -not $proc.HasExited -and $proc.PrivateMemorySize64 -gt 50MB) {
        try {
            if (-not $TrackedProc -or $TrackedProc.Id -ne $proc.Id) {
                $TrackedProc = $proc
                $SessionStartTime = $proc.StartTime
                try { $null = $TrackedProc.Handle } catch {}
            }

            $now = Get-Date
            $uptime = $now - $proc.StartTime
            $hours = [int][math]::Floor([math]::Max(0, $uptime.TotalHours))
            $uptimeStr = "{0:D2}:{1:D2}:{2:D2}" -f $hours, [math]::Max(0, $uptime.Minutes), [math]::Max(0, $uptime.Seconds)
            
            $ramMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
            $privateMB = [math]::Round($proc.PrivateMemorySize64 / 1MB, 1)

            $leakSuffix  = ""
            $baselineSec = $BaselineMinutes * 60

            if ($uptime.TotalSeconds -ge $baselineSec) {
                if (-not $PopupShown) {
                    $PopupShown = $true
                    Bring-ConsoleToFront
                }

                $MemHistory.Add([PSCustomObject]@{ Time = $now; Mem = $privateMB })
                $cutoff = $now.AddMinutes(-$LeakWindowMinutes)
                while ($MemHistory.Count -gt 2 -and $MemHistory[0].Time -lt $cutoff) {
                    $MemHistory.RemoveAt(0)
                }

                $windowSpanMin = ($now - $MemHistory[0].Time).TotalMinutes
                if ($windowSpanMin -ge 0.25) {
                    $leakedMB = $privateMB - $MemHistory[0].Mem
                    $ratePerMin = $leakedMB / $windowSpanMin
                    $remainMB = $WarningMB - $privateMB

                    if ($remainMB -le 0) {
                        $leakSuffix = "(Memory limit reached!)"
                    } elseif ($ratePerMin -gt 0.5) {
                        $minsLeft = [int][math]::Floor($remainMB / $ratePerMin)
                        $hLeft = [int][math]::Floor($minsLeft / 60)
                        $mLeft = $minsLeft % 60
                        if ($hLeft -gt 0) {
                            $leakSuffix = "(~${hLeft}h ${mLeft}m to ${WarningMB} MB)"
                        } else {
                            $leakSuffix = "(~${mLeft}m to ${WarningMB} MB)"
                        }
                    } else {
                        $leakSuffix = "(Memory stable)"
                    }
                }
            }

            $syncAlert = $false
            $syncText  = "Singleplayer / Waiting for MP data"
            $syncCol   = "DarkGray"

            if ($LogFile -and (Test-Path $LogFile)) {
                try {
                    $fs = [System.IO.File]::Open($LogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $readLen = [math]::Min($fs.Length, 16384)
                    if ($readLen -gt 0) {
                        $fs.Seek(-$readLen, [System.IO.SeekOrigin]::End) | Out-Null
                        $buf = New-Object byte[] $readLen
                        $null = $fs.Read($buf, 0, $readLen)
                        $tailText = [System.Text.Encoding]::UTF8.GetString($buf)
                        $tailLines = @($tailText -split "`r?`n")

                        $roundLine = $tailLines | Where-Object { $_ -match "(?:Current\s+round|Round)\s*:\s*(\d+)" } | Select-Object -Last 1
                        if ($roundLine -and ($roundLine -match "(?:Current\s+round|Round)\s*:\s*(?<rnd>\d+)")) {
                            $LastGameRound = $Matches['rnd']
                        }

                        # Register latest available tick delta without false stuck-tick alerts
                        $lastSyncLine = $tailLines | Where-Object { $_ -like "*SyncLogger*Received*Own:*" } | Select-Object -Last 1
                        if ($lastSyncLine -and ($lastSyncLine -match "Received\s+(?<recv>-?\d+)\s+Own:\s+(?<own>-?\d+)")) {
                            $recvTick = [long]$Matches['recv']
                            $ownTick  = [long]$Matches['own']
                            $delta    = [math]::Abs($recvTick - $ownTick)

                            if ($delta -ge $SyncWarnDelta) {
                                $syncText  = "{0} ticks (Own: {1}) [HIGH SYNC LOAD]" -f $delta, $ownTick
                                $syncCol   = "Red"
                                $syncAlert = $true
                            } else {
                                $syncText  = "{0} ticks (Own: {1}) [OK]" -f $delta, $ownTick
                                $syncCol   = "Green"
                            }
                        }
                    }
                    $fs.Close()
                    $fs.Dispose()
                } catch {
                    $syncText = "Log read busy..."
                }
            } else {
                $syncText = "logfile.log not found"
            }

            $saveDirMissing  = $false
            $saveWarnFlag    = $false
            $saveBrokenFlag  = $false
            $saveWritingFlag = $false
            $lastSave        = $null

            if ($SaveDir -and (Test-Path $SaveDir)) {
                $lastSave = Get-ChildItem -Path $SaveDir -Filter "*.wld" -File -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending |
                            Select-Object -First 1
                if ($lastSave) {
                    $preAgeSec = [math]::Max(0, ($now - $lastSave.LastWriteTime).TotalSeconds)
                    $preSizeMB = [math]::Round($lastSave.Length / 1MB, 2)

                    $refTime = if ($lastSave.LastWriteTime -gt $SessionStartTime) { $lastSave.LastWriteTime } else { $SessionStartTime }
                    $sessionNoSaveMin = [int][math]::Floor([math]::Max(0, ($now - $refTime).TotalMinutes))

                    if ($preSizeMB -lt $MinValidSaveMB) {
                        if ($preAgeSec -ge $SaveCorruptGrace) {
                            $saveBrokenFlag = $true
                        } else {
                            $saveWritingFlag = $true
                        }
                    } elseif ($sessionNoSaveMin -ge $SaveYellowMin) {
                        $saveWarnFlag = $true
                    }
                } else {
                    $sessionNoSaveMin = [int][math]::Floor([math]::Max(0, ($now - $SessionStartTime).TotalMinutes))
                    if ($sessionNoSaveMin -ge $SaveYellowMin) {
                        $saveWarnFlag = $true
                    }
                }
            } else {
                $saveDirMissing = $true
            }

            $memAlert    = ($privateMB -ge $WarningMB)
            $sessionWarn = ($uptime.TotalMinutes -ge $SessionWarnMin)
            $canBeep     = (($now - $LastAlertBeep).TotalSeconds -ge $AlertCooldownSec)

            if ($memAlert) {
                $alertText = "CRITICAL: MEMORY >= $WarningMB MB"
                $alertCol  = "Red"
                if ($canBeep) {
                    [console]::beep(800, 300)
                    $LastAlertBeep = $now
                }
            } elseif ($syncAlert) {
                $alertText = "ALERT: NETWORK SYNC OVERLOAD"
                $alertCol  = "Red"
                if ($canBeep) {
                    [console]::beep(600, 300)
                    $LastAlertBeep = $now
                }
            } else {
                $alertText = "OK"
                $alertCol  = "Green"
            }

            $warns = @()
            if ($saveBrokenFlag) { $warns += "BROKEN SAVE" }
            if ($saveDirMissing) { $warns += "SAVE DIR MISSING" }
            if ($sessionWarn)    { $warns += "RESTART RECOMMENDED" }
            if ($saveWarnFlag)   { $warns += "SAVE > ${SaveYellowMin}m AGO" }

            $stPrefix   = "Status: "
            $availWidth = 84 - ($stPrefix.Length + $alertText.Length + 1)

            if ($warns.Count -gt 0) {
                $fullWarn = "(" + ($warns -join ", ") + ")"
                if ($fullWarn.Length -le $availWidth) {
                    $warnText = $fullWarn
                } elseif ($warns.Count -gt 1) {
                    $warnText = "($($warns[0]) +$($warns.Count - 1))"
                } else {
                    $warnText = "($($warns[0]))"
                }
                $warnCol = "Yellow"
            } else {
                $warnText = "(NO_WARNING)"
                $warnCol  = "DarkGray"
            }

            $frame = New-Object System.Collections.Generic.List[PSObject]

            $hasSteamApi = ($GameDir -and (Test-Path (Join-Path $GameDir "steam_api.dll")))
            $titleParts = @("$ProcessName.exe", "PID: $($proc.Id)")
            if ($hasSteamApi) { $titleParts += "SteamID: $SteamAppId" }
            $titleParts += "Ver: $LaunchVersion"
            $titleParts += "Round: $LastGameRound"
            $titleLine = $titleParts -join " | "

            $frame.Add((New-FrameRow -Segments @(@{ Text = $titleLine; Color = "Cyan" })))
            $frame.Add((New-FrameRow -Segments @(
                @{ Text = $stPrefix; Color = "Gray" },
                @{ Text = "$alertText "; Color = $alertCol },
                @{ Text = $warnText; Color = $warnCol }
            )))
            $frame.Add((New-FrameRow -Segments @()))

            $frame.Add((New-BoxTopRow -Title "CRITICAL MEASURES" -InnerWidth $BoxInnerWidth))

            $timeColor = if ($sessionWarn) { "Red" } else { "Green" }
            $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                @{ Text = "Session Time:   "; Color = "Gray" },
                @{ Text = "$uptimeStr "; Color = $timeColor },
                @{ Text = $leakSuffix; Color = "DarkGray" }
            )))

            $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                @{ Text = "Private Memory: $privateMB MB / 4096 MB "; Color = "Gray" },
                @{ Text = "(Active RAM: $ramMB MB)"; Color = "DarkGray" }
            )))

            $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                @{ Text = "Sync Status:    "; Color = "Gray" },
                @{ Text = $syncText; Color = $syncCol }
            )))

            $frame.Add((New-BoxBottomRow -InnerWidth $BoxInnerWidth))
            $frame.Add((New-FrameRow -Segments @()))

            $frame.Add((New-BoxTopRow -Title "SAVE DATA" -InnerWidth $BoxInnerWidth))

            if (-not $saveDirMissing) {
                if ($lastSave) {
                    $ageSec  = [int][math]::Round([math]::Max(0, ($now - $lastSave.LastWriteTime).TotalSeconds))
                    $sizeMB  = [math]::Round($lastSave.Length / 1MB, 2)
                    $timeStr = $lastSave.LastWriteTime.ToString("HH:mm:ss")
                    $currKey = "$($lastSave.Name)_$($lastSave.LastWriteTime.Ticks)"

                    if ($saveWritingFlag) {
                        $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                            @{ Text = "[WRITING SAVE...] $($lastSave.Name) ($sizeMB MB) at $timeStr"; Color = "DarkGray" }
                        )))
                    } else {
                        if ($SeenSaveKeys.Add($currKey)) {
                            if ($sizeMB -ge $MinValidSaveMB) {
                                [console]::beep(1000, 100)
                                Start-Sleep -Milliseconds $SaveBeepGapMs
                                [console]::beep(1200, 120)

                                if ($EnableBackup) {
                                    if (-not (Test-Path $BackupDir)) {
                                        New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
                                    }
                                    $stamp = $lastSave.LastWriteTime.ToString("yyyyMMdd_HHmmss")
                                    $bkpName = "{0}_{1}.wld" -f $lastSave.BaseName, $stamp
                                    Copy-Item -Path $lastSave.FullName -Destination (Join-Path $BackupDir $bkpName) -Force -ErrorAction SilentlyContinue

                                    Get-ChildItem -Path $BackupDir -Filter "*.wld" -File -ErrorAction SilentlyContinue |
                                        Sort-Object LastWriteTime -Descending |
                                        Select-Object -Skip $MaxBackups |
                                        Remove-Item -Force -ErrorAction SilentlyContinue

                                    $BackupStatusText = "Backup OK: $bkpName ($sizeMB MB)"
                                    $BackupStatusCol  = "DarkGreen"
                                }
                            } else {
                                [console]::beep(1000, 100)
                                Start-Sleep -Milliseconds 100
                                [console]::beep(400, 250)

                                $BackupStatusText = "[CORRUPTED SAVE DETECTED! $sizeMB MB - BACKUP SKIPPED!]"
                                $BackupStatusCol  = "Red"
                            }
                        }

                        $ageMin = [int][math]::Floor($ageSec / 60)
                        if ($ageMin -lt 60) {
                            $ageLabel = "${ageMin}m ago"
                        } elseif ($ageMin -lt 1440) {
                            $h = [int][math]::Floor($ageMin / 60)
                            $m = $ageMin % 60
                            $ageLabel = "${h}h ${m}m ago"
                        } else {
                            $d = [int][math]::Floor($ageMin / 1440)
                            $h = [int][math]::Floor(($ageMin % 1440) / 60)
                            $ageLabel = "${d}d ${h}h ago"
                        }

                        if ($saveBrokenFlag) {
                            $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                                @{ Text = "[BROKEN SAVE!] $($lastSave.Name) ($sizeMB MB) at $timeStr"; Color = "Red" }
                            )))
                        } elseif ($ageSec -le $SaveGreenSec) {
                            $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                                @{ Text = "[SAVED ${ageSec}s AGO] $($lastSave.Name) ($sizeMB MB) at $timeStr"; Color = "Green" }
                            )))
                        } elseif (-not $saveWarnFlag) {
                            $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                                @{ Text = "[LAST SAVE] $($lastSave.Name) ($sizeMB MB) at $timeStr [$ageLabel]"; Color = "Gray" }
                            )))
                        } else {
                            $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                                @{ Text = "[LAST SAVE] $($lastSave.Name) ($sizeMB MB) at $timeStr "; Color = "Gray" },
                                @{ Text = "[$ageLabel]"; Color = "Yellow" }
                            )))
                        }
                    }

                    if ($EnableBackup) {
                        $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                            @{ Text = $BackupStatusText; Color = $BackupStatusCol }
                        )))
                    } else {
                        $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                            @{ Text = "Backup: Disabled in settings"; Color = "DarkGray" }
                        )))
                    }
                } else {
                    $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                        @{ Text = "[NO .WLD FILES FOUND IN SAVE FOLDER]"; Color = "DarkYellow" }
                    )))
                    $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @()))
                }
            } else {
                $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                    @{ Text = "[ERROR] Save folder not found"; Color = "Red" }
                )))
                $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @()))
            }

            $dispDir = Format-CompactPath -FullPath $SaveDir -MaxLen ($BoxInnerWidth - 9)
            $frame.Add((New-BoxLineRow -InnerWidth $BoxInnerWidth -Segments @(
                @{ Text = "SaveDir: $dispDir"; Color = "DarkGray" }
            )))

            $frame.Add((New-BoxBottomRow -InnerWidth $BoxInnerWidth))

            $LastFrameRows = $frame.Count
            Render-VirtualFrame -Rows $frame
        } catch {
            [Console]::SetCursorPosition(0, 0)
            Write-Host (Sanitize-Text ("Monitor tick error: " + $_.Exception.Message)).PadRight(84).Substring(0, 84) -ForegroundColor Red
        }
    } else {
        #region 5. SHUTDOWN & POST-MORTEM
        # ======================================================================
        $isCrash = $false
        if ($TrackedProc) {
            try {
                $TrackedProc.Refresh()
                if ($TrackedProc.HasExited -and ($null -ne $TrackedProc.ExitCode) -and ($TrackedProc.ExitCode -ne 0)) {
                    $isCrash = $true
                }
            } catch {}
        }

        if (-not $isCrash -and $GameDir -and (Test-Path $GameDir)) {
            $recentDump = Get-ChildItem -Path $GameDir -Filter "*.dmp" -File -ErrorAction SilentlyContinue |
                          Where-Object { ((Get-Date) - $_.LastWriteTime).TotalSeconds -le 10 } |
                          Select-Object -First 1
            if ($recentDump) { $isCrash = $true }
        }

        if ($isCrash) {
            [console]::beep(350, 600)
        }

        $lastLogText = "none"
        $logFileName = if ($LogFile) { Split-Path -Leaf $LogFile } else { "logfile.log" }

        if ($LogFile -and (Test-Path $LogFile)) {
            try {
                $fs = [System.IO.File]::Open($LogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $readLen = [math]::Min($fs.Length, 8192)
                if ($readLen -gt 0) {
                    $fs.Seek(-$readLen, [System.IO.SeekOrigin]::End) | Out-Null
                    $buf = New-Object byte[] $readLen
                    $null = $fs.Read($buf, 0, $readLen)
                    $tailText = [System.Text.Encoding]::UTF8.GetString($buf)
                    $lines = @($tailText -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
                    if ($lines.Count -gt 0) {
                        $lastLogText = Sanitize-Text ($lines[-1].Trim())
                    }
                }
                $fs.Close()
                $fs.Dispose()
            } catch {}
        }

        $maxLogContent = 84 - ("Last log: ".Length + " ($logFileName)".Length)
        if ($maxLogContent -gt 5 -and $lastLogText.Length -gt $maxLogContent) {
            $lastLogText = $lastLogText.Substring(0, $maxLogContent - 3) + "..."
        }

        [Console]::SetCursorPosition(0, $LastFrameRows + 1)
        [Console]::CursorVisible = $true
        Write-Host "$ProcessName.exe closed or crashed." -ForegroundColor Yellow
        Write-Host "Last log: " -ForegroundColor Gray -NoNewline
        Write-Host "$lastLogText " -ForegroundColor White -NoNewline
        Write-Host "($logFileName)" -ForegroundColor DarkGray
        break
        #endregion
    }
    
    Start-Sleep -Seconds $RefreshSec
}
#endregion
