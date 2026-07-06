#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installDotnet() {
    {
        checkAndInstallCommand "wget" "wget"
        if ! command -v dotnet &> /dev/null; then
            installMicrosoftDotnetRepo

            local runtime_pkg
            runtime_pkg=$(getAspnetRuntimePackage)
            if [ -z "$runtime_pkg" ]; then
                printf "${COLORS[RED]}Error:${COLORS[RESET]} Unsupported distribution: ${DISTRO} ${VERSION}\n"
                exit 1
            fi

            if ! dpkg -s "$runtime_pkg" &> /dev/null; then
                apt-get install -y "$runtime_pkg"
            fi

            apt-get clean
            apt-get autoremove -y
        fi
    } > /var/log/dotnet_install.log 2>&1 &
    showProgressIndicator "$(getMessage "dotnet_install")"
    
    if ! command -v dotnet &> /dev/null
    then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Dotnet installation failed.\n"
        printf "Attempting reinstallation...\n"
        local runtime_pkg
        runtime_pkg=$(getAspnetRuntimePackage)
        if [ -n "$runtime_pkg" ]; then
            apt-get install -y "$runtime_pkg"
        fi
        if ! command -v dotnet &> /dev/null
        then
            printf "${COLORS[RED]}Error:${COLORS[RESET]} Reinstallation failed. Please check your internet connection and try again.\n"
            exit 1
        fi
    fi

    if [ "$1" = "--install" ]; then
        printf "${COLORS[GREEN]}Success:${COLORS[RESET]} .NET has been installed.\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    installDotnet
else
    echo "Usage: $0 [--install] | [--import]"
    echo "This script installs .NET or imports the configuration. Use --install or --import to proceed with installation or import."
fi
