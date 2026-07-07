#!/bin/bash

set -euo pipefail

DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$DEFAULT_DIR/Plutonium/server_config.json"
SECRETS_FILE="/etc/xlr/secrets.env"
BACKUP_ROOT="$HOME/xlr-backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"

usage() {
    echo "Usage: $0 [--full-configure]"
    echo ""
    echo "  Default: git pull + restore server_config.json and secrets.env only."
    echo "  Does NOT run generateServerConfig or overwrite dedicated.cfg copies."
    echo ""
    echo "  --full-configure  Also run xlr-configure.sh (interactive, destructive cfg regen)."
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
        .security_hardening = ($new.security_hardening * ($old.security_hardening // {})) |
        .moderation = ($new.moderation * ($old.moderation // {})) |
        .servers = [
            .servers[] as $srv |
            ($old.servers[]? | select(.id == $srv.id)) as $prev |
            if $prev then
                $srv |
                .key = $prev.key |
                .rcon_password = $prev.rcon_password |
                .enabled = $prev.enabled |
                .port = $prev.port |
                .name = ($prev.name // $srv.name) |
                .additional_params = ($srv.additional_params * ($prev.additional_params // {}))
            else
                $srv
            end
        ]
    ' "$new_config" "$old_config" > "$tmp_out"
    mv "$tmp_out" "$new_config"
}

prepare_git_update() {
    local repo_user
    repo_user=$(stat -c '%U' "$DEFAULT_DIR")

    if [ -n "$repo_user" ] && [ "$repo_user" != "root" ]; then
        sudo chown -R "$repo_user:$repo_user" "$DEFAULT_DIR/Resources" 2>/dev/null || true
    fi

    while IFS= read -r -d '' cache_dir; do
        sudo rm -rf "$cache_dir"
    done < <(find "$DEFAULT_DIR" -type d -name __pycache__ -print0 2>/dev/null)
}

sync_install_paths() {
  local config_file="$1"
  local workdir="$2"
  local tmp_out

  tmp_out="$(mktemp)"
  jq --arg w "$workdir" --arg mp "$workdir/Server/Multiplayer" --arg zm "$workdir/Server/Zombie" '
    .general_config.install_dir = ($w + "/Plutonium") |
    .general_config.game_path_mp = $mp |
    .general_config.game_path_zm = $zm |
    .general_config.backup_dir = ($w + "/backups") |
    .iw4madmin_config.install_dir = ($w + "/IW4MAdmin") |
    .iw4madmin_config.manual_log_path = ($w + "/Plutonium/storage/t6/logs") |
    .servers |= map(.game_path = (if .mode == "t6zm" then $zm else $mp end))
  ' "$config_file" > "$tmp_out"
  mv "$tmp_out" "$config_file"
}

run_light_post_update() {
    local repo_user
    repo_user=$(stat -c '%U' "$DEFAULT_DIR")

    if [ -n "$repo_user" ] && [ "$repo_user" != "root" ]; then
        sudo chown -R "$repo_user:$repo_user" \
            "$DEFAULT_DIR/Server" \
            "$DEFAULT_DIR/Plutonium/storage" \
            "$DEFAULT_DIR/Plutonium/servers" \
            "$DEFAULT_DIR/Resources" \
            2>/dev/null || true
    fi

    # shellcheck source=/dev/null
    source "$DEFAULT_DIR/.config/config.sh"
    # shellcheck source=/dev/null
    source "$DEFAULT_DIR/.config/xlr/setupCustomization.sh" --import
    setupCustomization || true
    # shellcheck source=/dev/null
    source "$DEFAULT_DIR/.config/security/setupDdosProtection.sh" --import
    setupDdosProtection "$CONFIG_FILE" || true
}

FULL_CONFIGURE=0
if [ "${1:-}" = "--full-configure" ]; then
    FULL_CONFIGURE=1
elif [ "${1:-}" = "--no-configure" ]; then
    :
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
prepare_git_update
git fetch origin
git reset --hard origin/main
git pull --ff-only origin main

if [ -f "$BACKUP_DIR/server_config.json" ]; then
    merge_local_config "$CONFIG_FILE" "$BACKUP_DIR/server_config.json"
fi

sync_install_paths "$CONFIG_FILE" "$DEFAULT_DIR"

if [ -f "$BACKUP_DIR/secrets.env" ]; then
    sudo mkdir -p /etc/xlr
    sudo cp "$BACKUP_DIR/secrets.env" "$SECRETS_FILE"
    sudo chmod 600 "$SECRETS_FILE"
fi

chmod +x "$DEFAULT_DIR/Plutonium/XLRManager.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/Plutonium/lib/server_core.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/Plutonium/start_server_and_monitoring.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/Plutonium/T6Server.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/.config/xlr/"*.sh 2>/dev/null || true
chmod +x "$DEFAULT_DIR/.config/security/"*.sh 2>/dev/null || true
chmod +x "$DEFAULT_DIR/xlr-configure.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/xlr-update.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/install-plutonium.sh" 2>/dev/null || true
chmod +x "$DEFAULT_DIR/import-game-files.sh" 2>/dev/null || true
find "$DEFAULT_DIR/Plutonium" -maxdepth 2 -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

run_light_post_update

if [ "$FULL_CONFIGURE" -eq 1 ]; then
    echo ""
    echo "Running full xlr-configure (may overwrite dedicated.cfg from template)..."
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
echo "Verify keys and enabled servers:"
echo "  jq '.servers[] | {id, enabled, key: .key[0:6]}' $CONFIG_FILE"
echo ""
echo "Restart game servers without sudo:"
echo "  cd $DEFAULT_DIR/Plutonium && ./XLRManager.sh restart all"
echo ""
echo "Restart services:"
echo "  sudo systemctl restart xlr-player-tracker.service"
echo "  sudo systemctl restart xlr-discord-bot.service"
