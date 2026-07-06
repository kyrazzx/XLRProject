#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installIW4MAdmin() {
    local workdir="${WORKDIR}"
    local install_dir="$workdir/IW4MAdmin"
    local config_file="$workdir/Plutonium/server_config.json"

    if ! command -v dotnet &> /dev/null; then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} .NET is required for IW4MAdmin.\n"
        return 1
    fi

    mkdir -p "$install_dir"
    checkAndInstallCommand "unzip" "unzip"
    checkAndInstallCommand "jq" "jq"

    local release_url
    release_url=$(curl -s https://api.github.com/repos/RaidMax/IW4M-Admin/releases/latest | jq -r '.assets[] | select(.name | test("IW4MAdmin.*\\.zip$")) | .browser_download_url' | head -n 1)

    if [ -z "$release_url" ] || [ "$release_url" = "null" ]; then
        release_url=$(curl -s https://api.github.com/repos/RaidMax/IW4M-Admin/releases/latest | jq -r '.assets[0].browser_download_url')
    fi

    if [ -z "$release_url" ] || [ "$release_url" = "null" ]; then
        printf "${COLORS[RED]}Error:${COLORS[RESET]} Unable to find IW4MAdmin release.\n"
        return 1
    fi

    local tmp_zip="/tmp/iw4madmin_latest.zip"
    wget -q -O "$tmp_zip" "$release_url"
    unzip -oq "$tmp_zip" -d "$install_dir"
    rm -f "$tmp_zip"

    if [ -f "$install_dir/StartIW4MAdmin.sh" ]; then
        chmod +x "$install_dir/StartIW4MAdmin.sh"
    fi
    if [ -f "$install_dir/UpdateIW4MAdmin.sh" ]; then
        chmod +x "$install_dir/UpdateIW4MAdmin.sh"
    fi

    if [ -f "$config_file" ]; then
        jq '.iw4madmin_config.enabled = true' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    installIW4MAdmin
else
    echo "Usage: $0 [--install] | [--import]"
fi
