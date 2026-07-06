#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installWine() {
    {
        local wine_suite wine_family sources_file sources_url

        wine_suite=$(resolveWineSuite)
        wine_family=$(resolveWineRepoFamily)

        if [ ! -f /etc/apt/keyrings/winehq-archive.key ]; then
            mkdir -pm755 /etc/apt/keyrings
            wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
        fi

        sources_file="/etc/apt/sources.list.d/winehq-${wine_suite}.sources"
        if [ ! -f "$sources_file" ]; then
            sources_url="https://dl.winehq.org/wine-builds/${wine_family}/dists/${wine_suite}/winehq-${wine_suite}.sources"
            wget -O "$sources_file" "$sources_url"
        fi

        if ! dpkg -l | grep -q winehq-stable; then
            apt update -y
            apt install --install-recommends winehq-stable -y
        fi

        if [ ! -d "$HOME/.wine" ]; then
            declare -A wine_vars=(
                ["WINEPREFIX"]="$HOME/.wine"
                ["WINEDEBUG"]="-all"
                ["WINEARCH"]="win64"
                ["WINEESYNC"]="1"
                ["WINEFSYNC"]="1"
                ["WINEDLLOVERRIDES"]="mscoree,mshtml="
            )

            for var in "${!wine_vars[@]}"; do
                if ! grep -q "$var" "$HOME/.bashrc"; then
                    echo "export $var=${wine_vars[$var]}" >> "$HOME/.bashrc"
                fi
            done
            
            # shellcheck source=/dev/null
            source "$HOME/.bashrc"
            
            wineboot --init 2>/dev/null || true
        fi
    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "wine")"
    
    if ! command -v wine &> /dev/null; then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Wine installation failed.\n"
        printf "You can try running the installation script separately by executing:\n"
        printf "cd .config/wine && ./installWine.sh --install\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    installWine
else
    echo "Usage: $0 [--install] | [--import]"
    echo "This script installs Wine. Use --install or no argument to proceed with installation."
fi
