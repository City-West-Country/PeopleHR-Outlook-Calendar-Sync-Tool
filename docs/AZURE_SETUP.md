# Azure AD App Registration Setup Guide

This guide walks through creating and configuring the Azure AD app registration required for the PeopleHR-Outlook Calendar Sync Tool.

## Prerequisites

- Global Administrator or Application Administrator role in Azure AD
- Access to Azure Portal (https://portal.azure.com)

## Step 1: Create App Registration

1. Navigate to **Azure Active Directory** → **App registrations**
2. Click **New registration**
3. Fill in the details:
   - **Name**: `PeopleHR Calendar Sync`
   - **Supported account types**: `Accounts in this organizational directory only`
   - **Redirect URI**: Leave blank (not needed for client credentials flow)
4. Click **Register**

## Step 2: Note Application IDs

After creation, note down:
- **Application (client) ID** - You'll need this for `ClientId` in settings.json
- **Directory (tenant) ID** - You'll need this for `TenantId` in settings.json

## Step 3: Create Client Secret

1. In your app registration, go to **Certificates & secrets**
2. Click **New client secret**
3. Add a description: `PeopleHR Sync Secret`
4. Choose expiration period (recommended: 12-24 months)
5. Click **Add**
6. **IMPORTANT**: Copy the secret **Value** immediately - it won't be shown again
   - This is your `ClientSecret` for settings.json

## Step 4: Add API Permissions

1. Go to **API permissions**
2. Click **Add a permission**
3. Select **Microsoft Graph**
4. Select **Application permissions** (not Delegated)
5. Add the following permissions:
   - `Calendars.ReadWrite`
   - `User.Read.All`
6. Click **Add permissions**

## Step 5: Grant Admin Consent

1. Still in **API permissions**
2. Click **Grant admin consent for [Your Organization]**
3. Click **Yes** to confirm
4. Verify both permissions show green checkmarks in the "Status" column

## Step 6: Verify Configuration

Your app should now have:

### Overview
- Application (client) ID: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
- Directory (tenant) ID: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

### Certificates & secrets
- A client secret with a value (copy this!)

### API permissions
| Permission | Type | Admin Consent |
|------------|------|---------------|
| Calendars.ReadWrite | Application | ✓ Granted |
| User.Read.All | Application | ✓ Granted |

## Step 7: Update settings.json

Create your `settings.json` from the template:

```powershell
Copy-Item settings.json.template settings.json
```

Edit and add your values:

```json
{
  "TenantId": "YOUR-TENANT-ID-HERE",
  "ClientId": "YOUR-CLIENT-ID-HERE",
  "ClientSecret": "YOUR-CLIENT-SECRET-HERE",
  "PeopleHrApiKey": "your-peoplehr-api-key",
  "SyncDaysPast": 30,
  "SyncDaysFuture": 365,
  "LogDirectory": "./logs",
  "SkipUsers": []
}
```

## Security Best Practices

### Secret Rotation
- Set a reminder to rotate the client secret before expiration
- Create a new secret before the old one expires
- Update settings.json with the new secret
- Test thoroughly before deleting the old secret

### Least Privilege
The permissions granted are:
- **Calendars.ReadWrite**: Required to read and write calendar events
- **User.Read.All**: Required to query user mailboxes

These are the minimum permissions needed. Do not grant additional permissions.

### Access Control
- Restrict who can access the server/system where settings.json is stored
- Use file system permissions to limit access
- Consider using Azure Key Vault for production deployments

### Monitoring
- Review Azure AD sign-in logs periodically
- Monitor for unusual access patterns
- Set up alerts for failed authentication attempts

## Troubleshooting

### Error: "Insufficient privileges to complete the operation"
**Cause**: Admin consent not granted

**Solution**: 
1. Go to API permissions
2. Click "Grant admin consent for [Your Organization]"
3. Wait 5-10 minutes for changes to propagate

### Error: "AADSTS7000215: Invalid client secret"
**Cause**: Client secret expired or incorrect

**Solution**:
1. Go to Certificates & secrets
2. Create a new client secret
3. Update settings.json with the new value

### Error: "AADSTS700016: Application not found"
**Cause**: Client ID is incorrect

**Solution**:
1. Verify Client ID in Azure AD app registration
2. Update settings.json with correct Client ID

## Azure CLI Alternative

You can also create the app registration using Azure CLI:

```bash
# Login
az login

# Create app registration
az ad app create --display-name "PeopleHR Calendar Sync"

# Get the app ID (client ID)
APP_ID=$(az ad app list --display-name "PeopleHR Calendar Sync" --query [0].appId -o tsv)

# Create service principal
az ad sp create --id $APP_ID

# Get object ID
OBJECT_ID=$(az ad sp list --display-name "PeopleHR Calendar Sync" --query [0].id -o tsv)

# Add API permissions
az ad app permission add --id $APP_ID --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 798ee544-9d2d-430c-a058-570e29e34338=Role  # Calendars.ReadWrite

az ad app permission add --id $APP_ID --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions df021288-bdef-4463-88db-98f22de89214=Role  # User.Read.All

# Grant admin consent
az ad app permission admin-consent --id $APP_ID

# Create client secret
az ad app credential reset --id $APP_ID --display-name "PeopleHR Sync Secret"
```

## Next Steps

Once your app registration is complete:

1. ✅ Configure PeopleHR API queries
2. ✅ Test authentication: `.\run.ps1 -WhatIf`
3. ✅ Run first sync with a test user
4. ✅ Set up scheduled task for automatic syncing

---

**Last Updated**: January 2026
