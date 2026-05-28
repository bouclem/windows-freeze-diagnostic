Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$h = $env:USERPROFILE
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Report = Join-Path $ScriptDir "docs\diagnostic-report.md"

Add-Content -Path $Report -Value ""
Add-Content -Path $Report -Value "## P2.1b User home root scan (fixed)"
Add-Content -Path $Report -Value ""
Add-Content -Path $Report -Value ('Home folder: ' + $h)
Add-Content -Path $Report -Value '```'

$suspects = @(
    'node_modules','package.json','package-lock.json',
    '.npmrc','.yarnrc','yarn.lock','pnpm-lock.yaml',
    '.node-gyp','.npm','.yarn','.pnpm-store','.bun',
    '.cache','.nuget','.gradle','.m2'
)

foreach ($n in $suspects) {
    $p = Join-Path $h $n
    if (Test-Path $p) {
        $i = Get-Item $p -Force
        if ($i.PSIsContainer) {
            # Only count immediate children to stay fast
            $cnt = (Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Measure-Object).Count
            Add-Content -Path $Report -Value ("DIR  : $p  ($cnt direct children, last write $($i.LastWriteTime))")
        } else {
            Add-Content -Path $Report -Value ("FILE : $p  ($($i.Length) bytes, last write $($i.LastWriteTime))")
        }
    }
}

# List top-level entries in user home (NO recursion = fast)
Add-Content -Path $Report -Value ""
Add-Content -Path $Report -Value "Top-level entries in user home (last write date):"
Add-Content -Path $Report -Value ""

$entries = Get-ChildItem $h -Force -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object @{N='Type';E={if ($_.PSIsContainer) {'DIR'} else {'FILE'}}},
        Name, LastWriteTime,
        @{N='Size_KB';E={if (-not $_.PSIsContainer) {[math]::Round($_.Length/1KB,1)} else {''}}}

$out = ($entries | Format-Table -AutoSize | Out-String -Width 200).TrimEnd()
Add-Content -Path $Report -Value $out
Add-Content -Path $Report -Value '```'

Write-Output "Done. Wrote to $Report"
