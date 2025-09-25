#!/usr/bin/env bash

# =============================================================================
# HomeProxy Installer for GL-AXT1800
# Version: 1.1
# Author: qlxi
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.1"
readonly TARGET_DEVICE="GL-AXT1800"

# URLs
readonly LUCI_APP_URL="https://github.com/qlxi/Install-homeproxy-AXT1800/releases/download/homeproxy/luci-app-homeproxy.ipk"
readonly SING_BOX_URL="https://github.com/qlxi/Install-homeproxy-AXT1800/releases/download/homeproxy/sing-box"

# Paths
readonly TEMP_DIR="/tmp"
readonly LUCI_APP_FILE="${TEMP_DIR}/luci-app-homeproxy.ipk"
readonly SING_BOX_DEST="/usr/bin/sing-box"

# =============================================================================
# Color and Logging Configuration
# =============================================================================

# Text colors
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local color="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${color}[${timestamp}] [${level}]${COLOR_RESET} ${message}" >&2
}

log_info() { log "INFO" "$1" "$COLOR_GREEN"; }
log_warn() { log "WARN" "$1" "$COLOR_YELLOW"; }
log_error() { log "ERROR" "$1" "$COLOR_RED"; }
log_debug() { log "DEBUG" "$1" "$COLOR_BLUE"; }
log_step() { log "STEP" "$1" "$COLOR_CYAN"; }
log_success() { log "SUCCESS" "$1" "$COLOR_MAGENTA"; }

# =============================================================================
# Utility Functions
# =============================================================================

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check device compatibility
check_device() {
    local device_model
    device_model=$(cat /proc/device-tree/model 2>/dev/null || echo "Unknown")
    
    log_info "Detected device: $device_model"
    
    if [[ ! "$device_model" == *"$TARGET_DEVICE"* ]]; then
        log_warn "This script is designed for $TARGET_DEVICE"
        log_warn "Current device: $device_model"
        
        read -rp "Do you want to continue anyway? (y/N): " -n 1 response
        echo
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled by user"
            exit 0
        fi
    fi
}

# Check available disk space
check_disk_space() {
    log_step "Checking available disk space..."
    
    local available_kb
    available_kb=$(df /tmp | awk 'NR==2 {print $4}')
    
    if [[ $available_kb -lt 10240 ]]; then
        log_warn "Low disk space available: ${available_kb}KB"
        log_info "Consider cleaning up temporary files if installation fails"
    else
        log_success "Sufficient disk space available: ${available_kb}KB"
    fi
}

# Check internet connectivity
check_internet() {
    log_step "Checking internet connectivity..."
    
    if ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        log_error "No internet connectivity. Please check your connection."
        exit 1
    fi
    
    log_success "Internet connectivity confirmed"
}

# Cleanup temporary files
cleanup_temp_files() {
    log_step "Cleaning up temporary files..."
    
    local files_cleaned=0
    
    # Remove downloaded IPK file
    if [[ -f "$LUCI_APP_FILE" ]]; then
        rm -f "$LUCI_APP_FILE"
        log_info "Removed: $LUCI_APP_FILE"
        ((files_cleaned++))
    fi
    
    # Remove any temporary sing-box files
    if [[ -f "/tmp/sing-box-new" ]]; then
        rm -f "/tmp/sing-box-new"
        log_info "Removed temporary sing-box file"
        ((files_cleaned++))
    fi
    
    # Clean opkg cache
    if command -v opkg >/dev/null 2>&1; then
        opkg clean 2>/dev/null || true
        log_info "Cleaned opkg cache"
    fi
    
    if [[ $files_cleaned -gt 0 ]]; then
        log_success "Cleaned up $files_cleaned temporary files"
    else
        log_info "No temporary files to clean"
    fi
}

# Calculate freed space
calculate_freed_space() {
    local original_size=$1
    local final_size=$2
    local freed=$((original_size - final_size))
    
    if [[ $freed -gt 0 ]]; then
        log_success "Freed ${freed}KB of disk space"
    elif [[ $freed -lt 0 ]]; then
        log_info "Used $((freed * -1))KB additional space"
    else
        log_info "Disk space usage unchanged"
    fi
}

# Trap for cleanup on exit
trap 'cleanup_temp_files' EXIT

# =============================================================================
# Installation Functions
# =============================================================================

# Download files with error handling and progress
download_file() {
    local url="$1"
    local dest="$2"
    local filename=$(basename "$dest")
    
    log_step "Downloading $filename..."
    
    # Show progress if wget supports it
    if wget --help | grep -q "progress=bar"; then
        if ! wget --progress=bar:force --timeout=30 --tries=3 -O "$dest" "$url"; then
            log_error "Failed to download $filename from $url"
            return 1
        fi
    else
        if ! wget --timeout=30 --tries=3 -O "$dest" "$url"; then
            log_error "Failed to download $filename from $url"
            return 1
        fi
    fi
    
    if [[ ! -s "$dest" ]]; then
        log_error "Downloaded file is empty: $dest"
        return 1
    fi
    
    local file_size=$(du -k "$dest" | cut -f1)
    log_success "Downloaded $filename successfully (${file_size}KB)"
    return 0
}

# Install luci-app-homeproxy
install_luci_app() {
    log_step "Installing luci-app-homeproxy..."
    
    if [[ ! -f "$LUCI_APP_FILE" ]]; then
        log_error "Luci app file not found: $LUCI_APP_FILE"
        return 1
    fi
    
    # Check if opkg is available
    if ! command -v opkg >/dev/null 2>&1; then
        log_error "opkg package manager not found"
        return 1
    fi
    
    local ipk_size=$(du -k "$LUCI_APP_FILE" | cut -f1)
    log_info "Package size: ${ipk_size}KB"
    
    # Update package list quietly
    log_info "Updating package list..."
    if ! opkg update >/dev/null 2>&1; then
        log_warn "Package list update had issues, but continuing..."
    fi
    
    # Install the package
    if opkg install "$LUCI_APP_FILE"; then
        log_success "luci-app-homeproxy installed successfully"
        return 0
    else
        log_error "Failed to install luci-app-homeproxy"
        return 1
    fi
}

# Install sing-box binary
install_sing_box() {
    log_step "Installing sing-box binary..."
    
    local temp_singbox="${TEMP_DIR}/sing-box-new"
    
    # Download new sing-box
    if ! download_file "$SING_BOX_URL" "$temp_singbox"; then
        return 1
    fi
    
    # Make binary executable
    if ! chmod +x "$temp_singbox"; then
        log_error "Failed to set execute permissions on sing-box"
        return 1
    fi
    
    # Verify binary (basic check)
    if ! file "$temp_singbox" | grep -q "ELF"; then
        log_error "Downloaded file doesn't appear to be a valid ELF binary"
        return 1
    fi
    
    # Get file size before replacement
    local original_size=0
    if [[ -f "$SING_BOX_DEST" ]]; then
        original_size=$(du -k "$SING_BOX_DEST" | cut -f1)
    fi
    
    # Replace existing binary
    if ! mv "$temp_singbox" "$SING_BOX_DEST"; then
        log_error "Failed to move sing-box to $SING_BOX_DEST"
        return 1
    fi
    
    # Verify installation
    if [[ -x "$SING_BOX_DEST" ]]; then
        local new_size=$(du -k "$SING_BOX_DEST" | cut -f1)
        calculate_freed_space "$original_size" "$new_size"
        
        local version
        if version=$("$SING_BOX_DEST" version 2>/dev/null); then
            log_success "sing-box installed successfully: $version"
        else
            log_success "sing-box installed successfully (version check unavailable)"
        fi
        return 0
    else
        log_error "sing-box installation verification failed"
        return 1
    fi
}

# Restart services gracefully
restart_services() {
    log_step "Restarting related services..."
    
    # Restart homeproxy service if it exists
    if [[ -f "/etc/init.d/homeproxy" ]]; then
        log_info "Restarting homeproxy service..."
        if /etc/init.d/homeproxy restart >/dev/null 2>&1; then
            log_success "HomeProxy service restarted successfully"
        else
            log_warn "HomeProxy service restart had issues"
        fi
    else
        log_info "HomeProxy service not found (may need manual start)"
    fi
}

# Final system reboot with countdown
system_reboot() {
    log_step "Installation complete! Preparing for system reboot..."
    
    # Immediate cleanup before reboot
    cleanup_temp_files
    
    log_warn "The system will reboot in 10 seconds."
    log_warn "Press Ctrl+C to cancel and reboot manually later."
    
    for i in {10..1}; do
        echo -ne "⏰ Rebooting in $i seconds... \r"
        sleep 1
    done
    
    log_info "🚀 Rebooting system now..."
    echo
    reboot
}

# =============================================================================
# Main Installation Process
# =============================================================================

main() {
    # Display banner
    echo -e "${COLOR_CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           HomeProxy Installer for GL-AXT1800                ║"
    echo "║               Version: $SCRIPT_VERSION (Storage Optimized)        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
    
    # Get initial disk space
    local initial_space=$(df /tmp | awk 'NR==2 {print $4}')
    
    # Pre-flight checks
    check_root
    check_device
    check_disk_space
    check_internet
    
    # Installation steps
    log_step "Starting optimized HomeProxy installation..."
    
    # Download and install luci-app-homeproxy
    if ! download_file "$LUCI_APP_URL" "$LUCI_APP_FILE"; then
        log_error "Failed to download luci-app-homeproxy"
        exit 1
    fi
    
    if ! install_luci_app; then
        log_error "Failed to install luci-app-homeproxy"
        exit 1
    fi
    
    # Install sing-box binary
    if ! install_sing_box; then
        log_error "Failed to install sing-box binary"
        exit 1
    fi
    
    # Restart services
    restart_services
    
    # Calculate final disk space
    local final_space=$(df /tmp | awk 'NR==2 {print $4}')
    calculate_freed_space "$initial_space" "$final_space"
    
    # Final reboot
    system_reboot
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Usage: $SCRIPT_NAME [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  -v, --version  Show version information"
        echo "  --no-reboot    Install without automatic reboot"
        echo "  --no-cleanup   Skip automatic cleanup (not recommended)"
        echo ""
        exit 0
        ;;
    -v|--version)
        echo "$SCRIPT_NAME version $SCRIPT_VERSION"
        exit 0
        ;;
    --no-reboot)
        # Modify the script to not reboot
        system_reboot() {
            log_success "Installation completed successfully!"
            log_info "Manual reboot recommended: reboot"
            cleanup_temp_files
        }
        ;;
    --no-cleanup)
        # Skip cleanup
        trap '' EXIT
        log_warn "Automatic cleanup disabled - temporary files will remain"
        ;;
esac

# Run main function
main "$@"
