#!/bin/bash


if [ "$1" = "--uninstall" ]; then
    source /opt/T6Server/.config/config.sh
fi

uninstallWine() {
    {
        if dpkg -l | grep -q winehq-stable; then
            apt-get remove --purge winehq-stable -y
        fi

        rm -f /etc/apt/sources.list.d/wine.list
        rm -f /etc/apt/sources.list.d/winehq-*.sources
        rm -f /etc/apt/trusted.gpg.d/winehq.asc
        rm -f /etc/apt/keyrings/winehq-archive.key

        sed -i '/WINEPREFIX/d' ~/.bashrc
        sed -i '/WINEDEBUG/d' ~/.bashrc
        sed -i '/WINEARCH/d' ~/.bashrc
        sed -i '/WINEESYNC/d' ~/.bashrc
        sed -i '/WINEFSYNC/d' ~/.bashrc
        sed -i '/WINEDLLOVERRIDES/d' ~/.bashrc

        if [ -d "$HOME/.wine" ]; then
            rm -rf "$HOME/.wine"
        fi

        apt-get update
    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "uninstallWine")"
    
    if ! dpkg -l | grep -q winehq-stable; then
        printf "${COLORS[GREEN]}Success:${COLORS[RESET]} Wine has been uninstalled.\n"
    else
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Wine uninstallation may have failed.\n"
        printf "You can try manually removing Wine using:\n"
        printf "sudo apt-get remove --purge winehq-stable\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--uninstall" ]; then
    uninstallWine
else
    echo "Usage: $0 [--uninstall] | [--import]"
    echo "This script uninstalls Wine. Use --uninstall or no argument to proceed with uninstallation."
fi
