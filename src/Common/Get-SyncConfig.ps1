function Get-SyncConfig {
    <#
    .SYNOPSIS
        Loads, validates and normalises settings.json into a config object.

    .DESCRIPTION
        Secrets (ClientSecret, PeopleHrApiKey) may be supplied either in settings.json or
        via environment variables, which take precedence so secrets can be kept out of the
        file entirely:

            GRAPH_CLIENT_SECRET   -> ClientSecret
            PEOPLEHR_API_KEY      -> PeopleHrApiKey

        Relative paths (LogDirectory) are resolved against the repository root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        # Repository root used to resolve relative paths in settings.json.
        [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Settings file not found: $Path. Copy settings.example.json to settings.json and fill it in."
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse $Path as JSON: $($_.Exception.Message)"
    }

    # Defaults merged with the loaded file.
    $defaults = @{
        TenantId             = ''
        ClientId             = ''
        ClientSecret         = ''
        PeopleHrApiKey       = ''
        PeopleHrBaseUri      = 'https://api.peoplehr.net/Query'
        PeopleHrAction       = 'GetQueryResultByQueryName'
        HolidayQueryName     = 'Holiday : Outlook Feed (DO NOT REMOVE)'
        OtherEventsQueryName = 'Other Events : Outlook Feed (DO NOT REMOVE)'
        SyncDaysPast         = 30
        SyncDaysFuture       = 365
        TimeZone             = 'GMT Standard Time'
        LogDirectory         = './logs'
        SkipUsers            = @()
        WhatIf               = $false
        VerboseLogging       = $false
    }

    $config = [ordered]@{}
    foreach ($key in $defaults.Keys) {
        if ($raw.PSObject.Properties.Name -contains $key -and $null -ne $raw.$key) {
            $config[$key] = $raw.$key
        }
        else {
            $config[$key] = $defaults[$key]
        }
    }

    # Secret resolution, lowest precedence first:
    #   1. value in settings.json (discouraged)
    #   2. Windows Credential Manager (set via Setup.ps1 / Set-SyncCredential)
    #   3. environment variable (highest, useful for ad-hoc/override)
    $credSecret = Get-SyncCredential -For ClientSecret
    if ($credSecret)              { $config['ClientSecret']  = $credSecret }
    if ($env:GRAPH_CLIENT_SECRET) { $config['ClientSecret']  = $env:GRAPH_CLIENT_SECRET }

    $credApiKey = Get-SyncCredential -For ApiKey
    if ($credApiKey)              { $config['PeopleHrApiKey'] = $credApiKey }
    if ($env:PEOPLEHR_API_KEY)    { $config['PeopleHrApiKey'] = $env:PEOPLEHR_API_KEY }

    # Validate required fields.
    $required = 'TenantId', 'ClientId', 'ClientSecret', 'PeopleHrApiKey'
    $missing = $required | Where-Object { [string]::IsNullOrWhiteSpace($config[$_]) }
    if ($missing) {
        throw "Missing required settings: $($missing -join ', '). Run .\Setup.ps1 to configure them (secrets are stored in Windows Credential Manager), or set them in $Path / environment variables."
    }

    # Resolve LogDirectory relative to repo root.
    if (-not [System.IO.Path]::IsPathRooted($config['LogDirectory'])) {
        $config['LogDirectory'] = Join-Path $RootPath ($config['LogDirectory'] -replace '^\./', '')
    }

    # Normalise SkipUsers to a lower-cased string array for case-insensitive matching.
    $config['SkipUsers'] = @($config['SkipUsers']) | Where-Object { $_ } | ForEach-Object { $_.ToString().Trim().ToLowerInvariant() }

    return [pscustomobject]$config
}
