#!/bin/bash


if [ "$1" = "--enable" ]; then
    source /opt/T6Server/.config/config.sh
fi

enable32BitPackages() {
    {
        if ! dpkg --print-foreign-architectures | grep -q i386; then
            dpkg --add-architecture i386
            apt-get update -y
        fi
    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "bit")"
    
    if ! dpkg --print-foreign-architectures | grep -q i386; then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} 32-bit package activation failed.\n"
        printf "Attempting reactivation...\n"
        dpkg --add-architecture i386
        apt-get update -y
        if ! dpkg --print-foreign-architectures | grep -q i386; then
            printf "${COLORS[RED]}Error:${COLORS[RESET]} Reactivation failed. Please check your system and try again.\n"
            exit 1
        fi
    fi

    if [ "$1" = "--enable" ]; then
        printf "${COLORS[GREEN]}Success:${COLORS[RESET]} 32-bit architecture support has been enabled.\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--enable" ]; then
    enable32BitPackages
else
    echo "Usage: $0 [--enable] | [--import]"
    echo "This script enables 32-bit architecture support. Use --enable or no argument to proceed with enabling."
fi
