#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installXLRStack() {
    checkAndInstallCommand "jq" "jq"
    checkAndInstallCommand "bc" "bc"
    checkAndInstallCommand "netcat-openbsd" "netcat-openbsd"

    generateServerConfig
    applyServerCredentials
    setupSecurityConfig 2>/dev/null || true

    if [[ "${xlr_backups:-yes}" =~ ^[yYoO]$ ]] || [[ -z "${xlr_backups}" ]]; then
        bash "$WORKDIR/.config/xlr/runBackup.sh" "$WORKDIR/Plutonium/server_config.json" 2>/dev/null || true
    fi

    if [[ "${xlr_iw4madmin:-}" =~ ^[yYoO]$ ]] || [[ -z "${xlr_iw4madmin}" && "${dotnet:-}" =~ ^[yYoO]$ ]]; then
        if command -v dotnet &> /dev/null; then
            installIW4MAdmin
            configureIW4MAdmin
        fi
    fi

    if [[ "${xlr_discord:-}" =~ ^[yYoO]$ ]]; then
        jq '.discord_config.enabled = true' "$WORKDIR/Plutonium/server_config.json" > "$WORKDIR/Plutonium/server_config.json.tmp" \
            && mv "$WORKDIR/Plutonium/server_config.json.tmp" "$WORKDIR/Plutonium/server_config.json"
    fi

    installXlrPython 2>/dev/null || true
    setupDdosProtection "$WORKDIR/Plutonium/server_config.json" 2>/dev/null || true
    setupCustomization 2>/dev/null || true
    source "$WORKDIR/.config/xlr/setupBotWarfare.sh" --import 2>/dev/null || true
    setupBotWarfare 2>/dev/null || true

    setupSystemdServices

    if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        jq -r '.servers[]? | select(.enabled == true) | .port' "$WORKDIR/Plutonium/server_config.json" 2>/dev/null | while read -r game_port; do
            ufw allow "${game_port}/udp" 2>/dev/null || true
        done
        web_port=$(jq -r '.iw4madmin_config.web_port // 1624' "$WORKDIR/Plutonium/server_config.json" 2>/dev/null)
        ufw allow "${web_port}/tcp" 2>/dev/null || true
    fi

    chmod +x "$WORKDIR/.config/xlr/"*.sh 2>/dev/null || true
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    {
        installXLRStack
    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "xlr_install")"
    wait
else
    echo "Usage: $0 [--install] | [--import]"
fi
