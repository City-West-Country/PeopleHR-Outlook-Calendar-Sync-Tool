#requires -Version 5.1
<#
.SYNOPSIS
    Entry point for the PeopleHR -> Outlook calendar sync.

.DESCRIPTION
    Loads settings.json, authenticates to Microsoft Graph, pulls the PeopleHR holiday and
    other-event feeds, and reconciles each mailbox's calendar within the configured window.

.PARAMETER SettingsPath
    Path to settings.json. Defaults to ./settings.json next to this script.

.PARAMETER WhatIf
    Mock mode: read everything and report planned actions without writing to Graph.

.PARAMETER VerboseLogging
    Emit DEBUG lines (per-event detail) to the console and log file.

.EXAMPLE
    ./run.ps1

.EXAMPLE
    ./run.ps1 -WhatIf -VerboseLogging
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'settings.json'),
    [switch]$VerboseLogging
)

$ErrorActionPreference = 'Stop'

# Import the module fresh each run.
$modulePath = Join-Path $PSScriptRoot 'src/PeopleHrSync.psd1'
Import-Module $modulePath -Force

try {
    $config = Get-SyncConfig -Path $SettingsPath -RootPath $PSScriptRoot

    # CLI switches override settings.json.
    if ($VerboseLogging) { $config.VerboseLogging = $true }
    if ($PSBoundParameters.ContainsKey('WhatIf') -or $WhatIfPreference) { $config.WhatIf = $true }

    $logFile = Initialize-SyncLog -LogDirectory $config.LogDirectory -VerboseLogging:$config.VerboseLogging
    Write-SyncLog "PeopleHR -> Outlook sync starting. Log: $logFile"

    $summary = Invoke-PeopleHrSync -Config $config

    # Exit non-zero if any mailbox reported errors, so schedulers can alert.
    if ($summary.TotalErrors -gt 0) {
        Write-SyncLog "Completed with $($summary.TotalErrors) error(s)." -Level ERROR
        exit 1
    }
    Write-SyncLog 'Completed successfully.' -Level SUCCESS
    exit 0
}
catch {
    # Write-SyncLog may not be initialised yet if config/log setup failed.
    $msg = "FATAL: $($_.Exception.Message)"
    try { Write-SyncLog $msg -Level ERROR } catch { Write-Host $msg -ForegroundColor Red }
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 2
}
