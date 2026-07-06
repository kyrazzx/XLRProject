#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

uninstallXLR() {
    systemctl stop xlr-manager.service xlr-iw4madmin.service xlr-discord-bot.service 2>/dev/null || true
    systemctl disable xlr-manager.service xlr-iw4madmin.service xlr-discord-bot.service 2>/dev/null || true
    systemctl disable xlr-backup.timer xlr-scheduled-restart.timer 2>/dev/null || true

    rm -f /etc/systemd/system/xlr-manager.service
    rm -f /etc/systemd/system/xlr-backup.service
    rm -f /etc/systemd/system/xlr-backup.timer
    rm -f /etc/systemd/system/xlr-scheduled-restart.service
    rm -f /etc/systemd/system/xlr-scheduled-restart.timer
    rm -f /etc/systemd/system/xlr-iw4madmin.service
    rm -f /etc/systemd/system/xlr-discord-bot.service
    systemctl daemon-reload 2>/dev/null || true

    if [ -x "${WORKDIR}/Plutonium/XLRManager.sh" ]; then
        "${WORKDIR}/Plutonium/XLRManager.sh" stop all 2>/dev/null || true
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    uninstallXLR
else
    echo "Usage: $0 [--install] | [--import]"
fi
