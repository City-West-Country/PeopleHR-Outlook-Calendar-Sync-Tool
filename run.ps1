<#
.SYNOPSIS
    PeopleHR to Outlook Calendar Sync Tool

.DESCRIPTION
    Synchronizes holidays and other events from PeopleHR to Outlook calendars via Microsoft Graph.
    Uses client credentials authentication and supports configurable sync windows.

.PARAMETER ConfigPath
    Path to the settings.json configuration file. Default: ./settings.json

.PARAMETER WhatIf
    If specified, runs in mock mode without making any changes to calendars.

.EXAMPLE
    .\run.ps1
    
.EXAMPLE
    .\run.ps1 -ConfigPath "C:\config\settings.json"

.EXAMPLE
    .\run.ps1 -WhatIf
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "./settings.json",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Script start time
$startTime = Get-Date

Write-Host "======================================================================"
Write-Host "  PeopleHR → Outlook Calendar Sync Tool"
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "======================================================================"
Write-Host ""

# Load all function definitions
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Loading function definitions..."

$scriptRoot = $PSScriptRoot

# Load PeopleHR functions
. "$scriptRoot/src/PeopleHr/Get-PeopleHrHolidays.ps1"
. "$scriptRoot/src/PeopleHr/Get-PeopleHrOtherEvents.ps1"

# Load Graph functions
. "$scriptRoot/src/Graph/Connect-Graph.ps1"
. "$scriptRoot/src/Graph/Get-UserCalendarEvents.ps1"
. "$scriptRoot/src/Graph/Upsert-CalendarEvent.ps1"
. "$scriptRoot/src/Graph/Delete-CalendarEvent.ps1"
. "$scriptRoot/src/Graph/Find-MatchingEvent.ps1"

# Load Processing functions
. "$scriptRoot/src/Processing/Normalize-PeopleHrHoliday.ps1"
. "$scriptRoot/src/Processing/Normalize-PeopleHrOtherEvent.ps1"
. "$scriptRoot/src/Processing/Build-EventObject.ps1"
. "$scriptRoot/src/Processing/Sync-User.ps1"

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Functions loaded successfully"
Write-Host ""

# Load configuration
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Loading configuration from: $ConfigPath"

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

try {
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Configuration loaded successfully"
}
catch {
    Write-Error "Failed to load configuration: $_"
    exit 1
}

# Validate required configuration
$requiredFields = @('TenantId', 'ClientId', 'ClientSecret', 'PeopleHrApiKey')
foreach ($field in $requiredFields) {
    if (-not $config.$field) {
        Write-Error "Missing required configuration field: $field"
        exit 1
    }
}

# Calculate sync date range
$syncStartDate = (Get-Date).AddDays(-$config.SyncDaysPast)
$syncEndDate = (Get-Date).AddDays($config.SyncDaysFuture)

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Sync window: $($syncStartDate.ToString('yyyy-MM-dd')) to $($syncEndDate.ToString('yyyy-MM-dd'))"
Write-Host ""

# Initialize logging
$logDirectory = $config.LogDirectory
if (-not (Test-Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

$logFile = Join-Path $logDirectory "sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logFile -Append

try {
    # Step 1: Authenticate to Microsoft Graph
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Authenticating to Microsoft Graph..."
    
    if ($WhatIf) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ** WHATIF MODE - No changes will be made **"
        $token = "MOCK_TOKEN"
    }
    else {
        $token = Connect-GraphApi `
            -TenantId $config.TenantId `
            -ClientId $config.ClientId `
            -ClientSecret $config.ClientSecret
    }
    
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Successfully authenticated to Microsoft Graph"
    Write-Host ""

    # Step 2: Fetch holidays from PeopleHR
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Fetching PeopleHR holidays..."
    
    if ($WhatIf) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ** WHATIF MODE - Skipping PeopleHR API call **"
        $holidayRecords = @()
    }
    else {
        $holidayRecords = Get-PeopleHrHolidays -ApiKey $config.PeopleHrApiKey
    }
    
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Loaded $($holidayRecords.Count) holiday records"
    Write-Host ""

    # Step 3: Fetch other events from PeopleHR
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Fetching PeopleHR other events..."
    
    if ($WhatIf) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ** WHATIF MODE - Skipping PeopleHR API call **"
        $otherEventRecords = @()
    }
    else {
        $otherEventRecords = Get-PeopleHrOtherEvents -ApiKey $config.PeopleHrApiKey
    }
    
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Loaded $($otherEventRecords.Count) other event records"
    Write-Host ""

    # Step 4: Normalize all events
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Normalizing event data..."
    
    $allEvents = @()

    foreach ($record in $holidayRecords) {
        try {
            $normalized = Normalize-PeopleHrHoliday -HolidayRecord $record
            $allEvents += $normalized
        }
        catch {
            Write-Warning "Failed to normalize holiday record: $_"
        }
    }

    foreach ($record in $otherEventRecords) {
        try {
            $normalized = Normalize-PeopleHrOtherEvent -EventRecord $record
            $allEvents += $normalized
        }
        catch {
            Write-Warning "Failed to normalize other event record: $_"
        }
    }

    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Normalized $($allEvents.Count) total events"
    Write-Host ""

    # Step 5: Filter events to sync window
    $eventsInWindow = $allEvents | Where-Object {
        $_.StartDate -ge $syncStartDate -and $_.EndDate -le $syncEndDate
    }

    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($eventsInWindow.Count) events within sync window"
    Write-Host ""

    # Step 6: Group events by user email
    $eventsByUser = $eventsInWindow | Group-Object -Property Email

    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Processing $($eventsByUser.Count) users..."
    Write-Host ""

    # Step 7: Sync each user
    $totalStats = @{
        Users   = 0
        Created = 0
        Updated = 0
        Deleted = 0
        Skipped = 0
        Errors  = 0
    }

    foreach ($userGroup in $eventsByUser) {
        $userEmail = $userGroup.Name
        
        # Skip users in the skip list
        if ($config.SkipUsers -contains $userEmail) {
            Write-Host "  [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Skipping user (in skip list): $userEmail"
            continue
        }

        try {
            if ($WhatIf) {
                Write-Host "  [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ** WHATIF MODE ** Would sync: $userEmail ($($userGroup.Group.Count) events)"
                $totalStats.Users++
            }
            else {
                $stats = Sync-User `
                    -Token $token `
                    -UserEmail $userEmail `
                    -PeopleHrEvents $userGroup.Group `
                    -StartDate $syncStartDate `
                    -EndDate $syncEndDate

                $totalStats.Users++
                $totalStats.Created += $stats.Created
                $totalStats.Updated += $stats.Updated
                $totalStats.Deleted += $stats.Deleted
                $totalStats.Skipped += $stats.Skipped
            }
        }
        catch {
            Write-Error "Failed to sync user ${userEmail}: $_"
            $totalStats.Errors++
        }

        Write-Host ""
    }

    # Step 8: Display summary
    $endTime = Get-Date
    $duration = $endTime - $startTime

    Write-Host "======================================================================"
    Write-Host "  Sync Summary"
    Write-Host "======================================================================"
    Write-Host "  Users processed:    $($totalStats.Users)"
    Write-Host "  Events created:     $($totalStats.Created)"
    Write-Host "  Events updated:     $($totalStats.Updated)"
    Write-Host "  Events deleted:     $($totalStats.Deleted)"
    Write-Host "  Events skipped:     $($totalStats.Skipped)"
    Write-Host "  Errors:             $($totalStats.Errors)"
    Write-Host "  Duration:           $($duration.ToString('hh\:mm\:ss'))"
    Write-Host "  Completed:          $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "======================================================================"
    Write-Host ""

    # Exit with appropriate code
    if ($totalStats.Errors -gt 0) {
        Write-Host "Sync completed with errors. Check log file: $logFile"
        exit 1
    }
    else {
        Write-Host "Sync completed successfully. Log file: $logFile"
        exit 0
    }
}
catch {
    Write-Error "Fatal error during sync: $_"
    Write-Host "Check log file: $logFile"
    exit 1
}
finally {
    Stop-Transcript
}
