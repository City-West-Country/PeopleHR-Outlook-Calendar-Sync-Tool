function Sync-UserCalendar {
    <#
    .SYNOPSIS
        Reconciles a single mailbox's managed events against the desired set from PeopleHR.

    .DESCRIPTION
        Strategy (within the sync window only):
          * Fetch existing tool-managed events (category + UID property).
          * CREATE desired events whose UID is not present.
          * UPDATE existing events whose stored content hash differs from the desired hash.
          * DELETE managed events whose UID is no longer in the desired set (orphans).

        Personal events are never considered — only events carrying our category and UID.

    .OUTPUTS
        [pscustomobject] stats: Email, Created, Updated, Deleted, Unchanged, Errors.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$Email,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$DesiredEvents,
        [Parameter(Mandatory)] [datetime]$WindowStart,
        [Parameter(Mandatory)] [datetime]$WindowEnd,
        [string]$TimeZone = 'GMT Standard Time'
    )

    $stats = [pscustomobject]@{
        Email     = $Email
        Created   = 0
        Updated   = 0
        Deleted   = 0
        Unchanged = 0
        Errors    = 0
    }

    Write-SyncLog "Syncing mailbox: $Email" -Indent 1

    try {
        $existing = Get-UserCalendarEvents -UserId $Email -WindowStart $WindowStart -WindowEnd $WindowEnd
    }
    catch {
        Write-SyncLog "Failed to read calendar for $Email (mailbox missing or no access?): $($_.Exception.Message)" -Level ERROR -Indent 2
        $stats.Errors++
        return $stats
    }

    # Index existing managed events by UID (last one wins on the rare duplicate).
    $existingByUid = @{}
    foreach ($e in $existing) { $existingByUid[$e.Uid] = $e }

    # Only sync desired events whose start falls inside the window (defensive; the feed
    # may contain rows outside the window).
    $desiredInWindow = $DesiredEvents | Where-Object {
        $_.Start -ge $WindowStart.Date -and $_.Start -le $WindowEnd
    }

    $desiredUids = New-Object System.Collections.Generic.HashSet[string]

    foreach ($evt in $desiredInWindow) {
        [void]$desiredUids.Add($evt.Uid)
        $payload = New-GraphEventPayload -SyncEvent $evt -TimeZone $TimeZone
        $match = $existingByUid[$evt.Uid]

        try {
            if (-not $match) {
                [void](Set-CalendarEvent -UserId $Email -EventPayload $payload)
                $stats.Created++
                Write-SyncLog "Created: $($evt.EventType) $($evt.Start.ToString('yyyy-MM-dd')) -> $($evt.End.ToString('yyyy-MM-dd'))" -Level SUCCESS -Indent 2
            }
            elseif ($match.Hash -ne $evt.Hash) {
                [void](Set-CalendarEvent -UserId $Email -EventPayload $payload -ExistingEventId $match.Id)
                $stats.Updated++
                Write-SyncLog "Updated: $($evt.EventType) $($evt.Start.ToString('yyyy-MM-dd'))" -Level SUCCESS -Indent 2
            }
            else {
                $stats.Unchanged++
                Write-SyncLog "Unchanged: $($evt.EventType) $($evt.Start.ToString('yyyy-MM-dd'))" -Level DEBUG -Indent 2
            }
        }
        catch {
            Write-SyncLog "Error upserting event for $Email ($($evt.Uid)): $($_.Exception.Message)" -Level ERROR -Indent 2
            $stats.Errors++
        }
    }

    # Delete orphaned managed events.
    foreach ($e in $existing) {
        if (-not $desiredUids.Contains($e.Uid)) {
            try {
                Remove-CalendarEvent -UserId $Email -EventId $e.Id
                $stats.Deleted++
                Write-SyncLog "Deleted orphaned event: $($e.Subject) [$($e.Id.Substring(0, [Math]::Min(8, $e.Id.Length)))...]" -Level SUCCESS -Indent 2
            }
            catch {
                Write-SyncLog "Error deleting event $($e.Id) for $Email`: $($_.Exception.Message)" -Level ERROR -Indent 2
                $stats.Errors++
            }
        }
    }

    Write-SyncLog ("Done {0}: +{1} ~{2} -{3} ={4} !{5}" -f $Email, $stats.Created, $stats.Updated, $stats.Deleted, $stats.Unchanged, $stats.Errors) -Indent 1
    return $stats
}
