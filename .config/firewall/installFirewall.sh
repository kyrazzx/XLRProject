#!/bin/bash


if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installFirewall() {
    local ssh_port="$1"
    {
        if ! command -v ufw &> /dev/null; then
            apt install ufw -y
        fi

        if ! command -v fail2ban-client &> /dev/null; then
            apt install fail2ban -y
        fi

        ufw allow "$ssh_port"/tcp
        ufw default allow outgoing
        ufw default deny incoming
        ufw -f enable
    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "firewall_install")"
    
    if ! command -v ufw &> /dev/null || ! command -v fail2ban-client &> /dev/null
    then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Firewall installation failed.\n"
        printf "Attempting reinstallation...\n"
        {
            apt install ufw fail2ban -y
            ufw allow "$ssh_port"/tcp
            ufw default allow outgoing
            ufw default deny incoming
            ufw -f enable
        } > /dev/null 2>&1 &
        showProgressIndicator "$(getMessage "firewall_reinstall")"
        
        if ! command -v ufw &> /dev/null || ! command -v fail2ban-client &> /dev/null
        then
            printf "${COLORS[RED]}Error:${COLORS[RESET]} Reinstallation failed. Please check your internet connection and try again.\n"
            exit 1
        fi
    fi

    if [ "$1" = "--install" ]; then
        printf "${COLORS[GREEN]}Success:${COLORS[RESET]} Firewall has been installed and configured.\n"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    if [ -z "$2" ]; then
        echo "Error: SSH port is required."
        echo "Usage: $0 [--install] <ssh_port>"
        exit 1
    fi
    installFirewall "$2"
elif [ "$1" = "--install" ] && [ -n "$2" ]; then
    installFirewall "$2"
else
    echo "Usage: $0 [--install] <ssh_port> | [--import]"
    echo "This script installs the firewall or imports the configuration. Use --install followed by the SSH port number to proceed with installation or --import to import the configuration."
fi
