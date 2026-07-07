#!/bin/bash

DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEFAULT_DIR/.config/config.sh"

if [[ $UID != 0 ]]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

PLUTONIUM_DIR="$WORKDIR/Plutonium"
BOOTSTRAPPER="$PLUTONIUM_DIR/bin/plutonium-bootstrapper-win32.exe"
UPDATER="$PLUTONIUM_DIR/plutonium-updater"

mkdir -p "$PLUTONIUM_DIR/logs"

if [ ! -x "$UPDATER" ]; then
    printf "Downloading plutonium-updater...\n"
    cd "$PLUTONIUM_DIR" || exit 1
    wget -q -O plutonium-updater.tar.gz https://github.com/mxve/plutonium-updater.rs/releases/latest/download/plutonium-updater-x86_64-unknown-linux-gnu.tar.gz
    tar xf plutonium-updater.tar.gz plutonium-updater
    rm -f plutonium-updater.tar.gz
    chmod +x plutonium-updater
fi

if [ -f "$BOOTSTRAPPER" ]; then
    chmod +x "$BOOTSTRAPPER" 2>/dev/null || true
    printf "Plutonium bootstrapper already installed: %s\n" "$BOOTSTRAPPER"
    exit 0
fi

printf "Downloading Plutonium server files (this may take a few minutes)...\n"
"$UPDATER" -d "$PLUTONIUM_DIR" 2>&1 | tee "$PLUTONIUM_DIR/logs/updater.log"

if [ -f "$BOOTSTRAPPER" ]; then
    chmod +x "$BOOTSTRAPPER" 2>/dev/null || true
    printf "Success: %s\n" "$BOOTSTRAPPER"
    exit 0
fi

printf "Failed to install Plutonium bootstrapper.\n"
printf "Check log: %s/logs/updater.log\n" "$PLUTONIUM_DIR"
exit 1
