#!/bin/bash

set -euo pipefail

DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$DEFAULT_DIR/Plutonium/server_config.json"
SECRETS_FILE="/etc/xlr/secrets.env"
BACKUP_ROOT="$HOME/xlr-backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"

usage() {
    echo "Usage: $0 [--no-configure]"
    echo "  Updates XLRProject from git and restores local server settings."
}

merge_local_config() {
    local new_config="$1"
    local old_config="$2"
    local tmp_out

    tmp_out="$(mktemp)"
    jq -s '
        .[0] as $new | .[1] as $old |
        $new |
        .discord_config.enabled = ($old.discord_config.enabled // .discord_config.enabled) |
        .discord_config.reports_channel_id = ($old.discord_config.reports_channel_id // .discord_config.reports_channel_id) |
        .discord_config.status_channel_id = ($old.discord_config.status_channel_id // .discord_config.status_channel_id) |
        .discord_config.guild_id = ($old.discord_config.guild_id // .discord_config.guild_id) |
        .discord_config.token = "" |
        .monitoring_config.discord_webhook = ($old.monitoring_config.discord_webhook // .monitoring_config.discord_webhook) |
        .customization = ($new.customization * ($old.customization // {})) |
        .servers = [
            .servers[] as $srv |
            ($old.servers[]? | select(.id == $srv.id)) as $prev |
            if $prev then
                $srv |
                .key = $prev.key |
                .rcon_password = $prev.rcon_password |
                .enabled = $prev.enabled |
                .port = $prev.port |
                .name = ($prev.name // $srv.name)
            else
                $srv
            end
        ]
    ' "$new_config" "$old_config" > "$tmp_out"
    mv "$tmp_out" "$new_config"
}

NO_CONFIGURE=0
if [ "${1:-}" = "--no-configure" ]; then
    NO_CONFIGURE=1
elif [ -n "${1:-}" ]; then
    usage
    exit 1
fi

if [ ! -d "$DEFAULT_DIR/.git" ]; then
    echo "Error: $DEFAULT_DIR is not a git repository."
    exit 1
fi

mkdir -p "$BACKUP_DIR"
echo "Backup: $BACKUP_DIR"

if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_DIR/server_config.json"
fi

if [ -f "$SECRETS_FILE" ]; then
    sudo cp "$SECRETS_FILE" "$BACKUP_DIR/secrets.env" 2>/dev/null || cp "$SECRETS_FILE" "$BACKUP_DIR/secrets.env"
fi

cd "$DEFAULT_DIR"
git fetch origin

if [ -f "$BACKUP_DIR/server_config.json" ]; then
    git reset --hard origin/main
    git pull --ff-only origin main
    merge_local_config "$CONFIG_FILE" "$BACKUP_DIR/server_config.json"
else
    git reset --hard origin/main
    git pull --ff-only origin main
fi

if [ -f "$BACKUP_DIR/secrets.env" ]; then
    sudo mkdir -p /etc/xlr
    sudo cp "$BACKUP_DIR/secrets.env" "$SECRETS_FILE"
    sudo chmod 600 "$SECRETS_FILE"
fi

chmod +x "$DEFAULT_DIR/Plutonium/XLRManager.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/Plutonium/lib/server_core.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/.config/xlr/"*.sh 2>/dev/null || true
chmod +x "$DEFAULT_DIR/.config/security/"*.sh 2>/dev/null || true
chmod +x "$DEFAULT_DIR/xlr-configure.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/xlr-update.sh" 2>/dev/null || true

if [ "$NO_CONFIGURE" -eq 0 ] && [ -x "$DEFAULT_DIR/xlr-configure.sh" ]; then
    if [ "$EUID" -eq 0 ]; then
        "$DEFAULT_DIR/xlr-configure.sh"
    else
        sudo "$DEFAULT_DIR/xlr-configure.sh"
    fi
fi

echo ""
echo "Update complete."
echo "Backup saved in: $BACKUP_DIR"
echo ""
echo "Restart game servers without sudo:"
echo "  cd $DEFAULT_DIR/Plutonium && ./XLRManager.sh restart all"
echo ""
echo "Restart services:"
echo "  sudo systemctl restart xlr-player-tracker.service"
echo "  sudo systemctl restart xlr-discord-bot.service"
