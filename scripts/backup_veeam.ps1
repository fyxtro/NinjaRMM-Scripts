<#
.SYNOPSIS
Verdel NinjaRMM script – Veeam backup status check

.DESCRIPTION
This script checks Veeam Backup & Replication job and repository results
by parsing Windows Event Log entries. It is designed to work reliably
across Veeam v12, v13 and future versions.

The script is built for use with NinjaOne custom fields and alerting.

.AUTHOR
Quinten van Buul
Security Consultant | Verdel Digitaal Partner

.CREATED
2023

.LAST UPDATED
2026

.VERSION
2.0.0

.PLATFORM
Windows Server with Veeam Backup & Replication
NinjaOne RMM (Custom Field integration)

.FEATURES
- Parses Veeam Backup event log entries (job and repository results)
- Supports Veeam v12 and v13 event formats
- Determines worst and latest outcome within a configurable time window
- Writes structured output to NinjaOne custom fields
- Provides sentinel markers for reliable NinjaOne alert conditions
- Includes safe output truncation to avoid NinjaOne field limits
- Includes catch-all exception handling to prevent silent failures

.NOTES
- Intended for monitoring and alerting purposes only
- Non-success states (Warning, Failed, Unknown) are treated as issues
- Script exits with non-zero code on detected issues or parsing errors

.LICENSE
MIT License

This script is provided as-is without warranty of any kind.
Use at your own risk.

.OTHER
Custom field: VeeamBackupResultsLast24Hours
#>

# -------------------- Settings --------------------
$CustomFieldName = "VeeamBackupResultsLast24Hours"
$LookbackHours   = 24
$CustomFieldSafeMaxChars = 9000  # below 10,000 multi-line limit 
$EventIds = 190, 490, 40002
# --------------------------------------------------

function Convert-VeeamResult {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    switch ($Value.Trim()) {
        '0' { 'Success' }
        '1' { 'Warning' }
        '2' { 'Failed' }
        default { $Value.Trim() }
    }
}

function Normalize-Outcome {
    param([string]$Outcome)
    if ([string]::IsNullOrWhiteSpace($Outcome)) { return 'Unknown' }
    switch -Regex ($Outcome.Trim()) {
        '^(?i)success$' { 'Success' }
        '^(?i)warning$' { 'Warning' }
        '^(?i)failed$'  { 'Failed' }
        default         { 'Unknown' }
    }
}

function Outcome-Severity {
    param([string]$Outcome)
    switch (Normalize-Outcome $Outcome) {
        'Success' { 0 }
        'Warning' { 1 }
        'Failed'  { 2 }
        default   { 1 }  # Unknown -> issue
    }
}

function Get-EventValues {
    param([System.Diagnostics.Eventing.Reader.EventRecord]$Event)
    $vals = @()
    foreach ($p in $Event.Properties) {
        if ($null -eq $p.Value) { $vals += "" }
        else { $vals += [string]$p.Value }
    }
    return $vals
}

function Try-ParseJobFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $pattern = '(?i)(Backup\s+job|Backup\s+Copy\s+job|Replication\s+job|SureBackup\s+job|Agent\s+Backup\s+Job)\s+(?:''|")?(?<Name>.+?)(?:''|")?\s+finished\s+with\s+(?<State>Success|Failed|Warning)\b'
    if ($Text -match $pattern) {
        return @{ Name = $Matches['Name']; Outcome = $Matches['State'] }
    }
    return $null
}

function Try-ParseRepoFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $pattern = '(?i)storage management session for repository\s+(?<Name>.+?)\s+has finished:\s+(?<State>Failed|Success|Warning)\b'
    if ($Text -match $pattern) {
        return @{ Name = $Matches['Name'].Trim(); Outcome = $Matches['State'] }
    }
    return $null
}

function Get-OutcomeFromValues {
    param([string[]]$Values)

    foreach ($v in $Values) {
        if ($v -match '^(0|1|2)$') { return (Convert-VeeamResult $v) }
    }
    foreach ($v in $Values) {
        if ($v -match '^(Success|Warning|Failed)$') { return $v }
    }
    foreach ($v in $Values) {
        if ($v -match '(?i)\b(Success|Warning|Failed)\b') { return $Matches[1] }
    }
    return $null
}

function Is-GuidString($s) {
    $g = [guid]::Empty
    return [guid]::TryParse($s, [ref]$g)
}
function Is-VersionLike($s) { return ($s -match '^\d+\.\d+(\.\d+){1,3}$') }
function Is-BoolLike($s) { return ($s -match '^(True|False)$') }

function Is-CandidateName($s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    if ($s.Length -lt 2 -or $s.Length -gt 200) { return $false }
    if (Is-GuidString $s) { return $false }
    if (Is-VersionLike $s) { return $false }
    if (Is-BoolLike $s) { return $false }
    if ($s -match '^(0|1|2)$') { return $false }
    return $true
}

function Find-HostIndex {
    param([string[]]$Values)

    $host = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($host)) { return -1 }

    for ($i = 0; $i -lt $Values.Count; $i++) {
        $v = $Values[$i]
        if ([string]::IsNullOrWhiteSpace($v)) { continue }
        if ($v -eq $host) { return $i }
        if ($v -match "^$([regex]::Escape($host))(\.|$)") { return $i }
    }
    return -1
}

function Guess-NameNearHost {
    param([string[]]$Values)

    $hostIdx = Find-HostIndex -Values $Values
    if ($hostIdx -lt 0) { return $null }

    for ($j = $hostIdx - 1; $j -ge 0 -and ($hostIdx - $j) -le 10; $j--) {
        $cand = $Values[$j]
        if (Is-CandidateName $cand) { return $cand }
    }
    return $null
}

function Guess-BestName {
    param([string[]]$Values)
    $best = $null
    foreach ($v in $Values) {
        if (-not (Is-CandidateName $v)) { continue }
        if ($null -eq $best -or $v.Length -gt $best.Length) { $best = $v }
    }
    return $best
}

function Guess-BestDescription {
    param([string[]]$Values)
    $best = $null
    foreach ($v in $Values) {
        if ([string]::IsNullOrWhiteSpace($v)) { continue }
        if ($v.Length -lt 20) { continue }
        if ($null -eq $best -or $v.Length -gt $best.Length) { $best = $v }
    }
    return $best
}

function Update-StatusRecord {
    param(
        [hashtable]$Table,
        [string]$Name,
        [datetime]$EventTime,
        [string]$Outcome,
        [string]$Message
    )

    $Outcome = Normalize-Outcome $Outcome
    $sev = Outcome-Severity $Outcome

    if (-not $Table.ContainsKey($Name)) {
        $Table[$Name] = @{
            Name          = $Name
            LatestTime    = $EventTime
            LatestOutcome = $Outcome
            LatestMessage = $Message

            WorstTime     = $EventTime
            WorstOutcome  = $Outcome
            WorstMessage  = $Message
            WorstSeverity = $sev
        }
        return
    }

    $r = $Table[$Name]

    if ($EventTime -gt $r.LatestTime) {
        $r.LatestTime    = $EventTime
        $r.LatestOutcome = $Outcome
        $r.LatestMessage = $Message
    }

    if ($sev -gt $r.WorstSeverity -or ($sev -eq $r.WorstSeverity -and $EventTime -gt $r.WorstTime)) {
        $r.WorstTime     = $EventTime
        $r.WorstOutcome  = $Outcome
        $r.WorstMessage  = $Message
        $r.WorstSeverity = $sev
    }

    $Table[$Name] = $r
}

function Truncate-ForCustomField {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if ($Text.Length -le $CustomFieldSafeMaxChars) { return $Text }

    $suffix = "`n...(truncated to $CustomFieldSafeMaxChars chars)"
    $keep = $CustomFieldSafeMaxChars - $suffix.Length
    if ($keep -lt 0) { $keep = 0 }

    return ($Text.Substring(0, $keep) + $suffix)
}

function Write-ResultAndExit {
    param(
        [string]$Status,   # OK or ERROR
        [string]$Code,     # e.g. NOEVENTS, PARSING, ISSUES, EXCEPTION
        [string]$Body,
        [int]$ExitCode
    )

    $bodyOut = $Body.TrimEnd()

    $bodyOut += "`nVERDEL_VEEAM_CHECK_STATUS=$Status"
    $bodyOut += "`nVERDEL_VEEAM_CHECK_CODE=$Code`n"

    $bodyOut = Truncate-ForCustomField $bodyOut

    Write-Host $bodyOut
    Ninja-Property-Set $CustomFieldName $bodyOut
    exit $ExitCode
}

function Get-BackupResultsLast24Hours {
    $date = Get-Date
    $startTime = (Get-Date).AddHours(-1 * $LookbackHours)

    $backupOutput = ""
    $errorFound = $false

    $jobStatuses  = @{}
    $repoStatuses = @{}

    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'Veeam Backup'
        Id        = $EventIds
        StartTime = $startTime
    } -ErrorAction SilentlyContinue

    $eventsCount = if ($events) { $events.Count } else { 0 }

    Write-Host $date
    Write-Host "Veeam event scan: last $LookbackHours h, IDs: $($EventIds -join ', '), Events found: $eventsCount"

    if (-not $events) {
        Write-ResultAndExit -Status "ERROR" -Code "NOEVENTS" `
            -Body "Error: No backup information found in the last $LookbackHours hours" `
            -ExitCode 1
    }

    foreach ($event in $events) {
        $eventTime = $event.TimeCreated
        $values = Get-EventValues -Event $event

        $texts = @()
        if ($event.Message) { $texts += $event.Message }
        $texts += ($values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $texts = $texts | Select-Object -Unique

        switch ($event.Id) {

            190 { # Backup Job Finished
                $jobName = $null
                $outcome = $null
                $desc    = $null

                foreach ($t in $texts) {
                    $parsed = Try-ParseJobFromText -Text $t
                    if ($parsed) {
                        $jobName = $parsed.Name
                        $outcome = $parsed.Outcome
                        $desc    = $t
                        break
                    }
                }

                if (-not $outcome) { $outcome = Get-OutcomeFromValues -Values $values }
                if (-not $jobName) { $jobName = Guess-NameNearHost -Values $values }
                if (-not $jobName) { $jobName = Guess-BestName -Values $values }

                if (-not $desc) { $desc = Guess-BestDescription -Values $values }
                if (-not $desc -and $event.Message) { $desc = $event.Message }
                if (-not $desc) { $desc = "No message/description available." }

                # PATCH: Prefer job name/result from Description text
                if (-not [string]::IsNullOrWhiteSpace($desc)) {
                    $p = Try-ParseJobFromText -Text $desc
                    if ($p) { $jobName = $p.Name; $outcome = $p.Outcome }
                }

                if (-not $jobName) { continue }
                $outcome = Normalize-Outcome $outcome

                Update-StatusRecord -Table $jobStatuses -Name $jobName -EventTime $eventTime -Outcome $outcome -Message $desc
            }

            490 { # Backup Copy Job Finished
                $jobName = $null
                $outcome = $null
                $desc    = $null

                foreach ($t in $texts) {
                    $parsed = Try-ParseJobFromText -Text $t
                    if ($parsed) {
                        $jobName = $parsed.Name
                        $outcome = $parsed.Outcome
                        $desc    = $t
                        break
                    }
                }

                if (-not $outcome) { $outcome = Get-OutcomeFromValues -Values $values }
                if (-not $jobName) { $jobName = Guess-NameNearHost -Values $values }
                if (-not $jobName) { $jobName = Guess-BestName -Values $values }

                if (-not $desc) { $desc = Guess-BestDescription -Values $values }
                if (-not $desc -and $event.Message) { $desc = $event.Message }
                if (-not $desc) { $desc = "No message/description available." }

                # PATCH
                if (-not [string]::IsNullOrWhiteSpace($desc)) {
                    $p = Try-ParseJobFromText -Text $desc
                    if ($p) { $jobName = $p.Name; $outcome = $p.Outcome }
                }

                if (-not $jobName) { continue }
                $outcome = Normalize-Outcome $outcome

                Update-StatusRecord -Table $jobStatuses -Name $jobName -EventTime $eventTime -Outcome $outcome -Message $desc
            }

            40002 { # Storage Management Session Finished
                $repoName = $null
                $outcome  = $null
                $desc     = $null

                foreach ($t in $texts) {
                    $parsed = Try-ParseRepoFromText -Text $t
                    if ($parsed) {
                        $repoName = $parsed.Name
                        $outcome  = $parsed.Outcome
                        $desc     = $t
                        break
                    }
                }

                if (-not $outcome) { $outcome = Get-OutcomeFromValues -Values $values }
                if (-not $repoName) { $repoName = Guess-BestName -Values $values }

                if (-not $desc) { $desc = Guess-BestDescription -Values $values }
                if (-not $desc -and $event.Message) { $desc = $event.Message }
                if (-not $desc) { $desc = "No message/description available." }

                # Prefer from description if possible
                if (-not [string]::IsNullOrWhiteSpace($desc)) {
                    $p = Try-ParseRepoFromText -Text $desc
                    if ($p) { $repoName = $p.Name; $outcome = $p.Outcome }
                }

                if (-not $repoName) { continue }
                $outcome = Normalize-Outcome $outcome

                Update-StatusRecord -Table $repoStatuses -Name $repoName -EventTime $eventTime -Outcome $outcome -Message $desc
            }
        }
    }

    Write-Host "Parsed jobs: $($jobStatuses.Count) | Parsed repos: $($repoStatuses.Count)"

    if ($jobStatuses.Count -eq 0 -and $repoStatuses.Count -eq 0) {
        Write-ResultAndExit -Status "ERROR" -Code "PARSING" `
            -Body "Error: Veeam events were found (IDs: $($EventIds -join ',')) but none could be parsed into job/repo results. Likely different event IDs/job types on this server." `
            -ExitCode 1
    }

    # Build output + decide error based on WORST outcome
    foreach ($k in ($jobStatuses.Keys | Sort-Object)) {
        $s = $jobStatuses[$k]

        $backupOutput += "Job '$($s.Name)' finished with $($s.LatestOutcome):`n"
        $backupOutput += "Time: $($s.LatestTime.ToString('g')) Message: $($s.LatestMessage)`n"

        if ($s.WorstOutcome -ne $s.LatestOutcome) {
            if ($s.LatestOutcome -eq 'Success' -and $s.WorstOutcome -ne 'Success') {
                $backupOutput += "Note: Earlier in the last $LookbackHours hours this job finished with $($s.WorstOutcome) at $($s.WorstTime.ToString('g')), but later succeeded.`n"
            } else {
                $backupOutput += "Note: Worst status in the last $LookbackHours hours: $($s.WorstOutcome) at $($s.WorstTime.ToString('g')).`n"
            }
        }

        $backupOutput += "`n"

        # (1) + (2): Anything not Success in window => issue
        if ($s.WorstOutcome -ne 'Success') { $errorFound = $true }
    }

    foreach ($k in ($repoStatuses.Keys | Sort-Object)) {
        $s = $repoStatuses[$k]

        $backupOutput += "Storage management session for repository '$($s.Name)' finished with $($s.LatestOutcome):`n"
        $backupOutput += "Time: $($s.LatestTime.ToString('g')) Message: $($s.LatestMessage)`n"

        if ($s.WorstOutcome -ne $s.LatestOutcome) {
            if ($s.LatestOutcome -eq 'Success' -and $s.WorstOutcome -ne 'Success') {
                $backupOutput += "Note: Earlier in the last $LookbackHours hours this repository session finished with $($s.WorstOutcome) at $($s.WorstTime.ToString('g')), but later succeeded.`n"
            } else {
                $backupOutput += "Note: Worst status in the last $LookbackHours hours: $($s.WorstOutcome) at $($s.WorstTime.ToString('g')).`n"
            }
        }

        $backupOutput += "`n"

        if ($s.WorstOutcome -ne 'Success') { $errorFound = $true }
    }

    $backupOutput += "-" * 55

    if ($errorFound) {
        Write-ResultAndExit -Status "ERROR" -Code "ISSUES" `
            -Body ($backupOutput + "`nError: One or more jobs/repository sessions had Warning/Failed/Unknown in the last $LookbackHours hours (even if later succeeded).") `
            -ExitCode 1
    } else {
        Write-ResultAndExit -Status "OK" -Code "OK" `
            -Body ($backupOutput + "`nSuccess: All monitored backup jobs succeeded in the last $LookbackHours hours") `
            -ExitCode 0
    }
}

# -------------------- Main (catch-all) --------------------
try {
    Get-BackupResultsLast24Hours
}
catch {
    $msg  = "Error: Script exception: $($_.Exception.Message)"
    $msg += "`nVERDEL_VEEAM_CHECK_STATUS=ERROR"
    $msg += "`nVERDEL_VEEAM_CHECK_CODE=EXCEPTION`n"

    $msg = Truncate-ForCustomField $msg
    Write-Host $msg
    Ninja-Property-Set $CustomFieldName $msg
    exit 1
}
