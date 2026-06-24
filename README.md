# PeopleHR → Outlook Calendar Sync Tool

A PowerShell tool that syncs **Holidays** and **Other Events** from [PeopleHR](https://www.peoplehr.com/) into each employee's Outlook calendar via the **Microsoft Graph API**, using app-only (client credentials) authentication.

It replaces the legacy *Holiday Sync Service (HSS)*, whose fixed ~60-day window cannot be changed. This tool syncs a **configurable window** (default: 30 days back, 365 days forward) and reliably **creates, updates, and deletes** events as PeopleHR changes.

---

## Why this is safe to run against live mailboxes

Every event the tool writes is tagged two ways:

1. The Outlook **category** `PeopleHR Sync`, and
2. A custom **extended property** holding the canonical PeopleHR UID.

The tool will **only ever update or delete events that carry both markers**. Personal calendar entries are never read into the reconcile set and are never deleted. Use `-WhatIf` first to preview exactly what would change.

---

## How it works

```
settings.json ─▶ Graph auth (client secret)
                      │
   PeopleHR Holiday feed ─┐
   PeopleHR Other  feed ──┴─▶ normalise to unified events ─▶ group by mailbox
                                                                  │
                            for each mailbox, within the window:  ▼
                       fetch managed events ─▶ compare by UID + content hash
                                              ├─ create   (UID not present)
                                              ├─ update   (hash changed)
                                              ├─ delete   (managed orphan)
                                              └─ skip     (unchanged)
```

### Event identity & change detection
Each event gets a deterministic UID:

```
<email>|<start ISO>|<end ISO>|<eventType>
```

stored in an extended property (and mirrored as `PeopleHR-UID:<uid>` in the event body for visibility). A SHA-256 content hash of the rendered fields is also stored; when it differs from the desired hash, the event is **updated** in place.

> **Note:** because the start/end are part of the UID, *changing an event's dates* in PeopleHR produces a new UID — i.e. the old event is deleted and a new one created, rather than moved. Status/comment/approver changes (which don't affect the UID) are applied as in-place updates.

---

## Prerequisites

- **PowerShell 5.1+** (Windows PowerShell or PowerShell 7+).
- A **PeopleHR API key** with access to the two saved queries.
- Two saved PeopleHR queries returning the fields below:
  - `Holiday : Outlook Feed (DO NOT REMOVE)`
  - `Other Events : Outlook Feed (DO NOT REMOVE)`
- An **Entra (Azure AD) app registration** with a client secret and these **Application** Graph permissions (admin-consented):
  - `Calendars.ReadWrite`
  - `User.Read.All`

### Expected PeopleHR query columns
Field name matching is tolerant of spacing and common aliases (e.g. `Work Email` / `WorkEmail`):

| Purpose      | Accepted column names                                  |
|--------------|--------------------------------------------------------|
| Email        | `Work Email`, `WorkEmail`, `Email`                     |
| Name         | `First Name` / `Last Name` (`Surname`)                 |
| Start / End  | `StartDate` / `EndDate` (`From`/`To`)                  |
| Times        | `StartTime` / `EndTime` (optional → timed event)       |
| Type         | `HolidayType` / `EventType` / `Type`                   |
| Metadata     | `Status`, `Approver`/`AddedBy`, `Comments`, `Duration` |

Dates are parsed as UK `dd/MM/yyyy` first, then ISO and other common formats.

---

## Setup

### Recommended: run the setup wizard

```powershell
git clone <repo>
cd PeopleHR-Outlook-Calendar-Sync-Tool
.\Setup.ps1
```

`Setup.ps1` walks you through everything:

1. Collects your Entra (Graph) and PeopleHR settings.
2. **Stores the Graph client secret and PeopleHR API key in Windows Credential Manager** — they never touch `settings.json` or git.
3. Writes the non-secret values to `settings.json`.
4. Optionally tests the Graph + PeopleHR connections.
5. Optionally registers the daily Scheduled Task.

Re-run it any time to change settings or **rotate secrets** — your previous answers are offered as defaults.

> **Credential Manager scoping:** stored secrets are readable only by the Windows account that saved them. Run `Setup.ps1` as the **same account the Scheduled Task will run under** (the wizard defaults the task to the current user for this reason). To use a dedicated service account, log on as (or `runas`) that account and run `Setup.ps1` there.

Then verify with a dry run (reads everything, writes nothing):

```powershell
.\run.ps1 -WhatIf -VerboseLogging
.\run.ps1                      # real run
```

### Manual alternative

If you'd rather not use the wizard, copy `settings.example.json` to `settings.json`, fill in the non-secret values, and provide secrets by either:

- **Credential Manager** (matches the wizard):
  ```powershell
  Import-Module .\src\PeopleHrSync.psd1
  Set-SyncCredential -For ClientSecret -Secret (Read-Host 'Client secret' -AsSecureString)
  Set-SyncCredential -For ApiKey       -Secret (Read-Host 'PeopleHR API key' -AsSecureString)
  ```
- **or environment variables** (override Credential Manager): `GRAPH_CLIENT_SECRET`, `PEOPLEHR_API_KEY`.

`settings.json` is `.gitignore`d so secrets are never committed.

### Where secrets are resolved from

For each secret, the tool uses the first source that has a value:

1. Environment variable (`GRAPH_CLIENT_SECRET` / `PEOPLEHR_API_KEY`) — highest, handy for ad-hoc overrides.
2. **Windows Credential Manager** (`PeopleHrSync:GraphClientSecret`, `PeopleHrSync:PeopleHrApiKey`).
3. Plaintext value in `settings.json` — discouraged.

### Configuration (`settings.json`)

| Key                    | Default                                  | Notes |
|------------------------|------------------------------------------|-------|
| `TenantId`             | —                                        | Entra tenant GUID |
| `ClientId`             | —                                        | App registration (client) ID |
| `ClientSecret`         | *(blank — use Credential Manager)*       | App client secret. Prefer Credential Manager / `GRAPH_CLIENT_SECRET`; leave blank in the file. |
| `PeopleHrApiKey`       | *(blank — use Credential Manager)*       | PeopleHR API key. Prefer Credential Manager / `PEOPLEHR_API_KEY`; leave blank in the file. |
| `PeopleHrBaseUri`      | `https://api.peoplehr.net/Query`         | Query endpoint |
| `PeopleHrAction`       | `GetQueryResultByQueryName`              | API action |
| `HolidayQueryName`     | `Holiday : Outlook Feed (DO NOT REMOVE)` | Saved query name |
| `OtherEventsQueryName` | `Other Events : Outlook Feed (DO NOT REMOVE)` | Saved query name |
| `SyncDaysPast`         | `30`                                     | Window start = today − N |
| `SyncDaysFuture`       | `365`                                    | Window end = today + N |
| `TimeZone`             | `GMT Standard Time`                      | Windows time-zone id for events |
| `LogDirectory`         | `./logs`                                 | Resolved relative to repo root |
| `SkipUsers`            | `[]`                                     | Emails to exclude (case-insensitive) |
| `WhatIf`               | `false`                                  | Mock mode (no Graph writes) |
| `VerboseLogging`       | `false`                                  | Per-event DEBUG lines |

Secrets resolve in the order described above; CLI switches (`-WhatIf`, `-VerboseLogging`) override the file.

---

## Repository layout

```
src/
  PeopleHrSync.psd1 / .psm1     Module manifest + loader (dot-sources everything below)
  Common/                       Config, logging, constants, hashing, Credential Manager store
  PeopleHr/                     Query API + holiday/other-event fetchers
  Graph/                        Auth, throttle/pagination-aware request wrapper, CRUD
  Processing/                   Normalisers, UID, payload builder, per-user reconcile, orchestrator
Setup.ps1                       Interactive setup wizard (secrets -> Credential Manager)
run.ps1                         Entry point
settings.example.json           Config template (copy to settings.json)
tests/                          Pester v5 tests
deploy/                         Register-ScheduledTask.ps1 (Windows Scheduled Task helper)
logs/                           Daily log files (sync-YYYY-MM-DD.log)
```

---

## Running on a schedule (Windows Server)

This runs as a plain PowerShell **Scheduled Task** — no services, containers, or cloud
infrastructure required. The helper script registers a daily task that invokes `run.ps1`
with the repo as its working directory, and the task exits non-zero on errors so failures
show up in Task Scheduler history.

### 1. Decide how the task authenticates

A scheduled task does **not** see environment variables you set in your interactive
session. Pick one of:

- **Machine-level environment variables** (visible to every account incl. the task account):
  ```powershell
  [Environment]::SetEnvironmentVariable('GRAPH_CLIENT_SECRET', '<secret>', 'Machine')
  [Environment]::SetEnvironmentVariable('PEOPLEHR_API_KEY',    '<key>',    'Machine')
  ```
- **Or** put the secrets directly in `settings.json` and lock it down with NTFS
  permissions (only the task's run-as account + admins):
  ```powershell
  icacls .\settings.json /inheritance:r /grant:r "CONTOSO\svc-peoplehr:(R)" "BUILTIN\Administrators:(F)"
  ```

### 2. Register the task

Run from the repo root in an **elevated** PowerShell:

```powershell
# Run under a dedicated service account (recommended) — prompts for its password:
./deploy/Register-ScheduledTask.ps1 -Time 06:30 -RunAsUser 'CONTOSO\svc-peoplehr'

# Or run under the local SYSTEM account (use machine-level env vars or settings.json for secrets):
./deploy/Register-ScheduledTask.ps1 -Time 06:30
```

Options: `-TaskName`, `-Time`, `-RunAsUser`, `-RunWhatIf` (register a dry-run task for testing).
The script auto-detects PowerShell 7 (`pwsh`) and falls back to Windows PowerShell, and
launches with `-ExecutionPolicy Bypass` so no machine-wide policy change is needed.

### 3. Test and monitor

```powershell
Start-ScheduledTask -TaskName 'PeopleHR Outlook Sync'        # run it now
Get-ScheduledTaskInfo -TaskName 'PeopleHR Outlook Sync'      # last run time + result (0 = success)
Get-Content .\logs\sync-*.log -Tail 40                       # see what it did
```

> The service account only needs **log-on-as-a-batch-job** rights and read access to the
> repo + write access to `logs/`. All Graph access is via the app registration, not the
> account's own mailbox permissions.

---

## Testing

Unit tests (Pester **v5**) cover UID generation, date parsing, field extraction, payload building (all-day exclusive-end handling, categories, extended properties) and normalisation:

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser   # if needed
Invoke-Pester ./tests
```

The reconcile engine (create/update/delete/unchanged + orphan-only deletion) is exercised by stubbing the Graph layer in module scope.

Exit codes from `run.ps1`: `0` success, `1` completed with per-mailbox errors, `2` fatal (config/auth).

---

## Logging

Console + a daily file `logs/sync-YYYY-MM-DD.log`:

```
[2026-06-24 06:30:02] [INFO   ] Fetching PeopleHR holidays (query: 'Holiday : Outlook Feed (DO NOT REMOVE)')...
[2026-06-24 06:30:10] [SUCCESS] Loaded 265 holiday record(s).
[2026-06-24 06:30:11] [INFO   ]   Syncing mailbox: alice@example.com
[2026-06-24 06:30:11] [SUCCESS]     Created: Annual Leave 2026-07-01 -> 2026-07-03
[2026-06-24 06:30:12] [SUCCESS]     Updated: Sick 2026-07-10
[2026-06-24 06:30:12] [SUCCESS]     Deleted orphaned event: Holiday - PeopleHR Sync [a3f8182d...]
[2026-06-24 06:30:40] [SUCCESS] SUMMARY: 38 mailbox(es) | created 12, updated 4, deleted 3, unchanged 246, errors 0
```

A complete sample is in `logs/sample-sync.log`.

---

## Security notes

- Secrets are stored in **Windows Credential Manager** (per-user, `CRED_PERSIST_LOCAL_MACHINE`) by the setup wizard — not in `settings.json`. `settings.json` is also git-ignored. If you ever put a secret in the file directly, restrict it with NTFS permissions (see the scheduling section).
- Credential Manager entries are readable only by the account that stored them, so run `Setup.ps1` as the same account the Scheduled Task uses.
- The app uses **application** permissions, so it can read/write **any** mailbox in the tenant. Scope it down with an [application access policy](https://learn.microsoft.com/graph/auth-limit-mailbox-access) to only the mailboxes you sync.
- Rotate the client secret regularly — just re-run `Setup.ps1` (or `Set-SyncCredential -For ClientSecret ...`) to update the stored value.
