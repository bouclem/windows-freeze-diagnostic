Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ----------------------------------------------------------------------
# NGEN repair (REQUIRES ADMIN)
# Re-registers and restarts .NET Framework Optimization services,
# then queues a rebuild of native images.
# ----------------------------------------------------------------------

# Verify admin
$current = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($current)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell, choose 'Run as administrator', then run this script."
    exit 1
}

Write-Host "=== NGEN repair (admin mode) ===" -ForegroundColor Cyan
Write-Host ""

$services = @(
    'clr_optimization_v4.0.30319_32',
    'clr_optimization_v4.0.30319_64',
    'clr_optimization_v2.0.50727_32',
    'clr_optimization_v2.0.50727_64'
)

# Step 1: state via sc.exe (more robust than Get-Service when SCM is glitchy)
Write-Host "--- Step 1: current service state via sc.exe query ---" -ForegroundColor Yellow
foreach ($s in $services) {
    Write-Host ""
    Write-Host "  Service: $s"
    & sc.exe query $s 2>&1 | ForEach-Object { Write-Host "    $_" }
}

# Step 2: try to start each
Write-Host ""
Write-Host "--- Step 2: starting each NGEN service ---" -ForegroundColor Yellow
foreach ($s in $services) {
    Write-Host ""
    Write-Host "  Starting: $s"
    & sc.exe start $s 2>&1 | ForEach-Object { Write-Host "    $_" }
}

# Step 3: queue rebuild via ngen.exe
Write-Host ""
Write-Host "--- Step 3: ngen.exe update /queue ---" -ForegroundColor Yellow
$ngens = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\ngen.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\ngen.exe"
)
foreach ($n in $ngens) {
    if (Test-Path $n) {
        Write-Host ""
        Write-Host "  Running: $n update /queue"
        & $n update /queue 2>&1 | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-Host "  Not found: $n (skipping)"
    }
}

# Step 4: final state
Write-Host ""
Write-Host "--- Step 4: final service state ---" -ForegroundColor Yellow
foreach ($s in $services) {
    Write-Host ""
    Write-Host "  Service: $s"
    & sc.exe query $s 2>&1 | ForEach-Object { Write-Host "    $_" }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "If services started successfully, native images will rebuild in the background"
Write-Host "during idle moments. This can take 10-30 min spread over normal usage."
Write-Host ""
Write-Host "If services still fail to start, the next step is 'sfc /scannow' and 'DISM /Online"
Write-Host "/Cleanup-Image /RestoreHealth' to repair Windows component store."
