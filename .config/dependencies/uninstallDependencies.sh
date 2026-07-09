#!/bin/bash


if [ "$1" = "--uninstall" ]; then
    source /opt/T6Server/.config/config.sh
fi

uninstallDependencies() {
    {
        apt-get remove -y software-properties-common apt-transport-https
        apt-get autoremove -y
    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "cleanup")"
    
    if dpkg -s software-properties-common &> /dev/null || dpkg -s apt-transport-https &> /dev/null
    then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Dependencies uninstallation failed.\n"
        printf "Attempting manual removal...\n"
        apt-get remove -y software-properties-common apt-transport-https
        apt-get autoremove -y
        if dpkg -s software-properties-common &> /dev/null || dpkg -s apt-transport-https &> /dev/null
        then
            printf "${COLORS[RED]}Error:${COLORS[RESET]} Manual removal failed. Some dependencies may still be present.\n"
        else
            printf "${COLORS[GREEN]}Success:${COLORS[RESET]} Dependencies have been manually removed.\n"
        fi
    else
        if [ "$1" = "--uninstall" ]; then
            printf "${COLORS[GREEN]}Success:${COLORS[RESET]} Dependencies have been uninstalled.\n"
        fi
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--uninstall" ]; then
    uninstallDependencies
else
    echo "Usage: $0 [--uninstall] | [--import]"
    echo "This script uninstalls dependencies. Use --uninstall or no argument to proceed with uninstallation."
fi
