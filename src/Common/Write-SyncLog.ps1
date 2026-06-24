function Write-SyncLog {
    <#
    .SYNOPSIS
        Writes a timestamped log line to the console and (optionally) a daily log file.

    .DESCRIPTION
        Central logging helper used across the sync pipeline. Honours the module-level
        $script:SyncLogState set by Initialize-SyncLog so callers do not have to pass the
        log path on every call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'SUCCESS')]
        [string]$Level = 'INFO',

        # Indentation depth for nested operations (e.g. per-mailbox detail lines).
        [int]$Indent = 0
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $pad = '  ' * [Math]::Max(0, $Indent)
    $line = "[$timestamp] [$($Level.PadRight(7))] $pad$Message"

    switch ($Level) {
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        'DEBUG'   { if ($script:SyncLogState.Verbose) { Write-Host $line -ForegroundColor DarkGray } }
        default   { Write-Host $line }
    }

    if ($script:SyncLogState -and $script:SyncLogState.FilePath) {
        # DEBUG lines are only written to file when verbose logging is enabled.
        if ($Level -ne 'DEBUG' -or $script:SyncLogState.Verbose) {
            Add-Content -LiteralPath $script:SyncLogState.FilePath -Value $line -Encoding UTF8
        }
    }
}

function Initialize-SyncLog {
    <#
    .SYNOPSIS
        Prepares the daily log file and stores logging state for the session.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [switch]$VerboseLogging
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $fileName = 'sync-{0}.log' -f (Get-Date).ToString('yyyy-MM-dd')
    $filePath = Join-Path $LogDirectory $fileName

    $script:SyncLogState = [pscustomobject]@{
        FilePath = $filePath
        Verbose  = [bool]$VerboseLogging
    }

    return $filePath
}
