#!/bin/bash

XLR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XLR_WORKDIR="$(cd "$XLR_SCRIPT_DIR/../.." && pwd)"

if [ -f "$XLR_WORKDIR/.config/config.sh" ]; then
    source "$XLR_WORKDIR/.config/config.sh"
fi

if [ -z "${WORKDIR:-}" ]; then
    WORKDIR="$XLR_WORKDIR"
fi

BOT_WARFARE_REPO="https://github.com/ineedbots/t6_bot_warfare/archive/refs/heads/master.zip"

xlr_bot_warfare_enabled() {
    local config_file="${1:-$WORKDIR/Plutonium/server_config.json}"
    [ -f "$config_file" ] || return 1
    [ "$(jq -r '.bot_warfare.enabled // false' "$config_file")" = "true" ]
}

xlr_deploy_bot_warfare_scripts() {
    local workdir="$1"
    local dest_dir="$workdir/Plutonium/storage/t6/scripts/mp"
    local build_dir="$workdir/.build/bot-warfare"
    local zip_file="$build_dir/bot-warfare.zip"
    local extract_dir="$build_dir/extract"

    mkdir -p "$dest_dir" "$build_dir"
    rm -rf "$extract_dir"

    if ! command -v curl >/dev/null 2>&1; then
        echo "[XLR] ERROR: curl is required to install Bot Warfare" >&2
        return 1
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        echo "[XLR] ERROR: unzip is required to install Bot Warfare" >&2
        return 1
    fi

    echo "[XLR] Downloading Bot Warfare (t6_bot_warfare)..."
    if ! curl -fsSL "$BOT_WARFARE_REPO" -o "$zip_file"; then
        echo "[XLR] ERROR: failed to download Bot Warfare" >&2
        return 1
    fi

    unzip -q "$zip_file" -d "$extract_dir"
    local src_dir
    src_dir="$(find "$extract_dir" -maxdepth 1 -type d -name 't6_bot_warfare-*' | head -1)"
    if [ -z "$src_dir" ] || [ ! -d "$src_dir/scripts/mp" ]; then
        echo "[XLR] ERROR: Bot Warfare archive layout unexpected" >&2
        return 1
    fi

    cp -f "$src_dir/scripts/mp/"*.gsc "$dest_dir/"
    echo "[XLR] Bot Warfare scripts deployed to $dest_dir"
    return 0
}

xlr_apply_bot_warfare_dvars() {
    local workdir="$1"
    local config_file="$workdir/Plutonium/server_config.json"
    local mp_main="$workdir/Server/Multiplayer/main"
    local server_id cfg_file fill skill wait_host team_force

    [ -f "$config_file" ] || return 1
    xlr_bot_warfare_enabled "$config_file" || return 0

    fill=$(jq -r '.bot_warfare.manage_fill // 12' "$config_file")
    skill=$(jq -r '.bot_warfare.skill // 3' "$config_file")
    wait_host=$(jq -r '.bot_warfare.wait_for_host_seconds // 10' "$config_file")
    team_force=$(jq -r '.bot_warfare.team_force // 1' "$config_file")

    while IFS= read -r server_id; do
        [ -n "$server_id" ] || continue
        cfg_file=$(jq -r --arg sid "$server_id" '.servers[] | select(.id == $sid) | .config' "$config_file")
        [ -n "$cfg_file" ] && [ "$cfg_file" != "null" ] || continue
        cfg_path="$mp_main/$cfg_file"
        [ -f "$cfg_path" ] || continue

        if [ "$fill" = "0" ] || [ -z "$fill" ] || [ "$fill" = "null" ]; then
            fill=12
        fi

        local gametype srv_team_force is_team_mode
        gametype=$(jq -r --arg sid "$server_id" '.servers[] | select(.id == $sid) | .gametype // ""' "$config_file")
        case "$gametype" in
            dm|gun|oic|shrp|infect|hns|""|null)
                srv_team_force=0
                is_team_mode=0
                ;;
            *)
                srv_team_force="$team_force"
                is_team_mode=1
                ;;
        esac

        for key in bots_main bots_manage_fill bots_manage_fill_kick bots_manage_fill_mode \
            bots_team_force bots_skill bots_main_waitForHostTime bots_team bots_team_mode; do
            sed -i "/^set ${key} /d" "$cfg_path" 2>/dev/null || true
        done

        {
            echo "set bots_main 1"
            echo "set bots_manage_fill \"${fill}\""
            echo "set bots_manage_fill_kick 1"
            echo "set bots_manage_fill_mode 0"
            echo "set bots_team_force \"${srv_team_force}\""
            echo "set bots_skill \"${skill}\""
            echo "set bots_main_waitForHostTime \"${wait_host}\""
        } >> "$cfg_path"
        if [ "$is_team_mode" = "1" ]; then
            {
                echo "set bots_team autoassign"
                echo "set bots_team_mode 0"
            } >> "$cfg_path"
        fi
        echo "[XLR] Bot Warfare dvars applied to $cfg_file (mode=${gametype:-none}, fill=${fill}, skill=${skill}, team_force=${srv_team_force})"
    done < <(jq -r '.bot_warfare.server_ids[]?' "$config_file")
}

xlr_sync_bot_names() {
    local workdir="$1"
    local py="$workdir/Resources/xlr/venv/bin/python"
    if [ ! -x "$py" ]; then
        py="python3"
    fi
    if [ -f "$workdir/Resources/xlr/sync_bot_names.py" ]; then
        "$py" "$workdir/Resources/xlr/sync_bot_names.py" || return 1
    fi
}

setupBotWarfare() {
    local workdir="${WORKDIR:-$XLR_WORKDIR}"
    local config_file="$workdir/Plutonium/server_config.json"

    [ -f "$config_file" ] || return 1
    xlr_bot_warfare_enabled "$config_file" || {
        echo "[XLR] Bot Warfare disabled in server_config.json"
        return 0
    }

    xlr_deploy_bot_warfare_scripts "$workdir" || return 1
    xlr_apply_bot_warfare_dvars "$workdir" || return 1
    xlr_sync_bot_names "$workdir" || return 1
    local ids
    ids=$(jq -r '.bot_warfare.server_ids | join(", ")' "$config_file" 2>/dev/null)
    echo "[XLR] Bot Warfare ready for: ${ids:-none}"
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    setupBotWarfare
else
    echo "Usage: $0 [--install] | [--import]"
fi
