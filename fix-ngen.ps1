Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Output "=== NGEN repair ==="
Write-Output ""

$ngen64 = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\ngen.exe"
$ngen32 = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\ngen.exe"

foreach ($p in @($ngen64, $ngen32)) {
    if (Test-Path $p) {
        Write-Output "----------------------------------------"
        Write-Output "Running: $p update /queue"
        Write-Output "----------------------------------------"
        & $p update /queue 2>&1 | ForEach-Object { Write-Output ('  ' + $_) }
        Write-Output ""
    } else {
        Write-Output "Not found: $p (skipping)"
    }
}

Write-Output "=== Status ==="
foreach ($p in @($ngen64, $ngen32)) {
    if (Test-Path $p) {
        Write-Output ""
        Write-Output "Queue status: $p"
        & $p queue status 2>&1 | ForEach-Object { Write-Output ('  ' + $_) }
    }
}

Write-Output ""
Write-Output "=== NGEN service state ==="
Get-Service | Where-Object { $_.Name -match 'clr_optimization' } |
    Select-Object Name, DisplayName, Status, StartType |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Output

Write-Output "Done."
Write-Output ""
Write-Output "Native images will rebuild in the background while your system is idle."
Write-Output "You don't need to do anything. It can take 10-30 minutes spread over normal usage."
