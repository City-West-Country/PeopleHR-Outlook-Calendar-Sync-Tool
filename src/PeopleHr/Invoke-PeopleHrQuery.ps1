function Invoke-PeopleHrQuery {
    <#
    .SYNOPSIS
        Runs a saved PeopleHR query by name and returns the result rows.

    .DESCRIPTION
        Calls the PeopleHR Query API. The API returns a JSON envelope whose shape has
        historically varied between accounts/versions, so the result extraction here is
        deliberately defensive: it looks for the rows under the common property names
        (Result / Results / Output) and returns an array of row objects.

        The body is built from a hashtable and serialised with ConvertTo-Json so that an
        API key or query name containing quotes/backslashes cannot break the payload.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ApiKey,

        [Parameter(Mandatory)]
        [string]$QueryName,

        [string]$BaseUri = 'https://api.peoplehr.net/Query',

        [string]$Action = 'GetQueryResultByQueryName',

        [int]$MaxRetries = 3
    )

    $body = @{
        APIKey    = $ApiKey
        Action    = $Action
        QueryName = $QueryName
    } | ConvertTo-Json -Depth 5

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $response = Invoke-RestMethod -Method Post -Uri $BaseUri -Body $body -ContentType 'application/json' -ErrorAction Stop
            break
        }
        catch {
            if ($attempt -ge $MaxRetries) {
                throw "PeopleHR query '$QueryName' failed after $attempt attempt(s): $($_.Exception.Message)"
            }
            $delay = [Math]::Pow(2, $attempt)
            Write-SyncLog "PeopleHR query '$QueryName' attempt $attempt failed, retrying in ${delay}s: $($_.Exception.Message)" -Level WARN -Indent 1
            Start-Sleep -Seconds $delay
        }
    }

    # The API signals failure inside a 200 response via isError / Status fields.
    if ($response.PSObject.Properties.Name -contains 'isError' -and $response.isError) {
        $msg = if ($response.Message) { $response.Message } else { 'unknown error' }
        throw "PeopleHR returned an error for query '$QueryName': $msg"
    }

    foreach ($prop in 'Result', 'Results', 'Output') {
        if ($response.PSObject.Properties.Name -contains $prop -and $null -ne $response.$prop) {
            return @($response.$prop)
        }
    }

    # Some accounts return a top-level array directly.
    if ($response -is [System.Array]) { return @($response) }

    Write-SyncLog "PeopleHR query '$QueryName' returned no recognisable result set." -Level WARN
    return @()
}
