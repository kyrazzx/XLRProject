#!/bin/bash

DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEFAULT_DIR/.config/config.sh"
source "$DEFAULT_DIR/.config/function.sh"

if [[ $UID != 0 ]]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

selectLanguage 2>/dev/null || true

printf "\n${COLORS[CYAN]}XLR manual game files import${COLORS[RESET]}\n\n"

if ! verifyManualGameFiles; then
    exit 1
fi

if ! linkGameBinaries; then
    exit 1
fi

source "$DEFAULT_DIR/.config/xlr/repairPermissions.sh"
xlr_repair_permissions "$WORKDIR"

if [ ! -f "$WORKDIR/Plutonium/plutonium-updater" ]; then
    mkdir -p "$WORKDIR/Plutonium"
    cd "$WORKDIR/Plutonium/" || exit 1
    checkAndInstallCommand "wget" "wget"
    wget -q -O plutonium-updater.tar.gz https://github.com/mxve/plutonium-updater.rs/releases/latest/download/plutonium-updater-x86_64-unknown-linux-gnu.tar.gz
    tar xf plutonium-updater.tar.gz plutonium-updater
    rm -f plutonium-updater.tar.gz
    chmod +x plutonium-updater
fi

if [ ! -f "$WORKDIR/Plutonium/bin/plutonium-bootstrapper-win32.exe" ]; then
    mkdir -p "$WORKDIR/Plutonium/logs"
    "$WORKDIR/Plutonium/plutonium-updater" -d "$WORKDIR/Plutonium" >> "$WORKDIR/Plutonium/logs/updater.log" 2>&1
fi

printf "\n${COLORS[GREEN]}Game files linked successfully.${COLORS[RESET]}\n"
printf "Continue with: sudo ./install.sh (skip torrent) or sudo ./xlr-configure.sh\n"
