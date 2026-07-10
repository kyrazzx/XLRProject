#!/bin/bash

XLR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XLR_WORKDIR="$(cd "$XLR_SCRIPT_DIR/../.." && pwd)"

if [ -f "$XLR_WORKDIR/.config/config.sh" ]; then
    source "$XLR_WORKDIR/.config/config.sh"
fi

if [ -z "${WORKDIR:-}" ]; then
    WORKDIR="$XLR_WORKDIR"
fi

RESXT_REPO_ZIP="https://github.com/Resxt/Plutonium-T6-Scripts/archive/refs/heads/main.zip"

xlr_resxt_run_user() {
    local workdir="$1"
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        printf '%s\n' "$SUDO_USER"
        return 0
    fi
    local owner
    owner=$(stat -c '%U' "$workdir" 2>/dev/null || true)
    if [ -n "$owner" ] && [ "$owner" != "root" ]; then
        printf '%s\n' "$owner"
        return 0
    fi
    id -un
}

xlr_resxt_prepare_build_dir() {
    local workdir="$1"
    local build_dir="$workdir/.build/resxt"
    local run_user run_group

    run_user=$(xlr_resxt_run_user "$workdir")
    run_group=$(id -gn "$run_user" 2>/dev/null || echo "$run_user")

    if [ -d "$workdir/.build" ] && [ ! -w "$workdir/.build" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            chown -R "$run_user:$run_group" "$workdir/.build" 2>/dev/null || true
        elif command -v sudo >/dev/null 2>&1; then
            sudo chown -R "$run_user:$run_group" "$workdir/.build" 2>/dev/null || \
                sudo rm -rf "$workdir/.build" 2>/dev/null || true
        fi
    fi

    mkdir -p "$build_dir"
    if [ "$(id -u)" -eq 0 ] && [ "$run_user" != "root" ]; then
        chown -R "$run_user:$run_group" "$build_dir" 2>/dev/null || true
    fi
}

xlr_resxt_rm_rf() {
    local path="$1"
    [ -e "$path" ] || return 0
    rm -rf "$path" 2>/dev/null && return 0
    if command -v sudo >/dev/null 2>&1; then
        sudo rm -rf "$path" 2>/dev/null && return 0
    fi
    echo "[XLR] ERROR: cannot remove $path — run: sudo rm -rf $path" >&2
    return 1
}

xlr_resxt_enabled() {
    local feature="$1"
    local config_file="${2:-$WORKDIR/Plutonium/server_config.json}"
    [ -f "$config_file" ] || return 1
    [ "$(jq -r ".resxt_scripts.${feature}.enabled // false" "$config_file")" = "true" ]
}

xlr_build_server_ports_array() {
    local config_file="$1"
    local feature="$2"
    local ids_json

    ids_json=$(jq -c ".resxt_scripts.${feature}.server_ids // []" "$config_file")
    jq -r --argjson ids "$ids_json" '
        .servers[]?
        | select(.enabled == true)
        | select(.id as $id | ($ids | length) == 0 or ($ids | index($id)))
        | .port
    ' "$config_file" | awk '{printf "\"%s\", ", $0}' | sed 's/, $//'
}

xlr_purge_legacy_resxt_chat() {
    local dest_scripts="$1"
    local legacy

    for legacy in \
        "$dest_scripts"/z_chat_command_*.gsc \
        "$dest_scripts/mp/z_chat_command_suicide.gsc"
    do
        [ -e "$legacy" ] || continue
        rm -f "$legacy"
    done
}

xlr_mapvote_mode_for_server() {
    local config_file="$1"
    local server_id="$2"
    local gametype

    gametype=$(jq -r --arg sid "$server_id" '.servers[] | select(.id == $sid) | .gametype // "war"' "$config_file")
    case "$gametype" in
        dm) printf '%s' "Free for All,dm" ;;
        *) printf '%s' "Team Deathmatch,tdm" ;;
    esac
}

xlr_patch_ufo_mode_gsc() {
    local file="$1"

    python3 - "$file" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

if "xlr: only unlink when linked" in text:
    sys.exit(0)

def patch_else_unlink(src):
    patterns = [
        (
            re.compile(
                r"(\t\telse\r?\n"
                r"\t\t\{\r?\n"
                r"\t\t\tself Unlink\(\);\r?\n"
                r"\t\t\tself\.fly = 0;\r?\n"
                r"\t\t\})"
            ),
            (
                "\t\telse if (self.fly == 1)\n"
                "\t\t{\n"
                "\t\t\tself Unlink(); // xlr: only unlink when linked\n"
                "\t\t\tself.fly = 0;\n"
                "\t\t}"
            ),
        ),
        (
            re.compile(
                r"(\telse\r?\n"
                r"\t\{\r?\n"
                r"\t\tself Unlink\(\);\r?\n"
                r"\t\tself\.fly = 0;\r?\n"
                r"\t\})"
            ),
            (
                "\telse if (self.fly == 1)\n"
                "\t{\n"
                "\t\tself Unlink(); // xlr: only unlink when linked\n"
                "\t\tself.fly = 0;\n"
                "\t}"
            ),
        ),
    ]

    for pattern, repl in patterns:
        patched, count = pattern.subn(repl, src, count=1)
        if count == 1:
            return patched, 1

    flex = re.compile(
        r"([ \t]+)else[ \t]*\r?\n"
        r"\1\{[ \t]*\r?\n"
        r"\1[ \t]+self Unlink\(\);[ \t]*\r?\n"
        r"\1[ \t]+self\.fly = 0;[ \t]*\r?\n"
        r"\1\}"
    )

    def repl_fn(match):
        indent = match.group(1)
        inner = indent + ("\t" if "\t" in indent else "    ")
        return (
            f"{indent}else if (self.fly == 1)\n"
            f"{indent}{{\n"
            f"{inner}self Unlink(); // xlr: only unlink when linked\n"
            f"{inner}self.fly = 0;\n"
            f"{indent}}}"
        )

    patched, count = flex.subn(repl_fn, src, count=1)
    return patched, count

patched, count = patch_else_unlink(text)
if count != 1:
    print(f"[XLR] ERROR: ufo mode patch did not apply to {path}", file=sys.stderr)
    sys.exit(1)

open(path, "w", encoding="utf-8").write(patched)
PY
}

xlr_patch_chat_commands_gsc() {
    local file="$1"
    local ports_csv="$2"
    local owner_id="$3"

    python3 - "$file" "$ports_csv" "$owner_id" <<'PY'
import re
import sys

path, ports, owner_id = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()

text = re.sub(
    r'level\.chat_commands\["ports"\] = array\("4976", "4977"\);',
    f'level.chat_commands["ports"] = array({ports});',
    text,
    count=1,
)

text = text.replace(
    "\tplayer thread TellPlayer(InsufficientPermissionError(0), 1);\n\t\tcontinue; // stop",
    "\tcontinue; // xlr: silent for non-owner\n",
    1,
)
if "xlr: silent for non-owner" not in text:
    text = re.sub(
        r'player thread TellPlayer\(InsufficientPermissionError\(0\), 1\);\s*continue; // stop',
        "continue; // xlr: silent for non-owner",
        text,
        count=1,
    )

old = (
    '\t\tif (IsDefined(isCommand) && isCommand)\n'
    '\t\t{\n'
    '\t\t\tmessage = GetDvar("cc_prefix") + message;\n'
    '\t\t}\n'
    '\t\t\n'
    '\t\tself IPrintLnBold(message);'
)
new = (
    '\t\tif (IsDefined(isCommand) && isCommand)\n'
    '\t\t{\n'
    '\t\t\tmessage = GetDvar("cc_prefix") + message;\n'
    '\t\t}\n'
    '\t\telse\n'
    '\t\t{\n'
    '\t\t\tmessage = "^6[XLR]^7 " + message;\n'
    '\t\t}\n'
    '\n'
    '\t\tself IPrintLnBold(message);'
)
if old in text:
    text = text.replace(old, new, 1)
else:
    text = re.sub(
        r'(if \(IsDefined\(isCommand\) && isCommand\)\s*\{[^}]+\})\s*self IPrintLnBold\(message\);',
        r'\1\n\t\telse\n\t\t{\n\t\t\tmessage = "^6[XLR]^7 " + message;\n\t\t}\n\n\t\tself IPrintLnBold(message);',
        text,
        count=1,
    )

marker = 'GetPlayerPermissionLevelFromDvar()\n{'
if marker not in text:
    marker = 'GetPlayerPermissionLevelFromDvar()\r\n{'
if marker in text and 'xlr_owner_permission' not in text:
    insert = (
        'GetPlayerPermissionLevelFromDvar()\n'
        '{\n'
        '\t// xlr_owner_permission\n'
        f'\tif (isDefined(self.userid) && self.userid == {owner_id})\n'
        '\t{\n'
        '\t\treturn GetDvarInt("cc_permission_max");\n'
        '\t}\n'
    )
    text = text.replace(marker, insert, 1)

open(path, "w", encoding="utf-8").write(text)
PY
}

xlr_fetch_resxt_sources() {
    local workdir="$1"
    local build_dir="$workdir/.build/resxt"
    local zip_file="$build_dir/resxt.zip"
    local extract_dir="$build_dir/extract"

    xlr_resxt_prepare_build_dir "$workdir" || return 1
    xlr_resxt_rm_rf "$extract_dir" || return 1
    mkdir -p "$extract_dir"

    if ! command -v curl >/dev/null 2>&1; then
        echo "[XLR] ERROR: curl is required" >&2
        return 1
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        echo "[XLR] ERROR: unzip is required" >&2
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "[XLR] ERROR: python3 is required" >&2
        return 1
    fi

    echo "[XLR] Downloading Resxt Plutonium scripts..." >&2
    if ! curl -fsSL "$RESXT_REPO_ZIP" -o "$zip_file"; then
        echo "[XLR] ERROR: failed to download Resxt scripts" >&2
        return 1
    fi

    unzip -q "$zip_file" -d "$extract_dir"
    local root_dir
    root_dir="$(find "$extract_dir" -maxdepth 1 -type d -name 'Plutonium-T6-Scripts-*' | head -1)"
    if [ -z "$root_dir" ] || [ ! -d "$root_dir" ]; then
        echo "[XLR] ERROR: unexpected Resxt archive layout" >&2
        return 1
    fi
    printf '%s' "$root_dir"
}

xlr_stage_chat_commands() {
    local workdir="$1"
    local config_file="$2"
    local root_dir="$3"
    local t6_root="$workdir/.build/resxt/t6-chat"
    local stage_dir="$t6_root/scripts"
    local src_dir="$root_dir/chat_commands"
    local owner_id ports_csv

    if [ ! -d "$src_dir" ] || [ ! -f "$src_dir/chat_commands.gsc" ]; then
        echo "[XLR] ERROR: Resxt chat_commands not found under $root_dir" >&2
        return 1
    fi

    owner_id=$(jq -r '.customization.owner.plutonium_id // "0"' "$config_file")
    ports_csv=$(xlr_build_server_ports_array "$config_file" "chat_commands")

    rm -rf "$t6_root" 2>/dev/null || xlr_resxt_rm_rf "$t6_root" || return 1
    mkdir -p "$stage_dir/mp"

    cp -f "$src_dir/chat_commands.gsc" "$stage_dir/" || return 1
    for file in "$src_dir"/chat_command_*.gsc; do
        [ -f "$file" ] || continue
        case "$(basename "$file")" in
            *"unlimited_ammo "*) cp -f "$file" "$stage_dir/chat_command_unlimited_ammo.gsc" || return 1 ;;
            *) cp -f "$file" "$stage_dir/" || return 1 ;;
        esac
    done
    [ -f "$src_dir/mp/chat_command_suicide.gsc" ] && cp -f "$src_dir/mp/chat_command_suicide.gsc" "$stage_dir/mp/" || true

    if [ -f "$stage_dir/chat_command_ufo_mode.gsc" ]; then
        xlr_patch_ufo_mode_gsc "$stage_dir/chat_command_ufo_mode.gsc" || return 1
    fi

    xlr_patch_chat_commands_gsc "$stage_dir/chat_commands.gsc" "$ports_csv" "$owner_id" || return 1
    printf '%s' "$t6_root"
}

xlr_stage_mapvote() {
    local workdir="$1"
    local root_dir="$2"
    local t6_root="$workdir/.build/resxt/t6-mapvote"
    local stage_dir="$t6_root/scripts"

    if [ ! -f "$root_dir/mapvote/mapvote.gsc" ] || [ ! -f "$root_dir/mapvote/mapvote_mp_extend.gsc" ]; then
        echo "[XLR] ERROR: Resxt mapvote files not found under $root_dir" >&2
        return 1
    fi

    rm -rf "$t6_root" 2>/dev/null || xlr_resxt_rm_rf "$t6_root" || return 1
    mkdir -p "$stage_dir/mp"
    cp -f "$root_dir/mapvote/mapvote.gsc" "$stage_dir/" || return 1
    cp -f "$root_dir/mapvote/mapvote_mp_extend.gsc" "$stage_dir/mp/" || return 1
    printf '%s' "$t6_root"
}

xlr_compile_resxt_tree() {
    local workdir="$1"
    local t6_root="$2"
    local dest_scripts="$3"
    local log_dir="${4:-$workdir/.build/resxt/logs}"
    local scripts_src="$t6_root/scripts"
    local gsc_tool compile_rel src dest log_file compile_tree compiled_out

    source "$workdir/.config/xlr/compileGsc.sh"
    gsc_tool="$(xlr_ensure_gsc_tool "$workdir/.tools/gsc-tool")" || return 1
    mkdir -p "$dest_scripts" "$log_dir"

    local ordered=()
    [ -f "$scripts_src/chat_commands.gsc" ] && ordered+=("chat_commands.gsc")
    while IFS= read -r -d '' src; do
        ordered+=("${src#$scripts_src/}")
    done < <(find "$scripts_src" -maxdepth 1 -name 'chat_command*.gsc' -type f -print0 | sort -z)
    while IFS= read -r -d '' src; do
        rel="${src#$scripts_src/}"
        [ "$rel" = "chat_commands.gsc" ] && continue
        case "$rel" in
            chat_command*) continue ;;
        esac
        ordered+=("$rel")
    done < <(find "$scripts_src" -name '*.gsc' -type f -print0 | sort -z)

    compile_tree="$workdir/.build/resxt/compile-tree"
    xlr_resxt_rm_rf "$compile_tree" || return 1
    mkdir -p "$compile_tree/scripts"
    cp -a "$scripts_src/." "$compile_tree/scripts/"

    for compile_rel in "${ordered[@]}"; do
        src="$compile_tree/scripts/$compile_rel"
        dest="$dest_scripts/$compile_rel"
        log_file="$log_dir/${compile_rel//\//_}.compile.log"
        [ -f "$src" ] || {
            echo "[XLR] ERROR: missing staged source scripts/$compile_rel" >&2
            return 1
        }

        rm -rf "$compile_tree/compiled" "$compile_tree/scripts/compiled" \
            "$(dirname "$src")/compiled" 2>/dev/null || true

        : >"$log_file"
        if (
            cd "$compile_tree" || exit 1
            "$gsc_tool" -m comp -g t6 -s pc -w "$compile_tree" "scripts/$compile_rel"
        ) >>"$log_file" 2>&1; then
            :
        elif (
            cd "$(dirname "$src")" || exit 1
            "$gsc_tool" -m comp -g t6 -s pc -w "$compile_tree" "$(basename "$src")"
        ) >>"$log_file" 2>&1; then
            :
        else
            echo "[XLR] ERROR: gsc-tool compile failed for scripts/$compile_rel — see $log_file" >&2
            tail -30 "$log_file" >&2 || true
            return 1
        fi

        compiled_out="$(xlr_resolve_compiled_gsc_output "$src" "$compile_rel" "$compile_tree" "$(dirname "$src")")" || {
            echo "[XLR] ERROR: compiled output not found for scripts/$compile_rel — see $log_file" >&2
            tail -30 "$log_file" >&2 || true
            find "$compile_tree" -type f \( -name '*.gsc' -o -name '*.gscbin' \) 2>/dev/null | head -20 >&2 || true
            return 1
        }

        xlr_copy_compiled_gsc "$compiled_out" "$dest" || return 1
        echo "[XLR] compiled scripts/$compile_rel -> $dest ($(wc -c < "$dest") bytes)" >&2

        cp -a "$scripts_src/." "$compile_tree/scripts/"
    done

    rm -rf "$compile_tree"
    return 0
}

xlr_set_cfg_dvar() {
    local cfg_path="$1"
    local key="$2"
    local value="$3"

    [ -f "$cfg_path" ] || return 0
    sed -i "/^set ${key} /d" "$cfg_path" 2>/dev/null || true
    echo "set ${key} \"${value}\"" >> "$cfg_path"
}

xlr_apply_chat_command_dvars() {
    local workdir="$1"
    local config_file="$workdir/Plutonium/server_config.json"
    local mp_main="$workdir/Server/Multiplayer/main"
    local owner_name prefix server_id cfg_file

    owner_name=$(jq -r '.customization.owner.name // "akan3"' "$config_file")
    prefix=$(jq -r '.resxt_scripts.chat_commands.prefix // "."' "$config_file")

    while IFS= read -r server_id; do
        [ -n "$server_id" ] || continue
        cfg_file=$(jq -r --arg sid "$server_id" '.servers[] | select(.id == $sid) | .config' "$config_file")
        [ -n "$cfg_file" ] && [ "$cfg_file" != "null" ] || continue
        cfg_path="$mp_main/$cfg_file"
        [ -f "$cfg_path" ] || continue

        xlr_set_cfg_dvar "$cfg_path" "cc_debug" "0"
        xlr_set_cfg_dvar "$cfg_path" "cc_prefix" "$prefix"
        xlr_set_cfg_dvar "$cfg_path" "cc_permission_enabled" "1"
        xlr_set_cfg_dvar "$cfg_path" "cc_permission_mode" "name"
        xlr_set_cfg_dvar "$cfg_path" "cc_permission_default" "0"
        xlr_set_cfg_dvar "$cfg_path" "cc_permission_max" "4"
        xlr_set_cfg_dvar "$cfg_path" "cc_permission_4" "$owner_name"
        xlr_set_cfg_dvar "$cfg_path" "cc_permission_3" ""
        xlr_set_cfg_dvar "$cfg_path" "cc_permission_2" ""
        xlr_set_cfg_dvar "$cfg_path" "cc_permission_1" ""
        xlr_set_cfg_dvar "$cfg_path" "cc_permission_0" ""
        echo "[XLR] Chat commands dvars applied to $cfg_file (owner=$owner_name, prefix=$prefix)"
    done < <(jq -r '.resxt_scripts.chat_commands.server_ids[]?' "$config_file")
}

xlr_apply_mapvote_dvars() {
    local workdir="$1"
    local config_file="$workdir/Plutonium/server_config.json"
    local mp_main="$workdir/Server/Multiplayer/main"
    local maps vote_time server_id cfg_file modes

    maps=$(jq -r '.resxt_scripts.mapvote.maps // "Hijacked:Raid:Nuketown:Slums:Express:Carrier:Meltdown"' "$config_file")
    vote_time=$(jq -r '.resxt_scripts.mapvote.vote_time // 30' "$config_file")

    while IFS= read -r server_id; do
        [ -n "$server_id" ] || continue
        cfg_file=$(jq -r --arg sid "$server_id" '.servers[] | select(.id == $sid) | .config' "$config_file")
        [ -n "$cfg_file" ] && [ "$cfg_file" != "null" ] || continue
        cfg_path="$mp_main/$cfg_file"
        [ -f "$cfg_path" ] || continue
        modes=$(xlr_mapvote_mode_for_server "$config_file" "$server_id")

        xlr_set_cfg_dvar "$cfg_path" "mapvote_enable" "1"
        xlr_set_cfg_dvar "$cfg_path" "mapvote_maps" "$maps"
        xlr_set_cfg_dvar "$cfg_path" "mapvote_modes" "$modes"
        xlr_set_cfg_dvar "$cfg_path" "mapvote_limits_maps" "0"
        xlr_set_cfg_dvar "$cfg_path" "mapvote_limits_modes" "0"
        xlr_set_cfg_dvar "$cfg_path" "mapvote_vote_time" "$vote_time"
        xlr_set_cfg_dvar "$cfg_path" "mapvote_colors_selected" "yellow"
        xlr_set_cfg_dvar "$cfg_path" "mapvote_colors_timer" "yellow"
        xlr_set_cfg_dvar "$cfg_path" "mapvote_colors_help_accent" "yellow"
        xlr_set_cfg_dvar "$cfg_path" "mapvote_colors_help_text" "white"
        echo "[XLR] Mapvote dvars applied to $cfg_file (maps only, fixed mode: $modes)"
    done < <(jq -r '.resxt_scripts.mapvote.server_ids[]?' "$config_file")

    while IFS= read -r server_id; do
        cfg_file=$(jq -r --arg sid "$server_id" '.servers[] | select(.id == $sid) | .config' "$config_file")
        [ -n "$cfg_file" ] && [ "$cfg_file" != "null" ] || continue
        cfg_path="$mp_main/$cfg_file"
        [ -f "$cfg_path" ] || continue
        if ! jq -e --arg sid "$server_id" '.resxt_scripts.mapvote.server_ids[]? | select(. == $sid)' "$config_file" >/dev/null; then
            xlr_set_cfg_dvar "$cfg_path" "mapvote_enable" "0"
        fi
    done < <(jq -r '.servers[]? | select(.enabled == true) | .id' "$config_file")
}

xlr_deploy_chat_commands() {
    local workdir="$1"
    local root_dir="$2"
    local config_file="$workdir/Plutonium/server_config.json"
    local t6_root dest_dir

    t6_root="$(xlr_stage_chat_commands "$workdir" "$config_file" "$root_dir")" || return 1
    dest_dir="$workdir/Plutonium/storage/t6/scripts"

    xlr_purge_legacy_resxt_chat "$dest_dir"

    xlr_compile_resxt_tree "$workdir" "$t6_root" "$dest_dir" "$workdir/.build/resxt/logs-chat" || return 1
    xlr_apply_chat_command_dvars "$workdir" || return 1
    echo "[XLR] Resxt chat commands deployed"
}

xlr_deploy_mapvote() {
    local workdir="$1"
    local root_dir="$2"
    local config_file="$workdir/Plutonium/server_config.json"
    local t6_root dest_dir

    t6_root="$(xlr_stage_mapvote "$workdir" "$root_dir")" || return 1
    dest_dir="$workdir/Plutonium/storage/t6/scripts"

    xlr_compile_resxt_tree "$workdir" "$t6_root" "$dest_dir" "$workdir/.build/resxt/logs-mapvote" || return 1
    xlr_apply_mapvote_dvars "$workdir" || return 1
    echo "[XLR] Resxt mapvote deployed"
}

setupResxtScripts() {
    local workdir="${WORKDIR:-$XLR_WORKDIR}"
    local config_file="$workdir/Plutonium/server_config.json"
    local chat map root_dir=""

    [ -f "$config_file" ] || return 1
    xlr_resxt_prepare_build_dir "$workdir" || return 1

    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        echo "[XLR] WARN: run as $SUDO_USER when possible — fixing .build ownership" >&2
    fi
    chat=$(jq -r '.resxt_scripts.chat_commands.enabled // false' "$config_file")
    map=$(jq -r '.resxt_scripts.mapvote.enabled // false' "$config_file")

    if [ "$chat" != "true" ] && [ "$map" != "true" ]; then
        echo "[XLR] Resxt scripts disabled in server_config.json"
        return 0
    fi

    root_dir="$(xlr_fetch_resxt_sources "$workdir")" || return 1
    if [ ! -d "$root_dir" ]; then
        echo "[XLR] ERROR: invalid Resxt source path: $root_dir" >&2
        return 1
    fi

    if [ "$chat" = "true" ]; then
        xlr_deploy_chat_commands "$workdir" "$root_dir" || return 1
    fi
    if [ "$map" = "true" ]; then
        xlr_deploy_mapvote "$workdir" "$root_dir" || return 1
    fi
    return 0
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    setupResxtScripts
else
    echo "Usage: $0 [--install] | [--import]"
fi
