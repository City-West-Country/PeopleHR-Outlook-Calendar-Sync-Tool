function Get-PeopleHrHolidays {
    <#
    .SYNOPSIS
        Fetches holiday records from PeopleHR API.

    .DESCRIPTION
        Queries the PeopleHR API for holiday data using the configured query name.
        Returns all holiday records within the configured date range.

    .PARAMETER ApiKey
        The PeopleHR API key for authentication.

    .PARAMETER QueryName
        The name of the PeopleHR query to execute.
        Default: "Holiday : Outlook Feed (DO NOT REMOVE)"

    .EXAMPLE
        $holidays = Get-PeopleHrHolidays -ApiKey $config.PeopleHrApiKey
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,

        [Parameter(Mandatory = $false)]
        [string]$QueryName = "Holiday : Outlook Feed (DO NOT REMOVE)"
    )

    Write-Verbose "Fetching PeopleHR holidays from query: $QueryName"

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

        Write-Verbose "Successfully retrieved $($response.Result.Count) holiday records"
        return $response.Result
    }
    catch {
        Write-Error "Failed to fetch PeopleHR holidays: $_"
        throw
    }
}
