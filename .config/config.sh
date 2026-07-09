#!/bin/bash





export LANG=C.UTF-8
export LC_ALL=C.UTF-8

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
    VERSION_ID=$VERSION_ID
else
    DISTRO="debian"
    VERSION="10"
    VERSION_ID="10"
fi

source "$(dirname "${BASH_SOURCE[0]}")/utility/distro.sh"

source "$(dirname "${BASH_SOURCE[0]}")/utility/colors.sh"


language=0    # Default language setting (0 for English)
firewall=""   # Firewall configuration (empty string for default behavior)
ssh_port=22   # Default SSH port
dotnet=""     # .NET installation flag (empty string for default behavior)
xlr_backups=""
xlr_iw4madmin=""
xlr_discord=""
xlr_chat_commands=""
xlr_mapvote=""
server_key=""
rcon_password=""
discord_token=""
manual_game_files=""

checkAndInstallCommand() {
    local command=$1
    local package=$2
    if ! command -v "$command" &> /dev/null; then
        printf "Installing %s...\n" "$package"
        apt-get install -y "$package" > /dev/null 2>&1
    fi
}