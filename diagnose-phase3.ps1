Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DocsDir = Join-Path $ScriptDir "docs"
if (-not (Test-Path $DocsDir)) { New-Item -ItemType Directory -Path $DocsDir | Out-Null }
$Report = Join-Path $DocsDir "diagnostic-report.md"

function Section { param([string]$T) Add-Content -Path $Report -Value ""; Add-Content -Path $Report -Value "## $T"; Add-Content -Path $Report -Value "" }
function L      { param([string]$X) Add-Content -Path $Report -Value $X }
function Code   { param([string]$X) Add-Content -Path $Report -Value '```'; Add-Content -Path $Report -Value $X; Add-Content -Path $Report -Value '```' }

Add-Content -Path $Report -Value ""
Add-Content -Path $Report -Value "---"
Add-Content -Path $Report -Value "# Phase 3 Diagnostic"
Add-Content -Path $Report -Value "Generated: $(Get-Date)"

# --- P3.1 Windows own perf diagnostics log ---
Section "P3.1 Windows Diagnostics-Performance log (last 7 days, top 30)"
try {
    $perfEvents = @(Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 30 -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeCreated -gt (Get-Date).AddDays(-7) } |
        Select-Object TimeCreated, Id, LevelDisplayName,
            @{N='Source';E={$_.ProviderName}},
            @{N='Summary';E={(($_.Message -split "`n")[0]) -replace '\s+',' '}})
    if ($perfEvents.Length -gt 0) {
        Code (($perfEvents | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd())
    } else {
        L "(No performance diagnostic events in last 7 days.)"
    }
} catch { L "ERROR: $_" }

# --- P3.2 Decode failed scheduled task error codes ---
Section "P3.2 Failed scheduled tasks - decoded"
try {
    $codes = @{
        '2147943467'  = '0x8007054B - The specified domain either does not exist or could not be contacted.'
        '2147746132'  = '0x80070774 - The location of the file (system) is invalid (resource pointer broken).'
        '2147942583'  = '0x80070037 - The specified network resource or device is no longer available.'
        '2147942450'  = '0x80070032 - The request is not supported.'
        '2147946720'  = '0x80071A60 - The function attempted to use a name reserved for use by another transaction.'
        '2147806724'  = '0x80190194 - HTTP 404 Not Found (BITS download failed).'
        '267009'      = '0x41301 - Task is currently running.'
        '267011'      = '0x41303 - Task has not yet run.'
        '267014'      = '0x41306 - Task was terminated by the user.'
        '268435456'   = '0x10000000 - Generic failure.'
        '1'           = '0x1 - Incorrect function / generic error.'
        '2'           = '0x2 - The system cannot find the file specified.'
    }
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        if ($info -and $info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 267011) {
            $code = "$($info.LastTaskResult)"
            $human = if ($codes.ContainsKey($code)) { $codes[$code] } else { 'Unknown code, search Microsoft Win32 error code list.' }
            [PSCustomObject]@{
                Task     = $_.TaskName
                Path     = $_.TaskPath
                LastRun  = $info.LastRunTime
                Code     = $code
                Meaning  = $human
                State    = $_.State
            }
        }
    } | Sort-Object LastRun -Descending | Select-Object -First 25
    if ($tasks) {
        Code (($tasks | Format-Table -AutoSize -Wrap | Out-String -Width 240).TrimEnd())
    } else {
        L "(No failing scheduled tasks now.)"
    }
} catch { L "ERROR: $_" }

# --- P3.3 .NET NGEN events ---
Section "P3.3 .NET / NGEN events (last 7 days, top 20)"
try {
    $ngen = @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='.NET Runtime Optimization Service'; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 20 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, @{N='Msg';E={(($_.Message -split "`n")[0]) -replace '\s+',' '}})
    if ($ngen.Length -gt 0) {
        Code (($ngen | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd())
    } else {
        L "(No NGEN events in last 7 days.)"
    }
} catch { L "ERROR: $_" }

# --- P3.4 Display / GPU events ---
Section "P3.4 Display / GPU events (last 24h)"
try {
    $gpu = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'Display|amdkmdag|nvlddmkm|igdkmd|Dxgkrnl|TDR' -or $_.Id -in 4101,4102,153 } |
        Select-Object TimeCreated, Id, ProviderName, @{N='Msg';E={(($_.Message -split "`n")[0]) -replace '\s+',' '}} -First 15)
    if ($gpu.Length -gt 0) {
        Code (($gpu | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd())
    } else {
        L "(No GPU/display events in last 24h - good sign.)"
    }
} catch { L "ERROR: $_" }

# --- P3.5 DistributedCOM 10016 ---
Section "P3.5 DistributedCOM 10016 errors (last 24h)"
try {
    $dcom = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DistributedCOM'; Id=10016; StartTime=(Get-Date).AddDays(-1)} -MaxEvents 10 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, @{N='Msg';E={(($_.Message -split "`n") -join ' ') -replace '\s+',' '}})
    if ($dcom.Length -gt 0) {
        foreach ($e in $dcom) {
            $short = $e.Msg
            if ($short.Length -gt 250) { $short = $short.Substring(0, 250) + '...' }
            L ("- [" + $e.TimeCreated + "] " + $short)
        }
    } else {
        L "(No DCOM 10016 in last 24h.)"
    }
} catch { L "ERROR: $_" }

# --- P3.6 Icon / Thumb cache ---
Section "P3.6 Icon / Thumb cache state"
try {
    $cacheDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    if (Test-Path $cacheDir) {
        $files = Get-ChildItem $cacheDir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^iconcache|^thumbcache' } |
            Sort-Object Length -Descending |
            Select-Object Name, @{N='Size_MB';E={[math]::Round($_.Length/1MB,2)}}, LastWriteTime
        if ($files) {
            Code (($files | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())
        } else {
            L "(No icon/thumb cache files found - they get rebuilt automatically.)"
        }
    } else {
        L "Explorer cache dir not found."
    }
} catch { L "ERROR: $_" }

# --- P3.7 ESET activity ---
Section "P3.7 ESET service / events"
try {
    $eset = Get-Service | Where-Object { $_.Name -match '^e' -and $_.DisplayName -match 'ESET' } | Select-Object Name, DisplayName, Status, StartType
    if ($eset) {
        Code (($eset | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())
    }
    $esetEvents = @(Get-WinEvent -LogName 'Application' -MaxEvents 200 -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'ESET' -and $_.TimeCreated -gt (Get-Date).AddDays(-1) } |
        Select-Object TimeCreated, Id, LevelDisplayName, @{N='Msg';E={(($_.Message -split "`n")[0]) -replace '\s+',' '}} -First 10)
    if ($esetEvents.Length -gt 0) {
        Code (($esetEvents | Format-Table -AutoSize -Wrap | Out-String -Width 200).TrimEnd())
    } else {
        L "(No ESET events in last 24h - suggests it's quiet.)"
    }
} catch { L "ERROR: $_" }

# --- P3.8 Reliability monitor (system stability index) ---
Section "P3.8 System Reliability score (last 14 days)"
try {
    $rel = @(Get-CimInstance Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue |
        Sort-Object TimeGenerated -Descending |
        Select-Object -First 14 @{N='Date';E={$_.TimeGenerated}}, @{N='Score';E={[math]::Round($_.SystemStabilityIndex,2)}})
    if ($rel.Length -gt 0) {
        Code (($rel | Format-Table -AutoSize | Out-String -Width 100).TrimEnd())
    } else {
        L "(Reliability data not available.)"
    }
} catch { L "ERROR: $_" }

# --- P3.9 Recent reliability records (crashes / hangs) ---
Section "P3.9 Recent app crashes / hangs (last 7 days)"
try {
    $rec = @(Get-CimInstance Win32_ReliabilityRecords -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeGenerated -gt (Get-Date).AddDays(-7) -and $_.SourceName -match 'Hang|Crash|Error' } |
        Sort-Object TimeGenerated -Descending |
        Select-Object -First 15 TimeGenerated, SourceName, ProductName, @{N='Msg';E={(($_.Message -split "`n")[0])}})
    if ($rec.Length -gt 0) {
        Code (($rec | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd())
    } else {
        L "(No app hangs/crashes recorded in last 7 days.)"
    }
} catch { L "ERROR: $_" }

Section "Phase 3 done"
Write-Output "Phase 3 appended to: $Report"
