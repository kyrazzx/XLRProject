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

    local motd_en motd_fr invite owner_name owner_id owner_tag owner_name_color owner_text_color
    motd_en=$(jq -r '.customization.motd_en // "^5XLR EU^7 — Fast, protected BO2 servers | discord.gg/63FAj2ZMrN"' "$config_file")
    motd_fr=$(jq -r '.customization.motd_fr // "^5XLR EU^7 — Serveurs BO2 rapides et proteges | discord.gg/63FAj2ZMrN"' "$config_file")
    invite=$(jq -r '.customization.discord_invite // "discord.gg/63FAj2ZMrN"' "$config_file")
    owner_name=$(jq -r '.customization.owner.name // "akan3"' "$config_file")
    owner_id=$(jq -r '.customization.owner.plutonium_id // "0"' "$config_file")
    owner_tag=$(jq -r '.customization.owner.chat_tag // "[OWNER]"' "$config_file")
    owner_name_color=$(jq -r '.customization.owner.chat_name_color // "3"' "$config_file")
    owner_text_color=$(jq -r '.customization.owner.chat_text_color // "5"' "$config_file")

    local gsc_src="$workdir/Resources/gsc/mp/xlr_messages.gsc"
    local gsc_dest="$workdir/Plutonium/storage/t6/scripts/mp"
    mkdir -p "$gsc_dest"
    if [ -f "$gsc_src" ]; then
        cp "$gsc_src" "$gsc_dest/xlr_messages.gsc"
        sed -i "s|discord.gg/63FAj2ZMrN|${invite}|g" "$gsc_dest/xlr_messages.gsc" 2>/dev/null || true
        sed -i "s|PLACEHOLDER_OWNER_NAME|${owner_name}|g" "$gsc_dest/xlr_messages.gsc" 2>/dev/null || true
        sed -i "s|PLACEHOLDER_OWNER_ID|${owner_id}|g" "$gsc_dest/xlr_messages.gsc" 2>/dev/null || true
        sed -i "s|PLACEHOLDER_OWNER_CHAT_TAG|${owner_tag}|g" "$gsc_dest/xlr_messages.gsc" 2>/dev/null || true
        sed -i "s|PLACEHOLDER_OWNER_NAME_COLOR|${owner_name_color}|g" "$gsc_dest/xlr_messages.gsc" 2>/dev/null || true
        sed -i "s|PLACEHOLDER_OWNER_TEXT_COLOR|${owner_text_color}|g" "$gsc_dest/xlr_messages.gsc" 2>/dev/null || true
        echo "[XLR] GSC deployed -> $gsc_dest/xlr_messages.gsc (owner=${owner_name} id=${owner_id})"
    else
        echo "[XLR] WARN: missing GSC source $gsc_src"
    fi

    for cfg in dedicated_ffa.cfg dedicated_tdm.cfg dedicated_gungame.cfg dedicated.cfg; do
        [ ! -f "$mp_main/$cfg" ] && continue
        [ ! -w "$mp_main/$cfg" ] && continue
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
