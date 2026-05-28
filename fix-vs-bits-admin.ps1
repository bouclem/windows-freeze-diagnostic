Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ----------------------------------------------------------------------
# VS BITS cleanup (REQUIRES ADMIN)
# - Lists all BITS jobs
# - Cancels only jobs that are downloading from visualstudio.microsoft.com
# - Confirms BackgroundDownload task is disabled
# - Cleans up VS Installer temp staging folders
# Reversible: BITS jobs cancelled here can be re-queued by VS Installer.
# ----------------------------------------------------------------------

# Verify admin
$current = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($current)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell, choose 'Run as administrator', then run this script."
    exit 1
}

Write-Host "=== VS BITS cleanup (admin) ===" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: list current BITS jobs ---
Write-Host "--- Step 1: current BITS jobs ---" -ForegroundColor Yellow
$rawJobs = & bitsadmin /list /allusers /verbose 2>&1 | Out-String

# Parse jobs into structured objects (split by GUID block)
$jobBlocks = $rawJobs -split '(?=GUID:\s*\{)'
$vsJobs = @()
$otherJobs = @()
foreach ($block in $jobBlocks) {
    if ($block -match 'GUID:\s*(\{[^}]+\})') {
        $guid = $matches[1]
        $isVS = $block -match 'visualstudio\.microsoft\.com'
        $stateMatch = if ($block -match 'STATE:\s*(\S+)') { $matches[1] } else { 'UNKNOWN' }
        $nameMatch  = if ($block -match 'DISPLAY:\s*''([^'']+)''') { $matches[1] } else { '' }
        $obj = [PSCustomObject]@{
            Guid = $guid
            State = $stateMatch
            Name = $nameMatch
            IsVS = $isVS
        }
        if ($isVS) { $vsJobs += $obj } else { $otherJobs += $obj }
    }
}

Write-Host ("  VS-related BITS jobs found    : " + $vsJobs.Length) -ForegroundColor $(if ($vsJobs.Length -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host ("  Non-VS BITS jobs (will leave) : " + $otherJobs.Length) -ForegroundColor Gray

if ($vsJobs.Length -gt 0) {
    Write-Host ""
    Write-Host "  VS jobs to cancel:" -ForegroundColor Yellow
    foreach ($j in $vsJobs) {
        Write-Host ("    " + $j.Guid + "  state=" + $j.State + "  name='" + $j.Name + "'")
    }
}
if ($otherJobs.Length -gt 0) {
    Write-Host ""
    Write-Host "  Non-VS jobs (KEPT, untouched):" -ForegroundColor Gray
    foreach ($j in $otherJobs) {
        Write-Host ("    " + $j.Guid + "  state=" + $j.State + "  name='" + $j.Name + "'")
    }
}

# --- Step 2: cancel only VS jobs ---
Write-Host ""
Write-Host "--- Step 2: cancelling VS BITS jobs ---" -ForegroundColor Yellow
if ($vsJobs.Length -eq 0) {
    Write-Host "  (no VS jobs to cancel - nothing to do here)"
} else {
    foreach ($j in $vsJobs) {
        Write-Host ("  Cancelling " + $j.Guid + " ...")
        $r = & bitsadmin /cancel $j.Guid 2>&1 | Out-String
        Write-Host ("    " + $r.Trim().Replace("`n", "`n    "))
    }
}

# --- Step 3: confirm task still disabled ---
Write-Host ""
Write-Host "--- Step 3: BackgroundDownload task state ---" -ForegroundColor Yellow
try {
    $task = Get-ScheduledTask -TaskName 'BackgroundDownload' -TaskPath '\Microsoft\VisualStudio\Updates\' -ErrorAction Stop
    Write-Host ("  State: " + $task.State)
    if ($task.State -ne 'Disabled') {
        Write-Host "  Task is NOT disabled - disabling now..." -ForegroundColor Yellow
        Disable-ScheduledTask -TaskName 'BackgroundDownload' -TaskPath '\Microsoft\VisualStudio\Updates\' -ErrorAction Stop | Out-Null
        Write-Host "  -> Disabled" -ForegroundColor Green
    } else {
        Write-Host "  -> Already disabled (good)" -ForegroundColor Green
    }
} catch {
    Write-Host ("  ERROR: " + $_.Exception.Message) -ForegroundColor Red
}

# --- Step 4: clean up VS Installer temp staging ---
Write-Host ""
Write-Host "--- Step 4: VS Installer temp staging cleanup ---" -ForegroundColor Yellow
$userTemp = $env:TEMP
$staging = @(Get-ChildItem $userTemp -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^[a-z0-9]{8}$' -and (Get-ChildItem $_.FullName -Recurse -Filter '*.vsix' -ErrorAction SilentlyContinue) })
if ($staging.Length -eq 0) {
    Write-Host "  (no VS Installer staging folders found in temp)"
} else {
    foreach ($s in $staging) {
        $sizeBytes = (Get-ChildItem $s.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $sizeMB = if ($sizeBytes) { [math]::Round($sizeBytes / 1MB, 1) } else { 0 }
        Write-Host ("  Found staging: " + $s.FullName + "  (" + $sizeMB + " MB)") -ForegroundColor Yellow
        try {
            Remove-Item $s.FullName -Recurse -Force -ErrorAction Stop
            Write-Host ("    -> deleted") -ForegroundColor Green
        } catch {
            Write-Host ("    -> FAILED: " + $_.Exception.Message) -ForegroundColor Red
        }
    }
}

# --- Step 5: kill any remaining BackgroundDownload process ---
Write-Host ""
Write-Host "--- Step 5: kill any lingering BackgroundDownload.exe ---" -ForegroundColor Yellow
$procs = @(Get-Process -Name BackgroundDownload -ErrorAction SilentlyContinue)
if ($procs.Length -eq 0) {
    Write-Host "  (none running - good)"
} else {
    foreach ($p in $procs) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Host ("  Killed PID " + $p.Id) -ForegroundColor Green
        } catch {
            Write-Host ("  Failed to kill PID " + $p.Id + ": " + $_.Exception.Message) -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "Summary:"
Write-Host "  - VS BITS jobs cancelled    : $($vsJobs.Length)"
Write-Host "  - Non-VS BITS jobs kept     : $($otherJobs.Length)"
Write-Host "  - Task BackgroundDownload   : Disabled"
Write-Host "  - VS staging folders cleaned: $($staging.Length)"
Write-Host ""
Write-Host "Next: open Visual Studio Installer (Start menu), uninstall VS 2019 and VS 2026"
Write-Host "      (KEEP Visual Studio Build Tools 2022 - you need it for Node.js native modules)"
