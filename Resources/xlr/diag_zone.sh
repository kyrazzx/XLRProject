#!/bin/bash
set -uo pipefail

xlr_resolve_workroot() {
    local start="${1:-$(pwd)}"
    local dir
    dir="$(cd "$start" 2>/dev/null && pwd)" || dir="$start"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/Plutonium/server_config.json" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    if [ -n "${XLR_PROJECT:-}" ] && [ -f "$XLR_PROJECT/Plutonium/server_config.json" ]; then
        echo "$XLR_PROJECT"
        return 0
    fi
    return 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKROOT="$(xlr_resolve_workroot "$SCRIPT_DIR")" || WORKROOT="$(xlr_resolve_workroot "$(pwd)")" || {
    echo "ERROR: cannot find XLR project root (no Plutonium/server_config.json)." >&2
    echo "Run from ~/XLRProject or set: export XLR_PROJECT=/home/bo2/XLRProject" >&2
    exit 1
}

ZONE="$WORKROOT/Resources/binaries/zone"
MP_ZONE="$WORKROOT/Server/Multiplayer/zone"

echo "=== XLR zone audit ==="
echo "workroot: $WORKROOT"
echo ""

if [ -L "$MP_ZONE" ]; then
    echo "Multiplayer zone symlink:"
    ls -la "$MP_ZONE"
    echo "  -> $(readlink -f "$MP_ZONE")"
elif [ -d "$MP_ZONE" ]; then
    echo "Multiplayer zone: directory (not symlink)"
else
    echo "Multiplayer zone: MISSING ($MP_ZONE)"
fi
echo ""

if [ ! -d "$ZONE" ]; then
    echo "ERROR: $ZONE does not exist"
    echo ""
    echo "Expected layout:"
    echo "  $WORKROOT/Resources/binaries/zone/"
    echo "  $WORKROOT/Server/Multiplayer/zone -> symlink to binaries/zone"
    exit 1
fi

echo "=== Top-level zone/ ==="
ls -la "$ZONE" 2>/dev/null | head -20
echo ""

for sub in all english french; do
    if [ -d "$ZONE/$sub" ]; then
        ff=$(find "$ZONE/$sub" -maxdepth 1 -type f \( -name '*.ff' -o -name '*.FF' \) 2>/dev/null | wc -l)
        ipak=$(find "$ZONE/$sub" -maxdepth 1 -type f -name '*.ipak' 2>/dev/null | wc -l)
        echo "zone/$sub: $ff fastfiles, $ipak ipaks"
    else
        echo "zone/$sub: MISSING"
    fi
done
echo ""

echo "=== Critical names (Plutonium dedicated probes these) ==="
check_file() {
    local label="$1"
    local path="$2"
    if [ -f "$path" ]; then
        local sz
        sz=$(stat -c%s "$path" 2>/dev/null || echo 0)
        printf "  OK   %-28s %10s bytes\n" "$label" "$sz"
    else
        printf "  MISS %-28s\n" "$label"
    fi
}

for name in en_base.ipak common_mp.ipak code_post_gfx_mp.ipak lowmip.ipak code_pre_gfx_mp.ff; do
    found=""
    for base in "$ZONE/all" "$ZONE/english" "$ZONE"; do
        [ -f "$base/$name" ] && found="$base/$name" && break
    done
    if [ -n "$found" ]; then
        sz=$(stat -c%s "$found" 2>/dev/null || echo 0)
        printf "  OK   %-28s %s (%s bytes)\n" "$name" "$found" "$sz"
    else
        printf "  MISS %-28s (not in all/, english/, or zone/ root)\n" "$name"
    fi
done
echo ""

echo "=== All .ipak files found ==="
find "$ZONE" -name '*.ipak' 2>/dev/null | sort | while read -r f; do
    sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
    printf "  %10s  %s\n" "$sz" "${f#$ZONE/}"
done
echo ""

echo "=== Notes ==="
echo "- 'ipak file not found' in stdout.log is often NORMAL: the engine tries"
echo "  zone/all/ then zone/english/ and may already have assets in memory."
echo "- If the server runs for hours, missing lines above are not your crash cause."
echo "- Retail Steam BO2 often has zone/english/*.ff only, without zone/all/."
echo "  Plutonium dedicated prefers zone/all/ + zone/english/ layout."
echo ""
echo "If zone/all/ is missing but english/ has files, try:"
echo "  mkdir -p $ZONE/all"
echo "  cp -al $ZONE/english/*.ff $ZONE/all/ 2>/dev/null || true"
echo "  (only if .ff exist in english/ — do not copy broken symlinks)"
echo ""
echo "Real crash after uptime? Check monitor restarts:"
echo "  grep -E 'limbo|Resource limit|restarting' $WORKROOT/Plutonium/logs/monitoring/manager.log | tail -15"
