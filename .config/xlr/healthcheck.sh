#!/bin/bash

readonly HEALTH_CONFIG="${1:-/opt/T6Server/Plutonium/server_config.json}"
readonly HEALTH_MANAGER="$(dirname "$HEALTH_CONFIG")/XLRManager.sh"
readonly HEALTH_LOG="/opt/T6Server/Plutonium/logs/monitoring/healthcheck.log"

mkdir -p "$(dirname "$HEALTH_LOG")"

if [ ! -f "$HEALTH_CONFIG" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') FAIL missing config" >> "$HEALTH_LOG"
    exit 1
fi

if [ ! -x "$HEALTH_MANAGER" ]; then
    chmod +x "$HEALTH_MANAGER"
fi

bash "$HEALTH_MANAGER" status > /tmp/xlr_health_status.txt 2>&1
cat /tmp/xlr_health_status.txt >> "$HEALTH_LOG"

if grep -q "DOWN" /tmp/xlr_health_status.txt; then
    webhook=$(jq -r '.monitoring_config.discord_webhook // ""' "$HEALTH_CONFIG")
    if [ -n "$webhook" ] && [ "$webhook" != "null" ]; then
        curl -s -H "Content-Type: application/json" \
            -d "{\"content\": \"XLR healthcheck: one or more servers are DOWN\"}" \
            "$webhook" > /dev/null 2>&1 || true
    fi
    exit 1
fi

exit 0
