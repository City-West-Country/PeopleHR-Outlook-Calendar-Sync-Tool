function Remove-CalendarEvent {
    <#
    .SYNOPSIS
        Deletes a calendar event from Microsoft Graph.

    .DESCRIPTION
        Removes the specified calendar event from the user's calendar.

    .PARAMETER Token
        The Microsoft Graph access token.

    .PARAMETER UserId
        The user's email address or user principal name.

    .PARAMETER EventId
        The ID of the event to delete.

    .EXAMPLE
        Remove-CalendarEvent -Token $token -UserId "user@example.com" -EventId $eventId
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $true)]
        [string]$EventId
    )

    Write-Verbose "Deleting event $EventId for user: $UserId"

    $headers = @{
        Authorization = "Bearer $Token"
    }

    $uri = "https://graph.microsoft.com/v1.0/users/$UserId/events/$EventId"

    try {
        Invoke-RestMethod -Method Delete -Uri $uri -Headers $headers
        Write-Verbose "Successfully deleted event $EventId"
    }
    catch {
        Write-Error "Failed to delete calendar event ${EventId} for ${UserId}: $_"
        throw
    }
}
