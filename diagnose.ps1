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

function Write-Line {
    param([string]$Line)
    Add-Content -Path $Report -Value $Line
}

# Reset report
$now = Get-Date
Set-Content -Path $Report -Value "# PC Diagnostic Report"
Write-Line "Generated: $now"
Write-Line ""
Write-Line "Read-only snapshot. No system changes were made."

# --- 1. OS & Uptime ---
Write-Section "1. System Info"
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $boot = $os.LastBootUpTime
    $uptime = (Get-Date) - $boot
    $totalRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $freeRamGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedRamGB = [math]::Round($totalRamGB - $freeRamGB, 2)
    $ramPct = [math]::Round(($usedRamGB / $totalRamGB) * 100, 1)

    Write-Line "- OS: $($os.Caption) ($($os.Version))"
    Write-Line "- Computer: $($cs.Manufacturer) $($cs.Model)"
    Write-Line "- CPU cores (logical): $($cs.NumberOfLogicalProcessors)"
    Write-Line "- Total RAM: $totalRamGB GB"
    Write-Line "- Used RAM: $usedRamGB GB ($ramPct percent)"
    Write-Line "- Free RAM: $freeRamGB GB"
    Write-Line "- Last boot: $boot"
    Write-Line "- Uptime: $([math]::Floor($uptime.TotalHours)) hours"
} catch { Write-Line "ERROR collecting system info: $_" }

# --- 2. CPU snapshot ---
Write-Section "2. CPU Load (snapshot)"
try {
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    Write-Line "- Current CPU load: $cpuLoad percent"
} catch { Write-Line "ERROR collecting CPU load: $_" }

# --- 3. Top processes by RAM ---
Write-Section "3. Top 15 processes by RAM"
try {
    Write-Line '```'
    Get-Process | Sort-Object WorkingSet64 -Descending |
        Select-Object -First 15 @{N='Name';E={$_.ProcessName}},
            @{N='RAM_MB';E={[math]::Round($_.WorkingSet64/1MB,1)}},
            @{N='Handles';E={$_.HandleCount}},
            @{N='Threads';E={$_.Threads.Count}} |
        Format-Table -AutoSize | Out-String -Width 200 | Add-Content -Path $Report
    Write-Line '```'
} catch { Write-Line "ERROR collecting top RAM processes: $_" }

# --- 4. Top processes by CPU time ---
Write-Section "4. Top 15 processes by CPU time"
try {
    Write-Line '```'
    Get-Process | Where-Object { $_.CPU -ne $null } |
        Sort-Object CPU -Descending |
        Select-Object -First 15 @{N='Name';E={$_.ProcessName}},
            @{N='CPU_seconds';E={[math]::Round($_.CPU,1)}},
            @{N='RAM_MB';E={[math]::Round($_.WorkingSet64/1MB,1)}} |
        Format-Table -AutoSize | Out-String -Width 200 | Add-Content -Path $Report
    Write-Line '```'
} catch { Write-Line "ERROR collecting top CPU processes: $_" }

# --- 5. Process count ---
Write-Section "5. Process count"
try {
    $procCount = (Get-Process).Count
    Write-Line "- Total running processes: $procCount"
} catch { Write-Line "ERROR: $_" }

# --- 6. Disk info ---
Write-Section "6. Disks"
try {
    Write-Line '```'
    Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, MediaType, BusType,
        @{N='Size_GB';E={[math]::Round($_.Size/1GB,1)}}, HealthStatus, OperationalStatus |
        Format-Table -AutoSize | Out-String -Width 200 | Add-Content -Path $Report
    Write-Line '```'
} catch { Write-Line "ERROR collecting physical disks: $_" }

Write-Section "7. Volumes / free space"
try {
    Write-Line '```'
    Get-Volume | Where-Object { $_.DriveLetter } |
        Select-Object DriveLetter, FileSystemLabel, FileSystem,
            @{N='Size_GB';E={[math]::Round($_.Size/1GB,1)}},
            @{N='Free_GB';E={[math]::Round($_.SizeRemaining/1GB,1)}},
            @{N='Free_pct';E={if ($_.Size) { [math]::Round(($_.SizeRemaining/$_.Size)*100,1) } else { 0 }}},
            HealthStatus |
        Format-Table -AutoSize | Out-String -Width 200 | Add-Content -Path $Report
    Write-Line '```'
} catch { Write-Line "ERROR collecting volumes: $_" }

# --- 8. Startup programs ---
Write-Section "8. Startup programs (auto-launch with Windows)"
try {
    Write-Line '```'
    Get-CimInstance Win32_StartupCommand |
        Select-Object Name, Command, Location, User |
        Format-Table -AutoSize -Wrap | Out-String -Width 200 | Add-Content -Path $Report
    Write-Line '```'
} catch { Write-Line "ERROR collecting startup commands: $_" }

# --- 9. Services running ---
Write-Section "9. Running services count"
try {
    $running = (Get-Service | Where-Object { $_.Status -eq 'Running' }).Count
    $stopped = (Get-Service | Where-Object { $_.Status -eq 'Stopped' }).Count
    Write-Line "- Running services: $running"
    Write-Line "- Stopped services: $stopped"
} catch { Write-Line "ERROR: $_" }

# --- 10. Page file ---
Write-Section "10. Page file usage"
try {
    Write-Line '```'
    Get-CimInstance Win32_PageFileUsage |
        Select-Object Name,
            @{N='AllocatedSize_MB';E={$_.AllocatedBaseSize}},
            @{N='CurrentUsage_MB';E={$_.CurrentUsage}},
            @{N='PeakUsage_MB';E={$_.PeakUsage}} |
        Format-Table -AutoSize | Out-String -Width 200 | Add-Content -Path $Report
    Write-Line '```'
} catch { Write-Line "ERROR: $_" }

# --- 11. Power plan ---
Write-Section "11. Active power plan"
try {
    $plan = powercfg /getactivescheme 2>$null
    Write-Line "- $plan"
} catch { Write-Line "ERROR: $_" }

# --- 12. Recent system errors (last 24h) ---
Write-Section "12. Recent System errors (last 24h, top 10)"
try {
    Write-Line '```'
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-1)} -MaxEvents 10 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, @{N='Message';E={($_.Message -split "`n")[0]}} |
        Format-Table -AutoSize -Wrap | Out-String -Width 200 | Add-Content -Path $Report
    Write-Line '```'
} catch { Write-Line "ERROR: $_" }

Write-Section "Done"
Write-Line "Report file: $Report"
Write-Output "Report written to: $Report"
