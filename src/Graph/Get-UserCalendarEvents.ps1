function Get-UserCalendarEvents {
    <#
    .SYNOPSIS
        Returns the tool-managed calendar events for a user within the sync window.

    .DESCRIPTION
        Uses Graph calendarView (which expands the window correctly) and expands our
        custom UID/hash extended properties. Only events that carry our category AND a
        PeopleHR UID property are returned, so personal events are never touched.

        Returns objects shaped as:
            @{ Id; Uid; Hash; Subject; Event }   (Event = raw Graph event)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$UserId,
        [Parameter(Mandatory)] [datetime]$WindowStart,
        [Parameter(Mandatory)] [datetime]$WindowEnd
    )

    $startUtc = $WindowStart.ToUniversalTime().ToString('o')
    $endUtc   = $WindowEnd.ToUniversalTime().ToString('o')

    # Expand only our extended properties to keep the payload small.
    $expandFilter = "id eq '$($script:PeopleHrUidPropertyId)' or id eq '$($script:PeopleHrHashPropertyId)'"
    $select = 'id,subject,categories,start,end,isAllDay'
    $uri = "https://graph.microsoft.com/v1.0/users/$UserId/calendarView" +
           "?startDateTime=$startUtc&endDateTime=$endUtc" +
           "&`$select=$select" +
           "&`$expand=singleValueExtendedProperties(`$filter=$([uri]::EscapeDataString($expandFilter)))" +
           "&`$top=100"

    $events = Invoke-GraphRequest -Method GET -Uri $uri -Paginate

    $managed = foreach ($evt in $events) {
        $uid = $null
        $hash = $null
        foreach ($p in @($evt.singleValueExtendedProperties)) {
            if ($p.id -eq $script:PeopleHrUidPropertyId)  { $uid = $p.value }
            if ($p.id -eq $script:PeopleHrHashPropertyId) { $hash = $p.value }
        }

        # Require both our category and our UID property before considering it managed.
        $hasCategory = @($evt.categories) -contains $script:PeopleHrCategory
        if ($uid -and $hasCategory) {
            [pscustomobject]@{
                Id      = $evt.id
                Uid     = $uid
                Hash    = $hash
                Subject = $evt.subject
                Event   = $evt
            }
        }
    }

    return @($managed)
}
