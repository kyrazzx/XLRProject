#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

xlr_apply_gsc_placeholders() {
    local file="$1"
    local invite="$2"
    local owner_name="$3"
    local owner_id="$4"
    local owner_tag="$5"
    local owner_name_color="$6"
    local owner_text_color="$7"
    local lang_fr_code="$8"

    sed -i "s|discord.gg/63FAj2ZMrN|${invite}|g" "$file" 2>/dev/null || true
    sed -i "s|PLACEHOLDER_OWNER_NAME|${owner_name}|g" "$file" 2>/dev/null || true
    sed -i "s|PLACEHOLDER_OWNER_ID|${owner_id}|g" "$file" 2>/dev/null || true
    sed -i "s|PLACEHOLDER_OWNER_CHAT_TAG|${owner_tag}|g" "$file" 2>/dev/null || true
    sed -i "s|PLACEHOLDER_OWNER_NAME_COLOR|${owner_name_color}|g" "$file" 2>/dev/null || true
    sed -i "s|PLACEHOLDER_OWNER_TEXT_COLOR|${owner_text_color}|g" "$file" 2>/dev/null || true
    sed -i "s|PLACEHOLDER_LANG_FR_CODE|${lang_fr_code}|g" "$file" 2>/dev/null || true
}

xlr_deploy_one_gsc() {
    local workdir="$1"
    local src_name="$2"
    local dest_name="$3"
    local required="$4"
    local invite="$5"
    local owner_name="$6"
    local owner_id="$7"
    local owner_tag="$8"
    local owner_name_color="$9"
    local owner_text_color="${10}"
    local lang_fr_code="${11}"

    local gsc_src="$workdir/Resources/gsc/mp/$src_name"
    local gsc_dest_dir="$workdir/Plutonium/storage/t6/scripts/mp"
    local gsc_build="$workdir/.build/gsc"
    local build_file="$gsc_build/$src_name"
    local dest_file="$gsc_dest_dir/$dest_name"
    local backup_file="$dest_file.bak"
    local log_file="$gsc_dest_dir/${dest_name%.gsc}.compile.log"

    mkdir -p "$gsc_dest_dir" "$gsc_build"

    if [ ! -f "$gsc_src" ]; then
        echo "[XLR] WARN: missing GSC source $gsc_src" >&2
        return 1
    fi

    if [ -f "$dest_file" ] && xlr_gsc_looks_compiled "$dest_file"; then
        cp -f "$dest_file" "$backup_file"
    fi

    cp "$gsc_src" "$build_file"
    xlr_apply_gsc_placeholders "$build_file" "$invite" "$owner_name" "$owner_id" "$owner_tag" "$owner_name_color" "$owner_text_color" "$lang_fr_code"

    if xlr_compile_gsc_file "$workdir" "$build_file" "$dest_file" "$log_file"; then
        echo "[XLR] deployed $dest_name (compiled)"
        return 0
    fi

    echo "[XLR] ERROR: failed to compile $src_name" >&2
    if [ -f "$backup_file" ] && xlr_gsc_looks_compiled "$backup_file"; then
        cp -f "$backup_file" "$dest_file"
        echo "[XLR] restored previous compiled $dest_name from backup" >&2
        return 0
    fi

    rm -f "$dest_file"
    if [ "$required" = "required" ]; then
        echo "[XLR] CRITICAL: no valid $dest_name — map load may fail if invalid gsc remains" >&2
        return 1
    fi

    echo "[XLR] optional $dest_name skipped — welcome script still active" >&2
    return 0
}

setupCustomization() {
    local workdir="${WORKDIR}"
    local config_file="$workdir/Plutonium/server_config.json"
    local mp_main="$workdir/Server/Multiplayer/main"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    local motd_en motd_fr invite owner_name owner_id owner_tag owner_name_color owner_text_color lang_fr_code
    motd_en=$(jq -r '.customization.motd_en // "^5XLR EU^7 — Fast, protected BO2 servers | discord.gg/63FAj2ZMrN"' "$config_file")
    motd_fr=$(jq -r '.customization.motd_fr // "^5XLR EU^7 — Serveurs BO2 rapides et proteges | discord.gg/63FAj2ZMrN"' "$config_file")
    invite=$(jq -r '.customization.discord_invite // "discord.gg/63FAj2ZMrN"' "$config_file")
    owner_name=$(jq -r '.customization.owner.name // "akan3"' "$config_file")
    owner_id=$(jq -r '.customization.owner.plutonium_id // "0"' "$config_file")
    owner_tag=$(jq -r '.customization.owner.chat_tag // "[OWNER]"' "$config_file")
    owner_name_color=$(jq -r '.customization.owner.chat_name_color // "3"' "$config_file")
    owner_text_color=$(jq -r '.customization.owner.chat_text_color // "6"' "$config_file")
    lang_fr_code=$(jq -r '.customization.owner.lang_fr_code // 1' "$config_file")

    local gsc_dest_dir="$workdir/Plutonium/storage/t6/scripts/mp"
    mkdir -p "$gsc_dest_dir"

    # shellcheck source=/dev/null
    source "$workdir/.config/xlr/compileGsc.sh"

    # Legacy monolithic script — SOURCE text here = "Server is not running a map"
    xlr_purge_invalid_gsc "$gsc_dest_dir/xlr_messages.gsc"
    rm -f "$gsc_dest_dir/xlr_messages.gsc" "$gsc_dest_dir/xlr_messages.gsc.bak"

    xlr_deploy_one_gsc "$workdir" "xlr_welcome.gsc" "xlr_welcome.gsc" "required" \
        "$invite" "$owner_name" "$owner_id" "$owner_tag" "$owner_name_color" "$owner_text_color" "$lang_fr_code"

    xlr_deploy_one_gsc "$workdir" "xlr_owner.gsc" "xlr_owner.gsc" "optional" \
        "$invite" "$owner_name" "$owner_id" "$owner_tag" "$owner_name_color" "$owner_text_color" "$lang_fr_code"

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
