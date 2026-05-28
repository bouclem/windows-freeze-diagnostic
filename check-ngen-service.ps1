Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Output "=== Search by name pattern 'clr_optimization' ==="
$svc = Get-Service -Name 'clr*' -ErrorAction SilentlyContinue
if ($svc) {
    $svc | Format-Table Name, DisplayName, Status, StartType -AutoSize | Out-String | Write-Output
} else {
    Write-Output "(none found by 'clr*' pattern)"
}

Write-Output ""
Write-Output "=== All services with 'optimization' in name or display ==="
Get-Service | Where-Object { $_.Name -match 'optimization' -or $_.DisplayName -match 'NGEN|optimization' } |
    Format-Table Name, DisplayName, Status, StartType -AutoSize | Out-String | Write-Output

Write-Output ""
Write-Output "=== Look directly in registry for clr_optimization ==="
$svckeys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match 'clr_optimization' }
if ($svckeys) {
    foreach ($k in $svckeys) {
        Write-Output ("- " + $k.PSChildName)
    }
} else {
    Write-Output "(no clr_optimization keys in registry either)"
}

Write-Output ""
Write-Output "=== ngen.exe presence ==="
foreach ($p in @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\ngen.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\ngen.exe",
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\mscorsvw.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\mscorsvw.exe"
)) {
    if (Test-Path $p) {
        $i = Get-Item $p
        Write-Output ("FOUND: $p  ($([math]::Round($i.Length/1KB,1)) KB, last write $($i.LastWriteTime))")
    } else {
        Write-Output ("MISSING: $p")
    }
}
