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

# HBSS Windows entry shim.
# Downloads (or, in dev mode, copies) the pinned benchmark payload into a
# temporary workspace, verifies its SHA-256, executes it as a FILE (never by
# evaluating downloaded text), propagates its exit code, and cleans up in finally.
# This script writes nothing to stdout; all diagnostics go to stderr.

$ErrorActionPreference = 'Stop'

$HBSS_VERSION = '1.0.0'

$BaseUrl = $env:HBSS_BASE_URL
if ([string]::IsNullOrEmpty($BaseUrl)) {
    $BaseUrl = 'https://raw.githubusercontent.com/useless-rs/HBSS/main'
}
$PayloadUrl = "$BaseUrl/bench.ps1"

# The parent release process replaces this literal with the real pinned digest.
$PayloadSha256 = '947ad0e3d356d67fa46ee1f50abe8e4024d21d330d563601966077310f40f0ac'

$tempDir = $null
$payloadPath = $null
$exitCode = 0

try {
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('hbss-' + [System.Guid]::NewGuid().ToString('N'))
    if (-not (New-Item -ItemType Directory -Path $tempDir -Force -ErrorAction SilentlyContinue)) {
        throw ('Could not create temporary workspace: ' + $tempDir)
    }
    $payloadPath = Join-Path $tempDir 'bench.ps1'

    $devSibling = Join-Path -Path $PSScriptRoot -ChildPath 'bench.ps1'
    $useDev = (($env:HBSS_DEV -eq '1') -and (Test-Path -LiteralPath $devSibling -PathType Leaf))

    if ($useDev) {
        Copy-Item -LiteralPath $devSibling -Destination $payloadPath -Force -ErrorAction Stop
    }
    else {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $PayloadUrl -OutFile $payloadPath -ErrorAction Stop
        }
        catch {
            [Console]::Error.WriteLine("HBSS: failed to download payload from '$PayloadUrl': $($_.Exception.Message)")
            exit 1
        }

        if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
            [Console]::Error.WriteLine("HBSS: downloaded payload was not found at '$payloadPath'.")
            exit 1
        }

        try {
            $actualHash = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        }
        catch {
            [Console]::Error.WriteLine("HBSS: could not compute the payload SHA-256: $($_.Exception.Message)")
            exit 1
        }

        $isPlaceholder = ($PayloadSha256 -eq 'REPLACE_WITH_PINNED_SHA256')
        $expected = $PayloadSha256.ToLowerInvariant()
        if ((-not $isPlaceholder) -and ($actualHash -ne $expected)) {
            [Console]::Error.WriteLine("HBSS: payload SHA-256 mismatch. Expected '$expected', got '$actualHash'. Refusing to execute.")
            exit 1
        }
    }

    & $payloadPath @args
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    $exitCode = [int]$code
}
catch {
    [Console]::Error.WriteLine("HBSS: fatal error: $($_.Exception.Message)")
    $exitCode = 1
}
finally {
    if (($null -ne $tempDir) -and (Test-Path -LiteralPath $tempDir)) {
        try {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Best-effort cleanup only; never mask the payload result.
        }
    }
}

exit $exitCode
