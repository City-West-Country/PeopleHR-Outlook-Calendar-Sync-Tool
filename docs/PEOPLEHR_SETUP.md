# PeopleHR API Setup Guide

This guide explains how to configure the PeopleHR queries required for the sync tool.

## Prerequisites

- PeopleHR Administrator access
- API key with query execution permissions

## Required Queries

The sync tool requires two specific queries to be configured in PeopleHR:

1. **Holiday : Outlook Feed (DO NOT REMOVE)**
2. **Other Events : Outlook Feed (DO NOT REMOVE)**

⚠️ **IMPORTANT**: The query names must match exactly, including spacing and case.

## Query 1: Holiday Feed

### Purpose
Retrieves all holiday/leave records for syncing to Outlook calendars.

### Required Fields

The query must return the following fields:

| Field Name | Description | Example |
|------------|-------------|---------|
| FirstName | Employee first name | John |
| LastName | Employee last name | Smith |
| WorkEmail | Employee work email | john.smith@example.com |
| StartDate | Holiday start date | 2026-03-15 |
| EndDate | Holiday end date | 2026-03-17 |
| Duration | Duration in days | 2.5 |
| Comments | Holiday comments/notes | Family vacation |
| Approver | Approver name | Jane Manager |
| Status | Approval status | Approved |
| StartTime | (Optional) Start time | 09:00 |
| EndTime | (Optional) End time | 17:00 |

### Sample Query Configuration

In PeopleHR:
1. Go to **Reports** → **Queries**
2. Create new query or edit existing
3. Name: `Holiday : Outlook Feed (DO NOT REMOVE)`
4. Add the fields listed above
5. Add filter: `Status = Approved` (optional but recommended)
6. Save query

### Example Data Output

```csv
FirstName,LastName,WorkEmail,StartDate,EndDate,Duration,Comments,Approver,Status
John,Smith,john.smith@example.com,2026-03-15,2026-03-17,2.5,Family vacation,Jane Manager,Approved
Alice,Jones,alice.jones@example.com,2026-04-10,2026-04-10,1.0,,Bob Supervisor,Approved
```

## Query 2: Other Events Feed

### Purpose
Retrieves non-holiday events (training, conferences, sick leave, etc.) for syncing to Outlook.

### Required Fields

| Field Name | Description | Example |
|------------|-------------|---------|
| FirstName | Employee first name | John |
| LastName | Employee last name | Smith |
| WorkEmail | Employee work email | john.smith@example.com |
| EventType | Type of event | Training |
| StartDate | Event start date | 2026-05-20 |
| EndDate | Event end date | 2026-05-21 |
| Duration | Duration in days | 2.0 |
| Comments | Event comments/notes | Leadership workshop |
| Approver | Approver name | Jane Manager |
| AddedBy | Who added the event | HR Admin |
| Status | Status | Confirmed |
| StartTime | (Optional) Start time | 09:00 |
| EndTime | (Optional) End time | 17:00 |

### Sample Query Configuration

In PeopleHR:
1. Go to **Reports** → **Queries**
2. Create new query or edit existing
3. Name: `Other Events : Outlook Feed (DO NOT REMOVE)`
4. Add the fields listed above
5. Add filter: `Status IN (Confirmed, Approved)` (optional)
6. Save query

### Example Data Output

```csv
FirstName,LastName,WorkEmail,EventType,StartDate,EndDate,Duration,Comments,Approver,AddedBy,Status,StartTime,EndTime
John,Smith,john.smith@example.com,Training,2026-05-20,2026-05-21,2.0,Leadership workshop,Jane Manager,HR Admin,Confirmed,09:00,17:00
Alice,Jones,alice.jones@example.com,Conference,2026-06-15,2026-06-17,3.0,Tech Summit,Bob Supervisor,Alice Jones,Approved,,,
```

## Getting Your API Key

### Method 1: PeopleHR Portal

1. Log in to PeopleHR as administrator
2. Go to **Settings** → **API**
3. View or generate API key
4. Copy the key for use in settings.json

### Method 2: Contact PeopleHR Support

If you don't see API settings:
1. Contact PeopleHR support
2. Request API access and key generation
3. Specify you need query execution permissions

## Testing the Queries

### Test in PeopleHR

Before using with the sync tool:

1. In PeopleHR, navigate to **Reports** → **Queries**
2. Find each query and click **Run**
3. Verify:
   - Data is returned
   - All required fields are present
   - Email addresses are correct
   - Dates are in correct format

### Test with PowerShell

You can test the API connection manually:

```powershell
$apiKey = "your-api-key"
$queryName = "Holiday : Outlook Feed (DO NOT REMOVE)"

$body = @{
    APIKey    = $apiKey
    Action    = "RunQuery"
    QueryName = $queryName
} | ConvertTo-Json

$response = Invoke-RestMethod `
    -Method Post `
    -Uri "https://api.peoplehr.net/Query" `
    -Body $body `
    -ContentType "application/json"

# Check for errors
if ($response.isError) {
    Write-Host "Error: $($response.Message)" -ForegroundColor Red
} else {
    Write-Host "Success! Found $($response.Result.Count) records" -ForegroundColor Green
    $response.Result | Select-Object -First 5 | Format-Table
}
```

## Common Issues

### Error: "Query not found"

**Cause**: Query name doesn't match exactly

**Solution**: 
- Verify query name in PeopleHR
- Check for extra spaces
- Ensure case matches exactly

### Error: "Invalid API Key"

**Cause**: API key is incorrect or expired

**Solution**:
- Regenerate API key in PeopleHR
- Update settings.json

### Missing Fields

**Cause**: Query doesn't include all required fields

**Solution**:
- Edit query in PeopleHR
- Add missing fields
- Save and test again

### No Data Returned

**Cause**: No records match query criteria

**Solution**:
- Check query filters
- Verify date ranges
- Ensure employees have approved holidays/events

## Data Quality Considerations

### Email Addresses
- Must be valid work email addresses
- Must match Azure AD user principal names
- No duplicates

### Dates
- Use consistent date format (YYYY-MM-DD recommended)
- End date must be >= start date
- Dates should be within sync window

### Status Values
- Use consistent status values (Approved, Confirmed, etc.)
- Consider filtering to only approved items

### Event Types
- Use consistent naming for event types
- Examples: Training, Conference, Sick Leave, Parental Leave

## Field Mapping Reference

### How Fields Are Used

| PeopleHR Field | Used For | Notes |
|----------------|----------|-------|
| WorkEmail | User identification | Must match Azure AD UPN |
| StartDate | Event start | Used in UID generation |
| EndDate | Event end | Used in UID generation |
| EventType | Event categorization | Used in UID, subject line |
| Duration | Display in event body | Informational only |
| Comments | Event body content | Optional but helpful |
| Approver | Event body metadata | Tracks approval chain |
| Status | Filtering (optional) | Can filter by status |
| StartTime | Timed events | Makes event non-all-day |
| EndTime | Timed events | Makes event non-all-day |

## Update settings.json

Once queries are configured and tested:

```json
{
  "PeopleHrApiKey": "your-actual-api-key-here"
}
```

## Next Steps

1. ✅ Verify both queries exist in PeopleHR
2. ✅ Test queries return expected data
3. ✅ Update settings.json with API key
4. ✅ Run sync tool in WhatIf mode: `.\run.ps1 -WhatIf`
5. ✅ Verify log output
6. ✅ Run actual sync

---

**Last Updated**: January 2026
