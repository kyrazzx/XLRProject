#!/bin/bash


if [ "$1" = "--uninstall" ]; then
    source /opt/T6Server/.config/config.sh
fi

uninstallGameBinaries () {
    {
        rm -rf "$WORKDIR/Server/Multiplayer" "$WORKDIR/Server/Zombie"

        rm -rf "$WORKDIR/Plutonium"

        rm -f "$WORKDIR/Server/Zombie/binkw32.dll" \
              "$WORKDIR/Server/Zombie/codshowLogo.bmp" \
              "$WORKDIR/Server/Multiplayer/binkw32.dll" \
              "$WORKDIR/Server/Multiplayer/codshowLogo.bmp" \
              "$WORKDIR/Server/Zombie/zone" \
              "$WORKDIR/Server/Multiplayer/zone"

        if [ -d "$WORKDIR/Resources" ]; then
            rm -rf "$WORKDIR/Resources"
        fi

        if [ -z "$(ls -A "$WORKDIR")" ]; then
            rm -rf "$WORKDIR"
        fi

    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "uninstall_binary")"
    
    if [ ! -d "$WORKDIR/Server" ] && [ ! -d "$WORKDIR/Plutonium" ]; then
        printf "${COLORS[GREEN]}Success:${COLORS[RESET]} Game binaries have been uninstalled.\n"
    else
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Game binaries uninstallation may have failed.\n"
        printf "You can try manually removing the directories:\n"
        printf "$WORKDIR/Server\n"
        printf "$WORKDIR/Plutonium\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--uninstall" ]; then
    uninstallGameBinaries
else
    echo "Usage: $0 [--uninstall] | [--import]"
    echo "This script uninstalls game binaries. Use --uninstall or no argument to proceed with uninstallation."
fi
