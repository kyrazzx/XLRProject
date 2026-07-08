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
    local configured
    configured=$(jq -r '.general_config.install_dir // ""' "$config_file")
    if [ -n "$configured" ] && [ "$configured" != "null" ] && [ -f "$configured/bin/plutonium-bootstrapper-win32.exe" ]; then
        echo "$configured"
        return 0
    fi
    echo "$XLR_PLUTONIUM_DIR"
}

xlr_get_workdir() {
    local config_file="$1"
    dirname "$(xlr_get_install_dir "$config_file")"
}

xlr_sync_config_paths() {
    local config_file="$1"
    local workdir plutonium_dir
    workdir=$(xlr_get_workdir "$config_file")
    plutonium_dir="$XLR_PLUTONIUM_DIR"
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    jq --arg w "$workdir" --arg pd "$plutonium_dir" --arg mp "$workdir/Server/Multiplayer" --arg zm "$workdir/Server/Zombie" '
        .general_config.install_dir = $pd |
        .general_config.game_path_mp = $mp |
        .general_config.game_path_zm = $zm |
        .general_config.backup_dir = ($w + "/backups") |
        .iw4madmin_config.install_dir = ($w + "/IW4MAdmin") |
        .iw4madmin_config.manual_log_path = ($pd + "/storage/t6/logs") |
        .servers |= map(.game_path = (if .mode == "t6zm" then $zm else $mp end))
    ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
}

xlr_resolve_game_path() {
    local config_file="$1"
    local server_config="$2"
    local game_path mode workdir
    game_path=$(echo "$server_config" | jq -r '.game_path // ""')
    mode=$(echo "$server_config" | jq -r '.mode')
    workdir=$(xlr_get_workdir "$config_file")
    if [ -n "$game_path" ] && [ "$game_path" != "null" ] && [ -d "$game_path" ]; then
        echo "$game_path"
        return 0
    fi
    if [ "$mode" = "t6zm" ]; then
        echo "$workdir/Server/Zombie"
    else
        echo "$workdir/Server/Multiplayer"
    fi
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
    local pid comm cmdline
    while IFS= read -r pid; do
        [ -z "$pid" ] && continue
        comm=$(ps -p "$pid" -o comm= 2>/dev/null | tr -d ' ')
        case "$comm" in
            bash|sh|nohup|runuser|sudo|sleep|nice) continue ;;
        esac
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
        if echo "$cmdline" | grep -Eq "net_port[[:space:]]+\"?${port}\"?"; then
            echo "$pid"
            return 0
        fi
    done < <(pgrep -f "plutonium-bootstrapper-win32.exe" 2>/dev/null)
    return 1
}

xlr_is_wrapper_running() {
    local port="$1"
    pgrep -f "servers/.*/logs/stdout.log" | while read -r pid; do
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "net_port $port" && echo "$pid" && return 0
    done
    pgrep -f "net_port \"$port\"" | head -n 1
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
            if xlr_find_server_pid "$port" >/dev/null; then
                echo "$(xlr_find_server_pid "$port")"
                return 0
            fi
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

xlr_get_run_user() {
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        echo "$SUDO_USER"
        return 0
    fi
    if [ "$(id -u)" -eq 0 ]; then
        local install_owner
        install_owner=$(stat -c '%U' "$XLR_PLUTONIUM_DIR" 2>/dev/null)
        if [ -n "$install_owner" ] && [ "$install_owner" != "root" ]; then
            echo "$install_owner"
            return 0
        fi
    fi
    id -un
}

xlr_get_run_user_home() {
    getent passwd "$(xlr_get_run_user)" | cut -d: -f6
}

xlr_prepare_bootstrapper() {
    local bootstrapper="$1"
    if [ ! -f "$bootstrapper" ]; then
        return 1
    fi
    chmod +x "$bootstrapper" 2>/dev/null || true
    return 0
}

xlr_update_plutonium() {
    local install_dir="$1"
    if [ -x "$install_dir/plutonium-updater" ]; then
        mkdir -p "$install_dir/logs"
        "$install_dir/plutonium-updater" -d "$install_dir" >> "$install_dir/logs/updater.log" 2>&1 || true
    fi
}

xlr_ensure_plutonium_bootstrapper() {
    local install_dir="$1"
    local bootstrapper="$install_dir/bin/plutonium-bootstrapper-win32.exe"

    if xlr_prepare_bootstrapper "$bootstrapper"; then
        return 0
    fi

    if [ ! -x "$install_dir/plutonium-updater" ]; then
        return 1
    fi

    mkdir -p "$install_dir/logs"
    "$install_dir/plutonium-updater" -d "$install_dir" >> "$install_dir/logs/updater.log" 2>&1
    xlr_prepare_bootstrapper "$bootstrapper"
}

xlr_launch_server_process() {
    local config_file="$1"
    local server_config="$2"

    local install_dir game_path game_mode server_key server_port server_rcon config_file_name mod server_name server_id
    local log_dir stdout_log additional_params gamesetting bootstrapper wine_home

    install_dir=$(xlr_get_install_dir "$config_file")
    bootstrapper="$install_dir/bin/plutonium-bootstrapper-win32.exe"
    wine_home=$(xlr_get_run_user_home)
    server_id=$(echo "$server_config" | jq -r '.id')
    server_name=$(echo "$server_config" | jq -r '.name')
    game_path=$(echo "$server_config" | jq -r '.game_path')
    game_mode=$(echo "$server_config" | jq -r '.mode')
    server_key=$(echo "$server_config" | jq -r '.key')
    server_port=$(echo "$server_config" | jq -r '.port')
    server_rcon=$(echo "$server_config" | jq -r '.rcon_password // .key // ""')
    config_file_name=$(echo "$server_config" | jq -r '.config')
    mod=$(echo "$server_config" | jq -r '.mods // ""')
    gamesetting=$(echo "$server_config" | jq -r '.gamesetting // ""')
    additional_params=$(xlr_build_additional_params "$server_config")

    log_dir=$(xlr_server_log_dir "$config_file" "$server_id")
    stdout_log="$log_dir/stdout.log"
    mkdir -p "$log_dir"

    if [ -z "$game_path" ] || [ "$game_path" = "null" ] || [ ! -d "$game_path" ]; then
        game_path=$(xlr_resolve_game_path "$config_file" "$server_config")
    fi

    cd "$install_dir" || return 1

    if ! xlr_ensure_plutonium_bootstrapper "$install_dir"; then
        xlr_write_log "$log_dir" "$server_id" "Missing plutonium-bootstrapper-win32.exe - run: ./install-plutonium.sh"
        return 1
    fi

    local gamesetting_param=""
    local run_user wine_runner
    run_user=$(xlr_get_run_user)
    wine_home=$(xlr_get_run_user_home)
    if [ "$(id -u)" -eq 0 ] && [ "$run_user" != "root" ]; then
        wine_runner="runuser -u $run_user --"
        chown -R "$run_user:$run_user" "$(xlr_get_servers_root "$config_file")/$server_id" 2>/dev/null || true
    else
        wine_runner=""
    fi

    xlr_write_log "$log_dir" "$server_id" "Starting $server_name on port $server_port"

    nohup $wine_runner bash -c "
        export WINEPREFIX=\"$wine_home/.wine\"
        export WINEDEBUG=\"-all\"
        export WINEARCH=\"win64\"
        export XDG_RUNTIME_DIR=\"/tmp/xlr-runtime-\$\$\"
        mkdir -p \"\$XDG_RUNTIME_DIR\"
        chmod 700 \"\$XDG_RUNTIME_DIR\"
        cd \"$install_dir\" || exit 1
        while true; do
            nice -n -10 wine \"$bootstrapper\" \"$game_mode\" \"$game_path\" -dedicated \
                +set key \"$server_key\" \
                +set fs_game \"$mod\" \
                +set net_ip \"0.0.0.0\" \
                +set net_port \"$server_port\" \
                +exec \"$config_file_name\" \
                $gamesetting_param \
                $additional_params \
                +set rcon_password \"$server_rcon\" \
                +map_rotate \
                >> \"$stdout_log\" 2>&1
            echo \"\$(date '+%Y-%m-%d %H:%M:%S') Server $server_id stopped, restarting...\" >> \"$log_dir/manager.log\"
            sleep 1
        done
    " >> "$log_dir/wrapper.log" 2>&1 &

    local wrapper_pid=$!
    echo "$wrapper_pid" > "$(xlr_server_pid_file "$config_file" "$server_id")"
    echo "running" > "$(xlr_server_state_file "$config_file" "$server_id")"
    return 0
}

xlr_stop_server() {
    local config_file="$1"
    local server_config="$2"

    local server_id port pid wrapper_pid pid_file stdout_log
    server_id=$(echo "$server_config" | jq -r '.id')
    port=$(echo "$server_config" | jq -r '.port')
    pid_file=$(xlr_server_pid_file "$config_file" "$server_id")
    stdout_log=$(xlr_server_log_dir "$config_file" "$server_id")/stdout.log
    local log_dir
    log_dir=$(xlr_server_log_dir "$config_file" "$server_id")

    if [ -f "$pid_file" ]; then
        wrapper_pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$wrapper_pid" ]; then
            pkill -P "$wrapper_pid" 2>/dev/null
            kill "$wrapper_pid" 2>/dev/null
            sleep 1
            kill -9 "$wrapper_pid" 2>/dev/null
        fi
        rm -f "$pid_file"
    fi

    pkill -f "$stdout_log" 2>/dev/null
    pkill -f "net_port $port" 2>/dev/null

    pid=$(xlr_find_server_pid "$port")
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        sleep 1
        kill -9 "$pid" 2>/dev/null
    fi

    sleep 1
    if xlr_find_server_pid "$port" >/dev/null; then
        pkill -9 -f "net_port $port" 2>/dev/null
        fuser -k "${port}/udp" 2>/dev/null || true
    fi

    echo "stopped" > "$(xlr_server_state_file "$config_file" "$server_id")" 2>/dev/null || true
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

xlr_port_listening() {
    local port="$1"
    ss -H -ulnp 2>/dev/null | grep -q ":${port} "
}

xlr_server_log_shows_limbo() {
    local stdout_log="$1"
    [ ! -f "$stdout_log" ] && return 1
    tail -200 "$stdout_log" | grep -qiE "No current map loaded|No map specified in sv_mapRotation|map_restart will do nothing"
}

xlr_process_uptime_seconds() {
    local pid="$1"
    local started_at now
    started_at=$(ps -p "$pid" -o lstart= 2>/dev/null | xargs -I{} date -d "{}" +%s 2>/dev/null || echo 0)
    now=$(date +%s)
    echo $((now - started_at))
}

xlr_server_needs_recovery() {
    local config_file="$1"
    local server_id="$2"
    local port="$3"
    local pid="$4"

    local stdout_log uptime_sec
    stdout_log="$(xlr_server_log_dir "$config_file" "$server_id")/stdout.log"

    if xlr_server_log_shows_limbo "$stdout_log"; then
        return 0
    fi

    uptime_sec=$(xlr_process_uptime_seconds "$pid")
    if [ "$uptime_sec" -ge 90 ] && ! xlr_port_listening "$port"; then
        return 0
    fi

    return 1
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
