function Normalize-PeopleHrHoliday {
    <#
    .SYNOPSIS
        Normalizes a PeopleHR holiday record into a standard format.

    .DESCRIPTION
        Converts a raw holiday record from PeopleHR into a normalized hashtable
        with consistent field names and data types.

    .PARAMETER HolidayRecord
        A hashtable containing the raw holiday data from PeopleHR.

    .EXAMPLE
        $normalized = Normalize-PeopleHrHoliday -HolidayRecord $record
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$HolidayRecord
    )

    Write-Verbose "Normalizing holiday record for: $($HolidayRecord.WorkEmail)"

    try {
        # Parse dates - handle various formats
        $startDate = [datetime]::Parse($HolidayRecord.StartDate)
        $endDate = [datetime]::Parse($HolidayRecord.EndDate)

        # Build normalized object
        $normalized = @{
            Email       = $HolidayRecord.WorkEmail
            FirstName   = $HolidayRecord.FirstName
            LastName    = $HolidayRecord.LastName
            StartDate   = $startDate
            EndDate     = $endDate
            Duration    = $HolidayRecord.Duration
            Comments    = $HolidayRecord.Comments
            Approver    = $HolidayRecord.Approver
            Status      = $HolidayRecord.Status
            EventType   = "Holiday"
            IsAllDay    = $true  # Holidays are typically all-day events
            StartTime   = $null
            EndTime     = $null
        }

        # Check if specific times are provided (rare for holidays)
        if ($HolidayRecord.StartTime) {
            $normalized.StartTime = $HolidayRecord.StartTime
            $normalized.IsAllDay = $false
        }

        if ($HolidayRecord.EndTime) {
            $normalized.EndTime = $HolidayRecord.EndTime
            $normalized.IsAllDay = $false
        }

        return $normalized
    }
    catch {
        Write-Error "Failed to normalize holiday record: $_"
        Write-Error "Record data: $($HolidayRecord | ConvertTo-Json)"
        throw
    }
}
