Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Output "=== Try alternative: schtasks /end ==="

$tasks = @(
    @{ Name='CacheTask';            Path='\Microsoft\Windows\Wininet\' },
    @{ Name='ResolutionHost';       Path='\Microsoft\Windows\WDI\' },
    @{ Name='SystemSoundsService';  Path='\Microsoft\Windows\Multimedia\' }
)

foreach ($t in $tasks) {
    $full = $t.Path + $t.Name
    Write-Output ""
    Write-Output ("Trying: " + $full)
    & schtasks /end /tn $full 2>&1 | ForEach-Object { Write-Output ('  ' + $_) }
}

Write-Output ""
Write-Output "=== Recheck state ==="
foreach ($t in $tasks) {
    try {
        $task = Get-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop
        $info = $task | Get-ScheduledTaskInfo
        Write-Output ("$($t.Name) -> state: $($task.State), last run: $($info.LastRunTime), result: $($info.LastTaskResult)")
    } catch {
        Write-Output "$($t.Name) ERROR: $($_.Exception.Message)"
    }
}
