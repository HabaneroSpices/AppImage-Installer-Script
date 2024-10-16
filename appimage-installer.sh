#!/usr/bin/env bash
# Light weight AppImage installer script with proper desktop intergration.
# Author: HabaneroSpices [admin@habanerospices.com]
# Version 1.0

set -euo pipefail

## Global variables
SCRIPT_NAME=$(basename "$0")
DESKTOP_FILE_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons"

log() {
    local -r RED='\033[0;31m' YELLOW='\033[1;33m' GREEN='\033[0;32m' NC='\033[0m'
    local -r YELLOW_BG='\033[43m' BLACK_FG='\033[30m'

    case "$1" in
        info)      printf "${GREEN}[i] ${2}${NC}\n" ;;
        warn)      printf "${YELLOW}[w] ${2}${NC}\n" ;;
        err)       printf "${RED}[e] ${2}${NC}\n" ;;
        highlight) printf "${YELLOW_BG}${BLACK_FG}[h] ${2}${NC}\n" ;;
        *)         echo "WRONG SEVERITY : $1"; return 1 ;;
    esac
}

usage() {
    echo "Usage: $SCRIPT_NAME <path_to_appimage> [install_directory]"
    echo "If install_directory is not provided, it defaults to ~/.local/bin"
    exit 1
}

# Function to clean up temporary directory
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        log info "Cleaning up temporary directory..."
        rm -rf "$TEMP_DIR"
    fi
}

## Main function
# Check if at least one argument is provided
if [ $# -lt 1 ]; then
    usage
fi

## Set variables
APPIMAGE_PATH="$1"
INSTALL_DIR="${2:-$HOME/.local/bin}"

# Check if the AppImage file exists
if [ ! -f "$APPIMAGE_PATH" ]; then
    log error "AppImage file not found."
    exit 1
fi

# Set up trap to call cleanup function if the script exits prematurely
trap cleanup EXIT

# Copy AppImage to temporary directory
log info "Copying AppImage to temporary directory..."
TEMP_DIR=$(mktemp -d)
cp "$APPIMAGE_PATH" "$TEMP_DIR"

## Update appimage path
APPIMAGE_PATH="$TEMP_DIR/$(basename "$APPIMAGE_PATH")"

# Extract AppImage
log info "Extracting AppImage..."
cd "$TEMP_DIR"
chmod +x "$APPIMAGE_PATH"
"$APPIMAGE_PATH" --appimage-extract > /dev/null

# Find desktop file and icon
DESKTOP_FILE=$(find squashfs-root -maxdepth 1 -name "*.desktop" | head -n 1)
ICON_FILE=$(find squashfs-root -maxdepth 1 -name "*.png" -o -name "*.svg" | head -n 1)

if [ -z "$DESKTOP_FILE" ]; then
    log error "No desktop file found in AppImage."
    exit 1
fi

# Install AppImage to custom location
log info "Installing AppImage to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
mv "$APPIMAGE_PATH" "$INSTALL_DIR"

## Update appimage path
APPIMAGE_PATH="$INSTALL_DIR/$(basename "$APPIMAGE_PATH")"

# Move desktop file and icon
log info "Moving desktop file and icon..."
mkdir -p "$DESKTOP_FILE_DIR" "$ICON_DIR"
chmod +x "$DESKTOP_FILE" # This fixes icon issues
cp "$DESKTOP_FILE" "$DESKTOP_FILE_DIR"
if [ -n "$ICON_FILE" ]; then
    # Resolve symlink if the icon is a symlink
    if [ -L "${ICON_FILE}" ]; then
        ICON_FILE=$(readlink -f "${ICON_FILE}")
    fi
    cp "$ICON_FILE" "$ICON_DIR"
else
    log warn "No suitable icon file found in AppImage."
fi

DESKTOP_FILE="$DESKTOP_FILE_DIR/$(basename "$DESKTOP_FILE")"
ICON_FILE="$ICON_DIR/$(basename "$ICON_FILE")"

# Edit desktop file
log info "Updating desktop file..."
DESKTOP_FILE_NAME=$(basename "$DESKTOP_FILE")
ICON_FILE_NAME=$(basename "$ICON_FILE")
sed -i "s|Exec=.*|Exec=$APPIMAGE_PATH|" "$DESKTOP_FILE"
if [ -n "$ICON_FILE" ]; then
    sed -i "s|Icon=.*|Icon=$ICON_FILE|" "$DESKTOP_FILE"
fi

# Add uninstall action to desktop file
log info "Adding uninstall action to desktop file..."
if grep -q "Actions=" "$DESKTOP_FILE"; then
    sed -i "s|Actions=.*|&Uninstall-Proper|" "$DESKTOP_FILE"
else
    echo -e "\nActions=Uninstall-Proper;" >> "$DESKTOP_FILE"
fi
cat >> "$DESKTOP_FILE" << EOF

[Desktop Action Uninstall-Proper]
Name=Uninstall (Proper)
Exec=/usr/bin/rm -f '$APPIMAGE_PATH' '$ICON_FILE' '$DESKTOP_FILE'
EOF

log info "Installation complete!"