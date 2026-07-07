#!/bin/bash
# Plutonium T6 requires COMPILED .gsc (not source text).
# See: https://forum.plutonium.pw/topic/27664/gsc-tool-error-help

GSC_TOOL_VERSION="${GSC_TOOL_VERSION:-1.4.10}"

xlr_ensure_gsc_tool() {
    local tools_dir="$1"
    local gsc_tool="$tools_dir/gsc-tool"

    if [ -x "$gsc_tool" ]; then
        echo "$gsc_tool"
        return 0
    fi

    mkdir -p "$tools_dir"
    local arch asset url tmp found
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) asset="linux-amd64-release.tar.gz" ;;
        aarch64|arm64) asset="linux-arm64-release.tar.gz" ;;
        *)
            echo "[XLR] ERROR: unsupported CPU arch for gsc-tool: $arch" >&2
            return 1
            ;;
    esac

    url="https://github.com/xensik/gsc-tool/releases/download/${GSC_TOOL_VERSION}/${asset}"
    tmp="$tools_dir/gsc-tool-download.tar.gz"
    echo "[XLR] Downloading gsc-tool ${GSC_TOOL_VERSION} (${asset})..."
    if ! curl -fsSL "$url" -o "$tmp"; then
        echo "[XLR] ERROR: failed to download gsc-tool from GitHub" >&2
        return 1
    fi

    tar -xzf "$tmp" -C "$tools_dir"
    rm -f "$tmp"

    if [ -f "$tools_dir/gsc-tool" ]; then
        chmod +x "$tools_dir/gsc-tool"
        echo "$tools_dir/gsc-tool"
        return 0
    fi

    found="$(find "$tools_dir" -maxdepth 3 -type f -name gsc-tool 2>/dev/null | head -1)"
    if [ -n "$found" ]; then
        chmod +x "$found"
        echo "$found"
        return 0
    fi

    echo "[XLR] ERROR: gsc-tool binary not found after extract" >&2
    return 1
}

xlr_gsc_looks_compiled() {
    local file="$1"
    [ -f "$file" ] || return 1
    local first
    first="$(head -c 1 "$file" | od -An -tu1 2>/dev/null | tr -d ' ')"
    [ "$first" = "128" ]
}

xlr_compile_gsc_file() {
    local workdir="$1"
    local source_file="$2"
    local dest_file="$3"
    local log_file="${4:-$(dirname "$dest_file")/xlr_messages.compile.log}"
    local tools_dir="$workdir/.tools/gsc-tool"
    local gsc_tool compiled_out

    if [ ! -f "$source_file" ]; then
        echo "[XLR] ERROR: missing GSC source $source_file" >&2
        return 1
    fi

    if ! gsc_tool="$(xlr_ensure_gsc_tool "$tools_dir")"; then
        echo "[XLR] ERROR: gsc-tool not available — cannot compile (T6 needs compiled scripts)" >&2
        return 1
    fi

    mkdir -p "$(dirname "$dest_file")" "$(dirname "$log_file")"
    rm -rf "$workdir/compiled"

    local build_dir
    build_dir="$(dirname "$source_file")"
    (
        cd "$build_dir" || exit 1
        "$gsc_tool" -m comp -g t6 -s pc "$(basename "$source_file")"
    ) >"$log_file" 2>&1 || {
        echo "[XLR] ERROR: gsc-tool compile failed — see $log_file" >&2
        tail -20 "$log_file" >&2 || true
        return 1
    }

    compiled_out="$workdir/compiled/t6/$(basename "$source_file")"
    if [ ! -f "$compiled_out" ]; then
        echo "[XLR] ERROR: expected compiled output at $compiled_out" >&2
        tail -20 "$log_file" >&2 || true
        return 1
    fi

    cp "$compiled_out" "$dest_file"
    rm -rf "$workdir/compiled"

    if ! xlr_gsc_looks_compiled "$dest_file"; then
        echo "[XLR] ERROR: deploy file is still source text, not compiled binary" >&2
        return 1
    fi

    echo "[XLR] GSC compiled OK -> $dest_file ($(wc -c < "$dest_file") bytes)"
    return 0
}
