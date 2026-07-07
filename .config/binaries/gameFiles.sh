#!/bin/bash

verifyManualGameFiles() {
    local binaries_dir="$WORKDIR/Resources/binaries"
    local missing=0
    local zone_count=0

    mkdir -p "$binaries_dir"

    if [ ! -d "$binaries_dir/zone" ]; then
        printf "${COLORS[RED]}Missing:${COLORS[RESET]} %s/zone/\n" "$binaries_dir"
        missing=1
    else
        zone_count=$(find "$binaries_dir/zone" -type f \( -name "*.ff" -o -name "*.FF" \) 2>/dev/null | wc -l)
        if [ "$zone_count" -lt 1 ]; then
            printf "${COLORS[RED]}Missing:${COLORS[RESET]} no .ff files in %s/zone/\n" "$binaries_dir"
            missing=1
        fi
    fi

    if [ ! -f "$binaries_dir/binkw32.dll" ]; then
        printf "${COLORS[RED]}Missing:${COLORS[RESET]} %s/binkw32.dll\n" "$binaries_dir"
        missing=1
    fi

    if [ "$missing" -ne 0 ]; then
        printf "\n${COLORS[YELLOW]}%s${COLORS[RESET]}\n" "$(getMessage "manual_upload_help")"
        printf "  %s/zone/\n" "$binaries_dir"
        printf "  %s/binkw32.dll\n" "$binaries_dir"
        return 1
    fi

    printf "${COLORS[GREEN]}OK:${COLORS[RESET]} %s zone files found in %s/zone/\n" "$zone_count" "$binaries_dir"
    return 0
}

manualGameFilesReady() {
    local binaries_dir="$WORKDIR/Resources/binaries"
    [ -d "$binaries_dir/zone" ] && [ -f "$binaries_dir/binkw32.dll" ] && \
        [ "$(find "$binaries_dir/zone" -type f \( -name "*.ff" -o -name "*.FF" \) 2>/dev/null | wc -l)" -ge 1 ]
}

linkGameBinaries() {
    local binaries_dir="$WORKDIR/Resources/binaries"
    mkdir -p "$binaries_dir"
    verifyManualGameFiles || return 1

    for dir in Zombie Multiplayer; do
        mkdir -p "$WORKDIR/Server/$dir"
        ln -sfn "$binaries_dir/zone" "$WORKDIR/Server/$dir/zone"
        ln -sfn "$binaries_dir/binkw32.dll" "$WORKDIR/Server/$dir/binkw32.dll"
    done
    return 0
}

downloadGameFilesTorrent() {
    local torrent_path="$WORKDIR/Resources/sources/pluto_t6_full_game.torrent"
    local log_file="$WORKDIR/logs/torrent-download.log"

    mkdir -p "$WORKDIR/logs"
    downloadGameTorrent || return 1

    if [ ! -f "$torrent_path" ]; then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Torrent file not found: %s\n" "$torrent_path"
        return 1
    fi

    checkAndInstallCommand "aria2c" "aria2"
    rm -rf /tmp/pluto_t6_full_game /tmp/pluto_t6_full_game.*

    local select_files
    select_files=$(aria2c -S "$torrent_path" 2>/dev/null | grep -E "zone/|binkw32.dll" | cut -d'|' -f1 | tr '\n' ',' | sed 's/,$//')
    if [ -z "$select_files" ]; then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Unable to parse torrent file list.\n"
        return 1
    fi

    printf "${COLORS[CYAN]}Torrent download log:${COLORS[RESET]} %s\n" "$log_file"
    aria2c --dir=/tmp --seed-time=0 --console-log-level=notice --summary-interval=5 \
        --select-file="$select_files" "$torrent_path" 2>&1 | tee "$log_file"

    if [ ! -d "/tmp/pluto_t6_full_game/zone" ] || [ ! -f "/tmp/pluto_t6_full_game/binkw32.dll" ]; then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Torrent download incomplete.\n"
        printf "Use manual upload or run: sudo ./cleanup-download.sh\n"
        return 1
    fi

    mkdir -p "$WORKDIR/Resources/binaries"
    rsync -a "/tmp/pluto_t6_full_game/zone" "$WORKDIR/Resources/binaries/"
    rsync -a "/tmp/pluto_t6_full_game/binkw32.dll" "$WORKDIR/Resources/binaries/binkw32.dll"
    rm -rf /tmp/pluto_t6_full_game /tmp/pluto_t6_full_game.*
    return 0
}

cleanupIncompleteGameDownload() {
    pkill -f "aria2c.*pluto_t6_full_game" 2>/dev/null || true
    rm -rf /tmp/pluto_t6_full_game /tmp/pluto_t6_full_game.* /tmp/aria2*.log 2>/dev/null
    printf "${COLORS[GREEN]}Done:${COLORS[RESET]} Removed incomplete torrent data from /tmp\n"
}
