#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installDiscordBot() {
    local workdir="${WORKDIR}"
    local bot_dir="$workdir/Resources/discord"
    local config_file="$workdir/Plutonium/server_config.json"

    checkAndInstallCommand "python3" "python3"
    checkAndInstallCommand "python3-venv" "python3-venv"

    mkdir -p "$bot_dir"

    if [ ! -d "$bot_dir/venv" ]; then
        python3 -m venv "$bot_dir/venv"
    fi

    "$bot_dir/venv/bin/pip" install -q --upgrade pip
    "$bot_dir/venv/bin/pip" install -q -r "$bot_dir/requirements.txt"

    local token
    token=$(jq -r '.discord_config.token // ""' "$config_file" 2>/dev/null)
    if [ -n "$token" ] && [ "$token" != "null" ] && [ "$token" != "" ]; then
        jq '.discord_config.enabled = true' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    installDiscordBot
else
    echo "Usage: $0 [--install] | [--import]"
fi
