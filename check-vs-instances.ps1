Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"

Write-Output "=== All VS instances ==="
& $vswhere -all -prerelease -format value -property displayName, installationPath, installationVersion, productId 2>&1 |
    ForEach-Object { Write-Output $_ }

Write-Output ""
Write-Output "=== Instance 84ee9a5a details ==="
$path = "C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances\84ee9a5a"
if (Test-Path $path) {
    $stateFile = Join-Path $path "state.json"
    if (Test-Path $stateFile) {
        $j = Get-Content $stateFile -Raw | ConvertFrom-Json
        Write-Output ("displayName     : " + $j.displayName)
        Write-Output ("installationName: " + $j.installationName)
        Write-Output ("installationPath: " + $j.installationPath)
        Write-Output ("productId       : " + $j.productId)
        Write-Output ("channelId       : " + $j.channelId)
    }
}

Write-Output ""
Write-Output "=== List BackgroundDownload-style scheduled tasks for VS ==="
Get-ScheduledTask -TaskPath '\Microsoft\VisualStudio\*' -ErrorAction SilentlyContinue |
    Select-Object TaskName, TaskPath, State |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Output
