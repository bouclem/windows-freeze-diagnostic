Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Output "=== Quick Win 1: Delete IntelliJ heap dump ==="
$hprof = 'C:\Users\Utilisateur\java_error_in_idea.hprof'
if (Test-Path $hprof) {
    $size = (Get-Item $hprof).Length
    $sizeMB = [math]::Round($size/1MB, 1)
    try {
        Remove-Item $hprof -Force -ErrorAction Stop
        Write-Output "Deleted: $hprof ($sizeMB MB freed)"
    } catch {
        Write-Output "FAILED to delete: $_"
    }
} else {
    Write-Output "Not found (already gone)."
}

Write-Output ""
Write-Output "=== Quick Win 2: Stop hung scheduled tasks ==="
foreach ($t in 'CacheTask','ResolutionHost','SystemSoundsService') {
    try {
        $task = Get-ScheduledTask -TaskName $t -ErrorAction Stop
        $info = $task | Get-ScheduledTaskInfo
        Write-Output "$t -> state: $($task.State), last run: $($info.LastRunTime)"
        if ($task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $t -ErrorAction Stop
            Write-Output "  -> stopped OK"
        } else {
            Write-Output "  -> not running, nothing to do"
        }
    } catch {
        Write-Output "$t ERROR: $($_.Exception.Message)"
    }
}

Write-Output ""
Write-Output "Done."
