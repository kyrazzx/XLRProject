#!/bin/bash


importFunctions() {
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
    local current_file="$(basename "${BASH_SOURCE[0]}")"
    declare -A imported

    while IFS= read -r -d '' func_file; do
        local rel_path="${func_file#$SCRIPT_DIR/}"
        if [[ "$rel_path" =~ ^utility/dev/ ]]; then
            continue
        fi
        if [[ "$rel_path" == "config.sh" ]]; then
            continue
        fi
        if [[ "$rel_path" == "utility/distro.sh" || "$rel_path" == "utility/colors.sh" ]]; then
            continue
        fi
        if [[ "$rel_path" == "xlr/healthcheck.sh" ]]; then
            continue
        fi
        if [[ "$rel_path" != "$current_file" && -z "${imported[$rel_path]}" ]]; then
            if [[ "$1" == "--debug" ]]; then
                echo "Importing: $rel_path"  # Debug output
            fi
            imported[$rel_path]=1
            source "$func_file" --import
        fi
    done < <(find "$SCRIPT_DIR" -type f -name "*.sh" -print0)
}

if [[ -z "$FUNCTIONS_IMPORTED" ]]; then
    FUNCTIONS_IMPORTED=1
    importFunctions "$1"
fi
