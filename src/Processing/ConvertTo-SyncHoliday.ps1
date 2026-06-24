function ConvertTo-SyncHoliday {
    <#
    .SYNOPSIS
        Normalises a raw PeopleHR holiday row into a unified sync-event object.

    .OUTPUTS
        A sync-event [pscustomobject], or $null if the row lacks the essentials
        (work email + parseable start/end dates).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Row
    )

    $email = Get-PeopleHrFieldValue -Row $Row -Names 'WorkEmail', 'Work Email', 'Email', 'EmailAddress'
    if (-not $email) {
        Write-SyncLog 'Skipping holiday row with no work email.' -Level DEBUG
        return $null
    }

    $firstName = Get-PeopleHrFieldValue -Row $Row -Names 'FirstName', 'First Name'
    $lastName  = Get-PeopleHrFieldValue -Row $Row -Names 'LastName', 'Last Name', 'Surname'
    $displayName = (@($firstName, $lastName) | Where-Object { $_ }) -join ' '

    $startRaw = Get-PeopleHrFieldValue -Row $Row -Names 'StartDate', 'Start Date', 'HolidayStartDate', 'From', 'FromDate'
    $endRaw   = Get-PeopleHrFieldValue -Row $Row -Names 'EndDate', 'End Date', 'HolidayEndDate', 'To', 'ToDate'
    $startTime = Get-PeopleHrFieldValue -Row $Row -Names 'StartTime', 'Start Time'
    $endTime   = Get-PeopleHrFieldValue -Row $Row -Names 'EndTime', 'End Time'

    $start = ConvertTo-SyncDate -Value $startRaw -TimeValue $startTime
    $end   = ConvertTo-SyncDate -Value $endRaw   -TimeValue $endTime
    if (-not $start -or -not $end) {
        Write-SyncLog "Skipping holiday for $email — unparseable dates ('$startRaw' / '$endRaw')." -Level WARN
        return $null
    }

    # All-day unless explicit start/end times were supplied.
    $isAllDay = (-not $startTime) -and (-not $endTime)
    if ($isAllDay) {
        $start = $start.Date
        $end   = $end.Date
    }

    $comments  = Get-PeopleHrFieldValue -Row $Row -Names 'Comments', 'Comment', 'Notes'
    $approver  = Get-PeopleHrFieldValue -Row $Row -Names 'Approver', 'ApprovedBy', 'Approved By'
    $status    = Get-PeopleHrFieldValue -Row $Row -Names 'Status', 'HolidayStatus'
    $duration  = Get-PeopleHrFieldValue -Row $Row -Names 'Duration', 'TotalDuration', 'Days'
    $eventType = Get-PeopleHrFieldValue -Row $Row -Names 'HolidayType', 'LeaveType', 'Type'
    if (-not $eventType) { $eventType = 'Holiday' }

    return New-SyncEvent -Email $email -DisplayName $displayName -Category 'Holiday' `
        -Subject 'Holiday - PeopleHR Sync' -EventType $eventType `
        -Start $start -End $end -IsAllDay $isAllDay `
        -Comments $comments -Requester $displayName -Approver $approver -Status $status -Duration $duration
}
