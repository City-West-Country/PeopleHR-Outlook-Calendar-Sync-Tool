function Get-PeopleHrEventUid {
    <#
    .SYNOPSIS
        Builds the canonical, deterministic UID for a PeopleHR-derived event.

    .DESCRIPTION
        Format: <email>|<start ISO>|<end ISO>|<eventType>

        Email is lower-cased and dates are rendered in round-trip ("o") format so the same
        logical event always produces the same UID. Because start/end are part of the key,
        changing an event's dates in PeopleHR produces a new UID (i.e. delete + recreate
        rather than an in-place move) — this is intentional and documented in the README.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Email,
        [Parameter(Mandatory)] [datetime]$Start,
        [Parameter(Mandatory)] [datetime]$End,
        [Parameter(Mandatory)] [string]$Type
    )

    return '{0}|{1}|{2}|{3}' -f $Email.Trim().ToLowerInvariant(), $Start.ToString('o'), $End.ToString('o'), $Type
}
