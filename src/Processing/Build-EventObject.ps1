function Get-EventUid {
    <#
    .SYNOPSIS
        Generates a deterministic UID for an event.

    .DESCRIPTION
        Creates a unique identifier based on email, dates, and event type.
        Format: <email>|<start ISO>|<end ISO>|<eventType>

    .PARAMETER Email
        The user's email address.

    .PARAMETER Start
        The event start datetime.

    .PARAMETER End
        The event end datetime.

    .PARAMETER Type
        The event type (e.g., "Holiday", "Training").

    .EXAMPLE
        $uid = Get-EventUid -Email "user@example.com" -Start $start -End $end -Type "Holiday"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email,

        [Parameter(Mandatory = $true)]
        [datetime]$Start,

        [Parameter(Mandatory = $true)]
        [datetime]$End,

        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    $startIso = $Start.ToString("o")
    $endIso = $End.ToString("o")

    return "$Email|$startIso|$endIso|$Type"
}

function Build-EventObject {
    <#
    .SYNOPSIS
        Builds a Microsoft Graph event payload from normalized PeopleHR data.

    .DESCRIPTION
        Creates a hashtable formatted for the Microsoft Graph events API,
        including the deterministic UID for event matching.

    .PARAMETER NormalizedEvent
        A normalized event hashtable from Normalize-PeopleHrHoliday or Normalize-PeopleHrOtherEvent.

    .EXAMPLE
        $payload = Build-EventObject -NormalizedEvent $normalized
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$NormalizedEvent
    )

    Write-Verbose "Building event object for: $($NormalizedEvent.Email)"

    try {
        # Determine subject based on event type
        $subject = if ($NormalizedEvent.EventType -eq "Holiday") {
            "Holiday - PeopleHR Sync"
        }
        else {
            "Other Event - PeopleHR Sync"
        }

        # Build event start/end datetimes
        $startDateTime = $NormalizedEvent.StartDate
        $endDateTime = $NormalizedEvent.EndDate

        # If specific times are provided, add them to the dates
        if (-not $NormalizedEvent.IsAllDay -and $NormalizedEvent.StartTime) {
            $startTime = [datetime]::Parse($NormalizedEvent.StartTime)
            $startDateTime = $startDateTime.Date.Add($startTime.TimeOfDay)
        }

        if (-not $NormalizedEvent.IsAllDay -and $NormalizedEvent.EndTime) {
            $endTime = [datetime]::Parse($NormalizedEvent.EndTime)
            $endDateTime = $endDateTime.Date.Add($endTime.TimeOfDay)
        }

        # Generate deterministic UID
        $uid = Get-EventUid `
            -Email $NormalizedEvent.Email `
            -Start $startDateTime `
            -End $endDateTime `
            -Type $NormalizedEvent.EventType

        # Build event body with metadata
        $bodyLines = @()
        
        if ($NormalizedEvent.EventType -eq "Holiday") {
            $bodyLines += "Holiday request from PeopleHR"
        }
        else {
            $bodyLines += "Event Type: $($NormalizedEvent.EventType)"
        }
        
        if ($NormalizedEvent.Comments) {
            $bodyLines += "Comments: $($NormalizedEvent.Comments)"
        }
        
        $bodyLines += "Requester: $($NormalizedEvent.FirstName) $($NormalizedEvent.LastName)"
        
        if ($NormalizedEvent.Approver) {
            $bodyLines += "Approver: $($NormalizedEvent.Approver)"
        }
        
        if ($NormalizedEvent.AddedBy) {
            $bodyLines += "Added By: $($NormalizedEvent.AddedBy)"
        }
        
        $bodyLines += "Duration: $($NormalizedEvent.Duration)"
        $bodyLines += "Status: $($NormalizedEvent.Status)"
        $bodyLines += ""
        $bodyLines += "PeopleHR-UID:$uid"

        $bodyText = $bodyLines -join "`n"

        # Build Graph API event payload
        $eventPayload = @{
            subject  = $subject
            body     = @{
                contentType = "text"
                content     = $bodyText
            }
            start    = @{
                dateTime = $startDateTime.ToString("yyyy-MM-ddTHH:mm:ss")
                timeZone = "UTC"
            }
            end      = @{
                dateTime = $endDateTime.ToString("yyyy-MM-ddTHH:mm:ss")
                timeZone = "UTC"
            }
            isAllDay = $NormalizedEvent.IsAllDay
        }

        # Add UID to payload for reference
        $eventPayload.UID = $uid

        return $eventPayload
    }
    catch {
        Write-Error "Failed to build event object: $_"
        Write-Error "Event data: $($NormalizedEvent | ConvertTo-Json)"
        throw
    }
}
