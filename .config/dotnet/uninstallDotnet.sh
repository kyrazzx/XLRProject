#!/bin/bash

if [ "$1" = "--uninstall" ]; then
    source /opt/T6Server/.config/config.sh
fi

uninstallDotnet() {
    {
        if dpkg -l | grep -qE "aspnetcore-runtime-8.0|aspnetcore-runtime-7.0"; then
            local runtime_pkg
            runtime_pkg=$(getAspnetRuntimePackage)
            if [ -n "$runtime_pkg" ]; then
                apt-get remove --purge "$runtime_pkg" -y
            else
                apt-get remove --purge aspnetcore-runtime-8.0 aspnetcore-runtime-7.0 -y
            fi
        fi

        if [ -f /etc/apt/sources.list.d/microsoft-prod.list ]; then
            rm /etc/apt/sources.list.d/microsoft-prod.list
        fi

        if [ -f /etc/apt/trusted.gpg.d/microsoft.asc.gpg ]; then
            rm /etc/apt/trusted.gpg.d/microsoft.asc.gpg
        fi

        apt-get update
    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "uninstallDotnet")"
    
    if ! dpkg -l | grep -qE "aspnetcore-runtime-8.0|aspnetcore-runtime-7.0"; then
        printf "${COLORS[GREEN]}Success:${COLORS[RESET]} .NET has been uninstalled.\n"
    else
        printf "${COLORS[RED]}Error:${COLORS[RESET]} .NET uninstallation may have failed.\n"
        printf "You can try manually removing .NET using:\n"
        printf "sudo apt-get remove --purge aspnetcore-runtime-8.0 aspnetcore-runtime-7.0\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--uninstall" ]; then
    uninstallDotnet
else
    echo "Usage: $0 [--uninstall]"
    echo "This script uninstalls .NET. Use --uninstall or no argument to proceed with uninstallation."
fi
