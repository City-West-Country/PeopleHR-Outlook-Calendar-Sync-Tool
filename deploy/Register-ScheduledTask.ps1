#requires -Version 5.1
<#
.SYNOPSIS
    Registers a Windows Scheduled Task that runs the PeopleHR -> Outlook sync daily.

.DESCRIPTION
    Creates (or replaces) a daily task that invokes run.ps1 with the repository as the
    working directory. Provide -RunAsUser to run under a service account; you will be
    prompted for its password securely.

.EXAMPLE
    ./deploy/Register-ScheduledTask.ps1 -Time 06:30

.EXAMPLE
    ./deploy/Register-ScheduledTask.ps1 -Time 06:30 -RunAsUser 'CONTOSO\svc-peoplehr'
#>
[CmdletBinding()]
param(
    [string]$TaskName = 'PeopleHR Outlook Sync',
    [datetime]$Time = '06:30',
    [string]$RunAsUser,
    [switch]$RunWhatIf
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runScript = Join-Path $repoRoot 'run.ps1'
if (-not (Test-Path $runScript)) { throw "run.ps1 not found at $runScript" }

# Prefer PowerShell 7 if present, else Windows PowerShell.
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }

$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$runScript`""
if ($RunWhatIf) { $arguments += ' -WhatIf' }

$action    = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments -WorkingDirectory $repoRoot
$trigger   = New-ScheduledTaskTrigger -Daily -At $Time
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 2)

if ($RunAsUser) {
    $cred = Get-Credential -UserName $RunAsUser -Message "Password for scheduled task account $RunAsUser"
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
        -User $cred.UserName -Password $cred.GetNetworkCredential().Password -Force | Out-Null
}
else {
    # Run under SYSTEM if no account supplied. NOTE: SYSTEM cannot read user/DPAPI env
    # vars, so ensure secrets are in settings.json or machine-level environment variables.
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
        -Principal $principal -Force | Out-Null
}

Write-Host "Registered scheduled task '$TaskName' to run daily at $($Time.ToString('HH:mm'))." -ForegroundColor Green
Write-Host "Test it now with: Start-ScheduledTask -TaskName '$TaskName'"
