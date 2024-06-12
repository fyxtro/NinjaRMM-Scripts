# NinjaRMM Monitoring and Maintenance Scripts

## Overview

This repository contains a collection of PowerShell scripts designed for use with NinjaRMM to monitor various backup solutions and perform system maintenance tasks. The scripts included are:

- **Backup Monitoring:** Monitors the status of Veeam, Cove, and Backup Assist backups.
- **System Cleanup:** Cleans old temporary files and manages download folder content.
- **Event Log Parsing:** Parses the event viewer for failed login attempts and provides detailed output.

## Scripts

### Backup Monitoring

These scripts monitor the status of Veeam, Cove, and Backup Assist backups and require no extra configuration.

### System Cleanup

This script performs various system cleanup tasks, including:

- Cleaning old temporary files from Teams, Chrome, Edge, and Windows Update.
- Clearing the recycle bin.
- Analyzing the downloads folder of each user to check the size and identify files older than 30 days.
- Removing files older than 30 days from the downloads folders.

### Event Log Parsing

This script parses the event viewer for failed login attempts and provides a clear output, including:

- IP addresses and hostnames of the failed login attempts.
- Reason for each failed login attempt.
- Count of failed login attempts per user and total count.

## Usage

### Prerequisites

- PowerShell must be installed on the system.

### Installation

1. Clone this repository to your local machine:

    ```sh
    git clone https://github.com/yourusername/your-repo-name.git
    cd your-repo-name
    ```

2. Ensure you have the necessary permissions to execute the scripts.

### Running the Scripts

#### Backup Monitoring

Run the appropriate script for your backup solution:

```sh
.\Monitor-VeeamBackup.ps1
.\Monitor-CoveBackup.ps1
.\Monitor-BackupAssist.ps1
