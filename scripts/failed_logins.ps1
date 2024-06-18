# Define the hash table to hold detailed information
$attempts = @{}

# Define the time range for the past 24 hours
$endTime = Get-Date
$startTime = $endTime.AddHours(-24)

# Fetch the Security logs for failed logins (Event ID 4625) from the past 24 hours
$events = Get-WinEvent -LogName 'Security' -FilterXPath "*[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and (EventID=4625) and TimeCreated[timediff(@SystemTime) <= 86400000]]]"

# Loop through each event to populate the hash table
foreach ($event in $events) {
    $xml = [xml]$event.ToXml()

    # Function to safely extract a value from the XML
    function Get-XmlValue($xmlData, $name) {
        $node = $xmlData | Where-Object { $_.Name -eq $name }
        if ($null -ne $node) {
            return $node.'#text'
        } else {
            return $null
        }
    }

    # Retrieve details from the event using the helper function
    $sourceIp = Get-XmlValue $xml.Event.EventData.Data 'IpAddress'
    $username = Get-XmlValue $xml.Event.EventData.Data 'TargetUserName'
    $timestamp = $event.TimeCreated
    $workstationName = Get-XmlValue $xml.Event.EventData.Data 'WorkstationName'
    $subStatus = Get-XmlValue $xml.Event.EventData.Data 'SubStatus'
    $logonType = Get-XmlValue $xml.Event.EventData.Data 'LogonType'

    # Check for empty or undefined values
    if ([string]::IsNullOrWhiteSpace($sourceIp)) {
        $sourceIp = 'Unknown'
    }
    if ([string]::IsNullOrWhiteSpace($username)) {
        $username = 'Unknown'
    }
    if ([string]::IsNullOrWhiteSpace($workstationName)) {
        $workstationName = 'Unknown'
    }
    if ([string]::IsNullOrWhiteSpace($subStatus)) {
        $subStatus = '0x00000000' # Default to an unknown substatus
    }
    if ([string]::IsNullOrWhiteSpace($logonType)) {
        $logonType = '0' # Default to an unknown logon type
    }

    # Determine failure reason based on substatus
    $failureReason = Switch ($subStatus) {
        '0xC0000064' { 'Unknown user name' }
        '0xC000006A' { 'Wrong password' }
        '0xC0000234' { 'User account locked' }
        Default { 'Other' }
    }

    # Interpret logon type to determine service type
    $serviceType = Switch ($logonType) {
        '2' { 'Interactive' }
        '3' { 'Network' }
        '10' { 'RemoteInteractive' }
        '11' { 'CachedInteractive' }
        Default { 'Other' }
    }

    # Aggregate data
    $key = "$sourceIp $workstationName"
    $detailKey = "$username - Type: $serviceType - Reason: $failureReason"

    if ($attempts.ContainsKey($key)) {
        if ($attempts[$key].ContainsKey($detailKey)) {
            $attempts[$key][$detailKey]++
        } else {
            $attempts[$key].Add($detailKey, 1)
        }
        $attempts[$key].Total++
    } else {
        $attempts[$key] = @{'Total' = 1}
        $attempts[$key].Add($detailKey, 1)
    }
}

# Display the results
Write-Host "Failure Reason: Unknown user name or bad password"

Write-Host "Unique sources:"
$sortedKeys = $attempts.Keys | Sort-Object {$_ -ne 'Other Other'}
foreach ($key in $sortedKeys) {
    $total = $attempts[$key].Total
    Write-Host "$key ($total`x)"
    $attempts[$key].Keys | Where-Object {$_ -ne 'Total'} | ForEach-Object {
        $detail = $_
        $count = $attempts[$key][$detail]
        Write-Host " - $detail ($count`x)"
    }
}
