#!/bin/bash

readonly RESTART_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly RESTART_WORKROOT=$(dirname "$(dirname "$RESTART_SCRIPT_DIR")")
readonly RESTART_CONFIG="$RESTART_WORKROOT/Plutonium/server_config.json"
readonly RESTART_MANAGER="$RESTART_WORKROOT/Plutonium/XLRManager.sh"

if [ ! -f "$RESTART_CONFIG" ]; then
    echo "Configuration not found: $RESTART_CONFIG"
    exit 1
fi

if [ ! -x "$RESTART_MANAGER" ]; then
    chmod +x "$RESTART_MANAGER"
fi

bash "$RESTART_MANAGER" scheduled-restart
