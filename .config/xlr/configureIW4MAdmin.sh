#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

configureIW4MAdmin() {
    local workdir="${WORKDIR}"
    local config_file="$workdir/Plutonium/server_config.json"
    local iw4m_dir="$workdir/IW4MAdmin"
    local settings="$iw4m_dir/Configuration/IW4MAdminSettings.json"

    if [ ! -f "$settings" ] || [ ! -f "$config_file" ]; then
        return 1
    fi

    local rcon_ip web_port log_base parser_mp parser_zm
    rcon_ip=$(jq -r '.general_config.rcon_ip // "127.0.0.1"' "$config_file")
    web_port=$(jq -r '.iw4madmin_config.web_port // 1624' "$config_file")
    log_base=$(jq -r '.iw4madmin_config.manual_log_path // ""' "$config_file")
    parser_mp="Call of Duty Multiplayer - Ship COD_T6_S MP build 1.0.44 CL(1759941) CODPCAB2 CEG Fri May 9 19:19:19 2014 win-x86 813e66d5"
    parser_zm="Call of Duty - Ship COD_T6_S ZM build 1.0.44 CL(1759941) CODPCAB2 CEG Fri May 9 19:19:19 2014 win-x86 813e66d5"

    local servers_json
    servers_json=$(jq -c --arg ip "$rcon_ip" --arg parser_mp "$parser_mp" --arg parser_zm "$parser_zm" --arg log_base "$log_base" '
        [.servers[] | select(.enabled == true) | {
            IPAddress: $ip,
            Port: .port,
            Password: (.rcon_password // .key),
            Rules: [],
            AutoMessages: [],
            ManualLogPath: (if (.log_file | length) > 0 then ($log_base + "/" + .log_file) else null end),
            RConParserVersion: (if .mode == "t6zm" then $parser_zm else $parser_mp end),
            EventParserVersion: (if .mode == "t6zm" then $parser_zm else $parser_mp end),
            ReservedSlotNumber: 0,
            GameLogServerUrl: null,
            CustomHostname: .name
        }]
    ' "$config_file")

    jq --argjson servers "$servers_json" --argjson port "$web_port" '
        .Servers = $servers |
        .WebPort = $port |
        .EnableWebFront = true |
        .AcceptQueryGuidInformation = true
    ' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    configureIW4MAdmin
else
    echo "Usage: $0 [--install] | [--import]"
fi
