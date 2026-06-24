#requires -Version 5.1
<#
.SYNOPSIS
    Interactive setup wizard for the PeopleHR -> Outlook Calendar Sync Tool.

.DESCRIPTION
    Walks you through configuring the tool:
      1. Collects your Entra (Graph) and PeopleHR settings.
      2. Stores the Graph client secret and PeopleHR API key in Windows Credential Manager
         (for the CURRENT user) — they never touch settings.json or git.
      3. Writes the non-secret values to settings.json.
      4. Optionally tests the connections.
      5. Optionally registers the daily Scheduled Task.

    Re-run any time to update settings or rotate secrets; existing values are offered as
    defaults.

    IMPORTANT (Credential Manager scoping): credentials are readable only by the user
    account that stored them. Run this wizard as the SAME account the Scheduled Task will
    run under (the wizard defaults the task to the current user for exactly this reason).

.EXAMPLE
    .\Setup.ps1
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'settings.json')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/PeopleHrSync.psd1') -Force

# ---------------------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------------------
function Write-Heading($text) {
    Write-Host ''
    Write-Host "== $text ==" -ForegroundColor Cyan
}

function Read-WithDefault {
    param([string]$Prompt, [string]$Default, [switch]$AllowEmpty)
    while ($true) {
        $suffix = if ($Default) { " [$Default]" } else { '' }
        $value = Read-Host "$Prompt$suffix"
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        if ($AllowEmpty -or -not [string]::IsNullOrWhiteSpace($value)) { return $value }
        Write-Host '  A value is required.' -ForegroundColor Yellow
    }
}

function Read-Guid {
    param([string]$Prompt, [string]$Default)
    while ($true) {
        $value = Read-WithDefault -Prompt $Prompt -Default $Default
        $g = [guid]::Empty
        if ([guid]::TryParse($value, [ref]$g)) { return $value }
        Write-Host '  That is not a valid GUID (expected xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).' -ForegroundColor Yellow
    }
}

function Read-IntWithDefault {
    param([string]$Prompt, [int]$Default)
    while ($true) {
        $value = Read-WithDefault -Prompt $Prompt -Default "$Default"
        $n = 0
        if ([int]::TryParse($value, [ref]$n) -and $n -ge 0) { return $n }
        Write-Host '  Please enter a whole number (0 or greater).' -ForegroundColor Yellow
    }
}

function Read-YesNo {
    param([string]$Prompt, [bool]$DefaultYes = $true)
    $hint = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    $value = Read-Host "$Prompt [$hint]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultYes }
    return $value -match '^(y|yes)$'
}

function Read-SecretValue {
    param([string]$Prompt)
    while ($true) {
        $s1 = Read-Host "$Prompt" -AsSecureString
        if ($s1.Length -eq 0) { Write-Host '  Value cannot be empty.' -ForegroundColor Yellow; continue }
        $s2 = Read-Host '  Confirm (re-enter)' -AsSecureString
        $b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1)
        $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2)
        try {
            $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
            $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
        }
        if ($p1 -ceq $p2) { return $s1 }
        Write-Host '  Entries did not match — try again.' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------------------
# 0. Load existing settings (if any) to use as defaults
# ---------------------------------------------------------------------------------------
Clear-Host
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  PeopleHR -> Outlook Calendar Sync — Setup Wizard' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Running as: $env:USERDOMAIN\$env:USERNAME"

$existing = $null
if (Test-Path -LiteralPath $SettingsPath) {
    try { $existing = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json } catch { }
    Write-Host "Found existing settings.json — current values are offered as defaults." -ForegroundColor DarkGray
}
function Existing($name, $fallback) {
    if ($existing -and $existing.PSObject.Properties.Name -contains $name -and $null -ne $existing.$name) { return $existing.$name }
    return $fallback
}

# ---------------------------------------------------------------------------------------
# 1. Entra / Microsoft Graph
# ---------------------------------------------------------------------------------------
Write-Heading 'Microsoft Entra app registration (Microsoft Graph)'
Write-Host 'The app needs application permissions Calendars.ReadWrite and User.Read.All (admin-consented).'
$tenantId = Read-Guid -Prompt 'Tenant ID'        -Default (Existing 'TenantId' '')
$clientId = Read-Guid -Prompt 'Client (App) ID'  -Default (Existing 'ClientId' '')

# ---------------------------------------------------------------------------------------
# 2. PeopleHR
# ---------------------------------------------------------------------------------------
Write-Heading 'PeopleHR API'
$baseUri      = Read-WithDefault -Prompt 'PeopleHR API base URI' -Default (Existing 'PeopleHrBaseUri' 'https://api.peoplehr.net/Query')
$action       = Read-WithDefault -Prompt 'PeopleHR API action'   -Default (Existing 'PeopleHrAction' 'GetQueryResultByQueryName')
$holidayQuery = Read-WithDefault -Prompt 'Holiday query name'     -Default (Existing 'HolidayQueryName' 'Holiday : Outlook Feed (DO NOT REMOVE)')
$otherQuery   = Read-WithDefault -Prompt 'Other Events query name'-Default (Existing 'OtherEventsQueryName' 'Other Events : Outlook Feed (DO NOT REMOVE)')

# ---------------------------------------------------------------------------------------
# 3. Sync behaviour
# ---------------------------------------------------------------------------------------
Write-Heading 'Sync window & behaviour'
$daysPast   = Read-IntWithDefault -Prompt 'Days to sync into the PAST'   -Default ([int](Existing 'SyncDaysPast' 30))
$daysFuture = Read-IntWithDefault -Prompt 'Days to sync into the FUTURE' -Default ([int](Existing 'SyncDaysFuture' 365))

$tz = Read-WithDefault -Prompt 'Windows time zone id' -Default (Existing 'TimeZone' 'GMT Standard Time')
if (-not ([System.TimeZoneInfo]::GetSystemTimeZones().Id -contains $tz)) {
    Write-Host "  Warning: '$tz' is not a recognised Windows time zone id on this machine." -ForegroundColor Yellow
}

$skipRaw = Read-WithDefault -Prompt 'Emails to skip (comma-separated)' -Default ((@(Existing 'SkipUsers' @()) ) -join ', ') -AllowEmpty
$skipUsers = @($skipRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$logDir = Read-WithDefault -Prompt 'Log directory' -Default (Existing 'LogDirectory' './logs')

# ---------------------------------------------------------------------------------------
# 4. Secrets -> Windows Credential Manager
# ---------------------------------------------------------------------------------------
Write-Heading 'Secrets (stored in Windows Credential Manager)'

function Set-SecretInteractive {
    param([ValidateSet('ClientSecret', 'ApiKey')] [string]$For, [string]$Label)
    $have = Test-SyncCredential -For $For
    if ($have) {
        if (-not (Read-YesNo "A $Label is already stored. Replace it?" -DefaultYes:$false)) {
            Write-Host "  Keeping existing $Label." -ForegroundColor DarkGray
            return
        }
    }
    $secure = Read-SecretValue -Prompt "Enter $Label"
    Set-SyncCredential -For $For -Secret $secure
    Write-Host "  Stored $Label in Credential Manager ($(Get-SyncCredentialTarget -For $For))." -ForegroundColor Green
}

Set-SecretInteractive -For ClientSecret -Label 'Graph client secret'
Set-SecretInteractive -For ApiKey       -Label 'PeopleHR API key'

# ---------------------------------------------------------------------------------------
# 5. Write settings.json (no secrets)
# ---------------------------------------------------------------------------------------
Write-Heading 'Writing settings.json'
$settings = [ordered]@{
    TenantId             = $tenantId
    ClientId             = $clientId
    # Secrets intentionally left blank here — they live in Windows Credential Manager.
    ClientSecret         = ''
    PeopleHrApiKey       = ''
    PeopleHrBaseUri      = $baseUri
    PeopleHrAction       = $action
    HolidayQueryName     = $holidayQuery
    OtherEventsQueryName = $otherQuery
    SyncDaysPast         = $daysPast
    SyncDaysFuture       = $daysFuture
    TimeZone             = $tz
    LogDirectory         = $logDir
    SkipUsers            = $skipUsers
    WhatIf               = [bool](Existing 'WhatIf' $false)
    VerboseLogging       = [bool](Existing 'VerboseLogging' $false)
}
($settings | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
Write-Host "  Wrote $SettingsPath" -ForegroundColor Green

# ---------------------------------------------------------------------------------------
# 6. Optional connection test
# ---------------------------------------------------------------------------------------
Write-Heading 'Test connections'
if (Read-YesNo 'Test the Graph and PeopleHR connections now?') {
    try {
        $config = Get-SyncConfig -Path $SettingsPath -RootPath $PSScriptRoot
        Initialize-SyncLog -LogDirectory $config.LogDirectory | Out-Null

        Write-Host '  Authenticating to Microsoft Graph...'
        [void](Connect-GraphApi -TenantId $config.TenantId -ClientId $config.ClientId -ClientSecret $config.ClientSecret)
        Write-Host '  Graph authentication OK.' -ForegroundColor Green

        Write-Host '  Querying PeopleHR holiday feed...'
        $rows = Get-PeopleHrHolidays -ApiKey $config.PeopleHrApiKey -QueryName $config.HolidayQueryName -BaseUri $config.PeopleHrBaseUri -Action $config.PeopleHrAction
        Write-Host "  PeopleHR returned $($rows.Count) holiday row(s)." -ForegroundColor Green
    }
    catch {
        Write-Host "  Test failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  Fix the issue and re-run Setup.ps1 (your entries are saved as defaults).' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------------------
# 7. Optional scheduled task registration
# ---------------------------------------------------------------------------------------
Write-Heading 'Schedule the daily sync'
Write-Host 'The Scheduled Task must run as the account whose Credential Manager holds the secrets.'
Write-Host "You stored the secrets as: $env:USERDOMAIN\$env:USERNAME" -ForegroundColor DarkGray

if (Read-YesNo 'Register the daily Scheduled Task now?') {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host '  Registering a task requires an elevated (Run as administrator) PowerShell.' -ForegroundColor Yellow
        Write-Host "  Re-run from an elevated prompt, or run: .\deploy\Register-ScheduledTask.ps1 -RunAsUser '$env:USERDOMAIN\$env:USERNAME'" -ForegroundColor Yellow
    }
    else {
        $timeStr = Read-WithDefault -Prompt 'Daily run time (HH:mm)' -Default '06:30'
        $runAs = "$env:USERDOMAIN\$env:USERNAME"
        if (-not (Read-YesNo "Run the task as the current user ($runAs)?")) {
            $runAs = Read-WithDefault -Prompt 'Run-as account (DOMAIN\\user)' -Default $runAs
            Write-Host "  NOTE: secrets must also be stored in ${runAs}'s Credential Manager." -ForegroundColor Yellow
            Write-Host "        Re-run Setup.ps1 while logged on as $runAs to store them there." -ForegroundColor Yellow
        }
        & (Join-Path $PSScriptRoot 'deploy/Register-ScheduledTask.ps1') -Time ([datetime]$timeStr) -RunAsUser $runAs
    }
}

Write-Heading 'Done'
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host 'Run a dry run any time with:  .\run.ps1 -WhatIf -VerboseLogging'
