#!/bin/bash


if [ "$1" = "--uninstall" ]; then
    source /opt/T6Server/.config/config.sh
fi

uninstallFirewall() {
    {
        if command -v ufw >/dev/null 2>&1; then
            ufw disable
        fi

        if dpkg -l | grep -qE "ufw|fail2ban"; then
            apt-get remove --purge ufw fail2ban -y
        fi

        apt-get autoremove -y
        apt-get autoclean
    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "remove_firewall")"

    if command -v ufw >/dev/null 2>&1 || command -v fail2ban-client >/dev/null 2>&1; then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Firewall uninstallation failed.\n"
        printf "Attempting manual removal...\n"
        apt-get remove --purge ufw fail2ban -y
        apt-get autoremove -y
        apt-get autoclean
        if command -v ufw >/dev/null 2>&1 || command -v fail2ban-client >/dev/null 2>&1; then
            printf "${COLORS[RED]}Error:${COLORS[RESET]} Manual removal failed. Please check your system and try again.\n"
            exit 1
        fi
    fi

    if [ "$1" = "--uninstall" ]; then
        printf "${COLORS[GREEN]}Success:${COLORS[RESET]} Firewall has been uninstalled.\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--uninstall" ]; then
    uninstallFirewall
else
    echo "Usage: $0 [--uninstall | --import]"
    echo "This script uninstalls the firewall. Use --uninstall or --import to proceed with uninstallation."
fi
