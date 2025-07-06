#!/bin/bash

# Exit on any error
set -e

# Color definitions
RED="\033[0;31m"
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
ENDCOLOR="\033[0m"

# Configuration
CONFIG_FILE="/etc/linux-cleanser.conf"
LOG_FILE="/var/log/linux-cleanser.log"

# Global variables
OLDCONF=$(dpkg -l|grep "^rc"|awk '{print $2}')
CURKERNEL=$(uname -r|sed 's/-*[a-z]//g'|sed 's/-386//g')
LINUXPKG="linux-(image|headers|debian-modules|restricted-modules)"
METALINUXPKG="linux-(image|headers|restricted-modules)-(generic|i386|server|common|rt|xen)"
OLDKERNELS=$(dpkg -l|awk '{print $2}'|grep -E $LINUXPKG|grep -vE $METALINUXPKG|grep -v $CURKERNEL)

# Function to handle errors
error_exit() {
    echo -e "${RED}[ERROR]: $1${ENDCOLOR}" >&2
    exit 1
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Show banner
show_banner() {
    echo -e
    echo -e
    echo -e $BLUE"  ====================================================  "$ENDCOLOR
    echo -e $BLUE" ===                                                === "$ENDCOLOR
    echo -e $BLUE"==               "$RED"Linux-cleanser by px3l"$BLUE"               =="$ENDCOLOR
    echo -e $BLUE" ===                                                === "$ENDCOLOR
    echo -e $BLUE"  ====================================================  "$ENDCOLOR
    echo -e
    echo -e
}

# Function to check prerequisites
check_prerequisites() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
    
    # Check disk space
    check_disk_space
    
    # Load configuration
    load_config
}

# Function to check disk space before cleaning
check_disk_space() {
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        echo -e "${RED}[Linux-cleanser]:Warning: Low disk space detected!${ENDCOLOR}"
        echo -e "${YELLOW}[Linux-cleanser]:Available: $(($available_space / 1024))MB${ENDCOLOR}"
        if ! ask_user "Continue anyway?"; then
            exit 1
        fi
    fi
}

# Load configuration if exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to ask user with better formatting
ask_user() {
    local message="$1"
    local default="${2:-n}"
    local prompt="[Linux-cleanser]: $message (y/N): "
    
    if [[ "$default" == "y" ]]; then
        prompt="[Linux-cleanser]: $message (Y/n): "
    fi
    
    read -p "$(echo -e "${YELLOW}$prompt${ENDCOLOR}")" -n 1 -r
    echo
    
    if [[ "$default" == "y" ]]; then
        [[ $REPLY =~ ^[Nn]$ ]] && return 1
    else
        [[ $REPLY =~ ^[Yy]$ ]] && return 0
    fi
    
    return 1
}

# Function to show what will be cleaned
show_cleanup_preview() {
    echo -e "${YELLOW}[Linux-cleanser]:Preview of what will be cleaned:${ENDCOLOR}"
    echo -e "${GREEN}  - Package cache: $(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)${ENDCOLOR}"
    echo -e "${GREEN}  - Old config files: $(echo "$OLDCONF" | wc -w) packages${ENDCOLOR}"
    echo -e "${GREEN}  - Old kernels: $(echo "$OLDKERNELS" | wc -w) packages${ENDCOLOR}"
    echo -e "${GREEN}  - Journal logs: $(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]*[A-Z]' || echo "Unknown")${ENDCOLOR}"
    echo
}

# Create backup before cleaning
create_backup() {
    echo -e "${YELLOW}[Linux-cleanser]:Creating package list backup...${ENDCOLOR}"
    dpkg --get-selections > "/tmp/package-list-$(date +%Y%m%d-%H%M%S).txt"
}

# Clean package cache more thoroughly
clean_package_cache() {
    if ask_user "Do you want to clean package cache (apt, snap, flatpak)?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Flushing local cache from the retrieved package files...${ENDCOLOR}"
        apt-get clean
        
        echo -e "${YELLOW}[Linux-cleanser]:Clearing non-necessary packages...${ENDCOLOR}"
        apt-get autoclean
        apt-get clean
        
        echo -e "${YELLOW}[Linux-cleanser]:Cleaning apt cache...${ENDCOLOR}"
        apt-get clean
        
        # Clean snap cache if available
        if command_exists snap; then
            echo -e "${YELLOW}[Linux-cleanser]:Cleaning snap cache...${ENDCOLOR}"
            snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
                snap remove "$snapname" --revision="$revision" 2>/dev/null || true
            done
        fi
        
        # Clean flatpak cache if available
        if command_exists flatpak; then
            echo -e "${YELLOW}[Linux-cleanser]:Cleaning flatpak cache...${ENDCOLOR}"
            flatpak uninstall --unused -y 2>/dev/null || true
        fi
    fi
}

# Clean systemd journal logs
clean_journal_logs() {
    if ask_user "Do you want to clean systemd journal logs?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Cleaning systemd journal logs...${ENDCOLOR}"
        journalctl --vacuum-time=7d 2>/dev/null || true
        journalctl --vacuum-size=100M 2>/dev/null || true
    fi
}

# Clean temporary files
clean_temp_files() {
    if ask_user "Do you want to clean temporary files (older than 7 days)?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Cleaning temporary files...${ENDCOLOR}"
        find /tmp -type f -atime +7 -delete 2>/dev/null || true
        find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
    fi
}

# Clean old log files
clean_old_logs() {
    if ask_user "Do you want to clean old log files (older than 30 days)?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Cleaning old log files...${ENDCOLOR}"
        find /var/log -name "*.log" -type f -mtime +30 -delete 2>/dev/null || true
        find /var/log -name "*.gz" -type f -mtime +30 -delete 2>/dev/null || true
    fi
}

# Clean broken symlinks
clean_broken_symlinks() {
    if ask_user "Do you want to clean broken symlinks?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Cleaning broken symlinks...${ENDCOLOR}"
        find /home -type l -xtype l -delete 2>/dev/null || true
        find /usr -type l -xtype l -delete 2>/dev/null || true
    fi
}

# Clean browser caches
clean_browser_caches() {
    if ask_user "Do you want to clean browser caches?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Cleaning browser caches...${ENDCOLOR}"
        for user_home in /home/*; do
            if [[ -d "$user_home" ]]; then
                username=$(basename "$user_home")
                # Firefox
                rm -rf "$user_home/.mozilla/firefox/*/Cache" 2>/dev/null || true
                rm -rf "$user_home/.cache/mozilla" 2>/dev/null || true
                # Chrome/Chromium
                rm -rf "$user_home/.cache/google-chrome" 2>/dev/null || true
                rm -rf "$user_home/.cache/chromium" 2>/dev/null || true
                # Other browsers
                rm -rf "$user_home/.cache/opera" 2>/dev/null || true
            fi
        done
    fi
}

# Clean thumbnail cache
clean_thumbnail_cache() {
    if ask_user "Do you want to clean thumbnail cache?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Cleaning thumbnail cache...${ENDCOLOR}"
        find /home/*/.cache/thumbnails -type f -delete 2>/dev/null || true
        find /root/.cache/thumbnails -type f -delete 2>/dev/null || true
    fi
}

# Handle old config files
handle_old_configs() {
    echo -e "${YELLOW}[Linux-cleanser]:Found old config files: ${ENDCOLOR}${GREEN} $OLDCONF${ENDCOLOR}"
    if ask_user "Do you want to remove old config files?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Removing old config files...${ENDCOLOR}"
        apt-get purge $OLDCONF 2>/dev/null || true
    fi
}

# Handle old kernels
handle_old_kernels() {
    echo -e "${YELLOW}[Linux-cleanser]:Found old kernel files: ${ENDCOLOR}${GREEN} $OLDKERNELS${ENDCOLOR}"
    if ask_user "Do you want to remove old kernel files?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Removing old kernels...${ENDCOLOR}"
        apt-get purge $OLDKERNELS 2>/dev/null || true
    fi
}

# Handle bash history
handle_bash_history() {
    if ask_user "This will clear all bash history. Do you want to clear bash history?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Clearing all bash history...${ENDCOLOR}"
        rm -rf ~/.bash_history 2>/dev/null || true
    fi
}

# Show summary
show_summary() {
    echo -e "${YELLOW}[Linux-cleanser]:Script Finished!${ENDCOLOR}"
    echo -e
    echo -e $RED"Cleansing complete."$ENDCOLOR
    echo -e
}

# Main function
main() {
    # Show banner
    show_banner
    
    # Check prerequisites
    check_prerequisites
    
    # Show cleanup preview
    show_cleanup_preview
    
    # Create backup
    if ask_user "Do you want to create a package list backup?"; then
        create_backup
    fi
    
    # Clean package cache
    clean_package_cache
    
    # Remove redundant dependencies
    if ask_user "Do you want to remove redundant dependencies?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Removing redundant dependencies...${ENDCOLOR}"
        apt-get -y autoremove
        apt-get -y autoremove --purge
    fi
    
    # Clean old config files
    handle_old_configs
    
    # Clean old kernels
    handle_old_kernels
    
    # Clean system files
    clean_journal_logs
    clean_temp_files
    clean_old_logs
    clean_broken_symlinks
    
    # Clean user files
    clean_browser_caches
    clean_thumbnail_cache
    
    # Handle bash history
    handle_bash_history
    
    # Empty trash
    if ask_user "Do you want to empty the trash?"; then
        echo -e "${YELLOW}[Linux-cleanser]:Emptying the trash...${ENDCOLOR}"
        rm -rf /home/*/.local/share/Trash/*/** 2>/dev/null || true
        rm -rf /root/.local/share/Trash/*/** 2>/dev/null || true
    fi
    
    # Show summary
    show_summary
}

# Execute main function
main "$@"
