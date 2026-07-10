#!/bin/bash

if [ "$1" = "--install" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WORKROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    if [ -f "$WORKROOT/.config/config.sh" ]; then
        source "$WORKROOT/.config/config.sh"
    elif [ -f /opt/T6Server/.config/config.sh ]; then
        source /opt/T6Server/.config/config.sh
    else
        WORKDIR="$WORKROOT"
    fi
fi

setupSystemdServices() {
    local workdir="${WORKDIR}"
    local plutonium_dir="$workdir/Plutonium"
    local config_file="$plutonium_dir/server_config.json"
    local backup_interval
    backup_interval=$(jq -r '.backup_config.interval_hours // 6' "$config_file" 2>/dev/null)

    cat > /etc/systemd/system/xlr-manager.service << EOF
[Unit]
Description=XLR Plutonium T6 Server Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$plutonium_dir
TimeoutStopSec=120
KillMode=process
ExecStartPre=/bin/bash $plutonium_dir/XLRManager.sh validate-config
ExecStart=/bin/bash $plutonium_dir/XLRManager.sh monitor
# Do not stop game servers here — FFA/TDM keep running when the monitor restarts.
ExecStop=/bin/kill -TERM \$MAINPID
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/xlr-backup.service << EOF
[Unit]
Description=XLR Server Backup

[Service]
Type=oneshot
User=root
WorkingDirectory=$plutonium_dir
ExecStart=/bin/bash $workdir/.config/xlr/runBackup.sh $config_file
EOF

    cat > /etc/systemd/system/xlr-backup.timer << EOF
[Unit]
Description=XLR Backup Timer

[Timer]
OnBootSec=15min
OnUnitActiveSec=${backup_interval}h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    cat > /etc/systemd/system/xlr-scheduled-restart.service << EOF
[Unit]
Description=XLR Scheduled Server Restart

[Service]
Type=oneshot
User=root
WorkingDirectory=$plutonium_dir
ExecStart=/bin/bash $plutonium_dir/XLRManager.sh scheduled-restart
EOF

    cat > /etc/systemd/system/xlr-scheduled-restart.timer << EOF
[Unit]
Description=XLR Scheduled Restart Timer

[Timer]
OnBootSec=30min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    if [ -f "$workdir/IW4MAdmin/StartIW4MAdmin.sh" ]; then
        cat > /etc/systemd/system/xlr-iw4madmin.service << EOF
[Unit]
Description=IW4MAdmin for XLR T6 Servers
After=network.target xlr-manager.service

[Service]
Type=simple
User=root
WorkingDirectory=$workdir/IW4MAdmin
ExecStart=$workdir/IW4MAdmin/StartIW4MAdmin.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    fi

    if [ -f "$workdir/Resources/xlr/venv/bin/python" ]; then
        local discord_enabled
        discord_enabled=$(jq -r '.discord_config.enabled // false' "$config_file" 2>/dev/null)
        if [ "$discord_enabled" = "true" ]; then
            cat > /etc/systemd/system/xlr-discord-bot.service << EOF
[Unit]
Description=XLR Discord Bot
After=network.target xlr-player-tracker.service

[Service]
Type=simple
User=root
WorkingDirectory=$workdir/Resources/xlr
ExecStart=$workdir/Resources/xlr/venv/bin/python $workdir/Resources/xlr/xlr_bot.py
Restart=on-failure
RestartSec=15
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1
EnvironmentFile=-/etc/xlr/secrets.env

[Install]
WantedBy=multi-user.target
EOF
        fi

        cat > /etc/systemd/system/xlr-player-tracker.service << EOF
[Unit]
Description=XLR Player Tracker and Moderation
After=network.target xlr-manager.service

[Service]
Type=simple
User=root
WorkingDirectory=$workdir/Resources/xlr
ExecStart=$workdir/Resources/xlr/venv/bin/python $workdir/Resources/xlr/player_tracker.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1
EnvironmentFile=-/etc/xlr/secrets.env

[Install]
WantedBy=multi-user.target
EOF

        cat > /etc/systemd/system/xlr-crash-watchdog.service << EOF
[Unit]
Description=XLR Crash Watchdog (Discord alerts)
After=network.target xlr-manager.service

[Service]
Type=simple
User=root
WorkingDirectory=$workdir/Resources/xlr
ExecStart=$workdir/Resources/xlr/venv/bin/python $workdir/Resources/xlr/crash_watchdog.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1
EnvironmentFile=-/etc/xlr/secrets.env

[Install]
WantedBy=multi-user.target
EOF
    fi

    cat > /etc/systemd/system/xlr-healthcheck.service << EOF
[Unit]
Description=XLR Healthcheck

[Service]
Type=oneshot
User=root
ExecStart=/bin/bash $workdir/.config/xlr/healthcheck.sh $config_file
EOF

    cat > /etc/systemd/system/xlr-healthcheck.timer << EOF
[Unit]
Description=XLR Healthcheck Timer

[Timer]
OnBootSec=10min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable xlr-manager.service xlr-backup.timer xlr-scheduled-restart.timer xlr-healthcheck.timer 2>/dev/null || true
    systemctl enable xlr-iw4madmin.service 2>/dev/null || true
    systemctl enable xlr-player-tracker.service 2>/dev/null || true
    systemctl enable xlr-crash-watchdog.service 2>/dev/null || true
    systemctl enable xlr-discord-bot.service 2>/dev/null || true
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    setupSystemdServices
else
    echo "Usage: $0 [--install] | [--import]"
fi
