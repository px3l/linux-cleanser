# Linux Cleanser

A comprehensive system cleanup script for Linux distributions that helps remove unnecessary files, clear caches, and free up disk space.

## Features

- **Package Cache Cleaning**: Cleans apt, snap, and flatpak caches
- **Old Kernel Removal**: Safely removes old kernel packages while keeping the current one
- **Config File Cleanup**: Removes orphaned configuration files
- **System Log Management**: Cleans old systemd journal logs and log files
- **Temporary File Cleanup**: Removes old temporary files
- **Browser Cache Cleaning**: Cleans caches from Firefox, Chrome, Chromium, and Opera
- **Thumbnail Cache**: Removes thumbnail caches
- **Broken Symlinks**: Finds and removes broken symbolic links
- **Trash Emptying**: Empties all user trash directories
- **Bash History**: Option to clear bash command history
- **Interactive Mode**: Confirms each cleanup step before execution
- **Safety Features**: Disk space checks and backup creation

## Requirements

- Root privileges (must be run as root)
- Debian-based Linux distribution (Ubuntu, Debian, etc.)
- At least 1GB of available disk space

## Installation

1. Clone or download the script:
```bash
git clone <repository-url>
cd linux-cleanser
```

2. Make the script executable:
```bash
chmod +x linux-cleanser.sh
```

3. Run as root:
```bash
sudo ./linux-cleanser.sh
```

## Usage

The script runs in interactive mode, asking for confirmation before each cleanup step:

1. **Package List Backup**: Creates a backup of installed packages
2. **Package Cache Cleaning**: Cleans apt, snap, and flatpak caches
3. **Dependency Cleanup**: Removes orphaned packages and dependencies
4. **Old Config Files**: Removes configuration files from uninstalled packages
5. **Old Kernels**: Removes old kernel packages
6. **System Logs**: Cleans systemd journal and old log files
7. **Temporary Files**: Removes files older than 7 days from /tmp and /var/tmp
8. **Browser Caches**: Cleans browser cache directories
9. **Thumbnail Cache**: Removes thumbnail caches
10. **Broken Symlinks**: Removes broken symbolic links
11. **Bash History**: Optionally clears bash command history
12. **Trash**: Empties all trash directories

## Safety Features

- **Root Check**: Ensures the script is run with root privileges
- **Disk Space Check**: Warns if available disk space is low
- **Package Backup**: Creates a backup of installed packages before cleaning
- **Error Handling**: Graceful error handling with informative messages
- **Logging**: Logs all operations to `/var/log/linux-cleanser.log`

## Logs

All operations are logged to `/var/log/linux-cleanser.log` with timestamps and log levels.

## Backup Files

Package lists are backed up to `/tmp/package-list-YYYYMMDD-HHMMSS.txt` before cleaning.

## Warning

⚠️ **This script requires root privileges and can delete system files. Use with caution and ensure you have backups of important data.**
