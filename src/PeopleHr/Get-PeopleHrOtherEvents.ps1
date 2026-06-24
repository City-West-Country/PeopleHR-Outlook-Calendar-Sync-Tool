function Get-PeopleHrOtherEvents {
    <#
    .SYNOPSIS
        Fetches raw rows from the PeopleHR "Other Events : Outlook Feed" query.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ApiKey,
        [Parameter(Mandatory)] [string]$QueryName,
        [string]$BaseUri = 'https://api.peoplehr.net/Query',
        [string]$Action  = 'GetQueryResultByQueryName'
    )

    Write-SyncLog "Fetching PeopleHR other events (query: '$QueryName')..."
    $rows = Invoke-PeopleHrQuery -ApiKey $ApiKey -QueryName $QueryName -BaseUri $BaseUri -Action $Action
    Write-SyncLog "Loaded $($rows.Count) other-event record(s)." -Level SUCCESS
    return $rows
}
