# Description:
# This script contains the finishInstallation function, which is used to display
# a summary of the server installation and offer to display server information.

# Usage:
# This script is used to display a summary of the server installation and offer to display server information.

# Note:
# This script should be called after the server installation is complete.

finishInstallation() {
    showLogo
    printf "\n${COLORS[GREEN]}%s${COLORS[RESET]}\n" "$(getMessage "finish")"
    printf "\n${COLORS[YELLOW]}%s${COLORS[RESET]}\n" "$(getMessage "quit")"
    
    # Display summary of installed components
    printf "\n${COLORS[CYAN]} Installation Summary:${COLORS[RESET]}\n"
    
    if command -v ufw &> /dev/null ; then
        printf " - ${COLORS[GREEN]}✓${COLORS[RESET]} Firewall installed (SSH port: %s)\n" "${ssh_port:-22}"
    else
        printf " - ${COLORS[RED]}✕${COLORS[RESET]} Firewall not installed (${COLORS[ORANGE]}Optional${COLORS[RESET]})\n"
    fi
    
    if command -v dotnet &> /dev/null ; then
        printf " - ${COLORS[GREEN]}✓${COLORS[RESET]} .NET Framework installed\n"
    else
        printf " - ${COLORS[RED]}✕${COLORS[RESET]} .NET Framework not installed (${COLORS[ORANGE]}Optional${COLORS[RESET]})\n"
    fi
    
    if command -v wine &> /dev/null ; then
        printf " - ${COLORS[GREEN]}✓${COLORS[RESET]} Wine installed\n"
    else
        printf " - ${COLORS[RED]}✕${COLORS[RESET]} Wine not installed (${COLORS[ORANGE]}Optional${COLORS[RESET]})\n"
    fi

    printf " - ${COLORS[GREEN]}✓${COLORS[RESET]} Game binaries installed\n"
    
    # Display server information directly without asking
    printf "\n${COLORS[CYAN]} Server Information:${COLORS[RESET]}\n"
    printf " - Installation Directory: %s\n" "${WORKDIR:-/opt/T6Server}"
    printf " - Operating System: %s %s\n" "${DISTRO^}" "$VERSION"

    # Network Information
    printf "\n${COLORS[CYAN]} Host Information:${COLORS[RESET]}\n"
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || echo "Unknown")
    HOSTNAME=$(hostname)
    
    printf " - Hostname: %s\n" "$HOSTNAME"
    printf " - Local IP: %s\n" "${LOCAL_IP:-Unknown}"
    printf " - Public IP: %s\n" "${PUBLIC_IP}"
    
    # System Resources
    printf "\n${COLORS[CYAN]} System Resources:${COLORS[RESET]}\n"
    checkAndInstallCommand "free" "procps"
    TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
    FREE_RAM=$(free -h | awk '/^Mem:/ {print $4}')
    CPU_INFO=$(lscpu | grep "Model name" | cut -d ':' -f2 | xargs)
    DISK_SPACE=$(df -h "${WORKDIR:-/opt/T6Server}" | awk 'NR==2 {print $4}')
    
    printf " - CPU: %s\n" "$CPU_INFO"
    printf " - Total RAM: %s\n" "$TOTAL_RAM"
    printf " - Available RAM: %s\n" "$FREE_RAM"
    printf " - Available Disk Space: %s\n" "$DISK_SPACE"
    
    # Network Ports Status
    printf " - Network Ports Status:\n"
    if command -v netstat &> /dev/null; then
        printf "   ⚬ SSH Port (%s): %s\n" "${ssh_port:-22}" \
            "$(netstat -tuln | grep ":${ssh_port:-22}" > /dev/null && echo "${COLORS[GREEN]}Open${COLORS[RESET]}" || echo "${COLORS[RED]}Closed${COLORS[RESET]}")"
    fi
    
    if [ -f "${WORKDIR}/Plutonium/XLRManager.sh" ]; then
        printf " - ${COLORS[GREEN]}✓${COLORS[RESET]} XLR multi-server manager installed\n"
    fi

    if [ -f "${WORKDIR}/IW4MAdmin/StartIW4MAdmin.sh" ]; then
        printf " - ${COLORS[GREEN]}✓${COLORS[RESET]} IW4MAdmin installed\n"
    fi

    if [ -f "${WORKDIR}/Resources/discord/venv/bin/python" ]; then
        printf " - ${COLORS[GREEN]}✓${COLORS[RESET]} Discord bot environment ready\n"
    fi

    printf "\n${COLORS[CYAN]} XLR Management:${COLORS[RESET]}\n"
    printf " - Config: %s/Plutonium/server_config.json\n" "${WORKDIR:-/opt/T6Server}"
    printf " - Mono server: %s/Plutonium/T6Server.sh\n" "${WORKDIR:-/opt/T6Server}"
    printf " - Multi server: %s/Plutonium/XLRManager.sh [start|stop|status|monitor]\n" "${WORKDIR:-/opt/T6Server}"
    printf " - Systemd: systemctl start xlr-manager.service\n"
    printf " - IW4MAdmin: http://%s:%s\n" "${PUBLIC_IP}" "$(jq -r '.iw4madmin_config.web_port // 1624' "${WORKDIR}/Plutonium/server_config.json" 2>/dev/null || echo 1624)"
    printf " - Configure discord token in server_config.json if skipped during install\n"

    # Wait for user acknowledgment
    printf "\n${COLORS[YELLOW]}Press any key to exit...${COLORS[RESET]}"
    stty sane
    read -r 
    echo
    exit 0
}