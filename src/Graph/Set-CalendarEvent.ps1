function Set-CalendarEvent {
    <#
    .SYNOPSIS
        Creates or updates (upserts) a managed calendar event for a user.

    .PARAMETER ExistingEventId
        When supplied, the event is updated (PATCH); otherwise a new event is created (POST).

    .OUTPUTS
        The Graph event object returned by the API (or a stub when -WhatIf is used).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$UserId,
        [Parameter(Mandatory)] [hashtable]$EventPayload,
        [string]$ExistingEventId
    )

    if ($ExistingEventId) {
        $uri = "https://graph.microsoft.com/v1.0/users/$UserId/events/$ExistingEventId"
        $action = "Update event $ExistingEventId"
        $method = 'PATCH'
    }
    else {
        $uri = "https://graph.microsoft.com/v1.0/users/$UserId/events"
        $action = 'Create event'
        $method = 'POST'
    }

    if (-not $PSCmdlet.ShouldProcess($UserId, $action)) {
        return [pscustomobject]@{ id = '(whatif)'; WhatIf = $true }
    }

    return Invoke-GraphRequest -Method $method -Uri $uri -Body $EventPayload
}
