function Connect-GraphApi {
    <#
    .SYNOPSIS
        Authenticates to Microsoft Graph using client credentials flow.

    .DESCRIPTION
        Obtains an access token from Azure AD using client ID and secret.
        Uses the client credentials grant type for app-only authentication.

    .PARAMETER TenantId
        The Azure AD tenant ID.

    .PARAMETER ClientId
        The application (client) ID from Azure AD app registration.

    .PARAMETER ClientSecret
        The client secret from Azure AD app registration.

    .EXAMPLE
        $token = Connect-GraphApi -TenantId $config.TenantId -ClientId $config.ClientId -ClientSecret $config.ClientSecret
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret
    )

    Write-Verbose "Authenticating to Microsoft Graph..."

    $Body = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $ClientId
        client_secret = $ClientSecret
    }

    try {
        $TokenResponse = Invoke-RestMethod `
            -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Body $Body `
            -ContentType "application/x-www-form-urlencoded"

        Write-Verbose "Successfully authenticated to Microsoft Graph"
        return $TokenResponse.access_token
    }
    catch {
        Write-Error "Failed to authenticate to Microsoft Graph: $_"
        throw
    }
}
