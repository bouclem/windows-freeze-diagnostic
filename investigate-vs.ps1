Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Report = Join-Path $ScriptDir "docs\vs-investigation.md"
# Reset
Set-Content -Path $Report -Value "# Phase 5 - VS BackgroundDownload investigation"
Add-Content -Path $Report -Value "Generated: $(Get-Date)"

function Section { param([string]$T) Add-Content -Path $Report -Value ""; Add-Content -Path $Report -Value "## $T"; Add-Content -Path $Report -Value "" }
function L { param([string]$X) Add-Content -Path $Report -Value $X }
function Code { param([string]$X) Add-Content -Path $Report -Value '```'; Add-Content -Path $Report -Value $X; Add-Content -Path $Report -Value '```' }

# 1. VS Installer location & version
Section "P5.1 Visual Studio Installer presence"
$vsInstaller = "C:\Program Files (x86)\Microsoft Visual Studio\Installer"
if (Test-Path $vsInstaller) {
    L "Path: $vsInstaller"
    $items = Get-ChildItem $vsInstaller -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.exe$' } | Select-Object Name, Length, LastWriteTime
    Code (($items | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())
} else {
    L "Visual Studio Installer NOT FOUND at default location."
}

# 2. VS Installations registered
Section "P5.2 VS instances installed (vswhere)"
$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    try {
        $vsInfo = & $vswhere -all -prerelease -format json 2>&1 | Out-String
        Code $vsInfo.Trim()
    } catch {
        L "vswhere failed: $_"
    }
} else {
    L "vswhere.exe not found"
}

# 3. Pending state of VS packages (the killer info)
Section "P5.3 Pending package state (_Instances folder)"
$instancesPath = "C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances"
if (Test-Path $instancesPath) {
    $instances = Get-ChildItem $instancesPath -Directory -ErrorAction SilentlyContinue
    foreach ($inst in $instances) {
        L ""
        L ("Instance: " + $inst.Name)
        L ""
        $stateFiles = Get-ChildItem $inst.FullName -File -ErrorAction SilentlyContinue |
            Select-Object Name, @{N='Size_KB';E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime
        Code (($stateFiles | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())

        # Look for state.packages.json (lists pending downloads)
        $stateJson = Join-Path $inst.FullName "state.packages.json"
        if (Test-Path $stateJson) {
            try {
                $j = Get-Content $stateJson -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
                if ($j -and ($j.PSObject.Properties.Name -contains 'packages')) {
                    L "Pending/recorded packages count: $($j.packages.Length)"
                }
            } catch { L "Could not parse state.packages.json: $_" }
        }
    }
} else {
    L "$instancesPath not found"
}

# 4. Packages folder size & recent activity
Section "P5.4 Packages folder snapshot"
$pkgRoot = "C:\ProgramData\Microsoft\VisualStudio\Packages"
if (Test-Path $pkgRoot) {
    # Top-level only, no recursion (would be huge)
    $top = Get-ChildItem $pkgRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 15 Name, LastWriteTime
    Code (($top | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())

    # Look for partial / .download / .tmp files (corruption indicator)
    L ""
    L "Searching for partial download files (top 20):"
    L ""
    $partials = Get-ChildItem $pkgRoot -Recurse -ErrorAction SilentlyContinue -File |
        Where-Object { $_.Name -match '\.download$|\.tmp$|\.partial$|\.0\d+$' } |
        Sort-Object Length -Descending |
        Select-Object -First 20 FullName, @{N='Size_MB';E={[math]::Round($_.Length/1MB,1)}}, LastWriteTime
    if ($partials) {
        Code (($partials | Format-Table -AutoSize -Wrap | Out-String -Width 240).TrimEnd())
    } else {
        L "(No partial files found.)"
    }
}

# 5. VS Installer logs - find the most recent
Section "P5.5 Most recent VS Installer / Setup logs"
$logRoots = @("$env:TEMP", "$env:ProgramData\Microsoft\VisualStudio\Setup\Logs", "$env:ProgramData\Microsoft\VisualStudio\Packages")
$found = @()
foreach ($r in $logRoots) {
    if (Test-Path $r) {
        $found += Get-ChildItem $r -Recurse -File -ErrorAction SilentlyContinue -Filter "dd_*.log" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 5
        $found += Get-ChildItem $r -File -ErrorAction SilentlyContinue -Filter "BackgroundDownload*.log" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 5
    }
}
$found = $found | Sort-Object LastWriteTime -Descending | Select-Object -First 8 FullName, @{N='Size_KB';E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime
if ($found) {
    Code (($found | Format-Table -AutoSize -Wrap | Out-String -Width 240).TrimEnd())
} else {
    L "(No VS Installer logs found.)"
}

# 6. Tail of the most recent dd_setup or BackgroundDownload log
Section "P5.6 Last 80 lines of most recent VS log (looking for the actual error)"
$mostRecent = $found | Select-Object -First 1
if ($mostRecent) {
    L ("Reading: " + $mostRecent.FullName)
    L ""
    $tail = Get-Content $mostRecent.FullName -Tail 80 -ErrorAction SilentlyContinue
    Code ($tail -join "`n")
} else {
    L "(No log to read.)"
}

# 7. Last execution events for BackgroundDownload task
Section "P5.7 Recent Task Scheduler events for BackgroundDownload"
try {
    $events = @(Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -MaxEvents 200 -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                ($_.Message -match 'BackgroundDownload') -or
                ($_.Properties.Count -gt 0 -and $_.Properties[0].Value -match 'BackgroundDownload')
            } catch { $false }
        } |
        Select-Object -First 12 TimeCreated, Id, LevelDisplayName, @{N='Msg';E={(($_.Message -split "`n")[0]) -replace '\s+',' '}})
    if ($events.Length -gt 0) {
        Code (($events | Format-Table -AutoSize -Wrap | Out-String -Width 240).TrimEnd())
    } else {
        L "(No matching events.)"
    }
} catch { L "ERROR: $_" }

Write-Output "Phase 5 appended to: $Report"
