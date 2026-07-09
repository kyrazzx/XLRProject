#!/bin/bash

GSC_TOOL_VERSION="${GSC_TOOL_VERSION:-1.4.10}"

xlr_ensure_gsc_tool() {
    local tools_dir="$1"
    local gsc_tool="$tools_dir/gsc-tool"

    if [ -x "$gsc_tool" ]; then
        printf '%s\n' "$gsc_tool"
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
    echo "[XLR] Downloading gsc-tool ${GSC_TOOL_VERSION} (${asset})..." >&2
    if ! curl -fsSL "$url" -o "$tmp"; then
        echo "[XLR] ERROR: failed to download gsc-tool from GitHub" >&2
        return 1
    fi

    tar -xzf "$tmp" -C "$tools_dir"
    rm -f "$tmp"

    if [ -f "$tools_dir/gsc-tool" ]; then
        chmod +x "$tools_dir/gsc-tool"
        printf '%s\n' "$tools_dir/gsc-tool"
        return 0
    fi

    found="$(find "$tools_dir" -maxdepth 3 -type f -name gsc-tool 2>/dev/null | head -1)"
    if [ -n "$found" ]; then
        cp -f "$found" "$gsc_tool"
        chmod +x "$gsc_tool"
        printf '%s\n' "$gsc_tool"
        return 0
    fi

    echo "[XLR] ERROR: gsc-tool binary not found after extract in $tools_dir" >&2
    ls -la "$tools_dir" >&2 || true
    return 1
}

xlr_gsc_looks_compiled() {
    local file="$1"
    [ -f "$file" ] || return 1
    local first
    first="$(head -c 1 "$file" | od -An -tu1 2>/dev/null | tr -d ' ')"
    [ "$first" = "128" ]
}

xlr_gsc_looks_source() {
    local file="$1"
    [ -f "$file" ] || return 1
    local first
    first="$(head -c 1 "$file" | od -An -tu1 2>/dev/null | tr -d ' ')"
    [ "$first" = "35" ]
}

xlr_purge_invalid_gsc() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return 0
    fi

    if xlr_gsc_looks_source "$file"; then
        echo "[XLR] REMOVING invalid SOURCE gsc (breaks map load): $file" >&2
        rm -f "$file"
        return 0
    fi

    if ! xlr_gsc_looks_compiled "$file"; then
        echo "[XLR] REMOVING invalid gsc (not compiled binary): $file" >&2
        rm -f "$file"
    fi
}

xlr_compile_gsc_file() {
    local workdir="$1"
    local source_file="$2"
    local dest_file="$3"
    local log_file="${4:-$(dirname "$dest_file")/xlr_welcome.compile.log}"
    local tools_dir="$workdir/.tools/gsc-tool"
    local gsc_tool compiled_out

    if [ ! -f "$source_file" ]; then
        echo "[XLR] ERROR: missing GSC source $source_file" >&2
        return 1
    fi

    gsc_tool="$(xlr_ensure_gsc_tool "$tools_dir")" || {
        echo "[XLR] ERROR: gsc-tool not available — cannot compile (T6 needs compiled scripts)" >&2
        return 1
    }

    if [ ! -x "$gsc_tool" ]; then
        echo "[XLR] ERROR: gsc-tool is not executable: $gsc_tool" >&2
        return 1
    fi

    mkdir -p "$(dirname "$dest_file")" "$(dirname "$log_file")"
    rm -rf "$workdir/compiled"

    local build_dir base_name
    build_dir="$(dirname "$source_file")"
    base_name="$(basename "$source_file")"
    echo "[XLR] Compiling with $gsc_tool ..." >&2
    (
        cd "$build_dir" || exit 1
        "$gsc_tool" -m comp -g t6 -s pc "$base_name"
    ) >"$log_file" 2>&1 || {
        echo "[XLR] ERROR: gsc-tool compile failed — see $log_file" >&2
        tail -20 "$log_file" >&2 || true
        return 1
    }

    compiled_out="$build_dir/compiled/t6/$base_name"
    if [ ! -f "$compiled_out" ]; then
        compiled_out="$workdir/compiled/t6/$base_name"
    fi
    if [ ! -f "$compiled_out" ]; then
        compiled_out="$(find "$build_dir" "$workdir" -type f -path "*/compiled/t6/$base_name" 2>/dev/null | head -1)"
    fi
    if [ ! -f "$compiled_out" ]; then
        echo "[XLR] ERROR: expected compiled output at $compiled_out" >&2
        tail -20 "$log_file" >&2 || true
        return 1
    fi

    cp "$compiled_out" "$dest_file"
    rm -rf "$build_dir/compiled" "$workdir/compiled"

    if ! xlr_gsc_looks_compiled "$dest_file"; then
        echo "[XLR] ERROR: deploy file is still source text, not compiled binary" >&2
        return 1
    fi

    echo "[XLR] GSC compiled OK -> $dest_file ($(wc -c < "$dest_file") bytes)"
    return 0
}

xlr_resolve_compiled_gsc_output() {
    local source_file="$1"
    local compile_rel="$2"
    shift 2
    local base candidate root

    base="$(basename "$source_file")"

    if [ -f "$source_file" ] && xlr_gsc_looks_compiled "$source_file"; then
        printf '%s\n' "$source_file"
        return 0
    fi

    if [ -f "${source_file%.gsc}.gscbin" ] && xlr_gsc_looks_compiled "${source_file%.gsc}.gscbin"; then
        printf '%s\n' "${source_file%.gsc}.gscbin"
        return 0
    fi

    for root in "$@"; do
        [ -n "$root" ] && [ -d "$root" ] || continue
        while IFS= read -r candidate; do
            [ -n "$candidate" ] || continue
            if xlr_gsc_looks_compiled "$candidate"; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done < <(find "$root" -type f \( \
            -path "*/compiled/t6/$compile_rel" -o \
            -path "*/compiled/t6/$base" -o \
            -path "*/compiled/t6/*/$base" \
        \) 2>/dev/null)
    done

    return 1
}

xlr_copy_compiled_gsc() {
    local compiled_out="$1"
    local dest_file="$2"

    mkdir -p "$(dirname "$dest_file")"
    cp -f "$compiled_out" "$dest_file"
    if ! xlr_gsc_looks_compiled "$dest_file"; then
        echo "[XLR] ERROR: deploy file is not compiled GSC binary: $dest_file" >&2
        return 1
    fi
    return 0
}

xlr_compile_gsc_dir() {
    local workdir="$1"
    local src_dir="$2"
    local dest_dir="$3"
    local log_dir="${4:-$dest_dir}"
    local gsc_tool src rel dest base log_file compiled_out compile_dir

    gsc_tool="$(xlr_ensure_gsc_tool "$workdir/.tools/gsc-tool")" || return 1
    mkdir -p "$dest_dir" "$log_dir"

    while IFS= read -r -d '' src; do
        rel="${src#$src_dir/}"
        dest="$dest_dir/$rel"
        base="$(basename "$src")"
        compile_dir="$(dirname "$src")"
        log_file="$log_dir/${rel//\//_}.compile.log"
        mkdir -p "$(dirname "$dest")"
        rm -rf "$compile_dir/compiled"
        (
            cd "$compile_dir" || exit 1
            "$gsc_tool" -m comp -g t6 -s pc "$base"
        ) >"$log_file" 2>&1 || {
            echo "[XLR] ERROR: gsc-tool compile failed for $rel — see $log_file" >&2
            tail -20 "$log_file" >&2 || true
            return 1
        }
        compiled_out="$compile_dir/compiled/t6/$base"
        if [ ! -f "$compiled_out" ]; then
            echo "[XLR] ERROR: expected compiled output for $rel at $compiled_out" >&2
            return 1
        fi
        cp -f "$compiled_out" "$dest"
        rm -rf "$compile_dir/compiled"
    done < <(find "$src_dir" -name '*.gsc' -type f -print0 | sort -z)
    return 0
}
