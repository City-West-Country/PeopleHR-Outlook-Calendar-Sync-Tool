function Sync-User {
    <#
    .SYNOPSIS
        Synchronizes PeopleHR events to a user's Outlook calendar.

    .DESCRIPTION
        Compares PeopleHR events with existing Outlook events for a user,
        then creates, updates, or deletes events as needed.

    .PARAMETER Token
        The Microsoft Graph access token.

    .PARAMETER UserEmail
        The user's email address.

    .PARAMETER PeopleHrEvents
        An array of normalized PeopleHR event objects for this user.

    .PARAMETER StartDate
        The start date of the sync window.

    .PARAMETER EndDate
        The end date of the sync window.

    .EXAMPLE
        Sync-User -Token $token -UserEmail "user@example.com" -PeopleHrEvents $events -StartDate $start -EndDate $end
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$UserEmail,

        [Parameter(Mandatory = $true)]
        [array]$PeopleHrEvents,

        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,

        [Parameter(Mandatory = $true)]
        [datetime]$EndDate
    )

    Write-Host "  [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Syncing mailbox: $UserEmail"

    try {
        # Fetch existing events from Outlook
        $existingEvents = Get-UserCalendarEvents `
            -Token $Token `
            -UserId $UserEmail `
            -StartDate $StartDate `
            -EndDate $EndDate

        # Track sync statistics
        $stats = @{
            Created = 0
            Updated = 0
            Deleted = 0
            Skipped = 0
        }

        # Process each PeopleHR event
        foreach ($peopleHrEvent in $PeopleHrEvents) {
            try {
                # Build Graph event payload
                $eventPayload = Build-EventObject -NormalizedEvent $peopleHrEvent
                $targetUid = $eventPayload.UID

                # Find matching event in Outlook
                $matchingEvent = Find-MatchingEvent `
                    -ExistingEvents $existingEvents `
                    -TargetUid $targetUid

                if ($matchingEvent) {
                    # Check if event needs updating
                    $needsUpdate = $false

                    if ($matchingEvent.subject -ne $eventPayload.subject) {
                        $needsUpdate = $true
                    }
                    elseif ($matchingEvent.start.dateTime -ne $eventPayload.start.dateTime) {
                        $needsUpdate = $true
                    }
                    elseif ($matchingEvent.end.dateTime -ne $eventPayload.end.dateTime) {
                        $needsUpdate = $true
                    }
                    elseif ($matchingEvent.isAllDay -ne $eventPayload.isAllDay) {
                        $needsUpdate = $true
                    }

                    if ($needsUpdate) {
                        # Update existing event
                        Upsert-CalendarEvent `
                            -Token $Token `
                            -UserId $UserEmail `
                            -EventPayload $eventPayload `
                            -ExistingEventId $matchingEvent.id

                        Write-Host "    [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]   Updated event: $($eventPayload.start.dateTime)"
                        $stats.Updated++
                    }
                    else {
                        $stats.Skipped++
                    }
                }
                else {
                    # Create new event
                    Upsert-CalendarEvent `
                        -Token $Token `
                        -UserId $UserEmail `
                        -EventPayload $eventPayload

                    Write-Host "    [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]   Created event: $($eventPayload.start.dateTime) → $($eventPayload.end.dateTime)"
                    $stats.Created++
                }
            }
            catch {
                Write-Warning "Failed to sync event for $UserEmail : $_"
            }
        }

        # Find and delete orphaned events (exist in Outlook but not in PeopleHR)
        $peopleHrUids = $PeopleHrEvents | ForEach-Object {
            $normalized = $_
            $payload = Build-EventObject -NormalizedEvent $normalized
            $payload.UID
        }

        foreach ($existingEvent in $existingEvents) {
            # Extract UID from event body
            if ($existingEvent.body.content -match "PeopleHR-UID:(.+)$") {
                $existingUid = $matches[1].Trim()

                if ($existingUid -notin $peopleHrUids) {
                    try {
                        # Delete orphaned event
                        Remove-CalendarEvent `
                            -Token $Token `
                            -UserId $UserEmail `
                            -EventId $existingEvent.id

                        Write-Host "    [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]   Deleted orphaned event: $($existingEvent.id)"
                        $stats.Deleted++
                    }
                    catch {
                        Write-Warning "Failed to delete orphaned event $($existingEvent.id) : $_"
                    }
                }
            }
        }

        # Log summary for this user
        Write-Host "    [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]   Summary: Created=$($stats.Created), Updated=$($stats.Updated), Deleted=$($stats.Deleted), Skipped=$($stats.Skipped)"

        return $stats
    }
    catch {
        Write-Error "Failed to sync user ${UserEmail}: $_"
        throw
    }
}
