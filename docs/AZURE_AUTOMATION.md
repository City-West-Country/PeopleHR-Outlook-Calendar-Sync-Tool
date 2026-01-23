# Azure Automation Deployment Guide

This guide explains how to run the PeopleHR-Outlook Calendar Sync Tool as an Azure Automation Runbook.

## Prerequisites

- Azure subscription
- Azure Automation Account
- PowerShell 7.2 runtime in Azure Automation

## Step 1: Create Azure Automation Account

### Using Azure Portal

1. Navigate to **Azure Portal** → **Create a resource**
2. Search for **Automation**
3. Click **Create**
4. Fill in details:
   - **Subscription**: Your subscription
   - **Resource group**: Create new or use existing
   - **Name**: `peoplehr-sync-automation`
   - **Region**: Select your region
5. Click **Review + Create** → **Create**

### Using Azure CLI

```bash
az automation account create \
  --resource-group peoplehr-sync-rg \
  --name peoplehr-sync-automation \
  --location eastus \
  --sku Basic
```

## Step 2: Configure Runtime Environment

1. In your Automation Account, go to **Runtime Environments**
2. Create new runtime:
   - **Name**: `PowerShell-7.2`
   - **Runtime**: PowerShell 7.2
3. Save

## Step 3: Store Credentials as Variables

Instead of using a settings.json file, use Azure Automation Variables:

### Create Variables

1. Go to **Shared Resources** → **Variables**
2. Create the following encrypted variables:
   - `TenantId` (String)
   - `ClientId` (String)
   - `ClientSecret` (Encrypted String) ⚠️ Mark as encrypted
   - `PeopleHrApiKey` (Encrypted String) ⚠️ Mark as encrypted

3. Create non-encrypted variables:
   - `SyncDaysPast` (Integer) = 30
   - `SyncDaysFuture` (Integer) = 365

### Using Azure CLI

```bash
# Create automation variables
az automation variable create \
  --resource-group peoplehr-sync-rg \
  --automation-account-name peoplehr-sync-automation \
  --name TenantId \
  --value "your-tenant-id"

az automation variable create \
  --resource-group peoplehr-sync-rg \
  --automation-account-name peoplehr-sync-automation \
  --name ClientId \
  --value "your-client-id"

az automation variable create \
  --resource-group peoplehr-sync-rg \
  --automation-account-name peoplehr-sync-automation \
  --name ClientSecret \
  --value "your-client-secret" \
  --encrypted true

az automation variable create \
  --resource-group peoplehr-sync-rg \
  --automation-account-name peoplehr-sync-automation \
  --name PeopleHrApiKey \
  --value "your-api-key" \
  --encrypted true
```

## Step 4: Create Runbook

### Create Main Runbook File

Create `AzureAutomation-Runbook.ps1`:

```powershell
<#
.SYNOPSIS
    Azure Automation Runbook for PeopleHR-Outlook Calendar Sync

.DESCRIPTION
    Runs the PeopleHR sync tool in Azure Automation using stored variables.
#>

# Get variables from Azure Automation
$TenantId = Get-AutomationVariable -Name 'TenantId'
$ClientId = Get-AutomationVariable -Name 'ClientId'
$ClientSecret = Get-AutomationVariable -Name 'ClientSecret'
$PeopleHrApiKey = Get-AutomationVariable -Name 'PeopleHrApiKey'
$SyncDaysPast = Get-AutomationVariable -Name 'SyncDaysPast'
$SyncDaysFuture = Get-AutomationVariable -Name 'SyncDaysFuture'

# Create in-memory config
$config = [PSCustomObject]@{
    TenantId       = $TenantId
    ClientId       = $ClientId
    ClientSecret   = $ClientSecret
    PeopleHrApiKey = $PeopleHrApiKey
    SyncDaysPast   = $SyncDaysPast
    SyncDaysFuture = $SyncDaysFuture
    LogDirectory   = ""  # Not used in Azure Automation
    SkipUsers      = @()
}

Write-Output "Starting PeopleHR-Outlook Calendar Sync..."
Write-Output "Sync window: $($SyncDaysPast) days past to $($SyncDaysFuture) days future"

# Load function definitions
# Note: In Azure Automation, you'd store each function as a separate runbook or module

# Import functions (these would be uploaded as modules in Azure Automation)
# For this example, we'll inline the key logic

function Connect-GraphApi {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret)
    
    $Body = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $ClientId
        client_secret = $ClientSecret
    }
    
    $TokenResponse = Invoke-RestMethod `
        -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body $Body `
        -ContentType "application/x-www-form-urlencoded"
    
    return $TokenResponse.access_token
}

# Authenticate
try {
    $token = Connect-GraphApi `
        -TenantId $config.TenantId `
        -ClientId $config.ClientId `
        -ClientSecret $config.ClientSecret
    
    Write-Output "Successfully authenticated to Microsoft Graph"
}
catch {
    Write-Error "Failed to authenticate: $_"
    throw
}

# Continue with rest of sync logic...
# (In production, you'd load all the other functions from modules)

Write-Output "Sync completed successfully"
```

### Upload to Azure Automation

1. Go to **Process Automation** → **Runbooks**
2. Click **Create a runbook**
3. Fill in details:
   - **Name**: `PeopleHR-Sync`
   - **Runbook type**: PowerShell
   - **Runtime version**: 7.2
4. Click **Create**
5. Paste the runbook code
6. Click **Save**
7. Click **Publish**

### Using Azure CLI

```bash
az automation runbook create \
  --resource-group peoplehr-sync-rg \
  --automation-account-name peoplehr-sync-automation \
  --name PeopleHR-Sync \
  --type PowerShell \
  --runtime-version 7.2

az automation runbook replace-content \
  --resource-group peoplehr-sync-rg \
  --automation-account-name peoplehr-sync-automation \
  --name PeopleHR-Sync \
  --content @AzureAutomation-Runbook.ps1

az automation runbook publish \
  --resource-group peoplehr-sync-rg \
  --automation-account-name peoplehr-sync-automation \
  --name PeopleHR-Sync
```

## Step 5: Create Modules

For better organization, create PowerShell modules:

### Create Module Structure

```
PeopleHRSync/
  PeopleHRSync.psd1
  PeopleHRSync.psm1
  Functions/
    Get-PeopleHrHolidays.ps1
    Connect-GraphApi.ps1
    ... (all other functions)
```

### Upload Module to Azure Automation

1. Zip the module folder
2. Go to **Shared Resources** → **Modules**
3. Click **Add a module**
4. Upload the zip file
5. Wait for import to complete

### Using PowerShell

```powershell
# Create module package
Compress-Archive -Path ./PeopleHRSync -DestinationPath PeopleHRSync.zip

# Upload to Azure Automation
New-AzAutomationModule `
  -ResourceGroupName "peoplehr-sync-rg" `
  -AutomationAccountName "peoplehr-sync-automation" `
  -Name "PeopleHRSync" `
  -ContentLinkUri "https://your-storage-account/PeopleHRSync.zip"
```

## Step 6: Schedule the Runbook

### Create Schedule

1. Go to **Runbooks** → Select your runbook
2. Click **Schedules** → **Add a schedule**
3. Click **Link a schedule to your runbook**
4. Click **Create a new schedule**
5. Configure:
   - **Name**: `Daily-Morning-Sync`
   - **Description**: Run PeopleHR sync every morning
   - **Starts**: Select date/time
   - **Recurrence**: Daily at 6:00 AM
   - **Time zone**: Select your timezone
6. Click **Create**

### Using Azure CLI

```bash
az automation schedule create \
  --resource-group peoplehr-sync-rg \
  --automation-account-name peoplehr-sync-automation \
  --name Daily-Morning-Sync \
  --frequency Day \
  --interval 1 \
  --start-time "2026-01-24T06:00:00+00:00"

az automation job-schedule create \
  --resource-group peoplehr-sync-rg \
  --automation-account-name peoplehr-sync-automation \
  --runbook-name PeopleHR-Sync \
  --schedule-name Daily-Morning-Sync
```

## Step 7: Test the Runbook

### Manual Test

1. Go to your runbook
2. Click **Start**
3. Monitor the **Output** pane for results
4. Check **Errors** if any issues occur

### Using PowerShell

```powershell
Start-AzAutomationRunbook `
  -ResourceGroupName "peoplehr-sync-rg" `
  -AutomationAccountName "peoplehr-sync-automation" `
  -Name "PeopleHR-Sync" `
  -Wait
```

## Monitoring and Logging

### View Job History

1. Go to **Jobs** in your Automation Account
2. Click on a job to view details
3. Check **Output**, **Errors**, and **All Logs**

### Set Up Alerts

Create alerts for failed jobs:

```bash
az monitor metrics alert create \
  --name peoplehr-sync-failed-jobs \
  --resource-group peoplehr-sync-rg \
  --scopes /subscriptions/{sub-id}/resourceGroups/peoplehr-sync-rg/providers/Microsoft.Automation/automationAccounts/peoplehr-sync-automation \
  --condition "avg TotalJob > 0" \
  --window-size 5m \
  --evaluation-frequency 5m \
  --action "/subscriptions/{sub-id}/resourceGroups/peoplehr-sync-rg/providers/Microsoft.Insights/actionGroups/email-alerts"
```

### Send to Log Analytics

Enable diagnostic settings to send logs to Log Analytics:

```bash
az monitor diagnostic-settings create \
  --resource /subscriptions/{sub-id}/resourceGroups/peoplehr-sync-rg/providers/Microsoft.Automation/automationAccounts/peoplehr-sync-automation \
  --name SendToLogAnalytics \
  --workspace /subscriptions/{sub-id}/resourceGroups/peoplehr-sync-rg/providers/Microsoft.OperationalInsights/workspaces/peoplehr-logs \
  --logs '[{"category": "JobLogs", "enabled": true}, {"category": "JobStreams", "enabled": true}]'
```

## Cost Optimization

### Pricing Considerations

- **Job runtime minutes**: Billed per minute
- **Watchers**: Not needed for this scenario
- **Variables**: Free

### Optimization Tips

1. **Optimize sync window**: Don't sync unnecessary historical data
2. **Skip users**: Use SkipUsers list to exclude inactive accounts
3. **Efficient queries**: Ensure PeopleHR queries are optimized
4. **Appropriate frequency**: Daily sync is usually sufficient

## Security Best Practices

### Use Managed Identity (Advanced)

Instead of client secrets, use System-assigned Managed Identity:

1. Enable Managed Identity on Automation Account
2. Grant Calendar permissions to the identity
3. Authenticate using `Connect-AzAccount -Identity`

### Key Vault Integration

Store secrets in Azure Key Vault:

```powershell
# In runbook
$TenantId = Get-AzKeyVaultSecret `
  -VaultName "peoplehr-keyvault" `
  -Name "TenantId" `
  -AsPlainText
```

## Troubleshooting

### Common Issues

**Error: "Get-AutomationVariable: Variable not found"**
- Verify variable name spelling
- Check variable is created in Automation Account

**Error: "Authentication failed"**
- Verify credentials are correct
- Check variables are not expired
- Ensure admin consent is granted

**Job times out**
- Increase job timeout in runbook settings
- Optimize sync to process fewer users per run
- Split into multiple runbooks if needed

---

**Last Updated**: January 2026
