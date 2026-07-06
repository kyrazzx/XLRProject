#!/bin/bash

runHealthcheck() {
    local health_config="${1:-/opt/T6Server/Plutonium/server_config.json}"
    local health_manager
    local health_log="/opt/T6Server/Plutonium/logs/monitoring/healthcheck.log"

    health_manager="$(dirname "$health_config")/XLRManager.sh"

    mkdir -p "$(dirname "$health_log")"

    if [ ! -f "$health_config" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') FAIL missing config" >> "$health_log"
        return 1
    fi

    if [ ! -x "$health_manager" ]; then
        chmod +x "$health_manager"
    fi

    bash "$health_manager" status > /tmp/xlr_health_status.txt 2>&1
    cat /tmp/xlr_health_status.txt >> "$health_log"

    if grep -q "DOWN" /tmp/xlr_health_status.txt; then
        local webhook
        webhook=$(jq -r '.monitoring_config.discord_webhook // ""' "$health_config")
        if [ -n "$webhook" ] && [ "$webhook" != "null" ]; then
            curl -s -H "Content-Type: application/json" \
                -d "{\"content\": \"XLR healthcheck: one or more servers are DOWN\"}" \
                "$webhook" > /dev/null 2>&1 || true
        fi
        return 1
    fi

    return 0
}

if [ "$1" = "--import" ]; then
    :
elif [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    runHealthcheck "$@"
fi
