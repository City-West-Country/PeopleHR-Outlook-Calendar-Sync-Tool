#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PeopleHrSync.psd1'
    Import-Module $modulePath -Force
}

Describe 'Get-PeopleHrEventUid' {
    It 'produces a deterministic, lower-cased, pipe-delimited UID' {
        $s = [datetime]'2026-03-16'
        $e = [datetime]'2026-03-18'
        $uid1 = Get-PeopleHrEventUid -Email 'Alice@Example.com' -Start $s -End $e -Type 'Holiday'
        $uid2 = Get-PeopleHrEventUid -Email 'alice@example.com' -Start $s -End $e -Type 'Holiday'
        $uid1 | Should -Be $uid2
        $uid1 | Should -Match '^alice@example\.com\|.+\|.+\|Holiday$'
    }
}

Describe 'ConvertTo-SyncDate' {
    It 'parses UK dd/MM/yyyy dates' {
        (ConvertTo-SyncDate -Value '16/03/2026') | Should -Be ([datetime]'2026-03-16')
    }
    It 'parses ISO dates' {
        (ConvertTo-SyncDate -Value '2026-03-16') | Should -Be ([datetime]'2026-03-16')
    }
    It 'combines date and time' {
        (ConvertTo-SyncDate -Value '16/03/2026' -TimeValue '09:30') | Should -Be ([datetime]'2026-03-16T09:30')
    }
    It 'returns $null for junk' {
        (ConvertTo-SyncDate -Value 'not a date') | Should -BeNullOrEmpty
    }
}

Describe 'Get-PeopleHrFieldValue' {
    It 'reads a scalar column by any candidate name' {
        $row = [pscustomobject]@{ 'Work Email' = 'bob@example.com' }
        Get-PeopleHrFieldValue -Row $row -Names 'WorkEmail', 'Work Email' | Should -Be 'bob@example.com'
    }
    It 'unwraps an object column with a Value property' {
        $row = [pscustomobject]@{ Status = [pscustomobject]@{ Value = 'Approved' } }
        Get-PeopleHrFieldValue -Row $row -Names 'Status' | Should -Be 'Approved'
    }
    It 'returns $null when nothing matches' {
        $row = [pscustomobject]@{ Foo = 'bar' }
        Get-PeopleHrFieldValue -Row $row -Names 'Baz' | Should -BeNullOrEmpty
    }
}

Describe 'Get-StringHash' {
    It 'is stable and 32 chars' {
        $h1 = Get-StringHash -Value 'hello'
        $h2 = Get-StringHash -Value 'hello'
        $h1 | Should -Be $h2
        $h1.Length | Should -Be 32
    }
    It 'differs for different input' {
        (Get-StringHash -Value 'a') | Should -Not -Be (Get-StringHash -Value 'b')
    }
}

Describe 'New-GraphEventPayload (all-day)' {
    BeforeAll {
        $evt = New-SyncEvent -Email 'alice@example.com' -DisplayName 'Alice A' -Category 'Holiday' `
            -Subject 'Holiday - PeopleHR Sync' -EventType 'Annual Leave' `
            -Start ([datetime]'2026-03-16') -End ([datetime]'2026-03-18') -IsAllDay $true `
            -Comments 'Skiing' -Requester 'Alice A' -Approver 'Manager M' -Status 'Approved'
        $payload = New-GraphEventPayload -SyncEvent $evt -TimeZone 'GMT Standard Time'
    }

    It 'marks the event all-day' {
        $payload.isAllDay | Should -BeTrue
    }
    It 'uses an exclusive end date (last day + 1) at midnight' {
        $payload.start.dateTime | Should -Be '2026-03-16T00:00:00.0000000'
        $payload.end.dateTime   | Should -Be '2026-03-19T00:00:00.0000000'
    }
    It 'applies the managed category and extended properties' {
        $payload.categories | Should -Contain 'PeopleHR Sync'
        ($payload.singleValueExtendedProperties | Where-Object { $_.value -eq $evt.Uid }) | Should -Not -BeNullOrEmpty
        ($payload.singleValueExtendedProperties | Where-Object { $_.value -eq $evt.Hash }) | Should -Not -BeNullOrEmpty
    }
    It 'embeds the UID marker in the body' {
        $payload.body.content | Should -Match ([regex]::Escape("PeopleHR-UID:$($evt.Uid)"))
    }
}

Describe 'New-GraphEventPayload (timed)' {
    It 'keeps wall-clock times and sets the time zone' {
        $evt = New-SyncEvent -Email 'bob@example.com' -Category 'Other Event' `
            -Subject 'Other Event - PeopleHR Sync' -EventType 'Training' `
            -Start ([datetime]'2026-04-01T09:00') -End ([datetime]'2026-04-01T17:00') -IsAllDay $false
        $payload = New-GraphEventPayload -SyncEvent $evt -TimeZone 'GMT Standard Time'
        $payload.isAllDay | Should -BeFalse
        $payload.start.dateTime | Should -Be '2026-04-01T09:00:00.0000000'
        $payload.end.dateTime   | Should -Be '2026-04-01T17:00:00.0000000'
        $payload.start.timeZone | Should -Be 'GMT Standard Time'
    }
}

Describe 'ConvertTo-SyncHoliday' {
    It 'normalises a row into an all-day holiday with the spec subject' {
        $row = [pscustomobject]@{
            'First Name' = 'Alice'
            'Last Name'  = 'Anderson'
            'Work Email' = 'alice@example.com'
            'StartDate'  = '16/03/2026'
            'EndDate'    = '18/03/2026'
            'Status'     = 'Approved'
            'Approver'   = 'Manager M'
            'Comments'   = 'Holiday'
        }
        $evt = ConvertTo-SyncHoliday -Row $row
        $evt.Subject  | Should -Be 'Holiday - PeopleHR Sync'
        $evt.IsAllDay | Should -BeTrue
        $evt.Email    | Should -Be 'alice@example.com'
        $evt.Start    | Should -Be ([datetime]'2026-03-16')
    }
    It 'returns $null when the work email is missing' {
        $row = [pscustomobject]@{ 'First Name' = 'NoEmail'; 'StartDate' = '01/01/2026'; 'EndDate' = '01/01/2026' }
        ConvertTo-SyncHoliday -Row $row | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-SyncOtherEvent' {
    It 'creates a timed event when start/end times are present' {
        $row = [pscustomobject]@{
            'Work Email' = 'bob@example.com'
            'EventType'  = 'Training'
            'StartDate'  = '01/04/2026'
            'EndDate'    = '01/04/2026'
            'StartTime'  = '09:00'
            'EndTime'    = '17:00'
        }
        $evt = ConvertTo-SyncOtherEvent -Row $row
        $evt.IsAllDay | Should -BeFalse
        $evt.Subject  | Should -Be 'Other Event - PeopleHR Sync'
        $evt.Start    | Should -Be ([datetime]'2026-04-01T09:00')
    }
}
