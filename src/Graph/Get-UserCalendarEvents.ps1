function Get-UserCalendarEvents {
    <#
    .SYNOPSIS
        Retrieves calendar events for a specific user from Microsoft Graph.

    .DESCRIPTION
        Fetches all calendar events for the specified user within the given date range.
        Filters for events created by this sync tool using the PeopleHR-UID marker.

    .PARAMETER Token
        The Microsoft Graph access token.

    .PARAMETER UserId
        The user's email address or user principal name.

    .PARAMETER StartDate
        The start date for the query range.

    .PARAMETER EndDate
        The end date for the query range.

    .EXAMPLE
        $events = Get-UserCalendarEvents -Token $token -UserId "user@example.com" -StartDate $start -EndDate $end
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,

        [Parameter(Mandatory = $true)]
        [datetime]$EndDate
    )

    Write-Verbose "Fetching calendar events for user: $UserId"

    $headers = @{
        Authorization = "Bearer $Token"
    }

    # Format dates for Graph API
    $startDateTime = $StartDate.ToString("yyyy-MM-ddTHH:mm:ss")
    $endDateTime = $EndDate.ToString("yyyy-MM-ddTHH:mm:ss")

    # Build filter to get events in date range
    $filter = "start/dateTime ge '$startDateTime' and end/dateTime le '$endDateTime'"
    $uri = "https://graph.microsoft.com/v1.0/users/$UserId/calendar/events?`$filter=$filter&`$top=999"

    try {
        $allEvents = @()
        
        do {
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
            $allEvents += $response.value
            $uri = $response.'@odata.nextLink'
        } while ($uri)

        # Filter for events created by this sync tool (containing PeopleHR-UID)
        $syncedEvents = $allEvents | Where-Object { 
            $_.body.content -match "PeopleHR-UID:" 
        }

        Write-Verbose "Found $($syncedEvents.Count) synced events for user: $UserId"
        return $syncedEvents
    }
    catch {
        Write-Error "Failed to fetch calendar events for ${UserId}: $_"
        throw
    }
}
