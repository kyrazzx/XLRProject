#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installDiscordBot() {
    source "$WORKDIR/.config/xlr/installXlrPython.sh" --import
    installXlrPython
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    installDiscordBot
else
    echo "Usage: $0 [--install] | [--import]"
fi
