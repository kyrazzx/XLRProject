#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

downloadGameTorrent() {
    local torrent_path="$WORKDIR/Resources/sources/pluto_t6_full_game.torrent"
    if [ -f "$torrent_path" ]; then
        return 0
    fi

    mkdir -p "$WORKDIR/Resources/sources"
    checkAndInstallCommand "wget" "wget"

    local urls=(
        "https://github.com/Sterbweise/T6Server/raw/main/Resources/sources/pluto_t6_full_game.torrent"
        "https://github.com/Sterbweise/T6Server/raw/master/Resources/sources/pluto_t6_full_game.torrent"
        "https://raw.githubusercontent.com/Sterbweise/T6Server/main/Resources/sources/pluto_t6_full_game.torrent"
    )

    for url in "${urls[@]}"; do
        if wget -q --method=HEAD "$url" 2>/dev/null || curl -fsI "$url" >/dev/null 2>&1; then
            wget -q -O "$torrent_path" "$url" && return 0
        fi
    done

    printf "${COLORS[RED]}Error:${COLORS[RESET]} Game torrent not found.\n"
    printf "Place pluto_t6_full_game.torrent in Resources/sources/\n"
    return 1
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    downloadGameTorrent
else
    echo "Usage: $0 [--install] | [--import]"
fi
