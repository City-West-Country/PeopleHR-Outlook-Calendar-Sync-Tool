function ConvertTo-SyncOtherEvent {
    <#
    .SYNOPSIS
        Normalises a raw PeopleHR "Other Event" row into a unified sync-event object.

    .OUTPUTS
        A sync-event [pscustomobject], or $null if the row lacks the essentials.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Row
    )

    $email = Get-PeopleHrFieldValue -Row $Row -Names 'WorkEmail', 'Work Email', 'Email', 'EmailAddress'
    if (-not $email) {
        Write-SyncLog 'Skipping other-event row with no work email.' -Level DEBUG
        return $null
    }

    $firstName = Get-PeopleHrFieldValue -Row $Row -Names 'FirstName', 'First Name'
    $lastName  = Get-PeopleHrFieldValue -Row $Row -Names 'LastName', 'Last Name', 'Surname'
    $displayName = (@($firstName, $lastName) | Where-Object { $_ }) -join ' '

    $eventType = Get-PeopleHrFieldValue -Row $Row -Names 'EventType', 'Event Type', 'OtherEventType', 'Type'
    if (-not $eventType) { $eventType = 'Other Event' }

    $startRaw  = Get-PeopleHrFieldValue -Row $Row -Names 'StartDate', 'Start Date', 'From', 'FromDate'
    $endRaw    = Get-PeopleHrFieldValue -Row $Row -Names 'EndDate', 'End Date', 'To', 'ToDate'
    $startTime = Get-PeopleHrFieldValue -Row $Row -Names 'StartTime', 'Start Time'
    $endTime   = Get-PeopleHrFieldValue -Row $Row -Names 'EndTime', 'End Time'

    $start = ConvertTo-SyncDate -Value $startRaw -TimeValue $startTime
    $end   = ConvertTo-SyncDate -Value $endRaw   -TimeValue $endTime
    if (-not $start) {
        Write-SyncLog "Skipping other-event for $email — unparseable start ('$startRaw')." -Level WARN
        return $null
    }
    if (-not $end) { $end = $start }

    $isAllDay = (-not $startTime) -and (-not $endTime)
    if ($isAllDay) {
        $start = $start.Date
        $end   = $end.Date
    }

    $comments = Get-PeopleHrFieldValue -Row $Row -Names 'Comments', 'Comment', 'Notes'
    $approver = Get-PeopleHrFieldValue -Row $Row -Names 'Approver', 'AddedBy', 'Added By', 'ApprovedBy', 'Approved By'
    $status   = Get-PeopleHrFieldValue -Row $Row -Names 'Status'
    $duration = Get-PeopleHrFieldValue -Row $Row -Names 'Duration', 'TotalDuration'

    return New-SyncEvent -Email $email -DisplayName $displayName -Category 'Other Event' `
        -Subject 'Other Event - PeopleHR Sync' -EventType $eventType `
        -Start $start -End $end -IsAllDay $isAllDay `
        -Comments $comments -Requester $displayName -Approver $approver -Status $status -Duration $duration
}
