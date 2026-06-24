function Invoke-PeopleHrSync {
    <#
    .SYNOPSIS
        End-to-end sync pipeline: PeopleHR feeds -> unified events -> per-mailbox reconcile.

    .PARAMETER Config
        The configuration object from Get-SyncConfig.

    .PARAMETER WhatIf
        Run without writing to Graph (mock mode). Reads still occur so the planned
        create/update/delete actions can be reported.

    .OUTPUTS
        A summary [pscustomobject] with totals and per-mailbox stats.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Config
    )

    # If the caller (or settings.json) requested mock mode, cascade -WhatIf to all nested
    # SupportsShouldProcess calls via the preference variable.
    if ($Config.WhatIf -and -not $WhatIfPreference) {
        $WhatIfPreference = $true
    }
    if ($WhatIfPreference) {
        Write-SyncLog 'Running in MOCK / -WhatIf mode: no changes will be written to Graph.' -Level WARN
    }

    $started = Get-Date

    # 1. Authenticate to Graph.
    [void](Connect-GraphApi -TenantId $Config.TenantId -ClientId $Config.ClientId -ClientSecret $Config.ClientSecret)

    # 2-3. Fetch both PeopleHR feeds.
    $holidayRows = Get-PeopleHrHolidays   -ApiKey $Config.PeopleHrApiKey -QueryName $Config.HolidayQueryName     -BaseUri $Config.PeopleHrBaseUri -Action $Config.PeopleHrAction
    $otherRows   = Get-PeopleHrOtherEvents -ApiKey $Config.PeopleHrApiKey -QueryName $Config.OtherEventsQueryName -BaseUri $Config.PeopleHrBaseUri -Action $Config.PeopleHrAction

    # 4. Normalise into unified sync events.
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($row in $holidayRows) {
        $e = ConvertTo-SyncHoliday -Row $row
        if ($e) { $events.Add($e) }
    }
    foreach ($row in $otherRows) {
        $e = ConvertTo-SyncOtherEvent -Row $row
        if ($e) { $events.Add($e) }
    }
    Write-SyncLog "Normalised $($events.Count) sync event(s) from PeopleHR feeds."

    # 5. Compute sync window.
    $windowStart = (Get-Date).Date.AddDays(-1 * [int]$Config.SyncDaysPast)
    $windowEnd   = (Get-Date).Date.AddDays([int]$Config.SyncDaysFuture)
    Write-SyncLog "Sync window: $($windowStart.ToString('yyyy-MM-dd')) -> $($windowEnd.ToString('yyyy-MM-dd'))"

    # 6. Group by mailbox, honouring SkipUsers.
    $byEmail = $events | Group-Object -Property Email
    $summaries = New-Object System.Collections.Generic.List[object]

    foreach ($group in $byEmail) {
        $email = $group.Name
        if ($Config.SkipUsers -contains $email.ToLowerInvariant()) {
            Write-SyncLog "Skipping $email (in SkipUsers)." -Level WARN -Indent 1
            continue
        }

        # 7. Reconcile this mailbox.
        $stats = Sync-UserCalendar -Email $email -DesiredEvents @($group.Group) `
            -WindowStart $windowStart -WindowEnd $windowEnd -TimeZone $Config.TimeZone
        $summaries.Add($stats)
    }

    # 8-9. Summarise.
    $summary = [pscustomobject]@{
        StartedAt     = $started
        FinishedAt    = Get-Date
        Mailboxes     = $summaries.Count
        TotalCreated  = ($summaries | Measure-Object -Property Created   -Sum).Sum
        TotalUpdated  = ($summaries | Measure-Object -Property Updated   -Sum).Sum
        TotalDeleted  = ($summaries | Measure-Object -Property Deleted   -Sum).Sum
        TotalUnchanged= ($summaries | Measure-Object -Property Unchanged -Sum).Sum
        TotalErrors   = ($summaries | Measure-Object -Property Errors    -Sum).Sum
        PerMailbox    = $summaries.ToArray()
    }

    Write-SyncLog ('SUMMARY: {0} mailbox(es) | created {1}, updated {2}, deleted {3}, unchanged {4}, errors {5}' -f `
        $summary.Mailboxes, $summary.TotalCreated, $summary.TotalUpdated, $summary.TotalDeleted, $summary.TotalUnchanged, $summary.TotalErrors) `
        -Level $(if ($summary.TotalErrors) { 'WARN' } else { 'SUCCESS' })

    return $summary
}
