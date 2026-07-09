#!/bin/bash

xlr_detect_run_user() {
    local workdir="$1"
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        echo "$SUDO_USER"
        return 0
    fi
    local owner
    owner=$(stat -c '%U' "$workdir/Plutonium" 2>/dev/null)
    if [ -n "$owner" ] && [ "$owner" != "root" ]; then
        echo "$owner"
        return 0
    fi
    owner=$(stat -c '%U' "$workdir" 2>/dev/null)
    if [ -n "$owner" ] && [ "$owner" != "root" ]; then
        echo "$owner"
        return 0
    fi
    id -un
}

xlr_chown_path() {
    local user="$1" group="$2" path="$3"
    [ -e "$path" ] || return 0
    if [ "$(id -u)" -eq 0 ]; then
        chown -R "$user:$group" "$path" 2>/dev/null || true
    elif command -v sudo >/dev/null 2>&1; then
        sudo chown -R "$user:$group" "$path" 2>/dev/null || true
    fi
}

xlr_repair_permissions() {
    local workdir="${1:-}"
    if [ -z "$workdir" ] || [ ! -d "$workdir/Plutonium" ]; then
        echo "[XLR] repairPermissions: invalid workdir" >&2
        return 1
    fi

    local run_user run_group
    run_user=$(xlr_detect_run_user "$workdir")
    run_group=$(id -gn "$run_user" 2>/dev/null || echo "$run_user")

    echo "[XLR] Repairing ownership ($run_user:$run_group) and modes under $workdir"

    if [ -f "$workdir/.config/xlr/normalizeLineEndings.sh" ]; then
        # shellcheck source=/dev/null
        source "$workdir/.config/xlr/normalizeLineEndings.sh" --import
        xlr_normalize_line_endings "$workdir" || true
    fi

    local path
    for path in \
        "$workdir/Plutonium" \
        "$workdir/Server" \
        "$workdir/Resources" \
        "$workdir/backups" \
        "$workdir/logs" \
        "$workdir/IW4MAdmin" \
        "$workdir/.build" \
        "$workdir/.tools"
    do
        xlr_chown_path "$run_user" "$run_group" "$path"
    done

    if [ -f /etc/xlr/secrets.env ]; then
        if [ "$(id -u)" -eq 0 ]; then
            chown root:"$run_group" /etc/xlr/secrets.env 2>/dev/null || true
            chmod 640 /etc/xlr/secrets.env 2>/dev/null || true
        elif command -v sudo >/dev/null 2>&1; then
            sudo chown root:"$run_group" /etc/xlr/secrets.env 2>/dev/null || true
            sudo chmod 640 /etc/xlr/secrets.env 2>/dev/null || true
        fi
    fi

    find "$workdir" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
    find "$workdir/Resources/xlr" -maxdepth 1 -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

    local exe
    for exe in \
        "$workdir/Plutonium/plutonium-updater" \
        "$workdir/Plutonium/bin/plutonium-bootstrapper-win32.exe" \
        "$workdir/.tools/gsc-tool/gsc-tool"
    do
        [ -f "$exe" ] && chmod +x "$exe" 2>/dev/null || true
    done

    if [ -d "$workdir/Resources/binaries/zone" ]; then
        chmod -R a+rX "$workdir/Resources/binaries/zone" 2>/dev/null || true
        find "$workdir/Resources/binaries/zone" -type d -exec chmod u+rwx {} + 2>/dev/null || true
    fi

    if [ -d "$workdir/Plutonium/servers" ]; then
        find "$workdir/Plutonium/servers" -type d -exec chmod u+rwx {} + 2>/dev/null || true
        find "$workdir/Plutonium/servers" -type f -name '*.log' -exec chmod u+rw {} + 2>/dev/null || true
    fi

    if [ -d "$workdir/Resources/xlr/venv" ]; then
        xlr_chown_path "$run_user" "$run_group" "$workdir/Resources/xlr/venv"
    fi

    chmod u+rw "$workdir/Plutonium/server_config.json" 2>/dev/null || true
    find "$workdir/Server/Multiplayer/main" -maxdepth 1 -name 'dedicated*.cfg' -exec chmod u+rw {} + 2>/dev/null || true

    return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    while [ "$ROOT" != "/" ]; do
        if [ -f "$ROOT/Plutonium/server_config.json" ]; then
            xlr_repair_permissions "$ROOT"
            exit $?
        fi
        ROOT="$(dirname "$ROOT")"
    done
    echo "Usage: source repairPermissions.sh; xlr_repair_permissions /path/to/XLRProject" >&2
    exit 1
fi
