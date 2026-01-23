function Upsert-CalendarEvent {
    <#
    .SYNOPSIS
        Creates or updates a calendar event in Microsoft Graph.

    .DESCRIPTION
        Creates a new event if ExistingEventId is not provided, otherwise updates the existing event.
        Uses the PATCH method for updates and POST for new events.

    .PARAMETER Token
        The Microsoft Graph access token.

    .PARAMETER UserId
        The user's email address or user principal name.

    .PARAMETER EventPayload
        A hashtable containing the event data (subject, body, start, end, etc.).

    .PARAMETER ExistingEventId
        The ID of an existing event to update. If null, creates a new event.

    .EXAMPLE
        Upsert-CalendarEvent -Token $token -UserId "user@example.com" -EventPayload $payload
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $true)]
        [hashtable]$EventPayload,

        [Parameter(Mandatory = $false)]
        [string]$ExistingEventId = $null
    )

    $headers = @{
        Authorization = "Bearer $Token"
        "Content-Type" = "application/json"
    }

    $jsonPayload = $EventPayload | ConvertTo-Json -Depth 10

    try {
        if ($ExistingEventId) {
            # Update existing event
            $uri = "https://graph.microsoft.com/v1.0/users/$UserId/events/$ExistingEventId"
            Write-Verbose "Updating event $ExistingEventId for user: $UserId"
            $result = Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $jsonPayload
            Write-Verbose "Successfully updated event $ExistingEventId"
        }
        else {
            # Create new event
            $uri = "https://graph.microsoft.com/v1.0/users/$UserId/events"
            Write-Verbose "Creating new event for user: $UserId"
            $result = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $jsonPayload
            Write-Verbose "Successfully created event with ID: $($result.id)"
        }

        return $result
    }
    catch {
        Write-Error "Failed to upsert calendar event for ${UserId}: $_"
        throw
    }
}
