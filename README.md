# 🚀 PeopleHR → Outlook Calendar Sync Tool

A PowerShell-based synchronization tool that syncs holidays and events from PeopleHR to Outlook calendars via Microsoft Graph API.

## 📋 Overview

This tool replaces the existing PeopleHR Holiday Sync Service (HSS) with a modern, fully customizable solution that:

- ✅ Syncs **Holidays** and **Other Events** from PeopleHR
- ✅ Writes events to each user's Outlook calendar via **Microsoft Graph**
- ✅ Syncs **365+ days** into the future (configurable)
- ✅ Authenticates using **Azure Entra Enterprise App** (Client Credentials + Secret)
- ✅ Creates, updates, and deletes events automatically
- ✅ Uses deterministic UIDs for reliable event matching
- ✅ Comprehensive logging for audit and debugging
- ✅ Can run as a Scheduled Task or Windows Service

## 🏗️ Architecture

```
/src
  /PeopleHr             - PeopleHR API integration
  /Graph                - Microsoft Graph API integration
  /Processing           - Data normalization and sync logic
/logs                   - Sync logs (auto-created)
run.ps1                 - Main execution script
settings.json.template  - Configuration template
```

## 🔐 Prerequisites

### 1. Azure AD App Registration

Create an Enterprise App in Azure AD with the following permissions:

- **Calendars.ReadWrite** (Application permission)
- **Users.Read.All** (Application permission)

You'll need:
- Tenant ID
- Client ID
- Client Secret

### 2. PeopleHR API Access

Ensure you have:
- PeopleHR API key
- Two queries configured:
  - `Holiday : Outlook Feed (DO NOT REMOVE)`
  - `Other Events : Outlook Feed (DO NOT REMOVE)`

### 3. PowerShell 5.1+

This tool requires PowerShell 5.1 or later.

```powershell
$PSVersionTable.PSVersion
```

## 🚀 Quick Start

### 1. Clone the Repository

```powershell
git clone https://github.com/City-West-Country/PeopleHR-Outlook-Calendar-Sync-Tool.git
cd PeopleHR-Outlook-Calendar-Sync-Tool
```

### 2. Configure Settings

Copy the template and fill in your credentials:

```powershell
Copy-Item settings.json.template settings.json
notepad settings.json
```

Update the following fields:
- `TenantId` - Your Azure AD tenant ID
- `ClientId` - Your app registration client ID
- `ClientSecret` - Your app registration client secret
- `PeopleHrApiKey` - Your PeopleHR API key

### 3. Run the Sync

```powershell
.\run.ps1
```

## ⚙️ Configuration

### settings.json

| Field | Description | Default |
|-------|-------------|---------|
| `TenantId` | Azure AD tenant ID | Required |
| `ClientId` | App registration client ID | Required |
| `ClientSecret` | App registration client secret | Required |
| `PeopleHrApiKey` | PeopleHR API key | Required |
| `SyncDaysPast` | Days to sync into the past | 30 |
| `SyncDaysFuture` | Days to sync into the future | 365 |
| `LogDirectory` | Directory for log files | ./logs |
| `SkipUsers` | Array of email addresses to skip | [] |

### Example Configuration

```json
{
  "TenantId": "12345678-1234-1234-1234-123456789012",
  "ClientId": "87654321-4321-4321-4321-210987654321",
  "ClientSecret": "your-secret-value",
  "PeopleHrApiKey": "your-api-key",
  "SyncDaysPast": 30,
  "SyncDaysFuture": 365,
  "LogDirectory": "./logs",
  "SkipUsers": [
    "external.user@example.com",
    "test.user@example.com"
  ]
}
```

## 📊 How It Works

### Data Flow

1. **Authentication** - Connects to Microsoft Graph using client credentials
2. **Fetch Data** - Retrieves holidays and events from PeopleHR API
3. **Normalize** - Converts PeopleHR data into a standard format
4. **Group** - Organizes events by user email
5. **Sync** - For each user:
   - Fetches existing Outlook events
   - Compares with PeopleHR events using UIDs
   - Creates new events
   - Updates modified events
   - Deletes orphaned events
6. **Log** - Records all operations

### Event Matching

Events are matched using a deterministic UID format:

```
<email>|<start ISO>|<end ISO>|<eventType>
```

Example:
```
user@example.com|2026-03-15T00:00:00.0000000|2026-03-16T00:00:00.0000000|Holiday
```

This UID is stored in the event body as:
```
PeopleHR-UID:<uid>
```

### Event Types

#### Holidays
- **Subject**: `Holiday - PeopleHR Sync`
- **All-day**: Yes (unless specific times provided)
- **Body includes**:
  - Comments
  - Requester name
  - Approver
  - Duration
  - Status
  - Unique UID

#### Other Events
- **Subject**: `Other Event - PeopleHR Sync`
- **All-day**: Depends on data (timed if start/end times provided)
- **Body includes**:
  - Event type
  - Comments
  - Requester name
  - Approver/Added by
  - Duration
  - Status
  - Unique UID

## 📖 Usage Examples

### Standard Sync

```powershell
.\run.ps1
```

### Test Run (WhatIf Mode)

Simulate the sync without making changes:

```powershell
.\run.ps1 -WhatIf
```

### Custom Configuration Path

```powershell
.\run.ps1 -ConfigPath "C:\config\production-settings.json"
```

### Scheduled Task

Create a Windows Scheduled Task to run the sync automatically:

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\Path\To\run.ps1"

$trigger = New-ScheduledTaskTrigger -Daily -At "06:00AM"

Register-ScheduledTask -TaskName "PeopleHR Calendar Sync" `
    -Action $action -Trigger $trigger `
    -Description "Syncs PeopleHR events to Outlook calendars"
```

## 📝 Logging

Logs are stored in the directory specified in `LogDirectory` (default: `./logs`).

Log files are named: `sync-yyyyMMdd-HHmmss.log`

### Example Log Output

```
[2026-01-23 10:15:02] Fetching PeopleHR holidays...
[2026-01-23 10:15:10] Loaded 265 holiday records
[2026-01-23 10:15:11] Loaded 48 other event records
[2026-01-23 10:15:12] Normalized 313 total events
[2026-01-23 10:15:13] Processing 87 users...

  [2026-01-23 10:15:14] Syncing mailbox: alice@example.com
    [2026-01-23 10:15:15]   Created event: 2026-03-16T00:00:00 → 2026-03-18T00:00:00
    [2026-01-23 10:15:16]   Updated event: 2026-02-12T00:00:00
    [2026-01-23 10:15:17]   Deleted orphaned event: a3f8182d-...
    [2026-01-23 10:15:18]   Summary: Created=1, Updated=1, Deleted=1, Skipped=3

======================================================================
  Sync Summary
======================================================================
  Users processed:    87
  Events created:     42
  Events updated:     15
  Events deleted:     8
  Events skipped:     248
  Errors:             0
  Duration:           00:05:23
  Completed:          2026-01-23 10:20:35
======================================================================
```

## 🧪 Testing

### Test Mode (WhatIf)

The `-WhatIf` flag runs the tool in mock mode without making any actual changes:

```powershell
.\run.ps1 -WhatIf
```

This will:
- Skip Graph authentication (uses mock token)
- Skip PeopleHR API calls (uses empty data)
- Display what would be synced without making changes

### Test with Single User

To test with a single user, configure `SkipUsers` to exclude all but one user:

```json
{
  "SkipUsers": [
    "all-other@example.com",
    "users-except@example.com",
    "test.user@example.com"
  ]
}
```

## 🔍 Troubleshooting

### Common Issues

#### Authentication Failed

**Error**: `Failed to authenticate to Microsoft Graph`

**Solution**:
- Verify Tenant ID, Client ID, and Client Secret
- Ensure app has required permissions
- Grant admin consent in Azure AD

#### PeopleHR API Error

**Error**: `PeopleHR API Error: ...`

**Solution**:
- Check API key is valid
- Verify query names match exactly:
  - `Holiday : Outlook Feed (DO NOT REMOVE)`
  - `Other Events : Outlook Feed (DO NOT REMOVE)`
- Ensure queries return data in expected format

#### User Not Found

**Error**: `Failed to fetch calendar events for user@example.com`

**Solution**:
- Verify user exists in Azure AD
- Check user has an Exchange Online mailbox
- Ensure app has User.Read.All permission

#### Events Not Appearing

**Check**:
- Events are within the sync window
- User is not in the SkipUsers list
- PeopleHR data includes the user's correct email address
- Check logs for specific errors

## 🔒 Security Considerations

### Protecting Credentials

1. **Never commit settings.json** - It contains secrets
2. **Use Azure Key Vault** (optional) - Store secrets securely
3. **Restrict file permissions** - Limit access to settings.json

```powershell
# Set restrictive permissions on settings.json
$acl = Get-Acl settings.json
$acl.SetAccessRuleProtection($true, $false)
$acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser, "FullControl", "Allow")
$acl.AddAccessRule($rule)
Set-Acl settings.json $acl
```

### Application Permissions

The app uses **Application permissions** (not delegated), which means it can access all user calendars. This is necessary for automated sync but should be carefully controlled.

## 🐳 Docker Support (Optional)

To run in a container:

```dockerfile
FROM mcr.microsoft.com/powershell:latest

WORKDIR /app
COPY . /app

CMD ["pwsh", "-File", "run.ps1"]
```

Build and run:

```bash
docker build -t peoplehr-sync .
docker run -v /path/to/settings.json:/app/settings.json peoplehr-sync
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

See [LICENSE](LICENSE) file for details.

## 🆘 Support

For issues or questions:

1. Check the [Troubleshooting](#-troubleshooting) section
2. Review logs in the `logs/` directory
3. Open an issue on GitHub

## 🗺️ Roadmap

- [ ] Azure Automation Runbook helper
- [ ] Windows Service wrapper
- [ ] Pester unit tests
- [ ] CI/CD with GitHub Actions
- [ ] Enhanced error handling and retry logic
- [ ] Email notifications on sync completion/failure
- [ ] Dashboard for sync statistics

---

**Last Updated**: January 2026  
**Version**: 1.0.0
