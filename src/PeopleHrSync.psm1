# PeopleHrSync module loader.
# Dot-sources every function file under the module's subfolders and exports the public API.

$ErrorActionPreference = 'Stop'

# Load order: Common first (constants/helpers used by everything else), then the rest.
$folders = 'Common', 'PeopleHr', 'Graph', 'Processing'

foreach ($folder in $folders) {
    $path = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path $path)) { continue }
    Get-ChildItem -Path $path -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
        . $_.FullName
    }
}

# Public API (private helpers such as Update-GraphToken / Get-GraphToken stay unexported).
$public = @(
    'Get-SyncConfig'
    'Initialize-SyncLog'
    'Write-SyncLog'
    'Get-SyncCredentialTarget'
    'Set-SyncCredential'
    'Get-SyncCredential'
    'Test-SyncCredential'
    'Remove-SyncCredential'
    'Connect-GraphApi'
    'Invoke-GraphRequest'
    'Get-UserCalendarEvents'
    'Set-CalendarEvent'
    'Remove-CalendarEvent'
    'Get-PeopleHrHolidays'
    'Get-PeopleHrOtherEvents'
    'Invoke-PeopleHrQuery'
    'Get-PeopleHrEventUid'
    'Get-PeopleHrFieldValue'
    'ConvertTo-SyncDate'
    'ConvertTo-SyncHoliday'
    'ConvertTo-SyncOtherEvent'
    'New-SyncEvent'
    'New-GraphEventPayload'
    'Sync-UserCalendar'
    'Invoke-PeopleHrSync'
    'Get-StringHash'
)

Export-ModuleMember -Function $public
