#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

xlr_deploy_welcome_gsc() {
    local workdir="$1"
    local invite="$2"
    local owner_name="$3"
    local owner_id="$4"

    local gsc_src="$workdir/Resources/gsc/mp/xlr_welcome.gsc"
    local gsc_dest_dir="$workdir/Plutonium/storage/t6/scripts/mp"
    local gsc_build="$workdir/.build/gsc"
    local build_file="$gsc_build/xlr_welcome.gsc"
    local dest_file="$gsc_dest_dir/xlr_welcome.gsc"
    local backup_file="$dest_file.bak"
    local log_file="$gsc_dest_dir/xlr_welcome.compile.log"

    mkdir -p "$gsc_dest_dir" "$gsc_build"

    if [ ! -f "$gsc_src" ]; then
        echo "[XLR] WARN: missing $gsc_src" >&2
        return 1
    fi

    if [ -f "$dest_file" ] && xlr_gsc_looks_compiled "$dest_file"; then
        cp -f "$dest_file" "$backup_file"
    fi

    cp "$gsc_src" "$build_file"
    sed -i "s|discord.gg/63FAj2ZMrN|${invite}|g" "$build_file" 2>/dev/null || true
    sed -i "s|PLACEHOLDER_OWNER_NAME|${owner_name}|g" "$build_file" 2>/dev/null || true
    sed -i "s|PLACEHOLDER_OWNER_ID|${owner_id}|g" "$build_file" 2>/dev/null || true

    if xlr_compile_gsc_file "$workdir" "$build_file" "$dest_file" "$log_file"; then
        echo "[XLR] deployed xlr_welcome.gsc (compiled)"
        return 0
    fi

    if [ -f "$backup_file" ] && xlr_gsc_looks_compiled "$backup_file"; then
        cp -f "$backup_file" "$dest_file"
        echo "[XLR] restored xlr_welcome.gsc from backup" >&2
        return 0
    fi

    rm -f "$dest_file"
    echo "[XLR] ERROR: welcome GSC compile failed — see $log_file" >&2
    return 1
}

xlr_purge_legacy_gsc() {
    local gsc_dest_dir="$1"
    local legacy

    for legacy in xlr_messages.gsc xlr_owner.gsc; do
        xlr_purge_invalid_gsc "$gsc_dest_dir/$legacy"
        rm -f "$gsc_dest_dir/$legacy" "$gsc_dest_dir/${legacy}.bak"
    done
}

setupCustomization() {
    local workdir="${WORKDIR}"
    local config_file="$workdir/Plutonium/server_config.json"
    local mp_main="$workdir/Server/Multiplayer/main"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    local motd_en motd_fr invite owner_name owner_id
    motd_en=$(jq -r '.customization.motd_en // "^5XLR EU^7 — Fast, protected BO2 servers | discord.gg/63FAj2ZMrN"' "$config_file")
    motd_fr=$(jq -r '.customization.motd_fr // "^5XLR EU^7 — Serveurs BO2 rapides et proteges | discord.gg/63FAj2ZMrN"' "$config_file")
    invite=$(jq -r '.customization.discord_invite // "discord.gg/63FAj2ZMrN"' "$config_file")
    owner_name=$(jq -r '.customization.owner.name // "akan3"' "$config_file")
    owner_id=$(jq -r '.customization.owner.plutonium_id // "0"' "$config_file")

    local gsc_dest_dir="$workdir/Plutonium/storage/t6/scripts/mp"
    mkdir -p "$gsc_dest_dir"

    # shellcheck source=/dev/null
    source "$workdir/.config/xlr/compileGsc.sh"

    xlr_purge_legacy_gsc "$gsc_dest_dir"
    xlr_deploy_welcome_gsc "$workdir" "$invite" "$owner_name" "$owner_id"

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
