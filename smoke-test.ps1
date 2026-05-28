Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Output "=== Smoke test: WMI counters ==="

try {
    $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
    Write-Output ("CPU: " + $cpu.PercentProcessorTime + "%   Idle: " + $cpu.PercentIdleTime + "%")
} catch {
    Write-Output ("CPU class FAILED: " + $_.Exception.Message)
}

try {
    $disk = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
    Write-Output ("DiskQueue: " + $disk.CurrentDiskQueueLength + "   PctTime: " + $disk.PercentDiskTime + "%   Read: " + [math]::Round($disk.DiskReadBytesPerSec/1MB,2) + " MB/s   Write: " + [math]::Round($disk.DiskWriteBytesPerSec/1MB,2) + " MB/s")
} catch {
    Write-Output ("Disk class FAILED: " + $_.Exception.Message)
}
