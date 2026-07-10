#!/bin/bash

readonly XLR_MANAGER_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly XLR_MANAGER_DIR=$(dirname "$XLR_MANAGER_PATH")

source "$XLR_MANAGER_DIR/lib/server_core.sh"

declare -A XLR_COLORS=(
    [reset]='\033[0m'
    [red]='\033[0;31m'
    [green]='\033[0;32m'
    [yellow]='\033[0;33m'
    [blue]='\033[0;34m'
    [cyan]='\033[0;36m'
)

xlr_default_config() {
    echo "$XLR_MANAGER_DIR/server_config.json"
}

xlr_check_dependencies() {
    local deps=("wine" "jq" "bc" "curl")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${XLR_COLORS[red]}Missing dependencies:${XLR_COLORS[reset]} ${missing[*]}"
        return 1
    fi
    return 0
}

xlr_display_help() {
    echo -e "${XLR_COLORS[blue]}XLR Server Manager${XLR_COLORS[reset]}"
    echo ""
    echo "Usage: $0 [command] [server_id]"
    echo ""
    echo "Commands:"
    echo "  start [id|all]     Start one or all enabled servers"
    echo "  stop [id|all]      Stop one or all servers"
    echo "  restart [id|all]   Restart one or all servers"
    echo "  status             Show server status"
    echo "  monitor            Monitor and auto-restart servers"
    echo "  backup             Run backup now"
    echo "  sync-iw4m          Sync IW4MAdmin server list"
    echo "  scheduled-restart  Restart idle servers based on schedule"
    echo "  sync-servers       Stop disabled servers and start enabled ones"
    echo "  validate-config    Check server_config.json integrity"
    echo "  restore-config     Restore server_config.json from latest backup"
    echo "  --help             Show this help"
    echo ""
    echo "Configuration: server_config.json"
}

xlr_get_server_by_id() {
    local config_file="$1"
    local server_id="$2"
    jq -c --arg id "$server_id" '.servers[] | select(.id == $id)' "$config_file"
}

xlr_foreach_server() {
    local config_file="$1"
    local target="$2"
    local callback="$3"

    if [ "$target" = "all" ] || [ -z "$target" ]; then
        while IFS= read -r server; do
            local enabled
            enabled=$(echo "$server" | jq -r '.enabled // true')
            if [ "$enabled" = "true" ]; then
                "$callback" "$config_file" "$server"
            fi
        done < <(jq -c '.servers[]' "$config_file")
    else
        local server
        server=$(xlr_get_server_by_id "$config_file" "$target")
        if [ -z "$server" ]; then
            echo -e "${XLR_COLORS[red]}Unknown server:${XLR_COLORS[reset]} $target"
            local reason
            reason=$(xlr_validate_server_config "$config_file" 2>&1 || true)
            if [ -n "$reason" ]; then
                echo -e "${XLR_COLORS[yellow]}Config problem:${XLR_COLORS[reset]} $reason"
                echo "Try: $0 restore-config"
            else
                echo "Configured servers: $(xlr_list_server_ids "$config_file" | paste -sd, -)"
            fi
            return 1
        fi
        "$callback" "$config_file" "$server"
    fi
}

xlr_cmd_validate_config() {
    local config_file="$1"
    local reason count

    if xlr_validate_server_config "$config_file" >/dev/null; then
        count=$(jq -r '.servers | length' "$config_file")
        echo -e "${XLR_COLORS[green]}OK${XLR_COLORS[reset]}: $config_file ($count servers)"
        jq -r '.servers[] | "  - \(.id) enabled=\(.enabled // true) port=\(.port)"' "$config_file"
        return 0
    fi

    reason=$(xlr_validate_server_config "$config_file")
    echo -e "${XLR_COLORS[red]}INVALID${XLR_COLORS[reset]}: $reason"
    echo "File: $config_file"
    if [ -f "${config_file}.bak" ]; then
        echo "Local backup exists: ${config_file}.bak"
    fi
    echo "Restore: $0 restore-config"
    return 1
}

xlr_cmd_restore_config() {
    local config_file="$1"
    if xlr_restore_server_config "$config_file"; then
        xlr_sync_config_paths "$config_file" || true
        echo -e "${XLR_COLORS[green]}Config restored. Verify with:${XLR_COLORS[reset]} $0 validate-config"
        return 0
    fi
    return 1
}

xlr_monitor_restart_server() {
    local config_file="$1"
    local server="$2"
    local reason="$3"
    local monitoring_log_dir webhook_url server_id

    server_id=$(echo "$server" | jq -r '.id')
    monitoring_log_dir=$(jq -r '.monitoring_config.log_directory // "./logs/monitoring"' "$config_file")
    if [[ "$monitoring_log_dir" != /* ]]; then
        monitoring_log_dir="$XLR_MANAGER_DIR/$monitoring_log_dir"
    fi
    webhook_url=$(jq -r '.monitoring_config.discord_webhook // ""' "$config_file")

    if ! xlr_monitor_restart_allowed "$config_file" "$server_id" 90; then
        xlr_write_log "$monitoring_log_dir" "$server_id" "Restart skipped (cooldown 90s): $reason"
        return 1
    fi

    xlr_write_log "$monitoring_log_dir" "$server_id" "$reason"
    xlr_send_discord_webhook "$webhook_url" "XLR: $server_id — $reason"
    xlr_stop_server "$config_file" "$server"
    sleep 2
    xlr_launch_server_process "$config_file" "$server"
    return 0
}

xlr_cmd_sync_servers() {
    local config_file="$1"
    while IFS= read -r server; do
        local enabled server_id port
        enabled=$(echo "$server" | jq -r '.enabled // true')
        server_id=$(echo "$server" | jq -r '.id')
        port=$(echo "$server" | jq -r '.port')
        if [ "$enabled" != "true" ]; then
            if xlr_is_server_running "$config_file" "$server_id" "$port" >/dev/null; then
                xlr_cmd_stop_one "$config_file" "$server"
            fi
        fi
    done < <(jq -c '.servers[]' "$config_file")
    xlr_foreach_server "$config_file" "all" xlr_cmd_start_one
}

xlr_cmd_start_one() {
    local config_file="$1"
    local server_config="$2"
    local server_id port pid
    server_id=$(echo "$server_config" | jq -r '.id')
    port=$(echo "$server_config" | jq -r '.port')
    if pid=$(xlr_is_server_running "$config_file" "$server_id" "$port"); then
        echo -e "${XLR_COLORS[yellow]}$server_id already running (pid $pid)${XLR_COLORS[reset]}"
        return 0
    fi
    if ! xlr_launch_server_process "$config_file" "$server_config"; then
        echo -e "${XLR_COLORS[red]}Failed to start $server_id${XLR_COLORS[reset]}"
        return 1
    fi
    echo -e "${XLR_COLORS[green]}Started $server_id on port $port${XLR_COLORS[reset]}"
}

xlr_cmd_stop_one() {
    local config_file="$1"
    local server_config="$2"
    local server_id
    server_id=$(echo "$server_config" | jq -r '.id')
    xlr_stop_server "$config_file" "$server_config"
    echo -e "${XLR_COLORS[green]}Stopped $server_id${XLR_COLORS[reset]}"
}

xlr_cmd_restart_one() {
    local config_file="$1"
    local server_config="$2"
    xlr_cmd_stop_one "$config_file" "$server_config"
    sleep 3
    xlr_cmd_start_one "$config_file" "$server_config"
}

xlr_cmd_status() {
    local config_file="$1"
    printf "%-16s %-8s %-8s %-10s %s\n" "SERVER" "PORT" "STATUS" "PLAYERS" "NAME"
    while IFS= read -r server; do
        local server_id port name pid status players rcon_ip rcon_pass enabled enabled_label
        server_id=$(echo "$server" | jq -r '.id')
        port=$(echo "$server" | jq -r '.port')
        name=$(echo "$server" | jq -r '.name')
        enabled=$(echo "$server" | jq -r '.enabled // true')
        if [ "$enabled" = "true" ]; then
            enabled_label=""
        else
            enabled_label=" (disabled)"
        fi
        rcon_ip=$(jq -r '.general_config.rcon_ip // "127.0.0.1"' "$config_file")
        rcon_pass=$(echo "$server" | jq -r '.rcon_password // .key')
        if pid=$(xlr_is_server_running "$config_file" "$server_id" "$port"); then
            status="${XLR_COLORS[green]}UP${XLR_COLORS[reset]}"
            players=$(xlr_get_player_count "$rcon_ip" "$port" "$rcon_pass")
        else
            status="${XLR_COLORS[red]}DOWN${XLR_COLORS[reset]}"
            players="-"
        fi
        printf "%-16s %-8s " "$server_id" "$port"
        echo -e -n "$status"
        printf " %-10s %s%s\n" "$players" "$name" "$enabled_label"
    done < <(jq -c '.servers[]' "$config_file")
}

xlr_monitor_once() {
    local config_file="$1"
    local monitoring_log_dir max_log_files webhook_url
    monitoring_log_dir=$(jq -r '.monitoring_config.log_directory // "./logs/monitoring"' "$config_file")
    if [[ "$monitoring_log_dir" != /* ]]; then
        monitoring_log_dir="$XLR_MANAGER_DIR/$monitoring_log_dir"
    fi
    max_log_files=$(jq -r '.monitoring_config.max_log_files // 30' "$config_file")
    webhook_url=$(jq -r '.monitoring_config.discord_webhook // ""' "$config_file")
    mkdir -p "$monitoring_log_dir"
    xlr_rotate_logs "$monitoring_log_dir" "$max_log_files"

    while IFS= read -r server; do
        local server_id port enabled max_cpu max_memory pid current_cpu current_memory
        server_id=$(echo "$server" | jq -r '.id')
        enabled=$(echo "$server" | jq -r '.enabled // true')
        [ "$enabled" != "true" ] && continue
        port=$(echo "$server" | jq -r '.port')
        max_cpu=$(echo "$server" | jq -r '.resource_limits.max_cpu_percent // 90')
        max_memory=$(echo "$server" | jq -r '.resource_limits.max_memory_mb // 4096')

        if ! pid=$(xlr_is_server_running "$config_file" "$server_id" "$port"); then
            local wrapper_pid wrapper_uptime
            if wrapper_pid=$(xlr_get_wrapper_pid "$config_file" "$server_id"); then
                wrapper_uptime=$(xlr_process_uptime_seconds "$wrapper_pid")
                if [ "$wrapper_uptime" -ge 45 ]; then
                    xlr_monitor_restart_server "$config_file" "$server" "Wrapper alive but no game process for ${wrapper_uptime}s, forcing full restart"
                else
                    xlr_write_log "$monitoring_log_dir" "$server_id" "Game process down, wrapper bootstrapping (${wrapper_uptime}s)"
                fi
                continue
            fi
            xlr_monitor_restart_server "$config_file" "$server" "Server down, restarting"
            continue
        fi

        if xlr_server_needs_recovery "$config_file" "$server_id" "$port" "$pid"; then
            xlr_monitor_restart_server "$config_file" "$server" "Server limbo (no map or UDP port down), restarting"
            continue
        fi

        current_cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
        current_memory=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print $1 / 1024}')
        current_cpu=${current_cpu:-0}
        current_memory=${current_memory:-0}
        local cpu_cores max_cpu_total
        cpu_cores=$(nproc 2>/dev/null || echo 1)
        max_cpu_total=$(echo "$max_cpu * $cpu_cores" | bc -l)

        xlr_write_log "$monitoring_log_dir" "$server_id" "CPU=${current_cpu}% MEM=${current_memory}MB PID=$pid"

        if (( $(echo "$current_cpu > $max_cpu_total" | bc -l) )) || (( $(echo "$current_memory > $max_memory" | bc -l) )); then
            xlr_monitor_restart_server "$config_file" "$server" "Resource limit exceeded, restarting"
        fi
    done < <(jq -c '.servers[]' "$config_file")
}

xlr_run_backup() {
    local config_file="$1"
    local workdir
    workdir=$(dirname "$(dirname "$XLR_MANAGER_DIR")")
    bash "$workdir/.config/xlr/runBackup.sh" "$config_file"
}

xlr_scheduled_restart() {
    local config_file="$1"
    local idle_hours rcon_ip
    idle_hours=$(jq -r '.restart_config.idle_hours // 2' "$config_file")
    rcon_ip=$(jq -r '.general_config.rcon_ip // "127.0.0.1"' "$config_file")
    local idle_seconds=$((idle_hours * 3600))

    while IFS= read -r server; do
        local server_id port rcon_pass pid uptime started_at player_count
        server_id=$(echo "$server" | jq -r '.id')
        port=$(echo "$server" | jq -r '.port')
        rcon_pass=$(echo "$server" | jq -r '.rcon_password // .key')
        if ! pid=$(xlr_is_server_running "$config_file" "$server_id" "$port"); then
            continue
        fi
        player_count=$(xlr_get_player_count "$rcon_ip" "$port" "$rcon_pass")
        started_at=$(ps -p "$pid" -o lstart= 2>/dev/null | xargs -I{} date -d "{}" +%s 2>/dev/null || echo 0)
        local now uptime_sec
        now=$(date +%s)
        uptime_sec=$((now - started_at))
        if [ "$player_count" -eq 0 ] && [ "$uptime_sec" -gt "$idle_seconds" ]; then
            xlr_write_log "$(xlr_server_log_dir "$config_file" "$server_id")" "$server_id" "Scheduled restart (idle)"
            xlr_cmd_restart_one "$config_file" "$server"
        fi
    done < <(jq -c '.servers[]' "$config_file")
}

xlr_main() {
    local command="${1:-}"
    local target="${2:-all}"
    local config_file
    config_file=$(xlr_resolve_config "${3:-}") || config_file=$(xlr_default_config)

    case "$command" in
        ""|--help|-h|help)
            xlr_display_help
            exit 0
            ;;
        start|stop|restart|status|monitor|backup|scheduled-restart|update|sync-iw4m|sync-servers|validate-config|restore-config)
            xlr_check_dependencies || exit 1
            ;;
        *)
            echo "Unknown command: $command"
            xlr_display_help
            exit 1
            ;;
    esac

    if [ ! -f "$config_file" ]; then
        echo -e "${XLR_COLORS[red]}Configuration not found:${XLR_COLORS[reset]} $config_file"
        exit 1
    fi

    if [ "$command" != "restore-config" ]; then
        local config_reason
        if ! config_reason=$(xlr_validate_server_config "$config_file"); then
            echo -e "${XLR_COLORS[red]}Invalid configuration:${XLR_COLORS[reset]} $config_reason"
            echo "Run: $0 restore-config"
            exit 1
        fi
        xlr_sync_config_paths "$config_file" || {
            echo -e "${XLR_COLORS[red]}Failed to sync install paths in server_config.json${XLR_COLORS[reset]}"
            exit 1
        }
    fi

    case "$command" in
        start)
            xlr_foreach_server "$config_file" "$target" xlr_cmd_start_one
            ;;
        stop)
            xlr_foreach_server "$config_file" "$target" xlr_cmd_stop_one
            ;;
        restart)
            xlr_foreach_server "$config_file" "$target" xlr_cmd_restart_one
            ;;
        status)
            xlr_cmd_status "$config_file"
            ;;
        monitor)
            local interval
            interval=$(jq -r '.monitoring_config.update_interval // 30' "$config_file")
            while true; do
                xlr_monitor_once "$config_file"
                sleep "$interval"
            done
            ;;
        backup)
            xlr_run_backup "$config_file"
            ;;
        sync-servers)
            xlr_cmd_sync_servers "$config_file"
            ;;
        validate-config)
            xlr_cmd_validate_config "$config_file"
            ;;
        restore-config)
            xlr_cmd_restore_config "$config_file"
            ;;
        sync-iw4m)
            local workdir
            workdir=$(dirname "$(dirname "$XLR_MANAGER_DIR")")
            source "$workdir/.config/config.sh"
            source "$workdir/.config/xlr/configureIW4MAdmin.sh" --import
            configureIW4MAdmin
            echo -e "${XLR_COLORS[green]}IW4MAdmin configuration synced${XLR_COLORS[reset]}"
            ;;
        scheduled-restart)
            xlr_scheduled_restart "$config_file"
            ;;
        update)
            xlr_update_plutonium "$(xlr_get_install_dir "$config_file")"
            echo -e "${XLR_COLORS[green]}Plutonium update completed${XLR_COLORS[reset]}"
            ;;
    esac
}

xlr_main "$@"
