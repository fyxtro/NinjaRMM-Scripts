# NinjaOne Monitoring and Maintenance Scripts

## Overview

This repository contains a collection of PowerShell scripts intended for use with NinjaOne (formerly NinjaRMM).
The scripts focus on monitoring backup solutions, parsing event logs, and performing basic system maintenance.

All monitoring scripts are designed to write structured output to NinjaOne custom fields and to exit with appropriate status codes for alerting.

## Included Scripts

### Backup Monitoring

Scripts for monitoring the health and status of various backup solutions:

- Veeam Backup & Replication  
  Parses the Veeam event log for job and repository results.  
  Supports Veeam v12, v13 and future versions.  
  Determines worst and latest outcome within a configurable time window.  
  Writes sentinel markers for reliable NinjaOne alerting.

- Cove Data Protection  
  Uses ClientTool.exe and StatusReport.xml.  
  Monitors backup service state, datasources, sessions, errors, and Local Speed Vault.  
  Different thresholds for servers and workstations.  
  Outputs detailed status to a NinjaOne custom field.

- BackupAssist  
  Detects BackupAssist installation.  
  Parses the Windows Application event log for BackupAssist events.  
  Flags warnings and errors in the last 24 hours.  
  Reports results to a NinjaOne custom field.

### System Cleanup

Scripts for basic system maintenance tasks, including:

- Cleaning old temporary files from Teams, Chrome, Edge, and Windows Update
- Clearing the recycle bin
- Analyzing user Downloads folders
- Optionally removing files older than a defined threshold

### Event Log Parsing

Scripts that parse the Windows Event Log to detect failed login attempts, including:

- Source IP addresses and hostnames
- Failure reasons
- Per-user and total failure counts

## Output and Alerting

- All monitoring scripts write results to a NinjaOne custom field defined inside the script
- Exit codes are used consistently
  - Exit 0 indicates success or no issues
  - Exit 1 indicates warnings, errors, or parsing failures
- Some scripts include sentinel strings that can be used in NinjaOne alert conditions

## Usage

### Prerequisites

- Windows PowerShell 5.1 or higher
- NinjaOne agent installed
- Sufficient permissions to read event logs and application data
- Administrator privileges where required

### Installation

Clone the repository using git and change into the directory.
```
git clone https://github.com/fyxtro/NinjaRMM-Scripts.git  
cd NinjaRMM-Scripts
```
### Running the Scripts

#### Backup Monitoring

Run the script that matches the backup solution in use.
```
.\VeeamBackup.ps1  
.\CoveBackup.ps1  
.\BackupAssist.ps1
```
Scripts can be executed manually or deployed via NinjaOne as scheduled or on-demand tasks.

## Attribution

Parts of the Cove Data Protection monitoring logic are based on and adapted from:

https://github.com/BackupNerd/Backup-Scripts

These portions remain subject to the original license terms.

## Disclaimer

Scripts are provided as-is without warranty.
Always test in a non-production environment before deploying at scale.
