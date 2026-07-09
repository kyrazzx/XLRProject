#!/bin/bash
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKROOT="$(cd "$DIR/../.." && pwd)"
CONFIG="$WORKROOT/Plutonium/server_config.json"
TARGET="${1:-all}"
TAIL_LINES="${2:-120}"

if [ ! -f "$CONFIG" ]; then
    echo "Config not found: $CONFIG" >&2
    exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "Missing jq" >&2; exit 1; }

servers_root=$(jq -r '.general_config.servers_root // "./servers"' "$CONFIG")
if [[ "$servers_root" != /* ]]; then
    servers_root="$WORKROOT/Plutonium/${servers_root#./}"
fi

PATTERNS='error|fatal|assert|crash|exception|corrupt|fastfile|ipak|zone|overflow|stack|signal|segfault|abort|wine:|err:|out of memory|cannot load|missing|failed'

echo "=== XLR crash diagnostic ==="
echo "workroot: $WORKROOT"
echo "time:     $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

echo "=== Kernel (OOM / segfault last 30 min) ==="
if command -v journalctl >/dev/null 2>&1; then
    journalctl -k --since "30 min ago" --no-pager 2>/dev/null \
        | grep -iE 'oom|killed process|segfault|out of memory|wine|plutonium' \
        | tail -20 || echo "(nothing relevant)"
else
    dmesg -T 2>/dev/null | grep -iE 'oom|killed process|segfault|out of memory|wine' | tail -20 || echo "(dmesg unavailable)"
fi
echo ""

echo "=== Memory / disk ==="
free -h 2>/dev/null || true
df -h "$WORKROOT" 2>/dev/null | tail -1 || true
echo ""

while IFS= read -r server_json; do
    sid=$(echo "$server_json" | jq -r '.id')
    port=$(echo "$server_json" | jq -r '.port')
    name=$(echo "$server_json" | jq -r '.name')
    enabled=$(echo "$server_json" | jq -r '.enabled // true')

    if [ "$enabled" != "true" ]; then
        continue
    fi
    if [ "$TARGET" != "all" ] && [ "$TARGET" != "$sid" ]; then
        continue
    fi

    log_dir="$servers_root/$sid/logs"
    stdout="$log_dir/stdout.log"
    manager="$log_dir/manager.log"
    wrapper="$log_dir/wrapper.log"
    monitoring="$WORKROOT/Plutonium/logs/monitoring/manager.log"

    echo "########################################################"
    echo "# $name ($sid) port $port"
    echo "########################################################"

    if pgrep -f "net_port \"$port\"" >/dev/null 2>&1 || pgrep -f "net_port $port" >/dev/null 2>&1; then
        echo "process: RUNNING"
    else
        echo "process: DOWN"
    fi

    if [ -f "$log_dir/../server.pid" ]; then
        echo "wrapper pid file: $(cat "$log_dir/../server.pid" 2>/dev/null || echo '?')"
    fi

    echo ""
    echo "--- manager.log (last restarts) ---"
    if [ -f "$manager" ]; then
        grep -E 'Starting|stopped|restart|stopped|Failed|permission' "$manager" 2>/dev/null | tail -15 || tail -15 "$manager"
    else
        echo "(missing $manager)"
    fi

    echo ""
    echo "--- monitoring (resource kills) ---"
    if [ -f "$monitoring" ]; then
        grep "$sid" "$monitoring" 2>/dev/null | tail -10 || echo "(no entries for $sid)"
    else
        echo "(no monitoring log)"
    fi

    echo ""
    echo "--- wrapper.log (Wine errors, last $TAIL_LINES lines) ---"
    if [ -f "$wrapper" ]; then
        tail -n "$TAIL_LINES" "$wrapper" | grep -iE "$PATTERNS" | tail -25
        if ! tail -n "$TAIL_LINES" "$wrapper" | grep -qiE "$PATTERNS"; then
            tail -5 "$wrapper"
        fi
    else
        echo "(missing $wrapper)"
    fi

    echo ""
    echo "--- stdout.log context (last crash window) ---"
    if [ ! -f "$stdout" ]; then
        echo "(missing $stdout)"
        echo ""
        continue
    fi

    echo "file size: $(stat -c%s "$stdout" 2>/dev/null || echo '?') bytes"
    echo ""
    echo "last map / rotate hints:"
    grep -iE 'Loading level|load map|map_rotate|----->|started map|ending map|gsc script|script compile' "$stdout" 2>/dev/null | tail -12 || echo "(none found)"
    echo ""
    echo "error lines (last 40 matches):"
    grep -niE "$PATTERNS" "$stdout" 2>/dev/null | tail -40 || echo "(no error pattern matches)"
    echo ""
    echo "last $TAIL_LINES lines of stdout.log:"
    tail -n "$TAIL_LINES" "$stdout"
    echo ""
done < <(jq -c '.servers[]' "$CONFIG")

echo "=== Done ==="
echo "Usage: $0 [server_id] [tail_lines]"
echo "Example: $0 tdm 200"
