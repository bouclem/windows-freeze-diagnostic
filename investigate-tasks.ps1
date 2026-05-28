Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Report = Join-Path $ScriptDir "docs\diagnostic-report.md"

function Section { param([string]$T) Add-Content -Path $Report -Value ""; Add-Content -Path $Report -Value "## $T"; Add-Content -Path $Report -Value "" }
function L      { param([string]$X) Add-Content -Path $Report -Value $X }

Add-Content -Path $Report -Value ""
Add-Content -Path $Report -Value "---"
Add-Content -Path $Report -Value "# Phase 4 - Failing tasks deep dive"
Add-Content -Path $Report -Value "Generated: $(Get-Date)"

# The failing tasks (real names) we care about
$targets = @(
    @{ Name='AnalyzeSystem';                    Path='\Microsoft\Windows\Power Efficiency Diagnostics\' },
    @{ Name='StorageSense';                     Path='\Microsoft\Windows\DiskFootprint\' },
    @{ Name='ThemesSyncedImageDownload';        Path='\Microsoft\Windows\Shell\' },
    @{ Name='PITRTask';                         Path='\Microsoft\Windows\Setup\' },
    @{ Name='ProcessMemoryDiagnosticEvents';    Path='\Microsoft\Windows\MemoryDiagnostic\' },
    @{ Name='AutomaticOfflineMemoryDiagnostic'; Path='\Microsoft\Windows\MemoryDiagnostic\' },
    @{ Name='Windows Defender Scheduled Scan';  Path='\Microsoft\Windows\Windows Defender\' },
    @{ Name='BgTaskRegistrationMaintenanceTask';Path='\Microsoft\Windows\BrokerInfrastructure\' },
    @{ Name='BackgroundDownload';               Path='\Microsoft\VisualStudio\Updates\' }
)

foreach ($t in $targets) {
    $full = $t.Path + $t.Name
    Section ("Task: " + $full)

    # Definition basics
    try {
        $task = Get-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop
        $info = $task | Get-ScheduledTaskInfo
        L ("- State           : " + $task.State)
        L ("- Last run        : " + $info.LastRunTime)
        L ("- Last result     : " + $info.LastTaskResult)
        L ("- Next run        : " + $info.NextRunTime)
        L ("- Author          : " + $task.Author)
        L ""
        L "Actions:"
        foreach ($a in $task.Actions) {
            $exec = $a.PSObject.Properties['Execute'].Value
            $args = $a.PSObject.Properties['Arguments'].Value
            $wd   = $a.PSObject.Properties['WorkingDirectory'].Value
            L ("  - exec : " + $exec)
            if ($args) { L ("    args : " + $args) }
            if ($wd)   { L ("    cwd  : " + $wd) }
        }
    } catch {
        L ("- ERROR reading task: " + $_.Exception.Message)
        continue
    }

    # Last 5 events for this task in the TaskScheduler log
    L ""
    L "Recent Task Scheduler events (last 7 days):"
    L ""
    L '```'
    try {
        $events = @(Get-WinEvent -FilterHashtable @{
            LogName='Microsoft-Windows-TaskScheduler/Operational'
            StartTime=(Get-Date).AddDays(-7)
        } -ErrorAction SilentlyContinue |
            Where-Object {
                try { $_.Properties.Count -gt 0 -and ($_.Properties[0].Value -eq $full -or ($_.Properties.Count -gt 1 -and $_.Properties[1].Value -eq $full)) } catch { $false }
            } |
            Select-Object -First 8 TimeCreated, Id, LevelDisplayName, @{N='Msg';E={(($_.Message -split "`n")[0]) -replace '\s+',' '}})

        if ($events.Length -gt 0) {
            $out = ($events | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd()
            Add-Content -Path $Report -Value $out
        } else {
            Add-Content -Path $Report -Value "(No events found for this task in last 7 days.)"
        }
    } catch {
        Add-Content -Path $Report -Value ("Error fetching events: " + $_.Exception.Message)
    }
    L '```'
}

Write-Output "Phase 4 appended to: $Report"
