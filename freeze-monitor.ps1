Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ----------------------------------------------------------------------
# Freeze Monitor - read-only sampler
# Logs CPU/RAM/disk + top processes every 2 seconds.
# When you experience a freeze, note the time. We then check the log
# to see exactly which process was hammering the system at that moment.
# Stop with Ctrl+C.
# ----------------------------------------------------------------------

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DocsDir = Join-Path $ScriptDir "docs"
if (-not (Test-Path $DocsDir)) { New-Item -ItemType Directory -Path $DocsDir | Out-Null }
$Log = Join-Path $DocsDir "freeze-log.csv"

# CSV header (overwrite previous run)
"Time,CPU_pct,RAM_used_GB,DiskQueue,DiskRead_MBs,DiskWrite_MBs,Top1_Name,Top1_CPU_pct,Top2_Name,Top2_CPU_pct,Top3_Name,Top3_CPU_pct,Note" |
    Out-File -FilePath $Log -Encoding UTF8

Write-Host ""
Write-Host "=================================================="
Write-Host "  FREEZE MONITOR - logging every 2 seconds"
Write-Host "  Log file: $Log"
Write-Host ""
Write-Host "  USE YOUR PC NORMALLY."
Write-Host "  When you feel a freeze, just remember the time."
Write-Host "  Press Ctrl+C in this window to stop."
Write-Host "=================================================="
Write-Host ""

$totalRamGB = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB

# Track previous CPU times for delta-based per-process CPU
$prevCpu = @{}
$prevTime = $null

while ($true) {
    $now = Get-Date

    # System metrics
    try {
        $samples = Get-Counter `
            '\Processor(_Total)\% Processor Time',
            '\PhysicalDisk(_Total)\Current Disk Queue Length',
            '\PhysicalDisk(_Total)\Disk Read Bytes/sec',
            '\PhysicalDisk(_Total)\Disk Write Bytes/sec' `
            -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue

        $cpu = [math]::Round($samples.CounterSamples[0].CookedValue, 1)
        $dq  = [math]::Round($samples.CounterSamples[1].CookedValue, 2)
        $dr  = [math]::Round($samples.CounterSamples[2].CookedValue / 1MB, 2)
        $dw  = [math]::Round($samples.CounterSamples[3].CookedValue / 1MB, 2)
    } catch {
        $cpu = 0; $dq = 0; $dr = 0; $dw = 0
    }

    # RAM
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $freeGB = $os.FreePhysicalMemory / 1MB
        $usedGB = [math]::Round($totalRamGB - $freeGB, 2)
    } else {
        $usedGB = 0
    }

    # Per-process CPU delta over interval
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
                    # CPU pct of one core; can exceed 100 across cores. Normalize to all cores.
                    $logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
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

    # Top 3 by CPU delta
    $top = $deltas | Sort-Object Pct -Descending | Select-Object -First 3
    $top1n = ''; $top1p = 0; $top2n = ''; $top2p = 0; $top3n = ''; $top3p = 0
    if ($top.Count -ge 1) { $top1n = $top[0].Name; $top1p = $top[0].Pct }
    if ($top.Count -ge 2) { $top2n = $top[1].Name; $top2p = $top[1].Pct }
    if ($top.Count -ge 3) { $top3n = $top[2].Name; $top3p = $top[2].Pct }

    # Note flag if anything looks suspicious
    $note = ''
    if ($dq -gt 5)  { $note += 'HIGH_DISK_QUEUE;' }
    if ($cpu -gt 85) { $note += 'HIGH_CPU;' }
    if ($dr -gt 100 -or $dw -gt 100) { $note += 'HIGH_DISK_IO;' }

    $line = "$($now.ToString('HH:mm:ss')),$cpu,$usedGB,$dq,$dr,$dw,$top1n,$top1p,$top2n,$top2p,$top3n,$top3p,$note"
    Add-Content -Path $Log -Value $line

    # Live console output
    $color = 'Gray'
    if ($note) { $color = 'Yellow' }
    Write-Host ("[{0}] CPU {1,5}%  RAM {2,5} GB  Q {3,5}  R/W {4,5}/{5,5} MB/s  | {6} {7}%" -f `
        $now.ToString('HH:mm:ss'), $cpu, $usedGB, $dq, $dr, $dw, $top1n, $top1p) -ForegroundColor $color

    Start-Sleep -Seconds 1
}
