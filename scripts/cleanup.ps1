param (
    [switch]$AnalyzeDownloads,
    [switch]$CleanOldDownloads,
    [switch]$CleanRecyclebin
)

# Function to analyze and optionally clean the Downloads folder
function Analyze-DownloadsFolder {
    param (
        [string]$UserPath,
        [string]$UserName
    )
    $downloadsPath = Join-Path $UserPath "Downloads"
    $currentDate = Get-Date
    $oldFiles = Get-ChildItem $downloadsPath -Recurse -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.LastWriteTime -lt $currentDate.AddDays(-30) }

    $totalSize = (Get-ChildItem $downloadsPath -Recurse -File -ErrorAction SilentlyContinue | 
                 Measure-Object -Property Length -Sum).Sum / 1MB
    $oldSize = ($oldFiles | Measure-Object -Property Length -Sum).Sum / 1MB

    Write-Host "$UserName's Downloads folder total size: $("{0:N2}" -f $totalSize) MB" -ForegroundColor Cyan
    Write-Host "$UserName's Downloads older than 30 days size: $("{0:N2}" -f $oldSize) MB" -ForegroundColor Magenta

    if ($CleanOldDownloads) {
        $oldFiles | Remove-Item -Force
        Write-Host "Deleted files older than 30 days in $UserName's Downloads folder" -ForegroundColor Green
    }
}

# Function to cleanup directory and report freed space
function Cleanup-Directory {
    param (
        [string]$Path,
        [string]$Description
    )
    if (Test-Path $Path) {
        try {
            $initialSize = ([math]::Round(((Get-ChildItem $Path -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1Gb), 2))
            Get-ChildItem $Path -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            $finalSize = ([math]::Round(((Get-ChildItem $Path -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1Gb), 2))
            $freedSpace = $initialSize - $finalSize
            Write-Host "Er is $freedSpace GB in $Description vrijgemaakt" -ForegroundColor DarkGray
        } catch {
            Write-Host "Failed to clean up $Description. Error: $_" -ForegroundColor Red
        }
    }
}

# Filter out system profiles
$users = Get-ChildItem C:\Users -Directory | Where-Object { $_.Name -notmatch "^(Administrator|Public|Default|Default User|All Users|User)$" }

if ($AnalyzeDownloads) {
    # If the switch is used, only analyze the Downloads folder
    foreach ($user in $users) {
        Analyze-DownloadsFolder -UserPath $user.FullName -UserName $user.Name
    }
} else {
  
  foreach ($user in $users) {
      # Define user-specific paths
      $teamsCachePath = "$($user.FullName)\AppData\Roaming\Microsoft\Teams\Cache"
      $chromeCachePath = "$($user.FullName)\AppData\Local\Google\Chrome\User Data\Default\Cache"
      $edgeCachePath = "$($user.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Cache"
      $userTempPath = "$($user.FullName)\AppData\Local\Temp"
  
      # Cleanup operations for each user
      Cleanup-Directory -Path $teamsCachePath -Description "Teams Cache for $($user.Name)"
      Cleanup-Directory -Path $chromeCachePath -Description "Chrome Cache for $($user.Name)"
      Cleanup-Directory -Path $edgeCachePath -Description "Edge Cache for $($user.Name)"
      Cleanup-Directory -Path $userTempPath -Description "User Temp for $($user.Name)"
  }
  
  # Common paths cleanup
  
  # Common paths
  $windowsTempPath = "$env:windir\Temp"
  $internetFilesPath = "$env:LOCALAPPDATA\Microsoft\Windows\Temporary Internet Files"
  $cbsLogPath = "$env:windir\logs\CBS"
  $perfLogsPath = "C:\PerfLogs"
  $memoryDumpPath = "$env:windir\memory.dmp"
  $prefetchPath = "$env:windir\Prefetch"
  $softwareDistributionPath = "C:\Windows\SoftwareDistribution\Download"
  
  # Disk information retrieval using Get-PSDrive
  function Get-DiskInfo {
      Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | 
      Select-Object Name, 
      @{Name="Size (GB)"; Expression={[math]::Round($_.Used / 1GB, 2)}},
      @{Name="FreeSpace (GB)"; Expression={[math]::Round($_.Free / 1GB, 2)}},
      @{Name="PercentFree"; Expression={"{0:P1}" -f ($_.Free / $_.Used)}} | 
      Format-Table -AutoSize | Out-String
  }
  
  # Function to empty the Recycle Bin
  function Empty-RecycleBin {
    # Path to the global Recycle Bin
    $globalRecycleBinPath = 'C:\$Recycle.Bin'
    
    try {
        # Ensure the script can access hidden and system items
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        $userRecycleBins = Get-ChildItem -Path $globalRecycleBinPath -Force -ErrorAction Stop
    
        foreach ($userBin in $userRecycleBins) {
            # Construct the full path to the user's Recycle Bin
            $userBinPath = Join-Path -Path $globalRecycleBinPath -ChildPath $userBin.Name
    
            # Get all items including hidden and system files
            $items = Get-ChildItem -Path $userBinPath -Recurse -Force
    
            foreach ($item in $items) {
                # Remove the item, suppress confirmation and errors
                Remove-Item $item.FullName -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
    
        Write-Host 'Recycle Bins for all users have been cleared.'
    } catch {
        Write-Host "An error occurred: $_"
    } finally {
        $ErrorActionPreference = $oldPreference
    }
  }
  
  # Capture disk info before cleanup
  $Before = Get-DiskInfo
  
  # Cleanup operations
  Cleanup-Directory -Path $windowsTempPath -Description "Windows Temp"
  Cleanup-Directory -Path $userTempPath -Description "User Temp"
  Cleanup-Directory -Path $edgeCachePath -Description "Edge Cache"
  Cleanup-Directory -Path $chromeCachePath -Description "Chrome Cache"
  Cleanup-Directory -Path $teamsCachePath -Description "Teams Cache"
  Cleanup-Directory -Path $internetFilesPath -Description "Temporary Internet Files"
  Cleanup-Directory -Path $cbsLogPath -Description "CBS Logs"
  Cleanup-Directory -Path $perfLogsPath -Description "Performance Logs"
  Cleanup-Directory -Path $memoryDumpPath -Description "Memory Dump"
  Cleanup-Directory -Path $prefetchPath -Description "Prefetch Files"
  Cleanup-Directory -Path $softwareDistributionPath -Description "SoftwareDistribution Downloads"
  
  if ($CleanRecyclebin) {
    # Cleanup the Recycle Bin
    Empty-RecycleBin
  }
  
  # Capture disk info after cleanup
  $After = Get-DiskInfo
  
  # Output before and after information
  Write-Host "Before: `n$Before"
  Write-Host "After: `n$After"
}
