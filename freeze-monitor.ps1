Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ----------------------------------------------------------------------
# Freeze Monitor v2 - locale-independent
# - Uses WMI Win32_PerfFormattedData_* classes (English regardless of UI lang)
# - Auto-detects freezes by measuring its own loop lag
# - Logs everything to docs/freeze-log.csv
# Stop with Ctrl+C.
# ----------------------------------------------------------------------

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DocsDir = Join-Path $ScriptDir "docs"
if (-not (Test-Path $DocsDir)) { New-Item -ItemType Directory -Path $DocsDir | Out-Null }
$Log = Join-Path $DocsDir "freeze-log.csv"

# CSV header (overwrite previous run)
"Time,LoopLag_sec,CPU_pct,RAM_used_GB,DiskQueue,DiskBusy_pct,DiskRead_MBs,DiskWrite_MBs,Top1_Name,Top1_CPU_pct,Top2_Name,Top2_CPU_pct,Top3_Name,Top3_CPU_pct,Note" |
    Out-File -FilePath $Log -Encoding UTF8

Write-Host ""
Write-Host "=================================================="
Write-Host "  FREEZE MONITOR v2 - locale-independent"
Write-Host "  Log file: $Log"
Write-Host ""
Write-Host "  USE YOUR PC NORMALLY."
Write-Host "  When you feel a freeze, just remember the time."
Write-Host "  FREEZES are auto-detected when loop lags >= 2 sec."
Write-Host "  Press Ctrl+C in this window to stop."
Write-Host "=================================================="
Write-Host ""

$totalRamGB = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
$logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

# Track previous CPU times for delta-based per-process CPU
$prevCpu = @{}
$prevTime = $null
$expectedInterval = 2.0   # we sleep 2s between samples

while ($true) {
    $now = Get-Date

    # ---- Loop lag (freeze auto-detection) ----
    $loopLag = 0
    if ($prevTime) {
        $loopLag = [math]::Round(($now - $prevTime).TotalSeconds - $expectedInterval, 2)
        if ($loopLag -lt 0) { $loopLag = 0 }
    }

    # ---- System CPU (locale-independent via WMI) ----
    try {
        $cpuObj = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
        $cpu = [math]::Round($cpuObj.PercentProcessorTime, 1)
    } catch {
        $cpu = -1
    }

    # ---- Physical disk (_Total) ----
    try {
        $disk = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction Stop
        $dq   = [math]::Round($disk.CurrentDiskQueueLength, 2)
        $dr   = [math]::Round($disk.DiskReadBytesPerSec / 1MB, 2)
        $dw   = [math]::Round($disk.DiskWriteBytesPerSec / 1MB, 2)
        $dbusy = [math]::Round($disk.PercentDiskTime, 1)
        if ($dbusy -gt 100) { $dbusy = 100 }
    } catch {
        $dq = -1; $dr = -1; $dw = -1; $dbusy = -1
    }

    # ---- RAM ----
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $freeGB = $os.FreePhysicalMemory / 1MB
        $usedGB = [math]::Round($totalRamGB - $freeGB, 2)
    } else {
        $usedGB = 0
    }

    # ---- Per-process CPU delta ----
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.CPU -ne $null }
    $deltas = @()
    if ($prevTime) {
        $intervalSec = ($now - $prevTime).TotalSeconds
        if ($intervalSec -lt 0.1) { $intervalSec = 1 }
        foreach ($p in $procs) {
            $key = "$($p.Id)_$($p.ProcessName)"
            if ($prevCpu.ContainsKey($key)) {
                $delta = $p.CPU - $prevCpu[$key]
                if ($delta -gt 0) {
                    $pct = [math]::Round(($delta / $intervalSec) * 100 / $logicalCores, 1)
                    $deltas += [PSCustomObject]@{ Name = $p.ProcessName; Pct = $pct }
                }
            }
        }
    }

    # Refresh cache for next iteration
    $prevCpu = @{}
    foreach ($p in $procs) { $prevCpu["$($p.Id)_$($p.ProcessName)"] = $p.CPU }
    $prevTime = $now

    # Top 3
    $top = @($deltas | Sort-Object Pct -Descending | Select-Object -First 3)
    $top1n = ''; $top1p = 0; $top2n = ''; $top2p = 0; $top3n = ''; $top3p = 0
    if ($top.Length -ge 1) { $top1n = $top[0].Name; $top1p = $top[0].Pct }
    if ($top.Length -ge 2) { $top2n = $top[1].Name; $top2p = $top[1].Pct }
    if ($top.Length -ge 3) { $top3n = $top[2].Name; $top3p = $top[2].Pct }

    # ---- Notes ----
    $note = ''
    if ($loopLag -ge 2)              { $note += 'FREEZE_DETECTED;' }
    if ($dq -gt 5)                   { $note += 'HIGH_DISK_QUEUE;' }
    if ($cpu -gt 85)                 { $note += 'HIGH_CPU;' }
    if ($dr -gt 100 -or $dw -gt 100) { $note += 'HIGH_DISK_IO;' }
    if ($dbusy -gt 90)               { $note += 'DISK_SATURATED;' }

    $line = "$($now.ToString('HH:mm:ss')),$loopLag,$cpu,$usedGB,$dq,$dbusy,$dr,$dw,$top1n,$top1p,$top2n,$top2p,$top3n,$top3p,$note"
    Add-Content -Path $Log -Value $line

    # ---- Live console output ----
    $color = 'Gray'
    if ($note -match 'FREEZE_DETECTED') { $color = 'Red' }
    elseif ($note) { $color = 'Yellow' }

    $lagDisplay = if ($loopLag -ge 0.5) { "LAG{0,4}s " -f $loopLag } else { "         " }
    Write-Host ("[{0}] {1}CPU {2,5}%  RAM {3,5} GB  Q {4,4}  Dbusy {5,4}%  R/W {6,5}/{7,5} MB/s  | {8} {9}%  {10}" -f `
        $now.ToString('HH:mm:ss'), $lagDisplay, $cpu, $usedGB, $dq, $dbusy, $dr, $dw, $top1n, $top1p, $note) -ForegroundColor $color

    Start-Sleep -Seconds 2
}
