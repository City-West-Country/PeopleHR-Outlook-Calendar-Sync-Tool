function Connect-GraphApi {
    <#
    .SYNOPSIS
        Acquires an app-only Microsoft Graph token via client credentials and stores a
        reusable context (with credentials) so the token can be auto-refreshed.

    .OUTPUTS
        The access token string (also cached in $script:GraphContext).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TenantId,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$ClientSecret
    )

    $script:GraphContext = [pscustomobject]@{
        TenantId     = $TenantId
        ClientId     = $ClientId
        ClientSecret = $ClientSecret
        AccessToken  = $null
        ExpiresOn    = [datetime]::MinValue
    }

    [void](Update-GraphToken)
    Write-SyncLog 'Acquired Microsoft Graph token (client credentials).' -Level SUCCESS
    return $script:GraphContext.AccessToken
}

function Update-GraphToken {
    <#
    .SYNOPSIS
        (Re)acquires the Graph token using the stored context. Internal helper.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:GraphContext) {
        throw 'Graph context not initialised. Call Connect-GraphApi first.'
    }
    $ctx = $script:GraphContext

    $body = @{
        grant_type    = 'client_credentials'
        scope         = 'https://graph.microsoft.com/.default'
        client_id     = $ctx.ClientId
        client_secret = $ctx.ClientSecret
    }

    $uri = "https://login.microsoftonline.com/$($ctx.TenantId)/oauth2/v2.0/token"
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop

    $ctx.AccessToken = $resp.access_token
    # Refresh 5 minutes before the stated expiry to avoid edge-of-expiry 401s.
    $ctx.ExpiresOn = (Get-Date).AddSeconds([int]$resp.expires_in - 300)
    return $ctx.AccessToken
}

function Get-GraphToken {
    <#
    .SYNOPSIS
        Returns a valid token, refreshing it if it is expired or about to expire.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:GraphContext) {
        throw 'Graph context not initialised. Call Connect-GraphApi first.'
    }
    if ((Get-Date) -ge $script:GraphContext.ExpiresOn) {
        Write-SyncLog 'Graph token expired/expiring, refreshing...' -Level DEBUG
        [void](Update-GraphToken)
    }
    return $script:GraphContext.AccessToken
}
