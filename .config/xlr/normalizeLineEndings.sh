#!/bin/bash

XLR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XLR_WORKDIR="$(cd "$XLR_SCRIPT_DIR/../.." && pwd)"

xlr_normalize_line_endings() {
    local workdir="${1:-$XLR_WORKDIR}"
    local fixed=0
    local path

    if [ ! -d "$workdir" ]; then
        echo "[XLR] normalizeLineEndings: invalid workdir" >&2
        return 1
    fi

    if command -v python3 >/dev/null 2>&1; then
        fixed=$(python3 - "$workdir" <<'PY'
import pathlib
import sys

workdir = pathlib.Path(sys.argv[1])
suffixes = {
    ".sh", ".bash", ".py", ".json", ".md", ".yml", ".yaml",
    ".cfg", ".gsc", ".txt", ".service",
}
names = {
    "xlr-update.sh", "xlr-configure.sh", "install.sh", "uninstall.sh",
    "import-game-files.sh", "install-plutonium.sh", ".editorconfig", ".gitattributes",
}
skip_dirs = {".git", ".build", "node_modules", "__pycache__", "venv"}
fixed = 0

for path in workdir.rglob("*"):
    if not path.is_file():
        continue
    if any(part in skip_dirs for part in path.parts):
        continue
    if path.suffix.lower() not in suffixes and path.name not in names:
        continue
    try:
        data = path.read_bytes()
    except OSError:
        continue
    if b"\r" not in data:
        continue
    path.write_bytes(data.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))
    fixed += 1

print(fixed)
PY
)
    else
        while IFS= read -r -d '' path; do
            if grep -q $'\r' "$path" 2>/dev/null; then
                tr -d '\r' <"$path" >"${path}.lf" && mv -f "${path}.lf" "$path"
                fixed=$((fixed + 1))
            fi
        done < <(find "$workdir" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.json' -o -name '*.cfg' -o -name '*.gsc' -o -name '*.service' -o -name 'xlr-update.sh' -o -name 'xlr-configure.sh' -o -name 'install.sh' -o -name 'uninstall.sh' -o -name 'import-game-files.sh' -o -name 'install-plutonium.sh' \) ! -path '*/.git/*' ! -path '*/.build/*' ! -path '*/venv/*' -print0 2>/dev/null)
    fi

    if [ "${fixed:-0}" -gt 0 ]; then
        echo "[XLR] Normalized line endings (CRLF -> LF) in $fixed file(s)"
    fi
    return 0
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    xlr_normalize_line_endings "${2:-$XLR_WORKDIR}"
else
    echo "Usage: $0 [--install] [workdir] | [--import]"
fi
