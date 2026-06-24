function Remove-CalendarEvent {
    <#
    .SYNOPSIS
        Deletes a managed calendar event by id.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$UserId,
        [Parameter(Mandatory)] [string]$EventId
    )

    if (-not $PSCmdlet.ShouldProcess($UserId, "Delete event $EventId")) {
        return
    }

    $uri = "https://graph.microsoft.com/v1.0/users/$UserId/events/$EventId"
    [void](Invoke-GraphRequest -Method DELETE -Uri $uri)
}
