function Get-PeopleHrOtherEvents {
    <#
    .SYNOPSIS
        Fetches other event records from PeopleHR API.

    .DESCRIPTION
        Queries the PeopleHR API for other events (non-holiday events) using the configured query name.
        Returns all event records within the configured date range.

    .PARAMETER ApiKey
        The PeopleHR API key for authentication.

    .PARAMETER QueryName
        The name of the PeopleHR query to execute.
        Default: "Other Events : Outlook Feed (DO NOT REMOVE)"

    .EXAMPLE
        $events = Get-PeopleHrOtherEvents -ApiKey $config.PeopleHrApiKey
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,

        [Parameter(Mandatory = $false)]
        [string]$QueryName = "Other Events : Outlook Feed (DO NOT REMOVE)"
    )

    Write-Verbose "Fetching PeopleHR other events from query: $QueryName"

    $uri = "https://api.peoplehr.net/Query"

    $body = @{
        APIKey    = $ApiKey
        Action    = "RunQuery"
        QueryName = $QueryName
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType "application/json"
        
        if ($response.isError -eq $true) {
            throw "PeopleHR API Error: $($response.Message)"
        }

        Write-Verbose "Successfully retrieved $($response.Result.Count) other event records"
        return $response.Result
    }
    catch {
        Write-Error "Failed to fetch PeopleHR other events: $_"
        throw
    }
}
