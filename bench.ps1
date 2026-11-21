<#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025 useless-rs
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version. This program is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#>

#requires -Version 5.1

param(
    [switch]$Quick,
    [switch]$Standard,
    [switch]$Full,
    [string[]]$Only,
    [string[]]$Skip,
    [switch]$AllDrives,
    [switch]$NoDownloads,
    [switch]$DownloadBenchmarks,
    [switch]$UseInstalledBenchmarks,
    [switch]$NoProprietary,
    [switch]$AllowNetwork,
    [switch]$AllowLargeDownloads,
    [string]$Endpoint,
    [switch]$Help,
    [switch]$Version,
    [string]$Output,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$HBSS_VERSION = '1.0.0'

if ($Help) {
    Write-Output @'
HBSS - Hardware Benchmark Suite Script 1.0.0 (Windows, PowerShell 5.1)

Usage:
  run.ps1 [-Quick|-Standard|-Full] [-Only cpu,gpu,...] [-Skip cpu,gpu,...]
          [-AllDrives] [-NoDownloads] [-DownloadBenchmarks]
          [-UseInstalledBenchmarks] [-NoProprietary]
          [-AllowNetwork -Endpoint host[:port]] [-AllowLargeDownloads]
          [-Output <file>] [-Json] [-Help] [-Version]

Profiles: Quick (90 s budget), Standard (600 s, default), Full (900 s).
Categories: cpu, gpu, memory, storage, network, npu, crypto, thermals, other.

Default policy: no third-party downloads; built-in .NET/PowerShell fallback
benchmarks are used. Pinned official engines (DiskSpd, fio) are downloaded and
SHA-256 verified only with -DownloadBenchmarks. -NoDownloads overrides all
download flags. Proprietary tools are detected only; they are never downloaded,
license-accepted, or result-uploaded.

Report is written to stdout as Markdown. External tool output is captured to
log files inside a temporary workspace and is never written to stdout.
'@
    exit 0
}

if ($Version) {
    Write-Output "HBSS $HBSS_VERSION"
    exit 0
}

# ---------------------------------------------------------------------------
# Profile, budgets and selection
# ---------------------------------------------------------------------------

$profileName = 'Standard'
if ($Full) { $profileName = 'Full' }
elseif ($Quick) { $profileName = 'Quick' }
elseif ($Standard) { $profileName = 'Standard' }

$budgetTable = @{ Quick = 90; Standard = 600; Full = 900 }
$cpuCapTable = @{ Quick = 20; Standard = 60; Full = 120 }
$memCapTable = @{ Quick = 10; Standard = 30; Full = 60 }
$stoCapTable = @{ Quick = 15; Standard = 45; Full = 90 }
$gpuCapTable = @{ Quick = 30; Standard = 120; Full = 240 }
$stoFileTable = @{
    Quick = [int64]256 * 1024 * 1024
    Standard = [int64]1024 * 1024 * 1024
    Full = [int64]2048 * 1024 * 1024
}
$cryptoCapTable = @{ Quick = 20; Standard = 45; Full = 90 }

$profileBudget = [int]$budgetTable[$profileName]
$cpuCap = [int]$cpuCapTable[$profileName]
$memCap = [int]$memCapTable[$profileName]
$stoCap = [int]$stoCapTable[$profileName]
$gpuCap = [int]$gpuCapTable[$profileName]
$stoFileCap = [int64]$stoFileTable[$profileName]
$cryptoCap = [int]$cryptoCapTable[$profileName]

$allCategories = @('cpu', 'gpu', 'memory', 'storage', 'network', 'npu', 'crypto', 'thermals', 'other')
$selected = @()
if ($Only -and ($Only.Count -gt 0)) {
    foreach ($item in $Only) {
        $norm = ([string]$item).Trim().ToLowerInvariant()
        if (($allCategories -contains $norm) -and ($selected -notcontains $norm)) {
            $selected += $norm
        }
    }
}
else {
    $selected = @($allCategories)
}
if ($Skip -and ($Skip.Count -gt 0)) {
    foreach ($item in $Skip) {
        $norm = ([string]$item).Trim().ToLowerInvariant()
        $selected = @($selected | Where-Object { $_ -ne $norm })
    }
}

function Test-Category {
    param([string]$Name)
    return ($selected -contains $Name)
}

function Test-Budget {
    return ([DateTime]::UtcNow -le $deadlineUtc)
}

function Run-Category {
    param([string]$Category, [scriptblock]$Body)
    if (-not (Test-Category $Category)) { return }
    if (-not (Test-Budget)) {
        Add-SkippedItem -Benchmark ($Category + ' suite') -Category $Category -Reason ('Global ' + $profileBudget + ' s budget reached; remaining tests skipped')
        return
    }
    try {
        & $Body
    }
    catch {
        $script:failedCount++
        Add-SkippedItem -Benchmark ($Category + ' suite') -Category $Category -Reason ('Unexpected error: ' + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

$startedUtc = [DateTime]::UtcNow
$deadlineUtc = $startedUtc.AddSeconds($profileBudget)
$script:results = @()
$script:skipped = @()
$script:failedCount = 0
$script:tempDir = $null
$script:reportLines = New-Object 'System.Collections.Generic.List[string]'
$script:hardTimeoutReached = $false

$pinnedAssets = @{
    DiskSpdUrl = 'https://github.com/microsoft/diskspd/releases/download/v2.3/DiskSpd.ZIP'
    DiskSpdSha = '18609981e8b04b4f645f1fd182ad0541615fe71722de36a9a933c54f747218a3'
    FioUrl = 'https://github.com/axboe/fio/releases/download/3.43/fio-3.43-x64.msi'
    FioSha = '8299e6e6fbc024d3b74aa1ce62fb94ef6960b45629fbfa678b720834b6eb34aa'
}

# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

function Add-Line {
    param([string]$Text = '')
    $script:reportLines.Add($Text)
}

function Add-SectionBreak {
    Add-Line ''
    Add-Line '---'
    Add-Line ''
}

function Escape-Md {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    $s = $s -replace '\|', '\|'
    $s = $s -replace '\r\n|\r|\n', ' '
    return $s
}

function Code-Md {
    param([object]$Value)
    $text = Escape-Md -Value $Value
    if ([string]::IsNullOrEmpty($text)) { return '' }
    return '`' + $text + '`'
}

function Add-Result {
    param([hashtable]$Fields)
    $script:results += [pscustomobject]@{
        Benchmark = $Fields.Benchmark
        Category = $Fields.Category
        Engine = $Fields.Engine
        Version = $Fields.Version
        Workload = $Fields.Workload
        Threads = $Fields.Threads
        Dataset = $Fields.Dataset
        Duration = $Fields.Duration
        Result = $Fields.Result
        Unit = $Fields.Unit
        Origin = $Fields.Origin
        Notes = $Fields.Notes
    }
}

function Add-SkippedItem {
    param([string]$Benchmark, [string]$Category, [string]$Reason)
    $script:skipped += [pscustomobject]@{
        Benchmark = $Benchmark
        Category = $Category
        Reason = $Reason
        Profile = $profileName
    }
}

function Get-CommandPath {
    param([string]$Name)
    try {
        $found = @(Get-Command -Name $Name -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) {
            return [string]$found[0].Source
        }
    }
    catch {
        return $null
    }
    return $null
}

function Get-CimSafe {
    param([string]$ClassName, [string]$Namespace = 'root\cimv2')
    try {
        return @(Get-CimInstance -ClassName $ClassName -Namespace $Namespace -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

function Get-QuotedArgument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -match '[\s"]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }
    return $Value
}

# Runs a native tool with both streams redirected to files in the temp
# workspace, so nothing the tool prints can ever reach HBSS stdout.
function Invoke-ExternalTool {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments,
        [string]$LogPath,
        [int]$TimeoutSeconds = 60,
        [string]$WorkingDirectory
    )

    $stdout = ''
    $stderr = ''
    $timedOut = $false
    $exitCode = -1

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $argParts = @()
    if ($Arguments) {
        foreach ($a in $Arguments) {
            $argParts += (Get-QuotedArgument -Value ([string]$a))
        }
    }
    $psi.Arguments = ($argParts -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        [void]$proc.Start()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            try { $proc.Kill() } catch { }
        }
        try { $stdout = $outTask.Result } catch { $stdout = '' }
        try { $stderr = $errTask.Result } catch { $stderr = '' }
        try { $exitCode = $proc.ExitCode } catch { $exitCode = -1 }
    }
    catch {
        $stderr = $_.Exception.Message
    }
    finally {
        try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
        try { $proc.Dispose() } catch { }
    }

    if ($LogPath) {
        try {
            $combined = $stdout
            if (-not [string]::IsNullOrEmpty($stderr)) {
                if ($combined.Length -gt 0) { $combined += "`n" }
                $combined += '--- STDERR ---' + "`n" + $stderr
            }
            [System.IO.File]::WriteAllText($LogPath, $combined)
        }
        catch {
            # Logging is best-effort; a report note is added by the caller.
        }
    }

    return [pscustomobject]@{
        TimedOut = $timedOut
        ExitCode = $exitCode
        LogPath = $LogPath
        StdOut = $stdout
        StdErr = $stderr
    }
}

# 5.1-compatible timeout wrapper: Start-Job + Wait-Job -Timeout + Stop-Job.
function Invoke-WithTimeout {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Script,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [string]$Label = 'task',
        [object[]]$Arguments
    )

    $job = $null
    try {
        if ($Arguments -and ($Arguments.Count -gt 0)) {
            $job = Start-Job -ScriptBlock $Script -ArgumentList $Arguments
        }
        else {
            $job = Start-Job -ScriptBlock $Script
        }

        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if ($null -eq $completed) {
            try { Stop-Job -Job $job -ErrorAction SilentlyContinue } catch { }
            return [pscustomobject]@{
                Completed = $false
                TimedOut = $true
                Result = $null
                Error = ('Timeout after ' + $TimeoutSeconds + ' s: ' + $Label)
            }
        }

        $output = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        $errorText = ''
        try {
            $childErrors = @()
            foreach ($child in $job.ChildJobs) { $childErrors += @($child.JobError) }
            if ($childErrors.Count -gt 0) { $errorText = ($childErrors -join '; ') }
        }
        catch {
            $errorText = ''
        }
        if (($job.State -eq 'Failed') -and ([string]::IsNullOrEmpty($errorText))) {
            $errorText = 'Job failed'
        }
        return [pscustomobject]@{
            Completed = ($job.State -eq 'Completed')
            TimedOut = $false
            Result = $output
            Error = $errorText
        }
    }
    catch {
        return [pscustomobject]@{
            Completed = $false
            TimedOut = $false
            Result = $null
            Error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $job) {
            try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}

function Convert-ToMbPerSec {
    param([double]$Bytes, [double]$Milliseconds)
    if ($Milliseconds -le 0) { return '0.00' }
    return ([math]::Round(($Bytes / ($Milliseconds / 1000.0)) / 1000000.0, 2)).ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
}

# ---------------------------------------------------------------------------
# Engine acquisition (opt-in only)
# ---------------------------------------------------------------------------

function Get-VerifiedAsset {
    param(
        [string]$Url,
        [string]$Sha256,
        [string]$FileName
    )

    $destination = Join-Path $script:tempDir $FileName
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $destination -ErrorAction Stop
        $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        if ($actual -ne $Sha256.ToLowerInvariant()) {
            return [pscustomobject]@{ Ok = $false; Path = $null; Reason = ('SHA-256 mismatch: expected ' + $Sha256 + ', got ' + $actual) }
        }
        return [pscustomobject]@{ Ok = $true; Path = $destination; Reason = '' }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Path = $null; Reason = $_.Exception.Message }
    }
}

function Resolve-DiskSpd {
    $installed = Get-CommandPath 'diskspd.exe'
    if (-not $installed) { $installed = Get-CommandPath 'diskspd' }
    if ($installed -and (Test-Path -LiteralPath $installed -PathType Leaf)) {
        return [pscustomobject]@{ Ok = $true; Path = $installed; Reason = '' }
    }

    if ($NoDownloads) {
        return [pscustomobject]@{ Ok = $false; Path = $null; Reason = 'DiskSpd not installed; downloads disabled (-NoDownloads)' }
    }
    if (-not $DownloadBenchmarks) {
        return [pscustomobject]@{ Ok = $false; Path = $null; Reason = 'DiskSpd not installed; opt in with -DownloadBenchmarks' }
    }

    $asset = Get-VerifiedAsset -Url $pinnedAssets.DiskSpdUrl -Sha256 $pinnedAssets.DiskSpdSha -FileName 'DiskSpd.ZIP'
    if (-not $asset.Ok) {
        return [pscustomobject]@{ Ok = $false; Path = $null; Reason = ('DiskSpd download failed: ' + $asset.Reason) }
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $extractDir = Join-Path $script:tempDir 'diskspd-extract'
        if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($asset.Path, $extractDir)
        $all = @(Get-ChildItem -LiteralPath $extractDir -Filter 'diskspd.exe' -Recurse -File -ErrorAction SilentlyContinue)
        if ($all.Count -eq 0) {
            return [pscustomobject]@{ Ok = $false; Path = $null; Reason = 'DiskSpd ZIP contained no diskspd.exe' }
        }
        $preferred = @($all | Where-Object { $_.FullName -match 'amd64' })
        $chosen = if ($preferred.Count -gt 0) { $preferred[0] } else { $all[0] }
        return [pscustomobject]@{ Ok = $true; Path = $chosen.FullName; Reason = '' }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Path = $null; Reason = ('DiskSpd extraction failed: ' + $_.Exception.Message) }
    }
}

function Resolve-Fio {
    $installed = Get-CommandPath 'fio.exe'
    if (-not $installed) { $installed = Get-CommandPath 'fio' }
    if ($installed -and (Test-Path -LiteralPath $installed -PathType Leaf)) {
        return [pscustomobject]@{ Ok = $true; Path = $installed; Reason = '' }
    }

    if ($NoDownloads) {
        return [pscustomobject]@{ Ok = $false; Path = $null; Reason = 'fio not installed; downloads disabled (-NoDownloads)' }
    }
    if (-not $DownloadBenchmarks) {
        return [pscustomobject]@{ Ok = $false; Path = $null; Reason = 'fio not installed; opt in with -DownloadBenchmarks' }
    }

    $asset = Get-VerifiedAsset -Url $pinnedAssets.FioUrl -Sha256 $pinnedAssets.FioSha -FileName 'fio-3.43-x64.msi'
    if (-not $asset.Ok) {
        return [pscustomobject]@{ Ok = $false; Path = $null; Reason = ('fio download failed: ' + $asset.Reason) }
    }

    try {
        $extractDir = Join-Path $script:tempDir 'fio-extract'
        if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
        [void](New-Item -ItemType Directory -Path $extractDir -Force)
        $msiexec = Join-Path $env:WINDIR 'System32\msiexec.exe'
        if (-not (Test-Path -LiteralPath $msiexec -PathType Leaf)) {
            return [pscustomobject]@{ Ok = $false; Path = $null; Reason = 'MSI extractor (msiexec.exe) unavailable' }
        }
        $run = Invoke-ExternalTool -FilePath $msiexec -Arguments @('/a', $asset.Path, '/qn', ('TARGETDIR=' + $extractDir)) -LogPath (Join-Path $script:tempDir 'fio-extract.log') -TimeoutSeconds 180
        if ($run.TimedOut) {
            return [pscustomobject]@{ Ok = $false; Path = $null; Reason = 'MSI extraction timed out' }
        }
        $all = @(Get-ChildItem -LiteralPath $extractDir -Filter 'fio.exe' -Recurse -File -ErrorAction SilentlyContinue)
        if ($all.Count -eq 0) {
            return [pscustomobject]@{ Ok = $false; Path = $null; Reason = 'No MSI extractor produced fio.exe (extraction skipped)' }
        }
        return [pscustomobject]@{ Ok = $true; Path = $all[0].FullName; Reason = '' }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Path = $null; Reason = ('fio extraction failed: ' + $_.Exception.Message) }
    }
}

# ---------------------------------------------------------------------------
# Inventory
# ---------------------------------------------------------------------------

$script:inv = @{}
function Read-Inventory {
    $script:inv['Processor'] = @(Get-CimSafe 'Win32_Processor')
    $script:inv['Memory'] = @(Get-CimSafe 'Win32_PhysicalMemory')
    $script:inv['Video'] = @(Get-CimSafe 'Win32_VideoController')
    $script:inv['DiskDrive'] = @(Get-CimSafe 'Win32_DiskDrive')
    $script:inv['Os'] = @(Get-CimSafe 'Win32_OperatingSystem')
    $script:inv['Board'] = @(Get-CimSafe 'Win32_BaseBoard')
    $script:inv['Bios'] = @(Get-CimSafe 'Win32_BIOS')
    $script:inv['Battery'] = @(Get-CimSafe 'Win32_Battery')
    $script:inv['Adapter'] = @(Get-CimSafe 'Win32_NetworkAdapter')
    $script:inv['Pnp'] = @(Get-CimSafe 'Win32_PnPEntity')
    $script:inv['Computer'] = @(Get-CimSafe 'Win32_ComputerSystem')

    try {
        $script:inv['PhysicalDisk'] = @(Get-PhysicalDisk -ErrorAction Stop)
    }
    catch {
        $script:inv['PhysicalDisk'] = @()
    }

    $temperatures = @()
    try {
        $wmiTemps = @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop)
        foreach ($t in $wmiTemps) {
            $raw = $null
            try { $raw = [double]$t.CurrentTemperature } catch { $raw = $null }
            if ($null -ne $raw) {
                $temperatures += [pscustomobject]@{
                    Source = 'MSAcpi_ThermalZoneTemperature'
                    Instance = [string]$t.InstanceName
                    Reading = (($raw / 10.0) - 273.15).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' C'
                }
            }
        }
    }
    catch {
        # Thermal zone data is frequently unavailable without elevation.
    }
    foreach ($p in @(Get-CimSafe 'Win32_TemperatureProbe')) {
        $reading = $null
        try { $reading = [string]$p.CurrentReading } catch { $reading = $null }
        $temperatures += [pscustomobject]@{
            Source = 'Win32_TemperatureProbe'
            Instance = [string]$p.Name
            Reading = $(if ($reading) { $reading + ' (vendor units)' } else { 'unavailable' })
        }
    }
    $script:inv['Temperature'] = $temperatures
}

# ---------------------------------------------------------------------------
# CPU benchmarks
# ---------------------------------------------------------------------------

function Invoke-CpuBenchmarks {
    $iterSingle = [int](@{ Quick = 1000000; Standard = 4000000; Full = 10000000 }[$profileName])
    $iterThread = [int](@{ Quick = 500000; Standard = 1000000; Full = 3000000 }[$profileName])

    $intScript = {
        param([int]$N)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $x = [long]88172645463325252
        for ($i = 0; $i -lt $N; $i++) {
            $x = $x -bxor ($x -shl 13)
            $x = $x -bxor ($x -shr 7)
            $x = $x -bxor ($x -shl 17)
        }
        $sw.Stop()
        [pscustomobject]@{ Ms = $sw.Elapsed.TotalMilliseconds; N = $N; Check = $x.ToString() }
    }

    $fpScript = {
        param([int]$N)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $d = 1.0000001
        $acc = 0.0
        for ($i = 0; $i -lt $N; $i++) {
            $d = $d * 1.0000001 + 0.0000001
            $acc += $d
            if ($acc -gt 1.0e12) { $acc = $acc / 1.0e6 }
        }
        $sw.Stop()
        [pscustomobject]@{ Ms = $sw.Elapsed.TotalMilliseconds; N = $N; Check = $acc.ToString('F3') }
    }

    $r = Invoke-WithTimeout -Script $intScript -Arguments @($iterSingle) -TimeoutSeconds $cpuCap -Label 'CPU integer single-thread'
    if ($r.Completed -and $r.Result.Count -gt 0) {
        $o = $r.Result[0]
        $mps = Convert-ToMbPerSec -Bytes ([double]$o.N) -Milliseconds ([double]$o.Ms)
        Add-Result @{
            Benchmark = 'CPU integer (single-thread)'; Category = 'cpu'
            Engine = 'HBSS .NET/PowerShell loop'; Version = $HBSS_VERSION
            Workload = '64-bit xorshift integer mix'; Threads = '1'
            Dataset = ($o.N.ToString() + ' iterations')
            Duration = (([double]$o.Ms).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' ms')
            Result = $mps; Unit = 'Mops/s'; Origin = 'HBSS fallback'
            Notes = ('checksum ' + $o.Check + '; PowerShell interpreter overhead included')
        }
    }
    else {
        $script:failedCount++
        Add-SkippedItem -Benchmark 'CPU integer (single-thread)' -Category 'cpu' -Reason $(if ($r.TimedOut) { 'Exceeded per-test CPU cap' } else { 'Execution error: ' + $r.Error })
    }

    $r = Invoke-WithTimeout -Script $fpScript -Arguments @($iterSingle) -TimeoutSeconds $cpuCap -Label 'CPU floating-point single-thread'
    if ($r.Completed -and $r.Result.Count -gt 0) {
        $o = $r.Result[0]
        $mps = Convert-ToMbPerSec -Bytes ([double]$o.N) -Milliseconds ([double]$o.Ms)
        Add-Result @{
            Benchmark = 'CPU floating-point (single-thread)'; Category = 'cpu'
            Engine = 'HBSS .NET/PowerShell loop'; Version = $HBSS_VERSION
            Workload = 'double-precision multiply-accumulate'; Threads = '1'
            Dataset = ($o.N.ToString() + ' iterations')
            Duration = (([double]$o.Ms).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' ms')
            Result = $mps; Unit = 'Mops/s'; Origin = 'HBSS fallback'
            Notes = ('checksum ' + $o.Check + '; PowerShell interpreter overhead included')
        }
    }
    else {
        $script:failedCount++
        Add-SkippedItem -Benchmark 'CPU floating-point (single-thread)' -Category 'cpu' -Reason $(if ($r.TimedOut) { 'Exceeded per-test CPU cap' } else { 'Execution error: ' + $r.Error })
    }

    $logical = 1
    try {
        $sum = (Get-CimSafe 'Win32_Processor' | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        if ($sum -and $sum -ge 1) { $logical = [int]$sum }
    }
    catch {
        $logical = 1
    }
    $threadCount = $logical
    if ($threadCount -gt 8) { $threadCount = 8 }

    $cpuKinds = @(
        [pscustomobject]@{ Name = 'integer'; Script = $intScript },
        [pscustomobject]@{ Name = 'floating-point'; Script = $fpScript }
    )
    foreach ($kind in $cpuKinds) {
        $labelName = [string]$kind.Name
        $workScript = [scriptblock]$kind.Script
        $jobs = @()
        $allOk = $true
        $wallMs = 0.0
        try {
            for ($t = 0; $t -lt $threadCount; $t++) {
                $jobs += Start-Job -ScriptBlock $workScript -ArgumentList @($iterThread)
            }
            [void](Wait-Job -Job $jobs -Timeout $cpuCap)
            foreach ($j in $jobs) {
                if ($j.State -eq 'Completed') {
                    $out = @(Receive-Job -Job $j -ErrorAction SilentlyContinue)
                    if (($out.Count -gt 0) -and ([double]$out[0].Ms -gt 0)) {
                        $wallMs = [math]::Max($wallMs, [double]$out[0].Ms)
                    }
                    else { $allOk = $false }
                }
                else { $allOk = $false }
            }
        }
        catch {
            $allOk = $false
        }
        finally {
            foreach ($j in $jobs) {
                try { Stop-Job -Job $j -ErrorAction SilentlyContinue } catch { }
                try { Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } catch { }
            }
        }

        if ($allOk -and $wallMs -gt 0) {
            $totalOps = [double]$iterThread * [double]$threadCount
            $mps = Convert-ToMbPerSec -Bytes $totalOps -Milliseconds $wallMs
            Add-Result @{
                Benchmark = ('CPU ' + $labelName + ' (all-thread)'); Category = 'cpu'
                Engine = 'HBSS .NET/PowerShell jobs'; Version = $HBSS_VERSION
                Workload = $(if ($labelName -eq 'integer') { '64-bit xorshift integer mix' } else { 'double-precision multiply-accumulate' })
                Threads = ([string]$threadCount); Dataset = ($iterThread.ToString() + ' iterations/thread')
                Duration = ($wallMs.ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' ms')
                Result = $mps; Unit = 'Mops/s'; Origin = 'HBSS fallback'
                Notes = ('logical processors ' + $logical + '; job fan-out capped at 8; interpreter overhead included')
            }
        }
        else {
            $script:failedCount++
            Add-SkippedItem -Benchmark ('CPU ' + $labelName + ' (all-thread)') -Category 'cpu' -Reason 'Timed out or job fan-out unavailable'
        }
    }
}

# ---------------------------------------------------------------------------
# Memory benchmarks
# ---------------------------------------------------------------------------

function Invoke-MemoryBenchmarks {
    $bufferBytes = [int](@{ Quick = 8 * 1024 * 1024; Standard = 32 * 1024 * 1024; Full = 64 * 1024 * 1024 }[$profileName])
    $passes = [int](@{ Quick = 20; Standard = 60; Full = 120 }[$profileName])
    $chaseSteps = [int](@{ Quick = 1000000; Standard = 4000000; Full = 8000000 }[$profileName])
    $chaseSlots = [int](@{ Quick = 262144; Standard = 1048576; Full = 2097152 }[$profileName])

    $bwScript = {
        param([int]$BufferBytes, [int]$Passes)
        $src = New-Object byte[] $BufferBytes
        $dst = New-Object byte[] $BufferBytes
        $rnd = New-Object System.Random 12345
        $rnd.NextBytes($src)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($p = 0; $p -lt $Passes; $p++) {
            [System.Array]::Copy($src, $dst, $BufferBytes)
        }
        $sw.Stop()
        $moved = [double]$BufferBytes * [double]$Passes * 2.0
        [pscustomobject]@{ Ms = $sw.Elapsed.TotalMilliseconds; Bytes = $moved; Check = [int]$dst[0] }
    }

    $latScript = {
        param([int]$Slots, [int]$Steps)
        $idx = New-Object int[] $Slots
        for ($i = 0; $i -lt $Slots; $i++) { $idx[$i] = $i }
        $rnd = New-Object System.Random 54321
        for ($i = $Slots - 1; $i -gt 0; $i--) {
            $j = $rnd.Next(0, $i + 1)
            $tmp = $idx[$i]; $idx[$i] = $idx[$j]; $idx[$j] = $tmp
        }
        $cur = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($s = 0; $s -lt $Steps; $s++) { $cur = $idx[$cur] }
        $sw.Stop()
        [pscustomobject]@{ Ms = $sw.Elapsed.TotalMilliseconds; Steps = $Steps; Check = $cur }
    }

    $r = Invoke-WithTimeout -Script $bwScript -Arguments @($bufferBytes, $passes) -TimeoutSeconds $memCap -Label 'Memory bandwidth'
    if ($r.Completed -and $r.Result.Count -gt 0) {
        $o = $r.Result[0]
        $mbps = Convert-ToMbPerSec -Bytes ([double]$o.Bytes) -Milliseconds ([double]$o.Ms)
        Add-Result @{
            Benchmark = 'Memory bandwidth (sequential copy)'; Category = 'memory'
            Engine = 'HBSS .NET Array.Copy loop'; Version = $HBSS_VERSION
            Workload = 'read+write sequential array copy'; Threads = '1'
            Dataset = (($bufferBytes.ToString()) + ' B x ' + $passes + ' passes')
            Duration = (([double]$o.Ms).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' ms')
            Result = $mbps; Unit = 'MB/s'; Origin = 'HBSS fallback'
            Notes = ('checksum ' + $o.Check + '; count includes both source read and destination write')
        }
    }
    else {
        $script:failedCount++
        Add-SkippedItem -Benchmark 'Memory bandwidth (sequential copy)' -Category 'memory' -Reason $(if ($r.TimedOut) { 'Exceeded per-test memory cap' } else { 'Execution error: ' + $r.Error })
    }

    $r = Invoke-WithTimeout -Script $latScript -Arguments @($chaseSlots, $chaseSteps) -TimeoutSeconds $memCap -Label 'Memory pointer-chase latency'
    if ($r.Completed -and $r.Result.Count -gt 0) {
        $o = $r.Result[0]
        $ns = if ([double]$o.Ms -gt 0) { ([math]::Round((([double]$o.Ms) * 1000000.0) / [double]$o.Steps, 2)).ToString('F2', [Globalization.CultureInfo]::InvariantCulture) } else { '0.00' }
        Add-Result @{
            Benchmark = 'Memory latency (pointer chase)'; Category = 'memory'
            Engine = 'HBSS custom microbenchmark'; Version = $HBSS_VERSION
            Workload = 'random permutation pointer chase'; Threads = '1'
            Dataset = (($chaseSlots.ToString()) + ' slots x ' + $chaseSteps + ' accesses')
            Duration = (([double]$o.Ms).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' ms')
            Result = $ns; Unit = 'ns/access'; Origin = 'HBSS fallback'
            Notes = ('checksum ' + $o.Check + '; PowerShell interpreter overhead inflates latency; relative indicator only')
        }
    }
    else {
        $script:failedCount++
        Add-SkippedItem -Benchmark 'Memory latency (pointer chase)' -Category 'memory' -Reason $(if ($r.TimedOut) { 'Exceeded per-test memory cap' } else { 'Execution error: ' + $r.Error })
    }

    Add-SkippedItem -Benchmark 'RAM latency (recognized engine)' -Category 'memory' -Reason 'RAM latency unavailable (no suitable runtime): Intel MLC needs admin/MSR and lmbench has publication restrictions; HBSS custom pointer-chase microbenchmark used instead'
}

# ---------------------------------------------------------------------------
# Storage benchmarks
# ---------------------------------------------------------------------------

function New-TestFile {
    param([string]$Path, [int64]$Size)
    try {
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $block = New-Object byte[] (1024 * 1024)
            $written = [int64]0
            while ($written -lt $Size) {
                $n = [int][math]::Min([int64]$block.Length, ($Size - $written))
                $fs.Write($block, 0, $n)
                $written += $n
            }
            $fs.Flush($true)
        }
        finally { $fs.Dispose() }
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-StorageBenchmarks {
    $testFile = Join-Path $script:tempDir 'hbss-storage-test.bin'
    $targetSize = $stoFileCap
    try {
        $root = [System.IO.Path]::GetPathRoot($script:tempDir)
        $di = New-Object System.IO.DriveInfo($root)
        $safe = [int64]($di.AvailableFreeSpace / 4)
        if ($safe -lt ([int64]8 * 1024 * 1024)) { $safe = [int64]8 * 1024 * 1024 }
        if ($targetSize -gt $safe) { $targetSize = $safe }
    }
    catch {
        # Keep the configured cap if free-space probing fails.
    }

    $randomOps = [int](@{ Quick = 1000; Standard = 4000; Full = 10000 }[$profileName])
    $blockBytes = 1024 * 1024

    $diskSpd = Resolve-DiskSpd
    $fio = Resolve-Fio

    if ($diskSpd.Ok) {
        $secs = [int](@{ Quick = 3; Standard = 8; Full = 15 }[$profileName])
        try {
            if (Test-Path -LiteralPath $testFile) { Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue }
            $argsD = @(
                ('-b4K'), ('-d' + $secs), '-o4', '-t2', '-w50', '-r', '-L',
                ('-c' + $targetSize), $testFile
            )
            $run = Invoke-ExternalTool -FilePath $diskSpd.Path -Arguments $argsD -LogPath (Join-Path $script:tempDir 'diskspd.log') -TimeoutSeconds $stoCap -WorkingDirectory $script:tempDir
            $log = ''
            if (Test-Path -LiteralPath (Join-Path $script:tempDir 'diskspd.log')) {
                $log = [System.IO.File]::ReadAllText((Join-Path $script:tempDir 'diskspd.log'))
            }
            $bwMatches = [regex]::Matches($log, '(\d+(?:\.\d+)?)\s*MB/s')
            $iopsMatches = [regex]::Matches($log, '(\d+(?:\.\d+)?)\s*(?:IOPS|I/Os/s)')
            if ($bwMatches.Count -gt 0) {
                $best = 0.0
                foreach ($m in $bwMatches) {
                    $v = 0.0
                    if ([double]::TryParse($m.Groups[1].Value, [ref]$v)) { if ($v -gt $best) { $best = $v } }
                }
                Add-Result @{
                    Benchmark = 'Storage random 4K mixed (50/50)'; Category = 'storage'
                    Engine = 'Microsoft DiskSpd v2.3'; Version = '2.3'
                    Workload = '4K random read/write, 50% write, no raw devices'; Threads = '2'
                    Dataset = ($targetSize.ToString() + ' B test file')
                    Duration = ($secs.ToString() + ' s')
                    Result = $best.ToString('F2', [Globalization.CultureInfo]::InvariantCulture); Unit = 'MB/s'
                    Origin = 'recognized open-source'
                    Notes = ($(if ($iopsMatches.Count -gt 0) { 'IOPS figures present in tool log; ' } else { '' }) + 'temporary file only; parsed from tool log')
                }
            }
            else {
                Add-SkippedItem -Benchmark 'Storage random 4K mixed (50/50)' -Category 'storage' -Reason 'DiskSpd ran but its output could not be parsed for MB/s (log discarded with temp workspace)'
            }
            if ($run.TimedOut) { $script:hardTimeoutReached = $true }
        }
        catch {
            Add-SkippedItem -Benchmark 'Storage random 4K mixed (50/50)' -Category 'storage' -Reason ('DiskSpd error: ' + $_.Exception.Message)
        }
        finally {
            if (Test-Path -LiteralPath $testFile) {
                try { Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue } catch { }
            }
        }
    }
    else {
        Add-SkippedItem -Benchmark 'Storage (DiskSpd engine)' -Category 'storage' -Reason $diskSpd.Reason
    }

    if ($fio.Ok) {
        $secs = [int](@{ Quick = 3; Standard = 8; Full = 15 }[$profileName])
        $jobPath = Join-Path $script:tempDir 'fio.job'
        try {
            if (Test-Path -LiteralPath $testFile) { Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue }
            $job = @"
[global]
ioengine=windowsaio
direct=0
[job1]
filename=$testFile
rw=randrw
rwmixread=50
bs=4k
size=$targetSize
runtime=$secs
time_based=1
numjobs=2
"@
            [System.IO.File]::WriteAllText($jobPath, $job)
            $run = Invoke-ExternalTool -FilePath $fio.Path -Arguments @($jobPath) -LogPath (Join-Path $script:tempDir 'fio.log') -TimeoutSeconds $stoCap -WorkingDirectory $script:tempDir
            $log = ''
            if (Test-Path -LiteralPath (Join-Path $script:tempDir 'fio.log')) {
                $log = [System.IO.File]::ReadAllText((Join-Path $script:tempDir 'fio.log'))
            }
            $bw = [regex]::Matches($log, 'bw=(\d+(?:\.\d+)?)([KMGT]iB/s)')
            if ($bw.Count -gt 0) {
                $bestBw = 0.0
                foreach ($m in $bw) {
                    $v = 0.0
                    if ([double]::TryParse($m.Groups[1].Value, [ref]$v)) {
                        $mult = 1.0
                        if ($m.Groups[2].Value -eq 'KiB/s') { $mult = 1.0 / 1024.0 }
                        elseif ($m.Groups[2].Value -eq 'MiB/s') { $mult = 1.0 }
                        elseif ($m.Groups[2].Value -eq 'GiB/s') { $mult = 1024.0 }
                        elseif ($m.Groups[2].Value -eq 'TiB/s') { $mult = 1024.0 * 1024.0 }
                        $v = $v * $mult
                        if ($v -gt $bestBw) { $bestBw = $v }
                    }
                }
                Add-Result @{
                    Benchmark = 'Storage random 4K mixed (fio)'; Category = 'storage'
                    Engine = 'fio 3.43'; Version = '3.43'
                    Workload = '4K random read/write, 50% read, temp file only'; Threads = '2'
                    Dataset = ($targetSize.ToString() + ' B test file')
                    Duration = ($secs.ToString() + ' s')
                    Result = $bestBw.ToString('F2', [Globalization.CultureInfo]::InvariantCulture); Unit = 'MB/s'
                    Origin = 'recognized open-source'
                    Notes = 'MSI extracted to temp; temporary file only; never raw devices'
                }
            }
            else {
                Add-SkippedItem -Benchmark 'Storage random 4K mixed (fio)' -Category 'storage' -Reason 'fio ran but no bw= value could be parsed from its output'
            }
            if ($run.TimedOut) { $script:hardTimeoutReached = $true }
        }
        catch {
            Add-SkippedItem -Benchmark 'Storage random 4K mixed (fio)' -Category 'storage' -Reason ('fio error: ' + $_.Exception.Message)
        }
        finally {
            if (Test-Path -LiteralPath $testFile) {
                try { Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue } catch { }
            }
        }
    }
    else {
        Add-SkippedItem -Benchmark 'Storage (fio engine)' -Category 'storage' -Reason $fio.Reason
    }

    # Always run the built-in fallback temp-file test so a result exists even
    # when no recognized engine is available.
    $storeScript = {
        param([string]$Path, [int64]$Size, [int]$RandomOps, [int]$BlockBytes)
        $buffer = New-Object byte[] $BlockBytes
        $rnd = New-Object System.Random 98765
        $rnd.NextBytes($buffer)

        $writeMs = 0.0; $written = [int64]0; $readMs = 0.0; $read = [int64]0
        $randomMs = 0.0

        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($written -lt $Size) {
                $n = [int][math]::Min([int64]$buffer.Length, ($Size - $written))
                $fs.Write($buffer, 0, $n)
                $written += $n
            }
            $fs.Flush($true)
            $sw.Stop()
            $writeMs = $sw.Elapsed.TotalMilliseconds
        }
        finally { $fs.Dispose() }

        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($true) {
                $n = $fs.Read($buffer, 0, $buffer.Length)
                if ($n -le 0) { break }
                $read += $n
            }
            $sw.Stop()
            $readMs = $sw.Elapsed.TotalMilliseconds
        }
        finally { $fs.Dispose() }

        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $rb = New-Object byte[] 4096
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt $RandomOps; $i++) {
                $span = [int64]($Size - 4096)
                if ($span -lt 0) { $span = 0 }
                $off = [int64]($rnd.NextDouble() * [double]$span)
                [void]$fs.Seek($off, [System.IO.SeekOrigin]::Begin)
                [void]$fs.Read($rb, 0, 4096)
            }
            $sw.Stop()
            $randomMs = $sw.Elapsed.TotalMilliseconds
        }
        finally { $fs.Dispose() }

        [pscustomobject]@{
            WriteMs = $writeMs; Written = $written
            ReadMs = $readMs; Read = $read
            RandomMs = $randomMs; RandomOps = $RandomOps
        }
    }

    try {
        $r = Invoke-WithTimeout -Script $storeScript -Arguments @($testFile, $targetSize, $randomOps, $blockBytes) -TimeoutSeconds $stoCap -Label 'Storage .NET fallback'
        if ($r.Completed -and $r.Result.Count -gt 0) {
            $o = $r.Result[0]
            $wr = Convert-ToMbPerSec -Bytes ([double]$o.Written) -Milliseconds ([double]$o.WriteMs)
            $rr = Convert-ToMbPerSec -Bytes ([double]$o.Read) -Milliseconds ([double]$o.ReadMs)
            $iop = if ([double]$o.RandomMs -gt 0) { ([math]::Round(([double]$o.RandomOps / ([double]$o.RandomMs / 1000.0)), 1)).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) } else { '0.0' }
            $dur = (([double]$o.WriteMs + [double]$o.ReadMs + [double]$o.RandomMs).ToString('F0', [Globalization.CultureInfo]::InvariantCulture) + ' ms')
            Add-Result @{
                Benchmark = 'Storage sequential write (fallback)'; Category = 'storage'
                Engine = 'HBSS .NET FileStream'; Version = $HBSS_VERSION
                Workload = '1 MiB buffered sequential write, flush-to-disk'; Threads = '1'
                Dataset = ($targetSize.ToString() + ' B test file')
                Duration = ($dur); Result = $wr; Unit = 'MB/s'; Origin = 'HBSS fallback'
                Notes = 'temporary file only; includes filesystem/OS caching effects'
            }
            Add-Result @{
                Benchmark = 'Storage sequential read (fallback)'; Category = 'storage'
                Engine = 'HBSS .NET FileStream'; Version = $HBSS_VERSION
                Workload = '1 MiB buffered sequential read'; Threads = '1'
                Dataset = ($targetSize.ToString() + ' B test file')
                Duration = ($dur); Result = $rr; Unit = 'MB/s'; Origin = 'HBSS fallback'
                Notes = 'temporary file only; includes filesystem/OS caching effects'
            }
            Add-Result @{
                Benchmark = 'Storage bounded random read (fallback)'; Category = 'storage'
                Engine = 'HBSS .NET FileStream'; Version = $HBSS_VERSION
                Workload = '4 KiB random reads at pseudo-random offsets'; Threads = '1'
                Dataset = ($targetSize.ToString() + ' B test file')
                Duration = (([double]$o.RandomMs).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' ms')
                Result = $iop; Unit = 'IOPS'; Origin = 'HBSS fallback'
                Notes = 'temporary file only; PowerShell overhead included; includes OS caching'
            }
        }
        else {
            $script:failedCount++
            Add-SkippedItem -Benchmark 'Storage .NET fallback' -Category 'storage' -Reason $(if ($r.TimedOut) { 'Exceeded per-test storage cap' } else { 'Execution error: ' + $r.Error })
        }
    }
    finally {
        if (Test-Path -LiteralPath $testFile) {
            try { Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}

# ---------------------------------------------------------------------------
# GPU benchmarks
# ---------------------------------------------------------------------------

function Invoke-GpuBenchmarks {
    $video = @($script:inv['Video'])
    if ($video.Count -eq 0) {
        Add-SkippedItem -Benchmark 'GPU benchmark' -Category 'gpu' -Reason 'GPU benchmark unavailable (no compatible engine; no GPU detected)'
        return
    }

    $ran = $false
    if ($UseInstalledBenchmarks -and (-not $NoProprietary)) {
        $clpeak = Get-CommandPath 'clpeak.exe'
        if (-not $clpeak) { $clpeak = Get-CommandPath 'clpeak' }
        if ($clpeak -and (Test-Path -LiteralPath $clpeak -PathType Leaf)) {
            try {
                $logPath = Join-Path $script:tempDir 'clpeak.log'
                $run = Invoke-ExternalTool -FilePath $clpeak -Arguments @('--bandwidth') -LogPath $logPath -TimeoutSeconds $gpuCap -WorkingDirectory $script:tempDir
                if (-not $run.TimedOut -and (Test-Path -LiteralPath $logPath)) {
                    $text = [System.IO.File]::ReadAllText($logPath)
                    $m = [regex]::Match($text, 'Global Bandwidth[^\r\n]*?(\d+(?:\.\d+)?)\s*(GB/s|MB/s)')
                    if ($m.Success) {
                        $val = [double]$m.Groups[1].Value
                        if ($m.Groups[2].Value -eq 'MB/s') { $val = $val / 1024.0 }
                        Add-Result @{
                            Benchmark = 'GPU compute bandwidth (clpeak)'; Category = 'gpu'
                            Engine = 'clpeak (installed)'; Version = 'installed'
                            Workload = 'OpenCL global memory bandwidth'; Threads = '1'
                            Dataset = 'engine-defined'; Duration = ('within ' + $gpuCap + ' s cap')
                            Result = $val.ToString('F2', [Globalization.CultureInfo]::InvariantCulture); Unit = 'GB/s'
                            Origin = 'recognized open-source'
                            Notes = 'executed only with -UseInstalledBenchmarks; unsigned upstream binaries are not auto-downloaded'
                        }
                        $ran = $true
                    }
                }
                if ($run.TimedOut) { $script:hardTimeoutReached = $true }
            }
            catch {
                Add-SkippedItem -Benchmark 'GPU compute bandwidth (clpeak)' -Category 'gpu' -Reason ('clpeak error: ' + $_.Exception.Message)
            }
        }
    }

    $gb = Get-CommandPath 'geekbench.exe'
    if (-not $gb) { $gb = Get-CommandPath 'geekbench6.exe' }
    if ($gb) {
        Add-SkippedItem -Benchmark 'Geekbench Compute' -Category 'gpu' -Reason $(if ($NoProprietary) { 'Proprietary engine disabled by -NoProprietary' } else { 'Detected only: proprietary EULA requires result upload; never auto-accepted or executed' })
    }

    if (-not $ran) {
        Add-SkippedItem -Benchmark 'GPU benchmark' -Category 'gpu' -Reason 'GPU benchmark unavailable (no compatible engine); GPU(s) detected but not benchmarked under default policy'
    }
}

# ---------------------------------------------------------------------------
# Network benchmarks
# ---------------------------------------------------------------------------

function Invoke-NetworkBenchmarks {
    $canTest = $AllowNetwork -and (-not [string]::IsNullOrEmpty($Endpoint))
    $endpointValid = $false
    if ($canTest) {
        if ($Endpoint -match '^[A-Za-z0-9.\[\]:_\-]+$') { $endpointValid = $true }
    }

    if (-not $canTest) {
        Add-SkippedItem -Benchmark 'Network throughput' -Category 'network' -Reason 'network throughput skipped (no endpoint configured)'
        return
    }
    if (-not $endpointValid) {
        Add-SkippedItem -Benchmark 'Network throughput' -Category 'network' -Reason 'Endpoint failed character validation; skipped'
        return
    }

    $iperf = Get-CommandPath 'iperf3.exe'
    if (-not $iperf) { $iperf = Get-CommandPath 'iperf3' }
    if (-not ($iperf -and (Test-Path -LiteralPath $iperf -PathType Leaf))) {
        Add-SkippedItem -Benchmark 'Network throughput' -Category 'network' -Reason 'iperf3 not installed; detection-only engine, never auto-downloaded'
        return
    }

    try {
        $logPath = Join-Path $script:tempDir 'iperf3.log'
        $run = Invoke-ExternalTool -FilePath $iperf -Arguments @('-c', $Endpoint, '-J', ('--logfile=' + $logPath)) -LogPath $logPath -TimeoutSeconds $profileBudget -WorkingDirectory $script:tempDir
        $bits = $null
        if (Test-Path -LiteralPath $logPath) {
            $text = [System.IO.File]::ReadAllText($logPath)
            try {
                $json = $text | ConvertFrom-Json
                if ($json.end.sum_received.bits_per_second) {
                    $bits = [double]$json.end.sum_received.bits_per_second
                }
            }
            catch {
                $bits = $null
            }
        }
        if ($null -ne $bits -and $bits -gt 0) {
            $mbps = [math]::Round($bits / 1000000.0, 2)
            Add-Result @{
                Benchmark = 'Network TCP throughput (iperf3)'; Category = 'network'
                Engine = 'iperf3 (installed)'; Version = 'installed'
                Workload = 'TCP receive throughput to user-specified endpoint'; Threads = '1'
                Dataset = ('endpoint ' + $Endpoint); Duration = ('within ' + $profileBudget + ' s budget')
                Result = $mbps.ToString('F2', [Globalization.CultureInfo]::InvariantCulture); Unit = 'Mbit/s'
                Origin = 'recognized open-source'
                Notes = 'external endpoint supplied by user; no data uploaded by HBSS'
            }
        }
        else {
            Add-SkippedItem -Benchmark 'Network throughput' -Category 'network' -Reason 'iperf3 ran but no JSON throughput value could be parsed'
        }
        if ($run.TimedOut) { $script:hardTimeoutReached = $true }
    }
    catch {
        Add-SkippedItem -Benchmark 'Network throughput' -Category 'network' -Reason ('iperf3 error: ' + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# NPU benchmarks
# ---------------------------------------------------------------------------

function Invoke-NpuBenchmarks {
    $patterns = 'NPU|Neural|AI Accelerator|AI Boost|Hexagon|XDNA|Tensor Processing|Neural Processing Unit'
    $hits = @()
    foreach ($p in @($script:inv['Pnp'])) {
        $name = ''
        try { $name = [string]$p.Name } catch { $name = '' }
        if ($name -match $patterns) { $hits += $name }
    }
    $script:inv['NpuDevices'] = @($hits | Select-Object -Unique)
    Add-SkippedItem -Benchmark 'NPU benchmark' -Category 'npu' -Reason 'NPU benchmark unavailable (no supported runtime); presence reported from PnP names only, no performance number fabricated'
}

# ---------------------------------------------------------------------------
# Crypto benchmarks
# ---------------------------------------------------------------------------

function Invoke-CryptoBenchmarks {
    $openssl = Get-CommandPath 'openssl.exe'
    if (-not $openssl) { $openssl = Get-CommandPath 'openssl' }

    if ($openssl -and (Test-Path -LiteralPath $openssl -PathType Leaf)) {
        $version = 'unknown'
        $vlog = Join-Path $script:tempDir 'openssl-version.log'
        [void](Invoke-ExternalTool -FilePath $openssl -Arguments @('version') -LogPath $vlog -TimeoutSeconds 10)
        if (Test-Path -LiteralPath $vlog) {
            $first = @(Get-Content -LiteralPath $vlog -TotalCount 1)
            if ($first.Count -gt 0 -and (-not [string]::IsNullOrEmpty($first[0]))) { $version = $first[0].Trim() }
        }

        $seconds = [int](@{ Quick = 2; Standard = 5; Full = 10 }[$profileName])
        foreach ($alg in @('aes-128-gcm', 'sha256')) {
            $logPath = Join-Path $script:tempDir ('openssl-' + $alg + '.log')
            try {
                $run = Invoke-ExternalTool -FilePath $openssl -Arguments @('speed', '-evp', $alg, '-seconds', ([string]$seconds), '-multi', '1') -LogPath $logPath -TimeoutSeconds $cryptoCap -WorkingDirectory $script:tempDir
                $best = 0.0
                if (Test-Path -LiteralPath $logPath) {
                    foreach ($line in @(Get-Content -LiteralPath $logPath)) {
                        if ($line -match ('^\s*' + [regex]::Escape($alg))) {
                            foreach ($tok in [regex]::Matches($line, '(\d+(?:\.\d+)?)([kmgKMG]?)')) {
                                $v = 0.0
                                if (-not [double]::TryParse($tok.Groups[1].Value, [ref]$v)) { continue }
                                $suffix = $tok.Groups[2].Value.ToLowerInvariant()
                                if ($suffix -eq 'k') { $v = $v * 1024.0 }
                                elseif ($suffix -eq 'm') { $v = $v * 1024.0 * 1024.0 }
                                elseif ($suffix -eq 'g') { $v = $v * 1024.0 * 1024.0 * 1024.0 }
                                if ($v -gt $best) { $best = $v }
                            }
                        }
                    }
                }
                if ($best -gt 0 -and (-not $run.TimedOut)) {
                    $mbps = $best / 1000000.0
                    Add-Result @{
                        Benchmark = ('Crypto ' + $alg + ' (openssl speed)'); Category = 'crypto'
                        Engine = 'openssl speed'; Version = $version
                        Workload = ($alg + ' EVP throughput'); Threads = '1'
                        Dataset = ($seconds.ToString() + ' s'); Duration = ($seconds.ToString() + ' s')
                        Result = $mbps.ToString('F2', [Globalization.CultureInfo]::InvariantCulture); Unit = 'MB/s'
                        Origin = 'recognized open-source'
                        Notes = 'system openssl only; never auto-downloaded; no result upload'
                    }
                }
                else {
                    Add-SkippedItem -Benchmark ('Crypto ' + $alg + ' (openssl speed)') -Category 'crypto' -Reason $(if ($run.TimedOut) { 'Exceeded crypto cap' } else { 'openssl speed output could not be parsed' })
                }
                if ($run.TimedOut) { $script:hardTimeoutReached = $true }
            }
            catch {
                Add-SkippedItem -Benchmark ('Crypto ' + $alg + ' (openssl speed)') -Category 'crypto' -Reason ('openssl error: ' + $_.Exception.Message)
            }
        }
        return
    }

    # .NET fallbacks, honestly labelled.
    $bufBytes = [int](@{ Quick = 8 * 1024 * 1024; Standard = 16 * 1024 * 1024; Full = 32 * 1024 * 1024 }[$profileName])
    $passes = [int](@{ Quick = 20; Standard = 40; Full = 80 }[$profileName])

    $hashScript = {
        param([int]$BufferBytes, [int]$Passes)
        $buf = New-Object byte[] $BufferBytes
        $rnd = New-Object System.Random 111
        $rnd.NextBytes($buf)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $check = $null
            for ($p = 0; $p -lt $Passes; $p++) { $check = $sha.ComputeHash($buf) }
            $sw.Stop()
            [pscustomobject]@{ Ms = $sw.Elapsed.TotalMilliseconds; Bytes = ([double]$BufferBytes * [double]$Passes); Check = [System.BitConverter]::ToString($check).Substring(0, 8) }
        }
        finally { $sha.Dispose() }
    }

    $aesScript = {
        param([int]$BufferBytes, [int]$Passes)
        $buf = New-Object byte[] $BufferBytes
        $out = New-Object byte[] $BufferBytes
        $rnd = New-Object System.Random 222
        $rnd.NextBytes($buf)
        $aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
        try {
            $aes.KeySize = 256
            $aes.GenerateKey()
            $aes.Mode = [System.Security.Cryptography.CipherMode]::ECB
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::None
            $enc = $aes.CreateEncryptor()
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                for ($p = 0; $p -lt $Passes; $p++) {
                    [void]$enc.TransformBlock($buf, 0, $BufferBytes, $out, 0)
                }
                $sw.Stop()
                [pscustomobject]@{ Ms = $sw.Elapsed.TotalMilliseconds; Bytes = ([double]$BufferBytes * [double]$Passes); Check = [System.BitConverter]::ToString($out).Substring(0, 8) }
            }
            finally { $enc.Dispose() }
        }
        finally { $aes.Dispose() }
    }

    $cryptoKinds = @(
        [pscustomobject]@{ Name = 'SHA-256'; Script = $hashScript },
        [pscustomobject]@{ Name = 'AES-256-ECB'; Script = $aesScript }
    )
    foreach ($pair in $cryptoKinds) {
        $name = [string]$pair.Name
        $scriptBlock = [scriptblock]$pair.Script
        $r = Invoke-WithTimeout -Script $scriptBlock -Arguments @($bufBytes, $passes) -TimeoutSeconds $cryptoCap -Label ('Crypto ' + $name)
        if ($r.Completed -and $r.Result.Count -gt 0) {
            $o = $r.Result[0]
            $mbps = Convert-ToMbPerSec -Bytes ([double]$o.Bytes) -Milliseconds ([double]$o.Ms)
            Add-Result @{
                Benchmark = ('Crypto ' + $name + ' (.NET)'); Category = 'crypto'
                Engine = 'HBSS .NET cryptography'; Version = $HBSS_VERSION
                Workload = $(if ($name -eq 'SHA-256') { 'SHA-256 hashing' } else { 'AES-256 ECB block encryption' })
                Threads = '1'
                Dataset = ($bufBytes.ToString() + ' B x ' + $passes + ' passes')
                Duration = (([double]$o.Ms).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' ms')
                Result = $mbps; Unit = 'MB/s'; Origin = 'HBSS fallback'
                Notes = ('checksum ' + $o.Check + '; ECB used for raw throughput only, not security')
            }
        }
        else {
            $script:failedCount++
            Add-SkippedItem -Benchmark ('Crypto ' + $name + ' (.NET)') -Category 'crypto' -Reason $(if ($r.TimedOut) { 'Exceeded crypto cap' } else { 'Execution error: ' + $r.Error })
        }
    }
}

# ---------------------------------------------------------------------------
# Optional per-drive storage sweep (-AllDrives)
# ---------------------------------------------------------------------------

function Invoke-AllDrivesStorage {
    try {
        $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction Stop | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })
    }
    catch {
        return
    }
    if ($drives.Count -eq 0) { return }

    foreach ($d in $drives) {
        $root = [string]$d.Root
        $path = $null
        try {
            $di = New-Object System.IO.DriveInfo($root)
            if ($di.DriveType -ne [System.IO.DriveType]::Fixed) { continue }
            $sizeBytes = [int64]16 * 1024 * 1024
            if ($di.AvailableFreeSpace -lt ($sizeBytes * 2)) { continue }

            $path = Join-Path $root ('hbss-' + [System.Guid]::NewGuid().ToString('N') + '.bin')
            $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $buf = New-Object byte[] (1024 * 1024)
                $written = [int64]0
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                while ($written -lt $sizeBytes) {
                    $n = [int][math]::Min([int64]$buf.Length, ($sizeBytes - $written))
                    $fs.Write($buf, 0, $n)
                    $written += $n
                }
                $fs.Flush($true)
                $sw.Stop()
                $mbps = Convert-ToMbPerSec -Bytes ([double]$written) -Milliseconds ([double]$sw.Elapsed.TotalMilliseconds)
                Add-Result @{
                    Benchmark = ('Storage sequential write (' + $root + ')'); Category = 'storage'
                    Engine = 'HBSS .NET FileStream'; Version = $HBSS_VERSION
                    Workload = '1 MiB buffered sequential write on all-drive sweep'; Threads = '1'
                    Dataset = ($sizeBytes.ToString() + ' B test file on ' + $root)
                    Duration = (($sw.Elapsed.TotalMilliseconds).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' ms')
                    Result = $mbps; Unit = 'MB/s'; Origin = 'HBSS fallback'
                    Notes = 'temporary file deleted in finally; raw devices never touched; includes OS caching'
                }
            }
            finally {
                $fs.Dispose()
            }
        }
        catch {
            Add-SkippedItem -Benchmark ('Storage sequential write (' + $root + ')') -Category 'storage' -Reason ('Drive test error: ' + $_.Exception.Message)
        }
        finally {
            if ($path -and (Test-Path -LiteralPath $path)) {
                try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch { }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

function Write-Report {
    $endUtc = [DateTime]::UtcNow
    $totalSeconds = ($endUtc - $startedUtc).TotalSeconds

    $overrides = @()
    if ($Only) { $overrides += ('Only=' + ($Only -join ',')) }
    if ($Skip) { $overrides += ('Skip=' + ($Skip -join ',')) }
    if ($AllDrives) { $overrides += 'AllDrives' }
    if ($NoDownloads) { $overrides += 'NoDownloads' }
    if ($DownloadBenchmarks) { $overrides += 'DownloadBenchmarks' }
    if ($UseInstalledBenchmarks) { $overrides += 'UseInstalledBenchmarks' }
    if ($NoProprietary) { $overrides += 'NoProprietary' }
    if ($AllowNetwork) { $overrides += 'AllowNetwork' }
    if ($AllowLargeDownloads) { $overrides += 'AllowLargeDownloads' }
    if ($Endpoint) { $overrides += ('Endpoint=' + $Endpoint) }
    if ($overrides.Count -eq 0) { $overrides += 'none' }

    $osCaption = ''
    $osVersion = ''
    $osArch = ''
    if (@($script:inv['Os']).Count -gt 0) {
        $os = $script:inv['Os'][0]
        try { $osCaption = [string]$os.Caption } catch { }
        try { $osVersion = [string]$os.Version } catch { }
        try { $osArch = [string]$os.OSArchitecture } catch { }
    }
    if ([string]::IsNullOrEmpty($osCaption)) { $osCaption = [Environment]::OSVersion.VersionString }
    if ([string]::IsNullOrEmpty($osArch)) { $osArch = [string]$env:PROCESSOR_ARCHITECTURE }
    $archDetail = $osArch
    if ($env:PROCESSOR_ARCHITEW6432) { $archDetail = $archDetail + ' / ' + $env:PROCESSOR_ARCHITEW6432 }
    $hostName = [string]$env:COMPUTERNAME

    Add-Line '# Hardware Benchmark Suite Report'
    Add-Line ''

    Add-Line '## Run Summary'
    Add-Line ''
    Add-Line '| Field | Value |'
    Add-Line '| --- | --- |'
    Add-Line ('| Profile | ' + (Escape-Md $profileName) + ' (' + $profileBudget + ' s budget) |')
    Add-Line ('| Started (UTC) | ' + $startedUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) + ' |')
    Add-Line ('| Total duration | ' + $totalSeconds.ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' s |')
    Add-Line ('| Tests completed | ' + $script:results.Count.ToString() + ' |')
    Add-Line ('| Tests skipped | ' + @($script:skipped).Count.ToString() + ' |')
    Add-Line ('| Tests failed | ' + $script:failedCount.ToString() + ' |')
    Add-Line ('| OS | ' + (Escape-Md ($osCaption + ' ' + $osVersion)).Trim() + ' |')
    Add-Line ('| Architecture | ' + (Escape-Md $archDetail) + ' |')
    Add-Line ('| Host | ' + (Escape-Md $hostName) + ' |')
    Add-Line ('| Overrides | ' + (Escape-Md ($overrides -join '; ')) + ' |')
    Add-SectionBreak

    Add-Line '## System Overview'
    Add-Line ''
    Add-Line '| Field | Value |'
    Add-Line '| --- | --- |'
    Add-Line ('| OS name | ' + (Escape-Md $osCaption) + ' |')
    Add-Line ('| OS version | ' + (Escape-Md $osVersion) + ' |')
    Add-Line ('| OS architecture | ' + (Escape-Md $osArch) + ' |')
    Add-Line ('| .NET runtime | ' + (Escape-Md ([Environment]::Version.ToString())) + ' |')
    Add-Line ('| PowerShell edition | Windows PowerShell 5.1 compatible |')

    $procs = @($script:inv['Processor'])
    if ($procs.Count -gt 0) {
        $p = $procs[0]
        Add-Line ('| CPU | ' + (Escape-Md $p.Name) + ' |')
        Add-Line ('| CPU cores / logical | ' + (Escape-Md $p.NumberOfCores) + ' / ' + (Escape-Md $p.NumberOfLogicalProcessors) + ' |')
        Add-Line ('| CPU max clock | ' + (Escape-Md $p.MaxClockSpeed) + ' MHz |')
    }
    else {
        Add-Line '| CPU | unavailable via CIM |'
    }

    $mems = @($script:inv['Memory'])
    $totalMem = [double]0
    foreach ($m in $mems) {
        try { $totalMem += [double]$m.Capacity } catch { }
    }
    if ($totalMem -le 0) {
        $comps = @($script:inv['Computer'])
        if ($comps.Count -gt 0) {
            try { $totalMem = [double]$comps[0].TotalPhysicalMemory } catch { }
        }
    }
    Add-Line ('| Installed RAM | ' + ([math]::Round($totalMem / 1GB, 2)).ToString('F2', [Globalization.CultureInfo]::InvariantCulture) + ' GiB |')
    Add-Line ('| Memory modules | ' + $mems.Count.ToString() + ' |')
    Add-SectionBreak

    Add-Line '## CPU'
    Add-Line ''
    if ($procs.Count -gt 0) {
        Add-Line '| Processor | Cores | Logical | Max clock |'
        Add-Line '| --- | --- | --- | --- |'
        foreach ($p in $procs) {
            Add-Line ('| ' + (Escape-Md $p.Name) + ' | ' + (Escape-Md $p.NumberOfCores) + ' | ' + (Escape-Md $p.NumberOfLogicalProcessors) + ' | ' + (Escape-Md $p.MaxClockSpeed) + ' MHz |')
        }
    }
    else {
        Add-Line 'CPU inventory unavailable via CIM.'
    }
    Add-Line ''
    Add-Line 'CPU benchmarks use labeled HBSS fallback loops; scores are not comparable to third-party suites.'
    Add-SectionBreak

    Add-Line '## GPU'
    Add-Line ''
    $video = @($script:inv['Video'])
    if ($video.Count -gt 0) {
        Add-Line '| Adapter | Video processor | Driver | Adapter RAM |'
        Add-Line '| --- | --- | --- | --- |'
        foreach ($v in $video) {
            $aram = ''
            try { $aram = ([math]::Round(([double]$v.AdapterRAM) / 1MB, 0)).ToString() + ' MiB' } catch { $aram = 'unavailable' }
            Add-Line ('| ' + (Escape-Md $v.Name) + ' | ' + (Escape-Md $v.VideoProcessor) + ' | ' + (Escape-Md $v.DriverVersion) + ' | ' + $aram + ' |')
        }
    }
    else {
        Add-Line 'No GPU reported by WMI/CIM.'
    }
    Add-Line ''
    Add-Line 'GPU compute benchmarks require an explicitly permitted, detected engine. No GPU result is fabricated.'
    Add-SectionBreak

    Add-Line '## Memory'
    Add-Line ''
    if ($mems.Count -gt 0) {
        Add-Line '| Module manufacturer | Part number | Capacity | Speed |'
        Add-Line '| --- | --- | --- | --- |'
        foreach ($m in $mems) {
            Add-Line ('| ' + (Escape-Md $m.Manufacturer) + ' | ' + (Escape-Md $m.PartNumber) + ' | ' + (Escape-Md $m.Capacity) + ' B | ' + (Escape-Md $m.Speed) + ' MT/s |')
        }
    }
    else {
        Add-Line 'Physical memory module inventory unavailable via CIM.'
    }
    Add-SectionBreak

    Add-Line '## Storage'
    Add-Line ''
    $disks = @($script:inv['DiskDrive'])
    $phys = @($script:inv['PhysicalDisk'])
    if ($disks.Count -gt 0) {
        Add-Line '| Disk drive | Model | Size | Media |'
        Add-Line '| --- | --- | --- | --- |'
        foreach ($d in $disks) {
            $size = ''
            try { $size = ([math]::Round(([double]$d.Size) / 1GB, 2)).ToString('F2', [Globalization.CultureInfo]::InvariantCulture) + ' GB' } catch { $size = 'unavailable' }
            Add-Line ('| ' + (Escape-Md $d.DeviceID) + ' | ' + (Escape-Md $d.Model) + ' | ' + $size + ' | ' + (Escape-Md $d.MediaType) + ' |')
        }
    }
    elseif ($phys.Count -gt 0) {
        Add-Line '| Physical disk | Media type | Bus | Health |'
        Add-Line '| --- | --- | --- | --- |'
        foreach ($d in $phys) {
            Add-Line ('| ' + (Escape-Md $d.FriendlyName) + ' | ' + (Escape-Md $d.MediaType) + ' | ' + (Escape-Md $d.BusType) + ' | ' + (Escape-Md $d.HealthStatus) + ' |')
        }
    }
    else {
        Add-Line 'Disk inventory unavailable via CIM/Storage cmdlets.'
    }
    Add-Line ''
    Add-Line 'All storage benchmarks use a bounded temporary file in the temp workspace. Raw block devices are never touched.'
    Add-SectionBreak

    Add-Line '## Network'
    Add-Line ''
    $adapters = @($script:inv['Adapter'])
    $shown = @($adapters | Where-Object { $_.NetEnabled -eq $true -or $_.NetConnectionStatus -eq 2 })
    if ($shown.Count -gt 0) { $adapters = $shown }
    if ($adapters.Count -gt 0) {
        Add-Line '| Adapter | MAC address | Speed | Status |'
        Add-Line '| --- | --- | --- | --- |'
        foreach ($a in $adapters) {
            $speed = ''
            try { $speed = ([math]::Round(([double]$a.Speed) / 1000000.0, 1)).ToString('F1', [Globalization.CultureInfo]::InvariantCulture) + ' Mbit/s' } catch { $speed = 'unavailable' }
            Add-Line ('| ' + (Escape-Md $a.Name) + ' | ' + (Escape-Md $a.MACAddress) + ' | ' + $speed + ' | ' + (Escape-Md $a.NetConnectionStatus) + ' |')
        }
    }
    else {
        Add-Line 'No network adapters reported by CIM.'
    }
    Add-Line ''
    Add-Line ('Throughput testing requires both -AllowNetwork and -Endpoint; current state: ' + $(if ($AllowNetwork -and $Endpoint) { 'enabled' } else { 'disabled' }) + '.')
    Add-SectionBreak

    Add-Line '## AI / NPU'
    Add-Line ''
    $npu = @()
    if ($script:inv.ContainsKey('NpuDevices')) { $npu = @($script:inv['NpuDevices']) }
    if ($npu.Count -gt 0) {
        Add-Line '| Detected device (PnP name) |'
        Add-Line '| --- |'
        foreach ($n in $npu) { Add-Line ('| ' + (Escape-Md $n) + ' |') }
        Add-Line ''
        Add-Line 'Names are inventory evidence only. No NPU throughput number is reported.'
    }
    else {
        Add-Line 'No NPU/accelerator identified from PnP device names.'
    }
    Add-SectionBreak

    Add-Line '## Other Hardware'
    Add-Line ''
    Add-Line '| Component | Detail |'
    Add-Line '| --- | --- |'
    $boards = @($script:inv['Board'])
    if ($boards.Count -gt 0) {
        Add-Line ('| Motherboard | ' + (Escape-Md ($boards[0].Manufacturer)) + ' ' + (Escape-Md ($boards[0].Product)) + ' |')
    }
    $bioses = @($script:inv['Bios'])
    if ($bioses.Count -gt 0) {
        Add-Line ('| BIOS | ' + (Escape-Md ($bioses[0].Manufacturer)) + ' ' + (Escape-Md ($bioses[0].SMBIOSBIOSVersion)) + ' |')
    }
    $batteries = @($script:inv['Battery'])
    if ($batteries.Count -gt 0) {
        Add-Line ('| Battery | ' + (Escape-Md ($batteries[0].Name)) + ', charge ' + (Escape-Md ($batteries[0].EstimatedChargeRemaining)) + ' % |')
    }
    else {
        Add-Line '| Battery | none reported |'
    }
    $comps = @($script:inv['Computer'])
    if ($comps.Count -gt 0) {
        Add-Line ('| System model | ' + (Escape-Md ($comps[0].Manufacturer)) + ' ' + (Escape-Md ($comps[0].Model)) + ' |')
        Add-Line ('| System type | ' + (Escape-Md ($comps[0].SystemType)) + ' |')
    }
    Add-Line ('| PnP entities | ' + @($script:inv['Pnp']).Count.ToString() + ' |')
    Add-SectionBreak

    Add-Line '## Thermals and Performance Behavior'
    Add-Line ''
    $temps = @($script:inv['Temperature'])
    if ($temps.Count -gt 0) {
        Add-Line '| Sensor | Instance | Reading |'
        Add-Line '| --- | --- | --- |'
        foreach ($t in $temps) {
            Add-Line ('| ' + (Escape-Md $t.Source) + ' | ' + (Escape-Md $t.Instance) + ' | ' + (Escape-Md $t.Reading) + ' |')
        }
    }
    else {
        Add-Line 'No read-only temperature sensor data is available via CIM/WMI on this system (common without elevation).'
    }
    Add-Line ''
    Add-Line 'A short benchmark run cannot establish sustained thermal stability; no sustained-power claim is made.'
    Add-SectionBreak

    Add-Line '## Benchmark Results'
    Add-Line ''
    Add-Line '| Benchmark | Category | Engine | Version | Workload | Threads | Dataset | Duration | Result | Unit | Origin | Notes |'
    Add-Line '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'
    foreach ($r in $script:results) {
        Add-Line ('| ' +
            (Escape-Md $r.Benchmark) + ' | ' +
            (Escape-Md $r.Category) + ' | ' +
            (Code-Md $r.Engine) + ' | ' +
            (Code-Md $r.Version) + ' | ' +
            (Escape-Md $r.Workload) + ' | ' +
            (Code-Md $r.Threads) + ' | ' +
            (Code-Md $r.Dataset) + ' | ' +
            (Code-Md $r.Duration) + ' | ' +
            (Code-Md $r.Result) + ' | ' +
            (Code-Md $r.Unit) + ' | ' +
            (Code-Md $r.Origin) + ' | ' +
            (Escape-Md $r.Notes) + ' |')
    }
    if ($script:results.Count -eq 0) {
        Add-Line '| none | - | - | - | - | - | - | - | - | - | - | No benchmark executed |'
    }
    Add-SectionBreak

    Add-Line '## Methodology'
    Add-Line ''
    Add-Line ('Profiles: Quick (90 s), Standard (600 s, default), Full (900 s) total budget. Per-test caps are CPU ' + $cpuCap + ' s, memory ' + $memCap + ' s, storage ' + $stoCap + ' s and GPU ' + $gpuCap + ' s, enforced with Start-Job/Wait-Job -Timeout/Stop-Job and native process WaitForExit.')
    Add-Line ('Storage test files are bounded to ' + $stoFileCap + ' B (also clamped to available free space) and deleted in a finally block; raw block devices are never used.')
    Add-Line 'Default policy downloads nothing. HBSS detects installed tools and otherwise uses labeled HBSS fallback/.NET benchmarks. Pinned engines are downloaded only with -DownloadBenchmarks, verified with SHA-256, and extracted to a temp workspace. -NoDownloads overrides all download flags.'
    Add-Line 'Pinned assets: Microsoft DiskSpd v2.3 (MIT, SHA-256 18609981e8b04b4f645f1fd182ad0541615fe71722de36a9a933c54f747218a3) and fio 3.43 (GPLv2, SHA-256 8299e6e6fbc024d3b74aa1ce62fb94ef6960b45629fbfa678b720834b6eb34aa). No pinned HBSS prebuilt release asset is configured in this build, so none was used.'
    Add-Line 'Proprietary tools (Geekbench, Cinebench) are detected only; HBSS never downloads them, accepts an EULA, bypasses activation/GUI, or uploads results. CrystalDiskMark is detected only because it is GUI-only with no non-interactive CLI. DiskSpd is the primary automated storage engine.'
    Add-Line 'Inventory uses read-only WMI/CIM (Win32_Processor, Win32_PhysicalMemory, Win32_VideoController, Win32_DiskDrive, Get-PhysicalDisk, Win32_OperatingSystem, Win32_BaseBoard, Win32_BIOS, Win32_Battery, Win32_NetworkAdapter, Win32_PnPEntity, Win32_ComputerSystem). Missing classes are handled without aborting.'
    Add-Line 'Scores from different engines or versions are not compared; every row records its own engine, workload, dataset and origin.'
    Add-SectionBreak

    Add-Line '## Trace and Privacy'
    Add-Line ''
    Add-Line 'HBSS intentionally creates no persistent application files, telemetry, or configuration changes. Temporary artifacts are cleaned up on normal termination. Unexpected power loss or OS-level logging may fall outside its control.'
    Add-Line ''
    Add-Line 'Third-party engines (when explicitly enabled) and operating-system logging may still record activity. HBSS itself transmits no data.'
    Add-SectionBreak

    Add-Line '## Skipped Tests'
    Add-Line ''
    Add-Line '| Benchmark | Category | Reason | Profile |'
    Add-Line '| --- | --- | --- | --- |'
    foreach ($s in $script:skipped) {
        Add-Line ('| ' + (Escape-Md $s.Benchmark) + ' | ' + (Escape-Md $s.Category) + ' | ' + (Escape-Md $s.Reason) + ' | ' + (Escape-Md $s.Profile) + ' |')
    }
    if (@($script:skipped).Count -eq 0) {
        Add-Line '| none | - | - | - |'
    }
    Add-SectionBreak

    Add-Line '## License'
    Add-Line ''
    Add-Line 'HBSS is licensed GPL-3.0-or-later (SPDX: GPL-3.0-or-later), Copyright (C) 2025 useless-rs. Third-party engines keep their own licenses; HBSS being GPL does not grant rights to redistribute proprietary binaries.'
    Add-SectionBreak

    Add-Line '## Caveats'
    Add-Line ''
    Add-Line '- Temperature, power settings, background applications and drivers affect results.'
    Add-Line '- Benchmarks from different engines or versions are not comparable.'
    Add-Line '- Short tests do not establish sustained thermal stability or long-term reliability.'
    Add-Line '- Storage results include filesystem and OS caching effects.'
    Add-Line '- Some hardware capabilities cannot be measured portably without admin rights or vendor tooling.'
    Add-Line '- HBSS is an evaluation tool, not a certification or a substitute for vendor-validated benchmarks.'

    $reportText = ($script:reportLines -join "`n") + "`n"
    [Console]::Out.Write($reportText)

    if ($Output) {
        try {
            [System.IO.File]::WriteAllText($Output, $reportText, [System.Text.Encoding]::UTF8)
            [Console]::Error.WriteLine(('Report written to ' + $Output))
        }
        catch {
            [Console]::Error.WriteLine('HBSS: could not write report to ' + $Output + ': ' + $_.Exception.Message)
        }
    }
    if ($Json) {
        $jsonPath = if ($Output) { $Output + '.json' } else { 'hbss_report.json' }
        try {
            $rows = @()
            foreach ($r in $script:results) {
                $rows += [pscustomobject]@{
                    benchmark = $r.Benchmark; category = $r.Category; engine = $r.Engine
                    version = $r.Version; workload = $r.Workload; threads = $r.Threads
                    dataset = $r.Dataset; duration_s = $r.Duration; result = $r.Result
                    unit = $r.Unit; origin = $r.Origin; notes = $r.Notes
                }
            }
            $json = $rows | ConvertTo-Json -Depth 3
            [System.IO.File]::WriteAllText($jsonPath, $json, [System.Text.Encoding]::UTF8)
            [Console]::Error.WriteLine(('JSON summary written to ' + $jsonPath))
        }
        catch {
            [Console]::Error.WriteLine('HBSS: could not write JSON summary: ' + $_.Exception.Message)
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$exitCode = 0

try {
    $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('hbss-' + [System.Guid]::NewGuid().ToString('N'))
    if (-not (New-Item -ItemType Directory -Path $script:tempDir -Force -ErrorAction SilentlyContinue)) {
        throw ('Could not create temporary workspace: ' + $script:tempDir)
    }

    Read-Inventory

    Run-Category -Category 'cpu' -Body { Invoke-CpuBenchmarks }
    Run-Category -Category 'gpu' -Body { Invoke-GpuBenchmarks }
    Run-Category -Category 'memory' -Body { Invoke-MemoryBenchmarks }
    Run-Category -Category 'storage' -Body {
        try { Invoke-StorageBenchmarks } catch { $script:failedCount++; Add-SkippedItem -Benchmark 'Storage suite' -Category 'storage' -Reason ('Unexpected error: ' + $_.Exception.Message) }
        if ($AllDrives) {
            try { Invoke-AllDrivesStorage } catch { $script:failedCount++; Add-SkippedItem -Benchmark 'Storage all-drive sweep' -Category 'storage' -Reason ('Unexpected error: ' + $_.Exception.Message) }
        }
    }
    Run-Category -Category 'network' -Body { Invoke-NetworkBenchmarks }
    Run-Category -Category 'npu' -Body { Invoke-NpuBenchmarks }
    Run-Category -Category 'crypto' -Body { Invoke-CryptoBenchmarks }
    # thermals and other are inventory-only and already collected by Read-Inventory.
}
catch {
    [Console]::Error.WriteLine('HBSS: fatal startup error: ' + $_.Exception.Message)
    $exitCode = 1
}
finally {
    if (($null -ne $script:tempDir) -and (Test-Path -LiteralPath $script:tempDir)) {
        try {
            Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Best-effort cleanup only.
        }
    }
}

if ($exitCode -eq 0) {
    Write-Report
}

exit $exitCode
