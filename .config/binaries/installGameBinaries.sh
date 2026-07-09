#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installGameBinaries() {
    local log_file="$WORKDIR/logs/install-binaries.log"
    mkdir -p "$WORKDIR/logs"

    {
        mkdir -p "$WORKDIR/Plutonium/storage/t6/"{players,gamesettings,playlists,stats,scripts,mods,logs}
        mkdir -p "$WORKDIR/Server/Multiplayer/usermaps"
        mkdir -p "$WORKDIR/Server/Multiplayer/main/"{configs}
        mkdir -p "$WORKDIR/Server/Zombie/usermaps"
        mkdir -p "$WORKDIR/Server/Zombie/main/"{configs}

        rm -rf /tmp/T6ServerConfigs
        checkAndInstallCommand "git" "git"
        git clone https://github.com/xerxes-at/T6ServerConfigs.git /tmp/T6ServerConfigs
        checkAndInstallCommand "rsync" "rsync"

        if [ -d "/tmp/T6ServerConfigs/localappdata/Plutonium/storage/t6/gamesettings/gamesettings_defaults (REFERENCE ONLY)" ]; then
            mkdir -p "$WORKDIR/Plutonium/storage/t6/gamesettings/default"
            rsync -a --delete "/tmp/T6ServerConfigs/localappdata/Plutonium/storage/t6/gamesettings/gamesettings_defaults (REFERENCE ONLY)/" "$WORKDIR/Plutonium/storage/t6/gamesettings/default"
        fi

        rsync -a "/tmp/T6ServerConfigs/localappdata/Plutonium/storage/t6/dedicated.cfg" "$WORKDIR/Server/Multiplayer/main"
        rsync -a "/tmp/T6ServerConfigs/localappdata/Plutonium/storage/t6/restricted.cfg" "$WORKDIR/Server/Multiplayer/main/config"
        rsync -a "/tmp/T6ServerConfigs/localappdata/Plutonium/storage/t6/dedicated_zm.cfg" "$WORKDIR/Server/Zombie/main"

        if [ -d "/tmp/T6ServerConfigs/localappdata/Plutonium/storage/t6/recipes/mp" ]; then
            mkdir -p "$WORKDIR/Plutonium/storage/t6/recipes"
            rsync -a --delete "/tmp/T6ServerConfigs/localappdata/Plutonium/storage/t6/recipes/mp/" "$WORKDIR/Plutonium/storage/t6/data/recipes/"
        fi

        for file in /tmp/T6ServerConfigs/localappdata/Plutonium/storage/t6/gamesettings/*; do
            rsync -a "$file" "$WORKDIR/Plutonium/storage/t6/gamesettings/"
        done

        rm -rf /tmp/T6ServerConfigs

        if [[ "${manual_game_files:-}" =~ ^[yYoO]$ ]] || manualGameFilesReady; then
            linkGameBinaries || exit 1
        else
            downloadGameFilesTorrent || exit 1
            linkGameBinaries || exit 1
        fi

        if [ ! -f "$WORKDIR/Plutonium/plutonium-updater" ]; then
            cd "$WORKDIR/Plutonium/" || exit
            checkAndInstallCommand "wget" "wget"
            wget -q -O plutonium-updater.tar.gz https://github.com/mxve/plutonium-updater.rs/releases/latest/download/plutonium-updater-x86_64-unknown-linux-gnu.tar.gz
            checkAndInstallCommand "tar" "tar"
            tar xf plutonium-updater.tar.gz plutonium-updater
            rm -f plutonium-updater.tar.gz
            chmod +x plutonium-updater
        fi

        if [ ! -f "$WORKDIR/Plutonium/bin/plutonium-bootstrapper-win32.exe" ]; then
            mkdir -p "$WORKDIR/Plutonium/logs"
            "$WORKDIR/Plutonium/plutonium-updater" -d "$WORKDIR/Plutonium" >> "$WORKDIR/Plutonium/logs/updater.log" 2>&1
        fi

        chmod +x "$WORKDIR/Plutonium/XLRManager.sh" 2>/dev/null || true
        chmod +x "$WORKDIR/Plutonium/lib/server_core.sh" 2>/dev/null || true
        chmod +x "$WORKDIR/.config/xlr/"*.sh 2>/dev/null || true
        chmod +x "$WORKDIR/xlr-configure.sh" 2>/dev/null || true
        chmod +x "$WORKDIR/import-game-files.sh" 2>/dev/null || true
        chmod +x "$WORKDIR/xlr-update.sh" 2>/dev/null || true
    } > "$log_file" 2>&1 &
    showProgressIndicator "$(getMessage "binary")"

    if [ ! -f "$WORKDIR/Plutonium/bin/plutonium-bootstrapper-win32.exe" ] || ! manualGameFilesReady; then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Game binaries installation failed.\n"
        printf "Log: %s\n" "$log_file"
        printf "Plutonium log: %s/Plutonium/logs/updater.log\n" "$WORKDIR"
        printf "Run: sudo ./install-plutonium.sh\n"
        printf "Manual upload help: %s/Resources/binaries/MANUAL_UPLOAD.txt\n" "$WORKDIR"
        printf "Retry: sudo ./import-game-files.sh\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    installGameBinaries
else
    echo "Usage: $0 [--install] | [--import]"
fi
