<#
.SYNOPSIS
Verdel NinjaRMM script – BackupAssist basic health check (Event Log)

.DESCRIPTION
Detects whether BackupAssist is installed by searching common installation paths.
If installed, queries the Windows Application event log for events from provider "BackupAssist"
within the last 24 hours and reports findings to a NinjaOne custom field.

Behavior:
- If BackupAssist is not installed: exits 0 and writes a short status to output
- If events exist and include Warning/Error: exits 1 and stores details
- If only Information (or none of Warning/Error): exits 0 and stores details
- If no BackupAssist events are found in the window: exits 1 and stores status

.AUTHOR
Quinten van Buul
Security Consultant | Verdel Digitaal Partner

.VERSION
1.0.0

.PLATFORM
Windows PowerShell 5.1+
Windows Event Log (Application)
NinjaOne RMM (Custom Field integration)

.CUSTOM FIELD
backupassistresultslast24hours

.NOTES
Provided as-is without warranty. Validate in a test environment before broad deployment.
#>


# Initialize the output variable
$outputMessages = ""

# Define the root directories to search for potential Backup Assist installations
$rootDirectories = @(
    "C:\Program Files",
    "C:\Program Files (x86)"
    # Add additional root directories if applicable
)

# Check for directories containing "BackupAssist" or "Backup Assist" in their names
$backupAssistInstalled = $false

foreach ($directory in $rootDirectories) {
    $matchingDirectories = Get-ChildItem -Path $directory -Directory |
        Where-Object { $_.Name -like "*BackupAssist*" -or $_.Name -like "*Backup Assist*" }

    if ($matchingDirectories) {
        $backupAssistInstalled = $true
        break
    }
}

# If no directories containing "BackupAssist" or "Backup Assist" are found, exit with a success message
if (-not $backupAssistInstalled) {
    Write-Output "Backup Assist is not installed."
    exit 0
}

# Set the time range for the log search
$startTime = (Get-Date).AddHours(-24)
$endTime = Get-Date

# Get the Backup Assist entries from the Windows Event Logs
$backupAssistEntries = Get-WinEvent -LogName "Application" -FilterXPath "*[System[Provider[@Name='BackupAssist']]] and *[System[TimeCreated[@SystemTime>='$($startTime.ToUniversalTime().ToString("o"))']]]" -ErrorAction SilentlyContinue

# Check if any entries are found
if ($backupAssistEntries) {
    $warningsOrErrorsFound = $false

    # Check if any warnings, errors, or information events are found
    foreach ($entry in $backupAssistEntries) {
        if ($entry.LevelDisplayName -eq "Warning" -or $entry.LevelDisplayName -eq "Error") {
            $warningsOrErrorsFound = $true
            $outputMessages += "Event ID: $($entry.Id)`n"
            $outputMessages += "Level: $($entry.LevelDisplayName)`n"
            $outputMessages += "Message: $($entry.Message)`n"
            $outputMessages += "------------------------------------`n"
        } elseif ($entry.LevelDisplayName -eq "Information") {
            $outputMessages += "Event ID: $($entry.Id)`n"
            $outputMessages += "Level: $($entry.LevelDisplayName)`n"
            $outputMessages += "Message: $($entry.Message)`n"
            $outputMessages += "------------------------------------`n"
        }
    }

    # Generate an error if warnings or errors are found
    if ($warningsOrErrorsFound) {
        Write-Error "Backup Assist Alert! - warnings or errors found in the last 24 hours."
        $outputMessages += "Backup Assist Alert! - warnings or errors found in the last 24 hours.`n"
        Ninja-Property-Set backupassistresultslast24hours $outputMessages
        exit 1
    } else {
        $outputMessages += "No Backup Assist warnings or errors found in the last 24 hours.`n"
        Ninja-Property-Set backupassistresultslast24hours $outputMessages
        exit 0
    }
} else {
    Write-Error "Backup Assist Alert! - No Backup Assist entries found in the last 24 hours."
    $outputMessages += "Backup Assist Alert! - No Backup Assist entries found in the last 24 hours.`n"
    Ninja-Property-Set backupassistresultslast24hours "No Backup Assist entries found in the last 24 hours."
    exit 1
}

# Add additional handling for the case when Backup Assist is not installed
if (-not $backupAssistInstalled) {
    $outputMessages = "Backup Assist is not installed."
    Ninja-Property-Set backupassistresultslast24hours $outputMessages
    exit 0
}
