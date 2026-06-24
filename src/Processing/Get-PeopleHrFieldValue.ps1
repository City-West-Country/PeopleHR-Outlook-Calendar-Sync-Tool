function Get-PeopleHrFieldValue {
    <#
    .SYNOPSIS
        Reads a field value from a PeopleHR query row, tolerant of naming and shape.

    .DESCRIPTION
        PeopleHR query rows expose columns under names that differ slightly between
        accounts, and a column may be a plain scalar or an object such as
        { DisplayValue = ...; Value = ... }. This helper takes a list of candidate column
        names and returns the first non-empty value found, unwrapping object columns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Row,
        [Parameter(Mandatory)] [string[]]$Names
    )

    foreach ($name in $Names) {
        $prop = $Row.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if (-not $prop) { continue }
        $val = $prop.Value
        if ($null -eq $val) { continue }

        # Unwrap common object shapes.
        if ($val -is [psobject] -or $val -is [pscustomobject]) {
            foreach ($inner in 'DisplayValue', 'Value', 'Text') {
                if ($val.PSObject.Properties.Name -contains $inner -and $val.$inner) {
                    return ([string]$val.$inner).Trim()
                }
            }
        }

        $s = ([string]$val).Trim()
        if ($s) { return $s }
    }
    return $null
}

function ConvertTo-SyncDate {
    <#
    .SYNOPSIS
        Parses a PeopleHR date/time string into a [datetime], trying UK and ISO formats.
    #>
    [CmdletBinding()]
    param(
        [string]$Value,
        [string]$TimeValue
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $combined = if ($TimeValue) { "$Value $TimeValue".Trim() } else { $Value.Trim() }

    [string[]]$formats = @(
        'dd/MM/yyyy HH:mm', 'dd/MM/yyyy H:mm', 'dd/MM/yyyy hh:mm tt',
        'dd/MM/yyyy', 'yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-dd', 'MM/dd/yyyy HH:mm', 'MM/dd/yyyy', 'dd-MM-yyyy', 'dd MMM yyyy'
    )
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::None

    [datetime]$parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($combined, $formats, $ci, $styles, [ref]$parsed)) {
        return $parsed
    }
    # Last resort: let .NET guess (handles locale-specific oddities).
    if ([datetime]::TryParse($combined, $ci, $styles, [ref]$parsed)) {
        return $parsed
    }
    return $null
}
