#!/bin/bash

readonly XLR_SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly XLR_LIB_DIR=$(dirname "$XLR_SCRIPT_PATH")
readonly XLR_PLUTONIUM_DIR=$(dirname "$XLR_LIB_DIR")

xlr_resolve_config() {
    local config_arg="${1:-}"
    if [ -n "$config_arg" ] && [ -f "$config_arg" ]; then
        echo "$config_arg"
        return 0
    fi
    if [ -f "$XLR_PLUTONIUM_DIR/server_config.json" ]; then
        echo "$XLR_PLUTONIUM_DIR/server_config.json"
        return 0
    fi
    return 1
}

xlr_get_install_dir() {
    local config_file="$1"
    jq -r '.general_config.install_dir // "/opt/T6Server/Plutonium"' "$config_file"
}

xlr_get_servers_root() {
    local config_file="$1"
    local install_dir
    local servers_root
    install_dir=$(xlr_get_install_dir "$config_file")
    servers_root=$(jq -r '.general_config.servers_root // "./servers"' "$config_file")
    if [[ "$servers_root" != /* ]]; then
        echo "$install_dir/$servers_root"
    else
        echo "$servers_root"
    fi
}

xlr_server_log_dir() {
    local config_file="$1"
    local server_id="$2"
    local servers_root
    servers_root=$(xlr_get_servers_root "$config_file")
    echo "$servers_root/$server_id/logs"
}

xlr_server_pid_file() {
    local config_file="$1"
    local server_id="$2"
    local servers_root
    servers_root=$(xlr_get_servers_root "$config_file")
    echo "$servers_root/$server_id/server.pid"
}

xlr_server_state_file() {
    local config_file="$1"
    local server_id="$2"
    local servers_root
    servers_root=$(xlr_get_servers_root "$config_file")
    echo "$servers_root/$server_id/server.state"
}

xlr_find_server_pid() {
    local port="$1"
    pgrep -f "net_port $port" | head -n 1
}

xlr_is_server_running() {
    local config_file="$1"
    local server_id="$2"
    local port="$3"
    local pid
    pid=$(xlr_find_server_pid "$port")
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi
    local pid_file
    pid_file=$(xlr_server_pid_file "$config_file" "$server_id")
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi
    return 1
}

xlr_write_log() {
    local log_dir="$1"
    local server_id="$2"
    local message="$3"
    mkdir -p "$log_dir"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$server_id] $message" >> "$log_dir/manager.log"
}

xlr_rotate_logs() {
    local log_dir="$1"
    local max_files="${2:-30}"
    mkdir -p "$log_dir"
    local count
    count=$(find "$log_dir" -maxdepth 1 -type f -name "manager.log.*" 2>/dev/null | wc -l)
    if [ "$count" -ge "$max_files" ]; then
        find "$log_dir" -maxdepth 1 -type f -name "manager.log.*" | sort | head -n $((count - max_files + 1)) | xargs rm -f
    fi
    if [ -f "$log_dir/manager.log" ]; then
        local size
        size=$(stat -c%s "$log_dir/manager.log" 2>/dev/null || echo 0)
        if [ "$size" -gt 10485760 ]; then
            mv "$log_dir/manager.log" "$log_dir/manager.log.$(date +%s)"
        fi
    fi
}

xlr_build_additional_params() {
    local server_config="$1"
    local params=""
    local additional
    additional=$(echo "$server_config" | jq -r '.additional_params // {}')
    if [ "$additional" != "null" ] && [ -n "$additional" ]; then
        while IFS= read -r line; do
            local key value
            key=$(echo "$line" | awk '{print $1}')
            value=$(echo "$line" | cut -d' ' -f2-)
            if [ -n "$key" ] && [ "$value" != "null" ]; then
                params+=" +set $key $value"
            fi
        done < <(echo "$additional" | jq -r 'to_entries[] | "\(.key) \(.value)"')
    fi
    local extra_exec
    extra_exec=$(echo "$server_config" | jq -r '.extra_exec // empty')
    if [ -n "$extra_exec" ] && [ "$extra_exec" != "null" ]; then
        while IFS= read -r exec_line; do
            if [ -n "$exec_line" ] && [ "$exec_line" != "null" ]; then
                params+=" +exec $exec_line"
            fi
        done < <(echo "$server_config" | jq -r '.extra_exec[]?')
    fi
    echo "$params"
}

xlr_update_plutonium() {
    local install_dir="$1"
    if [ -x "$install_dir/plutonium-updater" ]; then
        "$install_dir/plutonium-updater" -d "$install_dir" >> "$install_dir/logs/updater.log" 2>&1 || true
    fi
}

xlr_launch_server_process() {
    local config_file="$1"
    local server_config="$2"

    local install_dir game_path game_mode server_key server_port config_file_name mod server_name server_id
    local log_dir stdout_log additional_params gamesetting

    install_dir=$(xlr_get_install_dir "$config_file")
    server_id=$(echo "$server_config" | jq -r '.id')
    server_name=$(echo "$server_config" | jq -r '.name')
    game_path=$(echo "$server_config" | jq -r '.game_path')
    game_mode=$(echo "$server_config" | jq -r '.mode')
    server_key=$(echo "$server_config" | jq -r '.key')
    server_port=$(echo "$server_config" | jq -r '.port')
    config_file_name=$(echo "$server_config" | jq -r '.config')
    mod=$(echo "$server_config" | jq -r '.mods // ""')
    gamesetting=$(echo "$server_config" | jq -r '.gamesetting // ""')
    additional_params=$(xlr_build_additional_params "$server_config")

    log_dir=$(xlr_server_log_dir "$config_file" "$server_id")
    stdout_log="$log_dir/stdout.log"
    mkdir -p "$log_dir"

    if [ -z "$game_path" ] || [ "$game_path" = "null" ]; then
        game_path=$(jq -r --arg mode "$game_mode" 'if $mode == "t6zm" then .general_config.game_path_zm else .general_config.game_path_mp end' "$config_file")
    fi

    cd "$install_dir" || return 1

    local gamesetting_param=""
    if [ -n "$gamesetting" ] && [ "$gamesetting" != "null" ]; then
        gamesetting_param="+exec $gamesetting"
    fi

    xlr_write_log "$log_dir" "$server_id" "Starting $server_name on port $server_port"

    nohup bash -c "
        while true; do
            nice -n -10 wine ./bin/plutonium-bootstrapper-win32.exe $game_mode $game_path -dedicated \
                +set key $server_key \
                +set fs_game $mod \
                +set net_port $server_port \
                +exec $config_file_name \
                $gamesetting_param \
                $additional_params \
                +map_rotate \
                >> \"$stdout_log\" 2>&1
            echo \"\$(date '+%Y-%m-%d %H:%M:%S') Server $server_id stopped, restarting...\" >> \"$log_dir/manager.log\"
            sleep 1
        done
    " >> "$log_dir/wrapper.log" 2>&1 &

    local wrapper_pid=$!
    echo "$wrapper_pid" > "$(xlr_server_pid_file "$config_file" "$server_id")"
    echo "running" > "$(xlr_server_state_file "$config_file" "$server_id")"
    sleep 3
    local game_pid
    game_pid=$(xlr_find_server_pid "$server_port")
    if [ -n "$game_pid" ]; then
        echo "$game_pid" > "$(xlr_server_pid_file "$config_file" "$server_id")"
    fi
    return 0
}

xlr_stop_server() {
    local config_file="$1"
    local server_config="$2"

    local server_id port pid wrapper_pid pid_file
    server_id=$(echo "$server_config" | jq -r '.id')
    port=$(echo "$server_config" | jq -r '.port')
    pid_file=$(xlr_server_pid_file "$config_file" "$server_id")
    local log_dir
    log_dir=$(xlr_server_log_dir "$config_file" "$server_id")

    pid=$(xlr_find_server_pid "$port")
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        sleep 2
        kill -9 "$pid" 2>/dev/null
    fi

    if [ -f "$pid_file" ]; then
        wrapper_pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$wrapper_pid" ] && kill -0 "$wrapper_pid" 2>/dev/null; then
            pkill -P "$wrapper_pid" 2>/dev/null
            kill "$wrapper_pid" 2>/dev/null
        fi
        rm -f "$pid_file"
    fi

    pkill -f "net_port $port" 2>/dev/null
    echo "stopped" > "$(xlr_server_state_file "$config_file" "$server_id")"
    xlr_write_log "$log_dir" "$server_id" "Server stopped"
}

xlr_send_discord_webhook() {
    local webhook_url="$1"
    local message="$2"
    if [ -z "$webhook_url" ] || [ "$webhook_url" = "null" ]; then
        return 0
    fi
    curl -s -H "Content-Type: application/json" \
        -d "{\"content\": $(echo "$message" | jq -Rs .)}" \
        "$webhook_url" > /dev/null 2>&1 || true
}

xlr_get_player_count() {
    local ip="$1"
    local port="$2"
    local rcon_password="$3"
    if [ -z "$rcon_password" ] || [ "$rcon_password" = "null" ]; then
        echo "0"
        return 0
    fi
    local response
    response=$(echo -e "\xff\xff\xff\xffrcon $rcon_password status" | nc -u -w 2 "$ip" "$port" 2>/dev/null || true)
    local count
    count=$(echo "$response" | grep -oE '[0-9]+ players' | grep -oE '[0-9]+' | head -n 1)
    if [ -n "$count" ]; then
        echo "$count"
    else
        echo "0"
    fi
}
