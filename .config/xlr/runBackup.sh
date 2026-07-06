#!/bin/bash

resolve_workdir_from_config() {
    local config_file="$1"
    local install_dir
    install_dir=$(jq -r '.general_config.install_dir // "/opt/T6Server/Plutonium"' "$config_file")
    dirname "$(dirname "$install_dir")"
}

runBackup() {
    local config_file="${1:-/opt/T6Server/Plutonium/server_config.json}"
    if [ ! -f "$config_file" ]; then
        echo "Configuration not found: $config_file"
        return 1
    fi

    local enabled
    enabled=$(jq -r '.backup_config.enabled // true' "$config_file")
    if [ "$enabled" != "true" ]; then
        return 0
    fi

    local workdir backup_dir retention_days timestamp archive_name paths_file
    workdir=$(resolve_workdir_from_config "$config_file")
    backup_dir=$(jq -r '.backup_config.backup_dir // .general_config.backup_dir // ""' "$config_file")
    if [ -z "$backup_dir" ] || [ "$backup_dir" = "null" ]; then
        backup_dir="$workdir/backups"
    fi
    retention_days=$(jq -r '.backup_config.retention_days // 14' "$config_file")
    timestamp=$(date +%Y%m%d_%H%M%S)
    archive_name="xlr_backup_${timestamp}.tar.gz"

    mkdir -p "$backup_dir"
    paths_file=$(mktemp)

    while IFS= read -r rel_path; do
        if [ -n "$rel_path" ] && { [ -d "$workdir/$rel_path" ] || [ -f "$workdir/$rel_path" ]; }; then
            echo "$workdir/$rel_path"
        fi
    done < <(jq -r '.backup_config.paths[]?' "$config_file") > "$paths_file"

    if [ ! -s "$paths_file" ]; then
        rm -f "$paths_file"
        echo "No backup paths found"
        return 1
    fi

    tar -czf "$backup_dir/$archive_name" -T "$paths_file" 2>/dev/null
    rm -f "$paths_file"

    find "$backup_dir" -maxdepth 1 -type f -name "xlr_backup_*.tar.gz" -mtime +"$retention_days" -delete 2>/dev/null

    echo "Backup created: $backup_dir/$archive_name"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    runBackup "$@"
fi
