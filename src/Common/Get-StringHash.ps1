function Get-StringHash {
    <#
    .SYNOPSIS
        Returns a short, stable SHA-256 hex hash of a string (used for change detection).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Value
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash  = $sha.ComputeHash($bytes)
        $hex   = -join ($hash | ForEach-Object { $_.ToString('x2') })
        return $hex.Substring(0, 32)
    }
    finally {
        $sha.Dispose()
    }
}
