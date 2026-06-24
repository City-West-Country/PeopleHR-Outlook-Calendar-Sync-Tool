function New-GraphEventPayload {
    <#
    .SYNOPSIS
        Converts a unified sync-event object into the Microsoft Graph event payload.

    .DESCRIPTION
        Handles the two date shapes Graph requires:

          * All-day events: dateTime must be at midnight and the END is EXCLUSIVE (the day
            AFTER the last day). timeZone must be supplied.
          * Timed events: dateTime carries the local wall-clock time and timeZone names the
            zone Graph should interpret it in (PeopleHR times are treated as local).

        The canonical UID and content hash are written as single-value extended properties,
        and the managed-event category is applied, so the event can later be matched,
        updated, or safely deleted without parsing the body.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $SyncEvent,
        [string]$TimeZone = 'GMT Standard Time'
    )

    if ($SyncEvent.IsAllDay) {
        $startDateTime = $SyncEvent.Start.Date.ToString('yyyy-MM-ddT00:00:00.0000000')
        # Graph all-day end is exclusive: last day + 1.
        $endDateTime   = $SyncEvent.End.Date.AddDays(1).ToString('yyyy-MM-ddT00:00:00.0000000')
    }
    else {
        $startDateTime = $SyncEvent.Start.ToString('yyyy-MM-ddTHH:mm:ss.0000000')
        $endExclusive  = if ($SyncEvent.End -le $SyncEvent.Start) { $SyncEvent.Start.AddMinutes(30) } else { $SyncEvent.End }
        $endDateTime   = $endExclusive.ToString('yyyy-MM-ddTHH:mm:ss.0000000')
    }

    return @{
        subject = $SyncEvent.Subject
        body    = @{
            contentType = 'text'
            content     = $SyncEvent.BodyText
        }
        start = @{
            dateTime = $startDateTime
            timeZone = $TimeZone
        }
        end = @{
            dateTime = $endDateTime
            timeZone = $TimeZone
        }
        isAllDay   = $SyncEvent.IsAllDay
        showAs     = if ($SyncEvent.Category -eq 'Holiday') { 'oof' } else { 'busy' }
        categories = @($script:PeopleHrCategory)
        singleValueExtendedProperties = @(
            @{ id = $script:PeopleHrUidPropertyId;  value = $SyncEvent.Uid }
            @{ id = $script:PeopleHrHashPropertyId; value = $SyncEvent.Hash }
        )
    }
}
