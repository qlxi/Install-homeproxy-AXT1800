#!/bin/sh
# ============================================================
# HomeProxy One-Click Installer for GL-AXT1800 (OpenWrt v4.8.2)
# Author: qlxi
# ============================================================

set -e

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

# Vars
PKG_URL="https://github.com/qlxi/Install-homeproxy-AXT1800/releases/download/homeproxy/luci-app-homeproxy.ipk"
BIN_URL="https://github.com/qlxi/Install-homeproxy-AXT1800/releases/download/homeproxy/sing-box"
PKG_FILE="/tmp/luci-app-homeproxy.ipk"
BIN_FILE="/usr/bin/sing-box"
REQUIRED_MB=35

# Typing animation
print_slow() {
    str="$1"
    delay=${2:-0.01}
    while IFS= read -r -n1 char; do
        printf "%s" "$char"
        sleep "$delay"
    done <<< "$str"
    printf "\n"
}

clear
echo -e "${CYAN}============================================================${RESET}"
print_slow "   🚀 ${BOLD}HomeProxy Installer for GL-AXT1800 (OpenWrt v4.8.2)${RESET}" 0.02
echo -e "${CYAN}============================================================${RESET}"
sleep 1

# Step 0: Check if already installed
INSTALLED=0
if opkg list-installed | grep -q "luci-app-homeproxy"; then
    echo -e "   ${YELLOW}🔎 HomeProxy is already installed${RESET}"
    INSTALLED=1
fi
if [ -f "$BIN_FILE" ]; then
    echo -e "   ${YELLOW}🔎 sing-box binary already exists at $BIN_FILE${RESET}"
    INSTALLED=1
fi

if [ "$INSTALLED" -eq 1 ]; then
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}HomeProxy and/or sing-box are already installed.${RESET}"
    printf "Do you want to ${BOLD}reinstall${RESET} them? [y/N]: "
    read -r REPLY
    if [ ! "$REPLY" = "y" ] && [ ! "$REPLY" = "Y" ]; then
        echo -e "   ${RED}❌ Installation aborted by user${RESET}"
        exit 0
    else
        echo -e "   ${CYAN}🔄 Proceeding with reinstallation (memory check skipped)...${RESET}"
    fi
else
    # Step 0.1: Check free space only if not already installed
    echo -e "[0/4] ${CYAN}Checking free space...${RESET}"
    FREE_KB=$(df /overlay | awk 'NR==2 {print $4}')
    FREE_MB=$((FREE_KB / 1024))

    if [ "$FREE_MB" -lt "$REQUIRED_MB" ]; then
        echo -e "   ${RED}❌ Not enough space! Required: ${REQUIRED_MB}MB, Available: ${FREE_MB}MB${RESET}"
        echo -e "   ${YELLOW}💡 Please free up space before running the installer.${RESET}"
        exit 1
    else
        echo -e "   ${GREEN}✅ Free space OK: ${FREE_MB}MB available${RESET}"
    fi
fi

# Step 1: Download luci-app-homeproxy.ipk
echo -e "[1/4] ${CYAN}Downloading luci-app-homeproxy.ipk...${RESET}"
if wget -q -O "$PKG_FILE" "$PKG_URL"; then
    echo -e "   ${GREEN}✅ Package downloaded to $PKG_FILE${RESET}"
else
    echo -e "   ${RED}❌ Failed to download luci-app-homeproxy.ipk${RESET}"
    exit 1
fi

# Step 2: Install package with opkg
echo -e "[2/4] ${CYAN}Installing luci-app-homeproxy...${RESET}"
if opkg install "$PKG_FILE"; then
    echo -e "   ${GREEN}✅ luci-app-homeproxy installed successfully${RESET}"
    rm -f "$PKG_FILE"
    echo -e "   ${CYAN}🗑️ Removed $PKG_FILE to free up space${RESET}"
else
    echo -e "   ${RED}❌ Package installation failed${RESET}"
    rm -f "$PKG_FILE"
    exit 1
fi

# Step 3: Stop sing-box if running, remove old binary, then download new
echo -e "[3/4] ${CYAN}Updating sing-box binary...${RESET}"
if pgrep -x "sing-box" >/dev/null 2>&1; then
    echo -e "   ${YELLOW}⚠️ sing-box is currently running, stopping it...${RESET}"
    killall -9 sing-box || true
    sleep 1
fi

if [ -f "$BIN_FILE" ]; then
    echo -e "   ${CYAN}🗑️ Removing old sing-box binary to free space...${RESET}"
    rm -f "$BIN_FILE"
fi

echo -e "   ${CYAN}🔽 Downloading new sing-box binary...${RESET}"
if wget -O "$BIN_FILE" "$BIN_URL"; then
    chmod +x "$BIN_FILE"
    echo -e "   ${GREEN}✅ sing-box replaced at $BIN_FILE${RESET}"
    ls -lh "$BIN_FILE"
else
    echo -e "   ${RED}❌ Failed to download sing-box binary${RESET}"
    exit 1
fi

# Optionally restart sing-box immediately (before reboot)
if [ -x "$BIN_FILE" ]; then
    echo -e "   ${CYAN}🔄 Restarting sing-box...${RESET}"
    "$BIN_FILE" >/dev/null 2>&1 &
    echo -e "   ${GREEN}✅ sing-box started${RESET}"
fi

# Step 4: Reboot router
echo -e "[4/4] ${CYAN}Rebooting router to apply changes...${RESET}"
sleep 2
reboot

exit 0
