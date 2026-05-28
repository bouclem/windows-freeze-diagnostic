Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log = Join-Path $ScriptDir "docs\freeze-log.csv"

if (-not (Test-Path $Log)) {
    Write-Output "Log not found: $Log"
    exit 1
}

$rows = Import-Csv $Log
$total = $rows.Count
Write-Output ""
Write-Output "=== FREEZE LOG ANALYSIS ==="
Write-Output "Total samples: $total"
if ($total -eq 0) { exit 0 }
Write-Output ("Time range : " + $rows[0].Time + "  ->  " + $rows[-1].Time)
Write-Output ""

# Auto-detected freezes (wrap in @() so single results stay enumerable)
$freezes = @($rows | Where-Object { $_.Note -match 'FREEZE_DETECTED' })
Write-Output ("=== AUTO-DETECTED FREEZES: " + $freezes.Length + " ===")
if ($freezes.Length -gt 0) {
    foreach ($f in $freezes) {
        Write-Output ("  [" + $f.Time + "]  lag=" + $f.LoopLag_sec + "s  CPU=" + $f.CPU_pct + "%  Dbusy=" + $f.DiskBusy_pct + "%  Q=" + $f.DiskQueue + "  R=" + $f.DiskRead_MBs + " W=" + $f.DiskWrite_MBs + " MB/s  | top: " + $f.Top1_Name + " " + $f.Top1_CPU_pct + "% / " + $f.Top2_Name + " " + $f.Top2_CPU_pct + "% / " + $f.Top3_Name + " " + $f.Top3_CPU_pct + "%")
    }
}
Write-Output ""

# Other suspicious moments
$susp = @($rows | Where-Object { $_.Note -ne '' -and $_.Note -notmatch 'FREEZE_DETECTED' })
Write-Output ("=== OTHER SUSPICIOUS SAMPLES: " + $susp.Length + " ===")
foreach ($s in $susp | Select-Object -First 20) {
    Write-Output ("  [" + $s.Time + "]  " + $s.Note + "  CPU=" + $s.CPU_pct + "%  Dbusy=" + $s.DiskBusy_pct + "%  Q=" + $s.DiskQueue + "  | top: " + $s.Top1_Name + " " + $s.Top1_CPU_pct + "%")
}
Write-Output ""

# Top processes by total CPU across the run
$topProcs = $rows | ForEach-Object {
    [PSCustomObject]@{ Name = $_.Top1_Name; Pct = [double]$_.Top1_CPU_pct }
    [PSCustomObject]@{ Name = $_.Top2_Name; Pct = [double]$_.Top2_CPU_pct }
    [PSCustomObject]@{ Name = $_.Top3_Name; Pct = [double]$_.Top3_CPU_pct }
} | Where-Object { $_.Name -ne '' } | Group-Object Name | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Appearances = $_.Count
        AvgPct = [math]::Round(($_.Group | Measure-Object Pct -Average).Average, 1)
        MaxPct = [math]::Round(($_.Group | Measure-Object Pct -Maximum).Maximum, 1)
    }
} | Sort-Object Appearances -Descending | Select-Object -First 10

Write-Output "=== TOP PROCESSES (most often in top-3 CPU consumers) ==="
$topProcs | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

# Stats overall
$cpuStats   = $rows | Measure-Object CPU_pct -Average -Maximum
$diskStats  = $rows | Measure-Object DiskBusy_pct -Average -Maximum
$ramStats   = $rows | Measure-Object RAM_used_GB -Average -Maximum
$queueStats = $rows | Measure-Object DiskQueue -Maximum

Write-Output "=== OVERALL STATS ==="
Write-Output ("CPU      : avg " + [math]::Round($cpuStats.Average,1) + "%   max " + $cpuStats.Maximum + "%")
Write-Output ("DiskBusy : avg " + [math]::Round($diskStats.Average,1) + "%   max " + $diskStats.Maximum + "%")
Write-Output ("RAM used : avg " + [math]::Round($ramStats.Average,2) + " GB   max " + $ramStats.Maximum + " GB")
Write-Output ("DiskQueue: max " + $queueStats.Maximum)
