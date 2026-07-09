#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

xlr_patch_dedicated_cfg() {
    local cfg_file="$1"
    local hostname="$2"
    local maprotation="$3"
    local log_file="$4"
    local rcon_pass="${5:-}"

    [ ! -f "$cfg_file" ] && return 1

    if grep -q '^seta sv_hostname' "$cfg_file" 2>/dev/null; then
        sed -i "s|^seta sv_hostname.*|seta sv_hostname \"^7$hostname\"|" "$cfg_file"
    elif grep -q '^//seta sv_hostname' "$cfg_file" 2>/dev/null; then
        sed -i "s|^//seta sv_hostname.*|seta sv_hostname \"^7$hostname\"|" "$cfg_file"
    else
        echo "seta sv_hostname \"^7$hostname\"" >> "$cfg_file"
    fi

    if grep -q '^g_log ' "$cfg_file"; then
        sed -i "s|^g_log .*|g_log \"logs\\\\$log_file\"|" "$cfg_file"
    else
        echo "g_log \"logs\\\\$log_file\"" >> "$cfg_file"
    fi

    if grep -q '^g_logSync' "$cfg_file"; then
        sed -i 's|^g_logSync.*|g_logSync 2|' "$cfg_file"
    else
        echo "g_logSync 2" >> "$cfg_file"
    fi

    if [ -n "$rcon_pass" ]; then
        if grep -q '^rcon_password' "$cfg_file"; then
            sed -i "s|^rcon_password.*|rcon_password \"$rcon_pass\"|" "$cfg_file"
        else
            echo "rcon_password \"$rcon_pass\"" >> "$cfg_file"
        fi
    fi

    if grep -q '^sv_maprotation' "$cfg_file"; then
        sed -i "s|^sv_maprotation.*|sv_maprotation \"$maprotation\"|" "$cfg_file"
    else
        echo "sv_maprotation \"$maprotation\"" >> "$cfg_file"
    fi

    if grep -q '^sv_maprotationcurrent' "$cfg_file"; then
        sed -i 's|^sv_maprotationcurrent.*|sv_maprotationcurrent ""|' "$cfg_file"
    else
        echo 'sv_maprotationcurrent ""' >> "$cfg_file"
    fi
}

generateServerConfig() {
    local workdir="${WORKDIR}"
    local mp_main="$workdir/Server/Multiplayer/main"
    local zm_main="$workdir/Server/Zombie/main"
    local plutonium_dir="$workdir/Plutonium"
    local logs_dir="$workdir/Plutonium/storage/t6/logs"
    local servers_root="$plutonium_dir/servers"
    local template_config="$plutonium_dir/server_config.json"
    local map_pool="map mp_nuketown_2020 map mp_raid map mp_slums map mp_express map mp_hijacked map mp_carrier map mp_meltdown map mp_nuketown_2020"
    local rcon="${rcon_password:-}"

    mkdir -p "$servers_root"/{ffa,tdm,gungame,zombies}/logs
    mkdir -p "$plutonium_dir/logs/monitoring"
    mkdir -p "$logs_dir"
    mkdir -p "$workdir/backups"

    if [ -f "$mp_main/dedicated.cfg" ]; then
        cp "$mp_main/dedicated.cfg" "$mp_main/dedicated_ffa.cfg"
        cp "$mp_main/dedicated.cfg" "$mp_main/dedicated_tdm.cfg"
        cp "$mp_main/dedicated.cfg" "$mp_main/dedicated_gungame.cfg"

        xlr_patch_dedicated_cfg "$mp_main/dedicated_ffa.cfg" "XLR | FFA EU" \
            "execgts dm.cfg $map_pool" "games_mp_ffa.log" "$rcon"
        xlr_patch_dedicated_cfg "$mp_main/dedicated_tdm.cfg" "XLR | TDM EU" \
            "execgts tdm.cfg $map_pool" "games_mp_tdm.log" "$rcon"
        xlr_patch_dedicated_cfg "$mp_main/dedicated_gungame.cfg" "XLR | Gun Game EU" \
            "execgts gun.cfg $map_pool" "games_mp_gungame.log" "$rcon"

        cp -f "$mp_main/dedicated_ffa.cfg" "$plutonium_dir/dedicated_ffa.cfg"
        cp -f "$mp_main/dedicated_tdm.cfg" "$plutonium_dir/dedicated_tdm.cfg"
        cp -f "$mp_main/dedicated_gungame.cfg" "$plutonium_dir/dedicated_gungame.cfg"
    fi

    if [ -f "$zm_main/dedicated_zm.cfg" ]; then
        if grep -q '^g_log ' "$zm_main/dedicated_zm.cfg"; then
            sed -i 's|^g_log .*|g_log "logs\\games_zm.log"|' "$zm_main/dedicated_zm.cfg"
        fi
        if grep -q '^g_logSync' "$zm_main/dedicated_zm.cfg"; then
            sed -i 's|^g_logSync.*|g_logSync 2|' "$zm_main/dedicated_zm.cfg"
        fi
        if [ -n "$rcon" ] && grep -q '^rcon_password' "$zm_main/dedicated_zm.cfg"; then
            sed -i "s|^rcon_password.*|rcon_password \"$rcon\"|" "$zm_main/dedicated_zm.cfg"
        fi
    fi

    if [ -f "$template_config" ]; then
        jq --arg workdir "$workdir" --arg mp "$workdir/Server/Multiplayer" --arg zm "$workdir/Server/Zombie" '
            .general_config.install_dir = ($workdir + "/Plutonium") |
            .general_config.game_path_mp = $mp |
            .general_config.game_path_zm = $zm |
            .general_config.backup_dir = ($workdir + "/backups") |
            .iw4madmin_config.install_dir = ($workdir + "/IW4MAdmin") |
            .iw4madmin_config.manual_log_path = ($workdir + "/Plutonium/storage/t6/logs") |
            .servers = (.servers | map(
                .game_path = (if .mode == "t6zm" then $zm else $mp end) |
                if .id == "ffa" then
                    .gamesetting = "dm.cfg" | .gametype = "dm" | .log_file = "games_mp_ffa.log"
                elif .id == "tdm" then
                    .gamesetting = "tdm.cfg" | .gametype = "war" | .log_file = "games_mp_tdm.log"
                elif .id == "gungame" then
                    .gamesetting = "gun.cfg" | .gametype = "gun" | .log_file = "games_mp_gungame.log"
                elif .id == "zombies" then
                    .gamesetting = "zm_standard_transit.cfg" | .log_file = "games_zm.log"
                else . end
            ))
        ' "$template_config" > "$template_config.tmp" && mv -f "$template_config.tmp" "$template_config"
    fi

    chmod +x "$plutonium_dir/XLRManager.sh" 2>/dev/null || true
    chmod +x "$plutonium_dir/lib/server_core.sh" 2>/dev/null || true
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    generateServerConfig
else
    echo "Usage: $0 [--install] | [--import]"
fi
