Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ----------------------------------------------------------------------
# Disable the 4 cosmetic failing scheduled tasks (REQUIRES ADMIN)
# Reversible: each task can be re-enabled with Enable-ScheduledTask.
# ----------------------------------------------------------------------

$current = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($current)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell, choose 'Run as administrator', then run this script."
    exit 1
}

Write-Host "=== Disabling 4 cosmetic failing tasks ===" -ForegroundColor Cyan
Write-Host "(StorageSense kept active - you said you want to keep it)"
Write-Host ""

$targets = @(
    @{ Name='AnalyzeSystem';                 Path='\Microsoft\Windows\Power Efficiency Diagnostics\'; Reason='Power efficiency diagnostic - you do not use this' },
    @{ Name='ThemesSyncedImageDownload';     Path='\Microsoft\Windows\Shell\';                        Reason='Windows Spotlight wallpaper download' },
    @{ Name='PITRTask';                      Path='\Microsoft\Windows\Setup\';                        Reason='System Restore checkpoint task (already broken)' },
    @{ Name='ProcessMemoryDiagnosticEvents'; Path='\Microsoft\Windows\MemoryDiagnostic\';             Reason='Memory leak detection diagnostic' }
)

$succeeded = 0
$failed    = @()
$alreadyOff = 0

foreach ($t in $targets) {
    Write-Host "----------------------------------------"
    Write-Host ("Task   : " + $t.Path + $t.Name)
    Write-Host ("Reason : " + $t.Reason)
    try {
        $task = Get-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop
        Write-Host ("Before : state=" + $task.State)
        if ($task.State -eq 'Disabled') {
            Write-Host "  -> already disabled, skipping" -ForegroundColor Gray
            $alreadyOff++
            continue
        }
        Disable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop | Out-Null
        $taskAfter = Get-ScheduledTask -TaskName $t.Name -TaskPath $t.Path
        Write-Host ("After  : state=" + $taskAfter.State) -ForegroundColor Green
        if ($taskAfter.State -eq 'Disabled') {
            $succeeded++
        } else {
            $failed += $t.Name
            Write-Host "  -> disable command ran but state did not change" -ForegroundColor Red
        }
    } catch {
        $failed += $t.Name
        Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "========================================"
Write-Host ("Disabled    : " + $succeeded) -ForegroundColor Green
Write-Host ("Already off : " + $alreadyOff) -ForegroundColor Gray
Write-Host ("Failed      : " + $failed.Length) -ForegroundColor $(if ($failed.Length) {'Red'} else {'Gray'})
if ($failed.Length -gt 0) {
    Write-Host "Failed tasks:"
    foreach ($f in $failed) { Write-Host ("  - " + $f) -ForegroundColor Red }
}

Write-Host ""
Write-Host "To re-enable any of them later:"
Write-Host '  Enable-ScheduledTask -TaskName "<TaskName>" -TaskPath "<TaskPath>"'
Write-Host ""
Write-Host "Done."
