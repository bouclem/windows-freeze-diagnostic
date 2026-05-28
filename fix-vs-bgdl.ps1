Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Visual Studio BackgroundDownload triage ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: snapshot before
Write-Host "--- Before: BackgroundDownload processes ---" -ForegroundColor Yellow
$procs = @(Get-Process -Name BackgroundDownload -ErrorAction SilentlyContinue)
if ($procs.Length -eq 0) {
    Write-Host "  (no BackgroundDownload process currently running)"
} else {
    foreach ($p in $procs) {
        $ramMB = [math]::Round($p.WorkingSet64/1MB, 1)
        $cpuS  = if ($p.CPU) { [math]::Round($p.CPU, 1) } else { 0 }
        Write-Host ("  PID " + $p.Id + "  RAM " + $ramMB + " MB  CPU(total) " + $cpuS + "s  Started " + $p.StartTime)
    }
}

# Step 2: kill running process(es)
Write-Host ""
Write-Host "--- Killing BackgroundDownload process(es) ---" -ForegroundColor Yellow
if ($procs.Length -gt 0) {
    foreach ($p in $procs) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Host ("  Killed PID " + $p.Id) -ForegroundColor Green
        } catch {
            Write-Host ("  FAILED to kill PID " + $p.Id + " : " + $_.Exception.Message) -ForegroundColor Red
        }
    }
} else {
    Write-Host "  (nothing to kill)"
}

# Step 3: disable the scheduled task (temporarily)
Write-Host ""
Write-Host "--- Disabling scheduled task (reversible) ---" -ForegroundColor Yellow
try {
    $task = Get-ScheduledTask -TaskName 'BackgroundDownload' -TaskPath '\Microsoft\VisualStudio\Updates\' -ErrorAction Stop
    Write-Host ("  Task found, current state: " + $task.State)
    Disable-ScheduledTask -TaskName 'BackgroundDownload' -TaskPath '\Microsoft\VisualStudio\Updates\' -ErrorAction Stop | Out-Null
    $task2 = Get-ScheduledTask -TaskName 'BackgroundDownload' -TaskPath '\Microsoft\VisualStudio\Updates\'
    Write-Host ("  New state: " + $task2.State) -ForegroundColor Green
} catch {
    Write-Host ("  FAILED to disable task: " + $_.Exception.Message) -ForegroundColor Red
}

# Step 4: snapshot after
Start-Sleep -Seconds 2
Write-Host ""
Write-Host "--- After: BackgroundDownload processes ---" -ForegroundColor Yellow
$procs2 = @(Get-Process -Name BackgroundDownload -ErrorAction SilentlyContinue)
if ($procs2.Length -eq 0) {
    Write-Host "  (none running - good)" -ForegroundColor Green
} else {
    foreach ($p in $procs2) {
        Write-Host ("  STILL RUNNING: PID " + $p.Id) -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "Next: use your PC for 1-2 minutes, see if freezes stop."
Write-Host "Then we investigate WHY BackgroundDownload was stuck retrying."
Write-Host "(Re-enable later with: Enable-ScheduledTask -TaskName BackgroundDownload -TaskPath '\Microsoft\VisualStudio\Updates\')"
