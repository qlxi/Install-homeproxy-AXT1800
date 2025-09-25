#!/bin/sh
# ============================================================
# HomeProxy One-Click Installer for GL-AXT1800 (OpenWrt v4.8.2)
# Author: qlxi
# ============================================================

set -e

PKG_URL="https://github.com/qlxi/Install-homeproxy-AXT1800/releases/download/homeproxy/luci-app-homeproxy.ipk"
BIN_URL="https://github.com/qlxi/Install-homeproxy-AXT1800/releases/download/homeproxy/sing-box"
PKG_FILE="/tmp/luci-app-homeproxy.ipk"
BIN_FILE="/usr/bin/sing-box"
REQUIRED_MB=35

echo "============================================================"
echo "   🚀 HomeProxy Installer for GL-AXT1800 (OpenWrt v4.8.2)"
echo "============================================================"
sleep 1

# Step 0: Check if already installed
INSTALLED=0
if opkg list-installed | grep -q "luci-app-homeproxy"; then
    echo "   🔎 HomeProxy is already installed"
    INSTALLED=1
fi
if [ -f "$BIN_FILE" ]; then
    echo "   🔎 sing-box binary already exists at $BIN_FILE"
    INSTALLED=1
fi

if [ "$INSTALLED" -eq 1 ]; then
    echo "============================================================"
    echo "HomeProxy and/or sing-box are already installed."
    printf "Do you want to reinstall them? [y/N]: "
    read -r REPLY
    if [ ! "$REPLY" = "y" ] && [ ! "$REPLY" = "Y" ]; then
        echo "   ❌ Installation aborted by user"
        exit 0
    else
        echo "   🔄 Proceeding with reinstallation (memory check skipped)..."
    fi
else
    # Step 0.1: Check free space only if not already installed
    echo "[0/4] Checking free space..."
    FREE_KB=$(df /overlay | awk 'NR==2 {print $4}')
    FREE_MB=$((FREE_KB / 1024))

    if [ "$FREE_MB" -lt "$REQUIRED_MB" ]; then
        echo "   ❌ Not enough space! Required: ${REQUIRED_MB}MB, Available: ${FREE_MB}MB"
        echo "   💡 Please free up space before running the installer."
        exit 1
    else
        echo "   ✅ Free space OK: ${FREE_MB}MB available"
    fi
fi

# Step 1: Download luci-app-homeproxy.ipk
echo "[1/4] Downloading luci-app-homeproxy.ipk..."
if wget -q -O "$PKG_FILE" "$PKG_URL"; then
    echo "   ✅ Package downloaded to $PKG_FILE"
else
    echo "   ❌ Failed to download luci-app-homeproxy.ipk"
    exit 1
fi

# Step 2: Install package with opkg
echo "[2/4] Installing luci-app-homeproxy..."
if opkg install "$PKG_FILE"; then
    echo "   ✅ luci-app-homeproxy installed successfully"
    rm -f "$PKG_FILE"
    echo "   🗑️ Removed $PKG_FILE to free up space"
else
    echo "   ❌ Package installation failed"
    rm -f "$PKG_FILE"
    exit 1
fi

# Step 3: Download and replace sing-box binary
echo "[3/4] Updating sing-box binary..."
if wget -q -O "$BIN_FILE" "$BIN_URL"; then
    chmod +x "$BIN_FILE"
    echo "   ✅ sing-box replaced at $BIN_FILE"
else
    echo "   ❌ Failed to download sing-box binary"
    exit 1
fi

# Step 4: Reboot router
echo "[4/4] Rebooting router to apply changes..."
sleep 2
reboot

exit 0
