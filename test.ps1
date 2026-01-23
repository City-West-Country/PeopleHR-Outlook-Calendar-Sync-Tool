<#
.SYNOPSIS
    Test and validate PeopleHR-Outlook Calendar Sync Tool setup

.DESCRIPTION
    Performs basic validation of the tool configuration without making any changes.
    Tests authentication, API connectivity, and data retrieval.

.PARAMETER ConfigPath
    Path to settings.json file. Default: ./settings.json

.EXAMPLE
    .\test.ps1

.EXAMPLE
    .\test.ps1 -ConfigPath "C:\config\settings.json"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "./settings.json"
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "======================================================================"
Write-Host "  PeopleHR-Outlook Calendar Sync Tool - Validation"
Write-Host "======================================================================"
Write-Host ""

# Track test results
$testResults = @{
    Passed = 0
    Failed = 0
    Warnings = 0
}

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$TestScript
    )
    
    Write-Host "Testing: $Name" -ForegroundColor Cyan
    Write-Host "  " -NoNewline
    
    try {
        $result = & $TestScript
        if ($result.Success) {
            Write-Host "✓ PASSED" -ForegroundColor Green
            if ($result.Message) {
                Write-Host "    $($result.Message)" -ForegroundColor Gray
            }
            $script:testResults.Passed++
        }
        else {
            Write-Host "✗ FAILED" -ForegroundColor Red
            Write-Host "    $($result.Message)" -ForegroundColor Yellow
            $script:testResults.Failed++
        }
    }
    catch {
        Write-Host "✗ FAILED" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
        $script:testResults.Failed++
    }
    
    Write-Host ""
}

# Test 1: Configuration file exists
Test-Step "Configuration file exists" {
    if (Test-Path $ConfigPath) {
        return @{ Success = $true; Message = "Found: $ConfigPath" }
    }
    else {
        return @{ Success = $false; Message = "Configuration file not found: $ConfigPath" }
    }
}

# Test 2: Configuration file is valid JSON
Test-Step "Configuration file is valid JSON" {
    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        return @{ Success = $true; Message = "JSON parsed successfully" }
    }
    catch {
        return @{ Success = $false; Message = "Invalid JSON: $_" }
    }
}

# Load configuration for remaining tests
$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

# Test 3: Required fields present
Test-Step "Required configuration fields present" {
    $requiredFields = @('TenantId', 'ClientId', 'ClientSecret', 'PeopleHrApiKey')
    $missingFields = @()
    
    foreach ($field in $requiredFields) {
        if (-not $config.$field -or $config.$field -eq "your-$($field.ToLower())-here" -or $config.$field -like "xxxxxxxx*") {
            $missingFields += $field
        }
    }
    
    if ($missingFields.Count -eq 0) {
        return @{ Success = $true; Message = "All required fields configured" }
    }
    else {
        return @{ Success = $false; Message = "Missing or placeholder values: $($missingFields -join ', ')" }
    }
}

# Test 4: PowerShell version
Test-Step "PowerShell version" {
    $version = $PSVersionTable.PSVersion
    if ($version.Major -ge 5) {
        return @{ Success = $true; Message = "Version $version" }
    }
    else {
        return @{ Success = $false; Message = "PowerShell 5.1+ required. Current: $version" }
    }
}

# Test 5: Source files exist
Test-Step "Source files exist" {
    $requiredFiles = @(
        "src/PeopleHr/Get-PeopleHrHolidays.ps1",
        "src/PeopleHr/Get-PeopleHrOtherEvents.ps1",
        "src/Graph/Connect-Graph.ps1",
        "src/Graph/Get-UserCalendarEvents.ps1",
        "src/Graph/Upsert-CalendarEvent.ps1",
        "src/Graph/Delete-CalendarEvent.ps1",
        "src/Graph/Find-MatchingEvent.ps1",
        "src/Processing/Normalize-PeopleHrHoliday.ps1",
        "src/Processing/Normalize-PeopleHrOtherEvent.ps1",
        "src/Processing/Build-EventObject.ps1",
        "src/Processing/Sync-User.ps1"
    )
    
    $missingFiles = @()
    $scriptRoot = Split-Path -Parent $ConfigPath
    
    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $scriptRoot $file
        if (-not (Test-Path $fullPath)) {
            $missingFiles += $file
        }
    }
    
    if ($missingFiles.Count -eq 0) {
        return @{ Success = $true; Message = "All $($requiredFiles.Count) source files found" }
    }
    else {
        return @{ Success = $false; Message = "Missing files: $($missingFiles -join ', ')" }
    }
}

# Test 6: Microsoft Graph authentication
Test-Step "Microsoft Graph authentication" {
    try {
        $Body = @{
            grant_type    = "client_credentials"
            scope         = "https://graph.microsoft.com/.default"
            client_id     = $config.ClientId
            client_secret = $config.ClientSecret
        }
        
        $TokenResponse = Invoke-RestMethod `
            -Method Post `
            -Uri "https://login.microsoftonline.com/$($config.TenantId)/oauth2/v2.0/token" `
            -Body $Body `
            -ContentType "application/x-www-form-urlencoded" `
            -ErrorAction Stop
        
        $script:graphToken = $TokenResponse.access_token
        
        return @{ Success = $true; Message = "Authentication successful" }
    }
    catch {
        return @{ Success = $false; Message = "Authentication failed: $($_.Exception.Message)" }
    }
}

# Test 7: Graph API permissions
Test-Step "Microsoft Graph API permissions" {
    if (-not $script:graphToken) {
        return @{ Success = $false; Message = "No access token available (previous test failed)" }
    }
    
    try {
        $headers = @{ Authorization = "Bearer $($script:graphToken)" }
        
        # Try to access users endpoint
        $testUri = "https://graph.microsoft.com/v1.0/users?`$top=1"
        $response = Invoke-RestMethod -Method Get -Uri $testUri -Headers $headers -ErrorAction Stop
        
        return @{ Success = $true; Message = "User.Read.All permission verified" }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 403) {
            return @{ Success = $false; Message = "Permission denied. Ensure User.Read.All is granted with admin consent" }
        }
        else {
            return @{ Success = $false; Message = "API test failed: $($_.Exception.Message)" }
        }
    }
}

# Test 8: PeopleHR API connectivity
Test-Step "PeopleHR API connectivity" {
    try {
        $uri = "https://api.peoplehr.net/Query"
        $body = @{
            APIKey    = $config.PeopleHrApiKey
            Action    = "RunQuery"
            QueryName = "Holiday : Outlook Feed (DO NOT REMOVE)"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $uri `
            -Body $body `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        if ($response.isError -eq $true) {
            return @{ Success = $false; Message = "PeopleHR API error: $($response.Message)" }
        }
        
        return @{ Success = $true; Message = "API accessible, found $($response.Result.Count) holiday records" }
    }
    catch {
        return @{ Success = $false; Message = "Failed to connect: $($_.Exception.Message)" }
    }
}

# Test 9: PeopleHR Other Events query
Test-Step "PeopleHR Other Events query" {
    try {
        $uri = "https://api.peoplehr.net/Query"
        $body = @{
            APIKey    = $config.PeopleHrApiKey
            Action    = "RunQuery"
            QueryName = "Other Events : Outlook Feed (DO NOT REMOVE)"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $uri `
            -Body $body `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        if ($response.isError -eq $true) {
            return @{ Success = $false; Message = "PeopleHR API error: $($response.Message)" }
        }
        
        return @{ Success = $true; Message = "API accessible, found $($response.Result.Count) other event records" }
    }
    catch {
        return @{ Success = $false; Message = "Failed to connect: $($_.Exception.Message)" }
    }
}

# Test 10: Log directory
Test-Step "Log directory" {
    $logDir = $config.LogDirectory
    
    if (-not $logDir) {
        $logDir = "./logs"
    }
    
    if (Test-Path $logDir) {
        return @{ Success = $true; Message = "Log directory exists: $logDir" }
    }
    else {
        try {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            return @{ Success = $true; Message = "Log directory created: $logDir" }
        }
        catch {
            return @{ Success = $false; Message = "Cannot create log directory: $_" }
        }
    }
}

# Summary
Write-Host "======================================================================"
Write-Host "  Validation Summary"
Write-Host "======================================================================"
Write-Host "  Total Tests:    $($testResults.Passed + $testResults.Failed)"
Write-Host "  Passed:         $($testResults.Passed)" -ForegroundColor Green
Write-Host "  Failed:         $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -gt 0) { "Red" } else { "Green" })
Write-Host "======================================================================"
Write-Host ""

if ($testResults.Failed -eq 0) {
    Write-Host "✓ All tests passed! Ready to run sync." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Test with WhatIf mode:  .\run.ps1 -WhatIf"
    Write-Host "  2. Run actual sync:        .\run.ps1"
    Write-Host ""
    exit 0
}
else {
    Write-Host "✗ Some tests failed. Please fix the issues above before running sync." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common fixes:"
    Write-Host "  - Update settings.json with real credentials"
    Write-Host "  - Verify Azure AD app permissions and admin consent"
    Write-Host "  - Check PeopleHR query names match exactly"
    Write-Host ""
    exit 1
}
