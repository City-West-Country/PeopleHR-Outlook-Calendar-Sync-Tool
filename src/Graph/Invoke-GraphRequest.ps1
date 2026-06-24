function Invoke-GraphRequest {
    <#
    .SYNOPSIS
        Wrapper around Invoke-RestMethod for Microsoft Graph that handles auth headers,
        token refresh, throttling (429), transient 5xx errors, and pagination.

    .DESCRIPTION
        For GET requests that return a collection, all pages are followed via
        @odata.nextLink and the combined 'value' arrays are returned. For single-object
        GETs and write verbs, the raw response object is returned.

        Honours Retry-After on 429/503 and uses exponential backoff otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        # Hashtable/object body for POST/PATCH; serialised to JSON automatically.
        $Body,

        # Extra headers (e.g. Prefer for time zone) merged with the auth header.
        [hashtable]$Headers,

        [int]$MaxRetries = 5,

        # When set, follow @odata.nextLink and aggregate 'value' arrays.
        [switch]$Paginate
    )

    $results = New-Object System.Collections.Generic.List[object]
    $nextUri = $Uri

    while ($nextUri) {
        $attempt = 0
        $response = $null

        while ($true) {
            $attempt++
            $token = Get-GraphToken
            $requestHeaders = @{ Authorization = "Bearer $token" }
            if ($Headers) { $Headers.GetEnumerator() | ForEach-Object { $requestHeaders[$_.Key] = $_.Value } }

            $params = @{
                Method      = $Method
                Uri         = $nextUri
                Headers     = $requestHeaders
                ErrorAction = 'Stop'
            }
            if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body -and $Method -in 'POST', 'PATCH') {
                $params['Body'] = ($Body | ConvertTo-Json -Depth 12)
                $params['ContentType'] = 'application/json; charset=utf-8'
            }

            try {
                $response = Invoke-RestMethod @params
                break
            }
            catch {
                $status = $null
                if ($_.Exception.Response) {
                    try { $status = [int]$_.Exception.Response.StatusCode } catch { }
                }

                # 401: token may have been revoked early — force one refresh and retry.
                if ($status -eq 401 -and $attempt -lt $MaxRetries) {
                    Write-SyncLog 'Graph returned 401, forcing token refresh.' -Level DEBUG
                    $script:GraphContext.ExpiresOn = [datetime]::MinValue
                    continue
                }

                $retryable = $status -in 429, 500, 502, 503, 504
                if (-not $retryable -or $attempt -ge $MaxRetries) {
                    throw "Graph $Method $nextUri failed (HTTP $status): $($_.Exception.Message)"
                }

                # Respect Retry-After when present, otherwise exponential backoff.
                # Header access differs between PS 5.1 (WebException) and PS 7
                # (HttpResponseException), so read it defensively.
                $delay = [Math]::Pow(2, $attempt)
                try {
                    $retryAfter = $null
                    $hdrs = $_.Exception.Response.Headers
                    if ($hdrs) {
                        if ($hdrs.RetryAfter -and $hdrs.RetryAfter.Delta) { $retryAfter = $hdrs.RetryAfter.Delta.TotalSeconds }
                        elseif ($hdrs['Retry-After']) { $retryAfter = $hdrs['Retry-After'] }
                    }
                    if ($retryAfter) { $delay = [double]$retryAfter }
                }
                catch { }
                Write-SyncLog "Graph $Method throttled/transient (HTTP $status), retry $attempt in ${delay}s." -Level WARN -Indent 1
                Start-Sleep -Seconds $delay
            }
        }

        if ($Paginate) {
            if ($response.PSObject.Properties.Name -contains 'value') {
                foreach ($item in $response.value) { $results.Add($item) }
            }
            $nextUri = $response.'@odata.nextLink'
        }
        else {
            return $response
        }
    }

    return $results.ToArray()
}
