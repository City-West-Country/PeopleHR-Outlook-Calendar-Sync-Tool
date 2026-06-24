@{
    RootModule        = 'PeopleHrSync.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b7e6d5c4-3a21-4f09-8e7d-6c5b4a3f2e10'
    Author            = 'City West Country'
    CompanyName       = 'City West Country'
    Copyright         = '(c) City West Country. All rights reserved.'
    Description       = 'Syncs PeopleHR holidays and other events into Outlook calendars via Microsoft Graph (client-credentials/app-only auth).'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-SyncConfig'
        'Initialize-SyncLog'
        'Write-SyncLog'
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('PeopleHR', 'Outlook', 'MicrosoftGraph', 'Calendar', 'Sync')
            ProjectUri = 'https://github.com/'
        }
    }
}
