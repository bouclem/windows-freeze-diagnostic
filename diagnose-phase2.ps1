Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DocsDir = Join-Path $ScriptDir "docs"
if (-not (Test-Path $DocsDir)) { New-Item -ItemType Directory -Path $DocsDir | Out-Null }
$Report = Join-Path $DocsDir "diagnostic-report.md"

function Write-Section {
    param([string]$Title)
    Add-Content -Path $Report -Value ""
    Add-Content -Path $Report -Value "## $Title"
    Add-Content -Path $Report -Value ""
}
function Write-Line { param([string]$Line) Add-Content -Path $Report -Value $Line }
function Write-Code { param([string]$Block) Add-Content -Path $Report -Value '```'; Add-Content -Path $Report -Value $Block; Add-Content -Path $Report -Value '```' }

Add-Content -Path $Report -Value ""
Add-Content -Path $Report -Value "---"
Add-Content -Path $Report -Value ""
Add-Content -Path $Report -Value "# Phase 2 Diagnostic"
Add-Content -Path $Report -Value "Generated: $(Get-Date)"

# --- 1. User home root inspection ---
Write-Section "P2.1 User home root suspicious files (node leftovers)"
try {
    $home = $env:USERPROFILE
    Write-Line "Scanning: $home (top level only)"
    $suspects = @('node_modules','package.json','package-lock.json','.npmrc','.yarnrc','yarn.lock','pnpm-lock.yaml','.node-gyp','.npm','.yarn','.pnpm-store','.bun')
    Write-Line ""
    Write-Line '```'
    foreach ($name in $suspects) {
        $p = Join-Path $home $name
        if (Test-Path $p) {
            $item = Get-Item $p -Force
            if ($item.PSIsContainer) {
                $size = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                $sizeMB = if ($size) { [math]::Round($size/1MB,1) } else { 0 }
                $count = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
                Add-Content -Path $Report -Value ("FOUND DIR : {0}  ({1} MB, {2} items, last write {3})" -f $p, $sizeMB, $count, $item.LastWriteTime)
            } else {
                Add-Content -Path $Report -Value ("FOUND FILE: {0}  ({1} bytes, last write {2})" -f $p, $item.Length, $item.LastWriteTime)
            }
        }
    }
    Add-Content -Path $Report -Value '```'
} catch { Write-Line "ERROR: $_" }

# --- 2. Application event log errors (last 48h) ---
Write-Section "P2.2 Application errors (last 48h, top 20)"
try {
    $events = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=(Get-Date).AddDays(-2)} -MaxEvents 20 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, @{N='Message';E={(($_.Message -split "`n")[0]) -replace '\s+',' '}}
    if ($events) {
        Write-Code (($events | Format-Table -AutoSize -Wrap | Out-String -Width 200).TrimEnd())
    } else {
        Write-Line "(No errors in last 48h.)"
    }
} catch { Write-Line "ERROR: $_" }

# --- 3. Repeating event sources (last 24h) ---
Write-Section "P2.3 Most repeated event sources (last 24h, both logs)"
try {
    $sys = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue
    $app = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue
    $all = @()
    if ($sys) { $all += $sys }
    if ($app) { $all += $app }
    if ($all.Count -gt 0) {
        $grouped = $all | Group-Object ProviderName, Id |
            Sort-Object Count -Descending |
            Select-Object -First 15 Count, Name
        Write-Code (($grouped | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())
    } else {
        Write-Line "(No events.)"
    }
} catch { Write-Line "ERROR: $_" }

# --- 4. Failed scheduled tasks ---
Write-Section "P2.4 Scheduled tasks with non-zero last result"
try {
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        if ($info -and $info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 267011) {
            [PSCustomObject]@{
                TaskName = $_.TaskName
                Path = $_.TaskPath
                LastRun = $info.LastRunTime
                LastResult = $info.LastTaskResult
                NextRun = $info.NextRunTime
                State = $_.State
            }
        }
    } | Sort-Object LastRun -Descending | Select-Object -First 25
    if ($tasks) {
        Write-Code (($tasks | Format-Table -AutoSize -Wrap | Out-String -Width 200).TrimEnd())
    } else {
        Write-Line "(No failing scheduled tasks.)"
    }
} catch { Write-Line "ERROR: $_" }

# --- 5. Windows Search status ---
Write-Section "P2.5 Windows Search service status"
try {
    $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Line "- Service status: $($svc.Status)"
        Write-Line "- Startup type: $($svc.StartType)"
    } else {
        Write-Line "- WSearch service not found."
    }
    $idx = Get-Process -Name SearchIndexer -ErrorAction SilentlyContinue
    if ($idx) {
        $cpu = if ($idx.CPU) { [math]::Round($idx.CPU,1) } else { 0 }
        $ram = [math]::Round($idx.WorkingSet64/1MB,1)
        Write-Line "- SearchIndexer process: PID $($idx.Id), CPU sec $cpu, RAM $ram MB"
    }
} catch { Write-Line "ERROR: $_" }

# --- 6. TEMP folder current state ---
Write-Section "P2.6 TEMP folders state"
try {
    foreach ($t in @($env:TEMP, "C:\Windows\Temp")) {
        if (Test-Path $t) {
            $files = Get-ChildItem $t -Force -ErrorAction SilentlyContinue
            $total = ($files | Measure-Object Length -Sum).Sum
            $sizeMB = if ($total) { [math]::Round($total/1MB,1) } else { 0 }
            Write-Line "- $t : $($files.Count) items, $sizeMB MB"
        }
    }
} catch { Write-Line "ERROR: $_" }

# --- 7. Volume Shadow Copy / System Restore ---
Write-Section "P2.7 Volume Shadow Copy / Restore points"
try {
    $vssSvc = Get-Service -Name VSS -ErrorAction SilentlyContinue
    if ($vssSvc) { Write-Line "- VSS service: $($vssSvc.Status) ($($vssSvc.StartType))" }
    $shadows = vssadmin list shadows 2>&1 | Select-String -Pattern "Contents of shadow|Shadow Copy" | Select-Object -First 10
    if ($shadows) {
        Write-Code (($shadows | Out-String).TrimEnd())
    } else {
        Write-Line "- No vssadmin output (may need admin)."
    }
} catch { Write-Line "ERROR: $_" }

# --- 8. Duplicate processes (potential restart loops) ---
Write-Section "P2.8 Process names with multiple instances (>3)"
try {
    $dup = Get-Process | Group-Object ProcessName |
        Where-Object { $_.Count -gt 3 } |
        Sort-Object Count -Descending |
        Select-Object Count, Name
    if ($dup) {
        Write-Code (($dup | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())
    } else {
        Write-Line "(No process with more than 3 instances.)"
    }
} catch { Write-Line "ERROR: $_" }

# --- 9. Disk queue snapshot ---
Write-Section "P2.9 Disk queue length (1s sample)"
try {
    $samples = Get-Counter '\PhysicalDisk(_Total)\Current Disk Queue Length','\PhysicalDisk(_Total)\Avg. Disk sec/Read','\PhysicalDisk(_Total)\Avg. Disk sec/Write' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
    if ($samples) {
        foreach ($s in $samples.CounterSamples) {
            $val = [math]::Round($s.CookedValue,4)
            Write-Line "- $($s.Path): $val"
        }
    }
} catch { Write-Line "ERROR: $_" }

# --- 10. Pending Windows Update / reboot ---
Write-Section "P2.10 Pending reboot indicators"
try {
    $rebootKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
    )
    foreach ($k in $rebootKeys) {
        if (Test-Path $k) {
            Write-Line "- PENDING: $k"
        }
    }
} catch { Write-Line "ERROR: $_" }

Write-Section "Phase 2 done"
Write-Output "Phase 2 appended to: $Report"
