#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

setupCustomization() {
    local workdir="${WORKDIR}"
    local config_file="$workdir/Plutonium/server_config.json"
    local mp_main="$workdir/Server/Multiplayer/main"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    local motd_en motd_fr invite
    motd_en=$(jq -r '.customization.motd_en // "^5XLR EU^7 — Fast, protected BO2 servers | discord.gg/63FAj2ZMrN"' "$config_file")
    motd_fr=$(jq -r '.customization.motd_fr // "^5XLR EU^7 — Serveurs BO2 rapides et proteges | discord.gg/63FAj2ZMrN"' "$config_file")
    invite=$(jq -r '.customization.discord_invite // "discord.gg/63FAj2ZMrN"' "$config_file")

    for cfg in dedicated_ffa.cfg dedicated_tdm.cfg dedicated_gungame.cfg dedicated.cfg; do
        [ ! -f "$mp_main/$cfg" ] && continue
        if grep -q '^sets motd' "$mp_main/$cfg" 2>/dev/null; then
            sed -i "s|^sets motd.*|sets motd \"$motd_en / $motd_fr\"|" "$mp_main/$cfg"
        else
            echo "sets motd \"$motd_en / $motd_fr\"" >> "$mp_main/$cfg"
        fi
        if grep -q '^seta sv_motd' "$mp_main/$cfg" 2>/dev/null; then
            sed -i "s|^seta sv_motd.*|seta sv_motd \"$motd_en\"|" "$mp_main/$cfg"
        else
            echo "seta sv_motd \"$motd_en\"" >> "$mp_main/$cfg"
        fi
        if ! grep -q '^set g_allowvote' "$mp_main/$cfg" 2>/dev/null; then
            echo "set g_allowvote 1" >> "$mp_main/$cfg"
        fi
    done

    jq --arg invite "$invite" '
        .customization.discord_invite = $invite
    ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    setupCustomization
else
    echo "Usage: $0 [--install] | [--import]"
fi
