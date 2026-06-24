function New-SyncEvent {
    <#
    .SYNOPSIS
        Factory that builds the unified sync-event object shared by holidays and other
        events, including the canonical UID, the human-readable body, and a content hash.

    .OUTPUTS
        [pscustomobject] with: Email, DisplayName, Category, EventType, Subject, Start, End,
        IsAllDay, Comments, Requester, Approver, Status, Duration, Uid, BodyText, Hash.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Email,
        [string]$DisplayName,
        [Parameter(Mandatory)] [ValidateSet('Holiday', 'Other Event')] [string]$Category,
        [Parameter(Mandatory)] [string]$Subject,
        [Parameter(Mandatory)] [string]$EventType,
        [Parameter(Mandatory)] [datetime]$Start,
        [Parameter(Mandatory)] [datetime]$End,
        [Parameter(Mandatory)] [bool]$IsAllDay,
        [string]$Comments,
        [string]$Requester,
        [string]$Approver,
        [string]$Status,
        [string]$Duration
    )

    $uid = Get-PeopleHrEventUid -Email $Email -Start $Start -End $End -Type $EventType

    # Human-readable body. The UID marker line is retained for visibility/back-compat;
    # the authoritative copy lives in an extended property on the event.
    $bodyLines = @(
        "PeopleHR $Category"
        "Type:      $EventType"
        if ($Requester) { "Requester: $Requester" }
        if ($Approver)  { "Approver:  $Approver" }
        if ($Status)    { "Status:    $Status" }
        if ($Duration)  { "Duration:  $Duration" }
        if ($Comments)  { "Comments:  $Comments" }
        ''
        '---'
        'This event is managed automatically by the PeopleHR -> Outlook sync. Do not edit.'
        "$($script:PeopleHrUidBodyPrefix)$uid"
    )
    $bodyText = ($bodyLines | Where-Object { $null -ne $_ }) -join "`n"

    # Content hash drives update detection — include every field we render.
    $hashSource = @(
        $Subject, $EventType, $Start.ToString('o'), $End.ToString('o'), $IsAllDay,
        $Status, $Comments, $Approver, $Requester, $Duration
    ) -join '|'
    $hash = Get-StringHash -Value $hashSource

    return [pscustomobject]@{
        Email       = $Email.Trim().ToLowerInvariant()
        DisplayName = $DisplayName
        Category    = $Category
        EventType   = $EventType
        Subject     = $Subject
        Start       = $Start
        End         = $End
        IsAllDay    = $IsAllDay
        Comments    = $Comments
        Requester   = $Requester
        Approver    = $Approver
        Status      = $Status
        Duration    = $Duration
        Uid         = $uid
        BodyText    = $bodyText
        Hash        = $hash
    }
}
