#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

applyServerCredentials() {
    local workdir="${WORKDIR}"
    local key="${server_key:-}"
    local rcon="${rcon_password:-}"
    local config_file="$workdir/Plutonium/server_config.json"
    local t6_script="$workdir/Plutonium/T6Server.sh"

    if [ -z "$key" ] || [ "$key" = "YOURKEY" ]; then
        return 0
    fi

    if [ -z "$rcon" ]; then
        rcon="$key"
    fi

    if [ -f "$t6_script" ]; then
        sed -i "s|^readonly SERVER_KEY=.*|readonly SERVER_KEY=\"$key\"|" "$t6_script"
    fi

    if [ -f "$config_file" ]; then
        jq --arg key "$key" --arg rcon "$rcon" '
            .servers |= map(
                .key = $key |
                .rcon_password = $rcon
            )
        ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
    fi

    local mp_main="$workdir/Server/Multiplayer/main"
    for cfg in dedicated.cfg dedicated_ffa.cfg dedicated_tdm.cfg dedicated_gungame.cfg; do
        if [ -f "$mp_main/$cfg" ]; then
            if grep -q '^rcon_password' "$mp_main/$cfg"; then
                sed -i "s|^rcon_password.*|rcon_password \"$rcon\"|" "$mp_main/$cfg"
            else
                echo "rcon_password \"$rcon\"" >> "$mp_main/$cfg"
            fi
        fi
    done

    if [ -f "$workdir/Server/Zombie/main/dedicated_zm.cfg" ]; then
        if grep -q '^rcon_password' "$workdir/Server/Zombie/main/dedicated_zm.cfg"; then
            sed -i "s|^rcon_password.*|rcon_password \"$rcon\"|" "$workdir/Server/Zombie/main/dedicated_zm.cfg"
        else
            echo "rcon_password \"$rcon\"" >> "$workdir/Server/Zombie/main/dedicated_zm.cfg"
        fi
    fi

    if [ -n "${discord_token:-}" ] && [ -f "$config_file" ]; then
        mkdir -p /etc/xlr
        if grep -q '^DISCORD_TOKEN=' /etc/xlr/secrets.env 2>/dev/null; then
            sed -i "s|^DISCORD_TOKEN=.*|DISCORD_TOKEN=$discord_token|" /etc/xlr/secrets.env
        else
            echo "DISCORD_TOKEN=$discord_token" >> /etc/xlr/secrets.env
        fi
        chmod 600 /etc/xlr/secrets.env
        jq '
            .discord_config.enabled = true |
            .discord_config.token = ""
        ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
    fi

    if [ -n "${discord_webhook:-}" ]; then
        mkdir -p /etc/xlr
        if grep -q '^DISCORD_WEBHOOK=' /etc/xlr/secrets.env 2>/dev/null; then
            sed -i "s|^DISCORD_WEBHOOK=.*|DISCORD_WEBHOOK=$discord_webhook|" /etc/xlr/secrets.env
        else
            echo "DISCORD_WEBHOOK=$discord_webhook" >> /etc/xlr/secrets.env
        fi
        chmod 600 /etc/xlr/secrets.env
    fi

    if [ -n "${discord_webhook:-}" ] && [ -f "$config_file" ]; then
        jq --arg webhook "$discord_webhook" '.monitoring_config.discord_webhook = $webhook' \
            "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    applyServerCredentials
else
    echo "Usage: $0 [--install] | [--import]"
fi
