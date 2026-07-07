#!/bin/bash

DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEFAULT_DIR/.config/config.sh"
source "$DEFAULT_DIR/.config/function.sh"

if [[ $UID != 0 ]]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

printf "${COLORS[YELLOW]}Stopping aria2 torrent processes...${COLORS[RESET]}\n"
cleanupIncompleteGameDownload

if [ -d "$WORKDIR/Resources/binaries/zone" ]; then
    printf "${COLORS[YELLOW]}Keep manual uploads in Resources/binaries/? (Y/n)${COLORS[RESET]} "
    read -r keep_manual
    case "$keep_manual" in
        n|N|non|no)
            rm -rf "$WORKDIR/Resources/binaries/zone" "$WORKDIR/Resources/binaries/binkw32.dll"
            printf "Removed Resources/binaries/zone and binkw32.dll\n"
            ;;
        *)
            printf "Kept Resources/binaries/ (manual files preserved)\n"
            ;;
    esac
fi

printf "${COLORS[GREEN]}Cleanup complete.${COLORS[RESET]}\n"
