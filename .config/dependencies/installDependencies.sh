#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installDependencies() {
    {
        apt-get update
        apt-get install -y \
            sudo \
            aria2 \
            tar \
            wget \
            gnupg2 \
            software-properties-common \
            apt-transport-https \
            curl \
            rsync \
            procps \
            jq \
            bc \
            netcat-openbsd \
            python3 \
            python3-venv \
            python3-pip \
            unzip \
            ca-certificates

        installPlatformLibraries

    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "dependencies_install")"
    
    if ! command -v wget &> /dev/null || ! command -v gpg &> /dev/null || ! command -v curl &> /dev/null || ! dpkg -s software-properties-common &> /dev/null || ! dpkg -s apt-transport-https &> /dev/null
    then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Dependencies installation failed.\n"
        printf "Attempting reinstallation...\n"
        apt-get install -y sudo wget gnupg2 software-properties-common apt-transport-https curl ca-certificates
        installPlatformLibraries
        if ! command -v wget &> /dev/null || ! command -v gpg &> /dev/null || ! command -v curl &> /dev/null || ! dpkg -s software-properties-common &> /dev/null || ! dpkg -s apt-transport-https &> /dev/null
        then
            printf "${COLORS[RED]}Error:${COLORS[RESET]} Reinstallation failed. Please check your internet connection and try again.\n"
            exit 1
        fi
    fi
    
    if [ "$1" = "--install" ]; then
        printf "${COLORS[GREEN]}Success:${COLORS[RESET]} Dependencies have been installed.\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    installDependencies
else
    echo "Usage: $0 [--install] | [--import]"
    echo "This script installs dependencies. Use --install or no argument to proceed with installation."
fi
