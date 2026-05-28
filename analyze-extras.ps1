Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$Log = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "docs\freeze-log.csv"
$rows = Import-Csv $Log

Write-Output "=== Top 10 disk-busy moments ==="
$busy = $rows | Sort-Object { [double]$_.DiskBusy_pct } -Descending | Select-Object -First 10
foreach ($r in $busy) {
    Write-Output ("  [" + $r.Time + "]  Dbusy=" + $r.DiskBusy_pct + "%  Q=" + $r.DiskQueue + "  R=" + $r.DiskRead_MBs + " W=" + $r.DiskWrite_MBs + " MB/s  CPU=" + $r.CPU_pct + "%  | " + $r.Top1_Name + " " + $r.Top1_CPU_pct + "% / " + $r.Top2_Name + " " + $r.Top2_CPU_pct + "%")
}
Write-Output ""

Write-Output "=== Top 10 CPU spikes ==="
$cpubusy = $rows | Sort-Object { [double]$_.CPU_pct } -Descending | Select-Object -First 10
foreach ($r in $cpubusy) {
    Write-Output ("  [" + $r.Time + "]  CPU=" + $r.CPU_pct + "%  Dbusy=" + $r.DiskBusy_pct + "%  RAM=" + $r.RAM_used_GB + " GB  | " + $r.Top1_Name + " " + $r.Top1_CPU_pct + "% / " + $r.Top2_Name + " " + $r.Top2_CPU_pct + "%")
}
Write-Output ""

Write-Output "=== Loop lag distribution (highest 10) ==="
$lags = $rows | Sort-Object { [double]$_.LoopLag_sec } -Descending | Select-Object -First 10
foreach ($r in $lags) {
    Write-Output ("  [" + $r.Time + "]  lag=" + $r.LoopLag_sec + "s")
}
