function Get-BackupResultsLast24Hours {
    $backupOutput = ""
    $errorFound = $false
    $twentyFourHoursAgo = (Get-Date).AddHours(-24)
    $jobStatuses = @{} # Initialize a dictionary for tracking job names and their statuses

    # Get events from the Veeam Backup log under Applications and Services Logs
    $events = Get-WinEvent -LogName 'Veeam Backup' | Where-Object { 
        ($_.Id -eq 490 -or $_.Id -eq 190) -and ($_.TimeCreated -ge $twentyFourHoursAgo)
    }

    if ($events) {
        foreach ($event in $events) {
            $eventTime = $event.TimeCreated
            if ($event.Message -match "(Backup job|Backup Copy job|Replication job) '([^']+)' finished with (Success|Failed)") {
                $jobName = $matches[2]
                $outcome = $matches[3]

                # Only update if this event is more recent than what's already recorded
                if (-not $jobStatuses.ContainsKey($jobName) -or $jobStatuses[$jobName].TimeCreated -lt $eventTime) {
                    $jobStatuses[$jobName] = @{
                        "Name" = $jobName
                        "Outcome" = $outcome
                        "Messages" = New-Object System.Collections.ArrayList
                        "TimeCreated" = $eventTime
                    }
                }

                [void]$jobStatuses[$jobName]["Messages"].Add("`nTime: $($eventTime.ToString("g")) Message: $($event.Message)")
            }
        }

        # Generate output based on job statuses
        foreach ($jobName in $jobStatuses.Keys) {
            $status = $jobStatuses[$jobName]
            $backupOutput += "Job '$jobName' finished with $($status["Outcome"]):"
            $backupOutput += $status["Messages"][0] # Only get the latest message
            $backupOutput += "`n"

            if ($status["Outcome"] -eq "Failed") {
                $errorFound = $true
            }
        }
        $backupOutput += "-"*55
    
        if ($errorFound) {
            Write-Host $date
            Write-Host $backupOutput
            Write-Host "Error: Some backup jobs experienced failures in the last 24 hours"
            $backupOutput += "`nError: Some backup jobs experienced failures in the last 24 hours`n"
            Ninja-Property-Set VeeamBackupResultsLast24Hours $backupOutput
            exit 1
        } else {
            Write-Host $date
            Write-Host $backupOutput
            Write-Host "Success: All monitored backup jobs succeeded in the last 24 hours"
            $backupOutput += "`nSuccess: All monitored backup jobs succeeded in the last 24 hours`n"
            Ninja-Property-Set VeeamBackupResultsLast24Hours $backupOutput
            exit 0
        }
    } else {
        Write-Host "Error: No backup information found in the last 24 hours"
        $backupOutput += "`nError: No backup information found in the last 24 hours`n"
        Ninja-Property-Set VeeamBackupResultsLast24Hours $backupOutput
        exit 1
    }
}

Ninja-Property-Set VeeamBackupResultsLast24Hours "Error: Veeam backup check started but not yet completed"
# Main script
Get-BackupResultsLast24Hours
