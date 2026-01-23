function Find-MatchingEvent {
    <#
    .SYNOPSIS
        Finds a matching calendar event in an array of existing events.

    .DESCRIPTION
        Searches for an event with a matching PeopleHR-UID in the event body.
        Uses the deterministic UID format: <email>|<start ISO>|<end ISO>|<eventType>

    .PARAMETER ExistingEvents
        An array of existing calendar events from Microsoft Graph.

    .PARAMETER TargetUid
        The PeopleHR-UID to search for.

    .EXAMPLE
        $match = Find-MatchingEvent -ExistingEvents $events -TargetUid $uid
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$ExistingEvents,

        [Parameter(Mandatory = $true)]
        [string]$TargetUid
    )

    Write-Verbose "Searching for event with UID: $TargetUid"

    foreach ($event in $ExistingEvents) {
        if ($event.body.content -match "PeopleHR-UID:$([regex]::Escape($TargetUid))") {
            Write-Verbose "Found matching event: $($event.id)"
            return $event
        }
    }

    Write-Verbose "No matching event found for UID: $TargetUid"
    return $null
}
