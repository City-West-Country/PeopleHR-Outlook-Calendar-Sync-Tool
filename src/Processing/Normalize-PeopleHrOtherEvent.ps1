function Normalize-PeopleHrOtherEvent {
    <#
    .SYNOPSIS
        Normalizes a PeopleHR other event record into a standard format.

    .DESCRIPTION
        Converts a raw other event record from PeopleHR into a normalized hashtable
        with consistent field names and data types.

    .PARAMETER EventRecord
        A hashtable containing the raw event data from PeopleHR.

    .EXAMPLE
        $normalized = Normalize-PeopleHrOtherEvent -EventRecord $record
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$EventRecord
    )

    Write-Verbose "Normalizing other event record for: $($EventRecord.WorkEmail)"

    try {
        # Parse dates
        $startDate = [datetime]::Parse($EventRecord.StartDate)
        $endDate = [datetime]::Parse($EventRecord.EndDate)

        # Determine if this is an all-day event
        $isAllDay = $true
        if ($EventRecord.StartTime -and $EventRecord.EndTime) {
            $isAllDay = $false
        }

        # Build normalized object
        $normalized = @{
            Email       = $EventRecord.WorkEmail
            FirstName   = $EventRecord.FirstName
            LastName    = $EventRecord.LastName
            StartDate   = $startDate
            EndDate     = $endDate
            Duration    = $EventRecord.Duration
            Comments    = $EventRecord.Comments
            Approver    = $EventRecord.Approver
            AddedBy     = $EventRecord.AddedBy
            Status      = $EventRecord.Status
            EventType   = $EventRecord.EventType
            IsAllDay    = $isAllDay
            StartTime   = $EventRecord.StartTime
            EndTime     = $EventRecord.EndTime
        }

        return $normalized
    }
    catch {
        Write-Error "Failed to normalize other event record: $_"
        Write-Error "Record data: $($EventRecord | ConvertTo-Json)"
        throw
    }
}
